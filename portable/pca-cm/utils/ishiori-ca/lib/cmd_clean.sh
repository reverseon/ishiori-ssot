# cmd_clean.sh — clean non-valid certificates command

cmd_clean() {
    local dry_run=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1 ;;
            *) echo "Error: Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    # Use awk to parse index.txt and build deletion list
    local to_delete_info=""
    local files_to_delete=()

    to_delete_info=$(awk -v newcerts_dir="$NEWCERTS_DIR" -v private_dir="$ROOT_CA_DIR/private" -v enc_dir="$PRIVATE_ENC_DIR" 'BEGIN { FS="\t" }
    {
        status=$1; serial=$4; subject=$6

        if (status == "V") next
        if (status == "") next

        cn = subject; sub(/.*CN=/, "", cn); sub(/\/.*/, "", cn)

        if (status == "R") status_label = "Revoked"
        else if (status == "E") status_label = "Expired"
        else status_label = status

        cert_file = newcerts_dir "/" serial ".pem"
        unenc_key = private_dir "/" cn ".key.pem"
        enc_key = enc_dir "/private+" cn ".key.pem.age"

        printf "%s|%s|%s|%s|%s|%s|%s\n", status_label, serial, cn, cert_file, unenc_key, enc_key, serial
    }' "$INDEX_FILE")

    # Parse awk output and collect files to delete
    local to_delete=()
    while IFS='|' read -r status serial cn cert_file unenc_key enc_key serial_end; do
        [[ -z "$status" ]] && continue
        to_delete+=("$status|$serial|$cn")

        if [[ -f "$cert_file" ]]; then
            files_to_delete+=("$cert_file")
        fi
        if [[ -f "$unenc_key" ]]; then
            files_to_delete+=("$unenc_key")
        fi
        if [[ -f "$enc_key" ]]; then
            files_to_delete+=("$enc_key")
        fi
    done <<< "$to_delete_info"

    # If no actual files to delete
    if [[ ${#files_to_delete[@]} -eq 0 ]]; then
        echo "No files to delete."
        return 0
    fi

    # Display what will be deleted
    echo "The following certificates and keys will be deleted:"
    echo ""
    printf "%-9s %-7s %s\n" "Status" "Serial" "Common Name"
    printf '%s\n' "$(printf '%.0s-' {1..50})"

    for item in "${to_delete[@]}"; do
        IFS='|' read -r status serial cn <<< "$item"
        printf "%-9s %-7s %s\n" "$status" "$serial" "$cn"
    done

    echo ""
    echo "Files to delete:"
    for file in "${files_to_delete[@]}"; do
        echo "  $file"
    done

    # Ask for confirmation
    echo ""
    read -p "Continue with cleanup? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled."
        return 0
    fi

    # Perform cleanup
    for file in "${files_to_delete[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            echo "Deleted: $file"
        fi
    done

    echo "Cleanup complete."
}

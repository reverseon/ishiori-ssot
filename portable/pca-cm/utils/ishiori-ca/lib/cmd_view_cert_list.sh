# cmd_view_cert_list.sh — view cert list command

cmd_view_cert_list() {
    local filter="" search="" sort_by="serial"
    local valid_sort="serial expiry revoked-date"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --valid)    filter="valid"   ;;
            --revoked)  filter="revoked" ;;
            --filter)   shift; search="$1" ;;
            --sort-by)
                shift; sort_by="$1"
                local ok=0
                for s in $valid_sort; do [[ "$sort_by" == "$s" ]] && ok=1 && break; done
                [[ "$ok" -eq 0 ]] && { echo "Error: --sort-by must be one of: $valid_sort"; exit 1; }
                ;;
            *) echo "Error: Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    printf "%-9s %-8s %-17s %-17s %-24s %s\n" \
        "Status" "Serial" "Expiry (UTC)" "Revoked Date (UTC)" "Revoked Reason" "Common Name"
    printf '%s\n' "$(printf '%.0s-' {1..95})"
    parse_index "$filter" "$search" "$sort_by"
}

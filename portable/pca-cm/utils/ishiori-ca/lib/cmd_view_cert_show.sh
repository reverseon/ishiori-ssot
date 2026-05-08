# cmd_view_cert_show.sh — view cert show command

cmd_view_cert_show() {
    local serial="" short=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --serial) shift; serial="$1" ;;
            --cn)
                shift
                serial=$(awk -F'\t' -v cn="$1" '
                    { sub(/.*CN=/, "", $6); sub(/\/.*/, "", $6); if ($1 == "V" && $6 == cn) last=$4 }
                    END { print last }
                ' "$INDEX_FILE")
                if [[ -z "$serial" ]]; then
                    echo "Error: No valid certificate found with CN='$1'"
                    exit 1
                fi
                ;;
            --short) short=1 ;;
            *) echo "Error: Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    if [[ -z "$serial" ]]; then
        echo "Error: --serial or --cn required"
        usage
        exit 1
    fi

    local cert_file="${NEWCERTS_DIR}/${serial}.pem"
    if [[ ! -f "$cert_file" ]]; then
        echo "Error: Certificate file not found: ${cert_file}"
        exit 1
    fi

    if [[ "$short" -eq 1 ]]; then
        local subject issuer not_before not_after serial_hex san
        subject=$(x509_subject    "$cert_file")
        issuer=$(x509_issuer      "$cert_file")
        not_before=$(x509_not_before "$cert_file")
        not_after=$(x509_not_after   "$cert_file")
        serial_hex=$(x509_serial  "$cert_file")
        san=$(x509_san            "$cert_file")

        echo "Serial  : $serial_hex"
        echo "Valid   : $not_before  ->  $not_after"
        [[ -n "$san" ]] && echo "SANs    : $san" || true
        echo ""
        print_dn_table "Subject:" "$subject"
        echo ""
        print_dn_table "Issuer:" "$issuer"
    else
        openssl x509 -in "$cert_file" -noout -text
    fi
}

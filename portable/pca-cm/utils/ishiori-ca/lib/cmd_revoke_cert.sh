# cmd_revoke_cert.sh — revoke cert command

cmd_revoke_cert() {
    local cn="" serial="" reason="cessationOfOperation"
    local valid_reasons="unspecified keyCompromise CACompromise affiliationChanged superseded cessationOfOperation certificateHold"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cn)     shift; cn="$1" ;;
            --serial) shift; serial="$1" ;;
            --reason) shift; reason="$1" ;;
            *) echo "Error: Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    if [[ -n "$cn" && -n "$serial" ]]; then
        echo "Error: --cn and --serial are mutually exclusive"
        exit 1
    fi

    if [[ -z "$cn" && -z "$serial" ]]; then
        echo "Error: either --cn or --serial is required"
        usage; exit 1
    fi

    local valid=0
    for r in $valid_reasons; do
        [[ "$reason" == "$r" ]] && valid=1 && break
    done
    if [[ "$valid" -eq 0 ]]; then
        echo "Error: Invalid reason '$reason'. Valid reasons: $valid_reasons"
        exit 1
    fi

    local cert_file
    if [[ -n "$cn" ]]; then
        cert_file="${ROOT_CA_DIR}/certs/${cn}.cert.pem"

        local matches
        matches=$(awk -F'\t' -v cn="$cn" '
            { sub(/.*CN=/, "", $6); sub(/\/.*/, "", $6); if ($6 == cn) print $4 "\t" $1 }
        ' "$INDEX_FILE")

        if [[ -z "$matches" ]]; then
            echo "Error: No certificate found in database with CN='${cn}'"
            exit 1
        fi

        local match_count
        match_count=$(echo "$matches" | wc -l)

        if [[ "$match_count" -gt 1 ]]; then
            echo "Error: Multiple certificates found with CN='${cn}'. Use --serial to specify one:"
            echo "$matches" | while IFS=$'\t' read -r s st; do
                local label
                case "$st" in
                    V) label="Valid" ;;
                    R) label="Revoked" ;;
                    E) label="Expired" ;;
                    *) label="$st" ;;
                esac
                echo "  Serial: $s  Status: $label"
            done
            exit 1
        fi

        local serial_found status
        serial_found=$(echo "$matches" | cut -f1)
        status=$(echo "$matches" | cut -f2)

        if [[ "$status" == "R" ]]; then
            echo "Error: Certificate with CN='${cn}' is already revoked"
            exit 1
        fi
    else
        cert_file="${ROOT_CA_DIR}/newcerts/${serial}.pem"

        local status
        status=$(awk -F'\t' -v serial="$serial" '$4 == serial { print $1 }' "$INDEX_FILE" | head -1)

        if [[ -z "$status" ]]; then
            echo "Error: No certificate found in database with serial '${serial}'"
            exit 1
        fi
        if [[ "$status" == "R" ]]; then
            echo "Error: Certificate with serial '${serial}' is already revoked"
            exit 1
        fi
    fi

    if [[ ! -f "$cert_file" ]]; then
        echo "Error: Certificate file not found: ${cert_file}"
        exit 1
    fi

    openssl ca \
        -config "${ROOT_CA_DIR}/openssl.cnf" \
        -revoke "$cert_file" \
        -crl_reason "$reason"

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to revoke certificate"
        exit 1
    fi

    openssl ca \
        -config "${ROOT_CA_DIR}/openssl.cnf" \
        -gencrl \
        -out "${ROOT_CA_DIR}/crl/ca.crl.pem"

    if [[ $? -ne 0 ]]; then
        echo "Error: Certificate revoked but CRL regeneration failed"
        exit 1
    fi

    echo "Certificate revoked and CRL updated."
}

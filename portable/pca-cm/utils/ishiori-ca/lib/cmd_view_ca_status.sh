# cmd_view_ca_status.sh — view ca status command

cmd_view_ca_status() {
    local ca_cert="${ROOT_CA_DIR}/certs/ca.cert.pem"
    local crl_file="${ROOT_CA_DIR}/crl/ca.crl.pem"

    echo "=== CA Certificate ==="
    if [[ ! -f "$ca_cert" ]]; then
        echo "  CA certificate not found: $ca_cert"
    else
        local subject not_before not_after serial_hex days_left
        subject=$(x509_subject       "$ca_cert")
        not_before=$(x509_not_before "$ca_cert")
        not_after=$(x509_not_after   "$ca_cert")
        serial_hex=$(x509_serial     "$ca_cert")
        days_left=$(( ( $(date -d "$not_after" +%s) - $(date +%s) ) / 86400 ))

        echo "  Subject : $subject"
        echo "  Serial  : $serial_hex"
        echo "  Valid   : $not_before  ->  $not_after"
        if (( days_left <= 30 )); then
            echo "  Expires : $days_left days  [WARNING: expiring soon]"
        else
            echo "  Expires : $days_left days"
        fi
    fi

    echo ""
    echo "=== Certificate Database ==="
    if [[ ! -f "$INDEX_FILE" ]]; then
        echo "  Index file not found: $INDEX_FILE"
    else
        local total valid revoked expired
        total=$(wc -l < "$INDEX_FILE")
        valid=$(awk -F'\t' '$1=="V"' "$INDEX_FILE" | wc -l)
        revoked=$(awk -F'\t' '$1=="R"' "$INDEX_FILE" | wc -l)
        expired=$(awk -F'\t' '$1=="E"' "$INDEX_FILE" | wc -l)

        echo "  Total   : $total"
        echo "  Valid   : $valid"
        echo "  Revoked : $revoked"
        echo "  Expired : $expired"
    fi

    echo ""
    echo "=== CRL ==="
    if [[ ! -f "$crl_file" ]]; then
        echo "  CRL file not found: $crl_file"
    else
        local last_update next_update crl_days_left
        last_update=$(openssl crl -in "$crl_file" -noout -lastupdate 2>/dev/null | sed 's/^lastUpdate=//')
        next_update=$(openssl crl -in "$crl_file" -noout -nextupdate 2>/dev/null | sed 's/^nextUpdate=//')
        crl_days_left=$(( ( $(date -d "$next_update" +%s) - $(date +%s) ) / 86400 ))

        echo "  Last Update : $last_update"
        echo "  Next Update : $next_update"
        if (( crl_days_left <= 7 )); then
            echo "  Refresh in  : $crl_days_left days  [WARNING: CRL expiring soon]"
        else
            echo "  Refresh in  : $crl_days_left days"
        fi
    fi
}

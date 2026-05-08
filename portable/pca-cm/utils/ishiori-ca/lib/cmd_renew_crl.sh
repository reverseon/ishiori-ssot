# cmd_renew_crl.sh — renew crl command

cmd_renew_crl() {
    local crl_file="${ROOT_CA_DIR}/crl/ca.crl.pem"

    openssl ca \
        -config "${ROOT_CA_DIR}/openssl.cnf" \
        -gencrl \
        -out "$crl_file"

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to regenerate CRL"
        exit 1
    fi

    echo "CRL regenerated: $crl_file"
}

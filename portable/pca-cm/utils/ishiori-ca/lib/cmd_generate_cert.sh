# cmd_generate_cert.sh — generate cert command

cmd_generate_cert() {
    local cn="" no_passphrase=0 mode="" expires_in=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cn) shift; cn="$1" ;;
            --no-passphrase) no_passphrase=1 ;;
            --server)
                [[ -n "$mode" ]] && { echo "Error: --server and --client are mutually exclusive"; exit 1; }
                mode="server_cert"
                ;;
            --client)
                [[ -n "$mode" ]] && { echo "Error: --server and --client are mutually exclusive"; exit 1; }
                mode="usr_cert"
                ;;
            --expires-in) shift; expires_in="$1" ;;
            *) echo "Error: Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    if [[ -z "$cn" ]]; then
        echo "Error: --cn is required"
        usage; exit 1
    fi

    if [[ ! "$cn" =~ ^[a-zA-Z0-9*.\-@]+$ ]]; then
        echo "Error: --cn must contain only alphanumeric characters, dash, star, dot, or @"
        exit 1
    fi

    if [[ -z "$mode" ]]; then
        echo "Error: either --server or --client is required"
        usage; exit 1
    fi

    local key_file="${ROOT_CA_DIR}/private/${cn}.key.pem"
    local cert_file="${ROOT_CA_DIR}/certs/${cn}.cert.pem"
    local ca_cert="${ROOT_CA_DIR}/certs/ca.cert.pem"
    local rand
    rand=$(cat /proc/sys/kernel/random/uuid)
    local csr_file="/tmp/${rand}.csr"
    local ext_file=""

    local key_created=0
    if [[ -f "$key_file" ]]; then
        local reply
        read -r -p "Key already exists: $key_file. Use existing key and generate new cert? [y/N] " reply
        [[ "$reply" != "y" && "$reply" != "Y" ]] && { echo "Aborted."; exit 0; }
    else
        # Step 1: Generate private key
        if [[ "$no_passphrase" -eq 1 ]]; then
            openssl genrsa -out "$key_file" 4096
        else
            openssl genrsa -aes256 -out "$key_file" 4096
        fi

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to generate private key"
            exit 1
        fi

        chmod 400 "$key_file"
        key_created=1
    fi

    # Step 2: Build subject DN from CA cert, replacing CN
    local ca_subject
    ca_subject=$(x509_subject "$ca_cert")

    if [[ -z "$ca_subject" ]]; then
        echo "Error: Failed to read subject from CA cert: $ca_cert"
        [[ "$key_created" -eq 1 ]] && rm -f "$key_file"
        exit 1
    fi

    # Rebuild subject: strip existing CN, prepend new CN
    local new_subject
    new_subject=$(echo "$ca_subject" | sed 's/CN=[^,]*,\{0,1\}//' | sed 's/^,//')
    new_subject="CN=${cn},${new_subject}"

    # Step 2: Generate CSR
    openssl req -new -sha256 \
        -key "$key_file" \
        -subj "/${new_subject//,//}" \
        -out "$csr_file"

    local csr_rc=$?

    if [[ $csr_rc -ne 0 ]]; then
        echo "Error: Failed to generate CSR"
        rm -f "$csr_file"
        [[ "$key_created" -eq 1 ]] && rm -f "$key_file"
        exit 1
    fi

    # Step 3: Sign the CSR
    local sign_cmd=(
        openssl ca
        -config "${ROOT_CA_DIR}/openssl.cnf"
        -notext -md sha256
        -in "$csr_file"
        -out "$cert_file"
        -batch
    )

    if [[ "$mode" == "server_cert" ]]; then
        local san_type san_value
        if [[ "$cn" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            san_type="IP"
        else
            san_type="DNS"
        fi
        san_value="${san_type}:${cn}"

        ext_file="/tmp/${rand}.ext"
        cat > "$ext_file" <<EOF
[ server_cert_san ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "Ishiori.NET Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = ${san_value}
EOF
        sign_cmd+=(-extfile "$ext_file" -extensions server_cert_san)
    else
        sign_cmd+=(-extensions "$mode")
    fi

    [[ -n "$expires_in" ]] && sign_cmd+=(-days "$expires_in")

    "${sign_cmd[@]}"
    local sign_rc=$?

    # Step 4: Always remove CSR and ext file
    rm -f "$csr_file" "$ext_file"

    # Step 5: On failure, remove key only if we created it
    if [[ $sign_rc -ne 0 ]]; then
        echo "Error: Failed to sign certificate"
        [[ "$key_created" -eq 1 ]] && rm -f "$key_file"
        exit 1
    fi

    echo "Certificate written to: $cert_file"
}

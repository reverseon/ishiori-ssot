# cmd_load.sh — load command

cmd_load() {
    if [[ ! -d "$PUBLIC_DIR" ]]; then
        echo "Error: Public directory not found: $PUBLIC_DIR"
        exit 1
    fi

    if [[ ! -d "$PRIVATE_ENC_DIR" ]]; then
        echo "Error: Private encrypted directory not found: $PRIVATE_ENC_DIR"
        exit 1
    fi

    local secret_key
    read -r -s -p "age secret key (AGE-SECRET-KEY-1...): " secret_key
    echo
    if [[ -z "$secret_key" ]]; then
        echo "Error: secret key cannot be empty"
        exit 1
    fi

    local identity_path
    identity_path=$(mktemp /tmp/age-identity-XXXXXX)
    chmod 600 "$identity_path"
    echo "$secret_key" > "$identity_path"
    trap 'rm -f "$identity_path"' EXIT

    local had_error=0

    if [[ ! -d "$ROOT_CA_DIR" ]]; then
        echo "Error: Root CA directory does not exist: $ROOT_CA_DIR"
        echo "Please create it first: mkdir -p $ROOT_CA_DIR"
        echo "Note: if running inside Docker, run this on the host (./data maps to /data in the container):"
        echo "  mkdir -p ./data/root-ca"
        exit 1
    fi

    echo "Clearing $ROOT_CA_DIR..."
    rm -rf \
        "${ROOT_CA_DIR}/certs" \
        "${ROOT_CA_DIR}/crl" \
        "${ROOT_CA_DIR}/newcerts" \
        "${ROOT_CA_DIR}/private" \
        "${ROOT_CA_DIR}/index.txt" \
        "${ROOT_CA_DIR}/index.txt.attr" \
        "${ROOT_CA_DIR}/serial" \
        "${ROOT_CA_DIR}/crlnumber" \
        "${ROOT_CA_DIR}/openssl.cnf"

    echo "Creating directory structure..."
    mkdir -p \
        "${ROOT_CA_DIR}/certs" \
        "${ROOT_CA_DIR}/crl" \
        "${ROOT_CA_DIR}/newcerts" \
        "${ROOT_CA_DIR}/private"
    chmod 700 "${ROOT_CA_DIR}/private"

    echo "Restoring public files..."

    local public_files=(
        "root+index.txt:index.txt"
        "root+index.txt.attr:index.txt.attr"
        "root+serial:serial"
        "root+crlnumber:crlnumber"
        "root+openssl.cnf:openssl.cnf"
        "certs+ca.cert.pem:certs/ca.cert.pem"
        "crl+ca.crl.pem:crl/ca.crl.pem"
    )

    for entry in "${public_files[@]}"; do
        local src="${PUBLIC_DIR}/${entry%%:*}"
        local dst="${ROOT_CA_DIR}/${entry##*:}"
        if [[ ! -f "$src" ]]; then
            echo "  Warning: source not found, skipping: $src"
            continue
        fi
        cp "$src" "$dst" && echo "  Restored: ${entry##*:}" || { echo "  Error: failed to restore ${entry##*:}"; had_error=1; }
    done

    echo "  Extracting newcerts.tar..."
    local newcerts_tar="${PUBLIC_DIR}/newcerts.tar"
    if [[ ! -f "$newcerts_tar" ]]; then
        echo "  Warning: newcerts.tar not found, skipping"
    else
        tar -xf "$newcerts_tar" -C "$ROOT_CA_DIR" \
            && echo "  Restored: newcerts/" \
            || { echo "  Error: failed to extract newcerts.tar"; had_error=1; }
    fi

    echo "Decrypting private keys..."

    local found_keys=0
    for enc_file in "${PRIVATE_ENC_DIR}/private+"*.key.pem.age; do
        [[ -f "$enc_file" ]] || continue
        found_keys=1
        local basename
        basename=$(basename "$enc_file")
        local filename="${basename#private+}"   # strip "private+" prefix
        filename="${filename%.age}"             # strip ".age" suffix
        local dst="${ROOT_CA_DIR}/private/${filename}"

        age --decrypt \
            --identity "$identity_path" \
            --output "$dst" \
            "$enc_file" \
            && chmod 400 "$dst" \
            && echo "  Decrypted: private/${filename}" \
            || { echo "  Error: failed to decrypt $basename"; rm -f "$dst"; had_error=1; }
    done

    [[ "$found_keys" -eq 0 ]] && echo "  Warning: no encrypted keys found in ${PRIVATE_ENC_DIR}/"

    if [[ "$had_error" -eq 1 ]]; then
        echo "Load completed with errors."
        exit 1
    fi

    echo "Load complete."
}

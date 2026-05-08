# cmd_save.sh — save command

cmd_save() {
    if [[ ! -d "$PUBLIC_DIR" ]]; then
        echo "Error: Public directory not found: $PUBLIC_DIR"
        exit 1
    fi

    if [[ ! -d "$PRIVATE_ENC_DIR" ]]; then
        echo "Error: Private encrypted directory not found: $PRIVATE_ENC_DIR"
        exit 1
    fi

    local passphrase
    read -r -s -p "GPG passphrase: " passphrase
    echo

    local had_error=0

    echo "Clearing output directories..."
    rm -f "${PUBLIC_DIR}/"*
    rm -f "${PRIVATE_ENC_DIR}/"*

    echo "Saving public files..."

    local public_files=(
        "index.txt:root+index.txt"
        "index.txt.attr:root+index.txt.attr"
        "serial:root+serial"
        "crlnumber:root+crlnumber"
        "openssl.cnf:root+openssl.cnf"
        "certs/ca.cert.pem:certs+ca.cert.pem"
        "crl/ca.crl.pem:crl+ca.crl.pem"
    )

    for entry in "${public_files[@]}"; do
        local src="${ROOT_CA_DIR}/${entry%%:*}"
        local dst="${PUBLIC_DIR}/${entry##*:}"
        if [[ ! -f "$src" ]]; then
            echo "  Warning: source not found, skipping: $src"
            continue
        fi
        cp "$src" "$dst" && echo "  Saved: $(basename "$dst")" || { echo "  Error: failed to save $dst"; had_error=1; }
    done

    echo "  Archiving newcerts/..."
    tar -cf "${PUBLIC_DIR}/newcerts.tar" -C "$ROOT_CA_DIR" newcerts/ \
        && echo "  Saved: newcerts.tar" \
        || { echo "  Error: failed to archive newcerts/"; had_error=1; }

    echo "Encrypting private keys..."

    local found_keys=0
    for key_file in "${ROOT_CA_DIR}/private/"*.key.pem; do
        [[ -f "$key_file" ]] || continue
        found_keys=1
        local filename
        filename=$(basename "$key_file")
        local dst="${PRIVATE_ENC_DIR}/private+${filename}.asc"

        gpg --batch --yes --symmetric --armor \
            --pinentry-mode loopback \
            --passphrase "$passphrase" \
            --output "$dst" \
            "$key_file" \
            && echo "  Encrypted: private+${filename}.asc" \
            || { echo "  Error: failed to encrypt $filename"; had_error=1; }
    done

    [[ "$found_keys" -eq 0 ]] && echo "  Warning: no private keys found in ${ROOT_CA_DIR}/private/"

    if [[ "$had_error" -eq 1 ]]; then
        echo "Save completed with errors."
        exit 1
    fi

    echo "Save complete."
}

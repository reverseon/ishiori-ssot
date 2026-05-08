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

    local passphrase
    read -r -s -p "GPG passphrase: " passphrase
    echo

    local had_error=0

    if [[ ! -d "$ROOT_CA_DIR" ]]; then
        echo "Error: Root CA directory does not exist: $ROOT_CA_DIR"
        echo "Please create it first: mkdir -p $ROOT_CA_DIR"
        echo "Note: if running inside Docker, run this on the host (./data maps to /data in the container):"
        echo "  mkdir -p ./data/root-ca"
        exit 1
    fi

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
    for enc_file in "${PRIVATE_ENC_DIR}/private+"*.key.pem.asc; do
        [[ -f "$enc_file" ]] || continue
        found_keys=1
        local basename
        basename=$(basename "$enc_file")
        local filename="${basename#private+}"   # strip "private+" prefix
        filename="${filename%.asc}"             # strip ".asc" suffix
        local dst="${ROOT_CA_DIR}/private/${filename}"

        gpg --batch --yes --decrypt \
            --pinentry-mode loopback \
            --passphrase "$passphrase" \
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

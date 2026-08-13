# cmd_generate_ssh.sh — generate ssh command

cmd_generate_ssh() {
    local name="" expiry_in_days=1 principal=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) shift; name="$1" ;;
            --expiry-in-days) shift; expiry_in_days="$1" ;;
            --principal) shift; principal="$1" ;;
            *) echo "Error: Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    if [[ -z "$principal" ]]; then
        echo "Error: --principal is required"
        usage; exit 1
    fi

    [[ -z "$name" ]] && name="${principal}-tmp-key"

    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "Error: --name must contain only alphanumeric characters, dash, underscore, or dot"
        exit 1
    fi

    if [[ ! "$expiry_in_days" =~ ^[0-9]+$ || "$expiry_in_days" -eq 0 ]]; then
        echo "Error: --expiry-in-days must be a positive integer"
        exit 1
    fi

    local ca_key="${ROOT_CA_DIR}/private/ca.key.pem"
    if [[ ! -f "$ca_key" ]]; then
        echo "Error: CA private key not found: $ca_key"
        exit 1
    fi

    local ssh_keys_dir="${SSH_KEYS_DIR:-/data/ssh-keys}"
    mkdir -p "$ssh_keys_dir"

    local key_file="${ssh_keys_dir}/${name}"

    if [[ -f "$key_file" || -f "${key_file}.pub" ]]; then
        local reply
        read -r -p "Key already exists: $key_file. Overwrite? [y/N] " reply
        [[ "$reply" != "y" && "$reply" != "Y" ]] && { echo "Aborted."; exit 0; }
        rm -f "$key_file" "${key_file}.pub" "${key_file}-cert.pub"
    fi

    # Step 1: Generate the client keypair
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "$name" -q
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to generate SSH keypair"
        exit 1
    fi

    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"

    # Step 2: Sign the public key with the CA private key
    ssh-keygen -s "$ca_key" \
        -I "${name}-$(date +%Y%m%d-%H%M%S)" \
        -n "$principal" \
        -V "+${expiry_in_days}d" \
        "${key_file}.pub"

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to sign SSH public key"
        rm -f "$key_file" "${key_file}.pub"
        exit 1
    fi

    echo "SSH private key written to: ${key_file}"
    echo "SSH public key written to:  ${key_file}.pub"
    echo "SSH certificate written to: ${key_file}-cert.pub"
}

#! /bin/bash

# Global Variable
ROOT_CA_DIR="${ROOT_CA_DIR:-/data/root-ca}"
INDEX_FILE="${ROOT_CA_DIR}/index.txt"
NEWCERTS_DIR="${ROOT_CA_DIR}/newcerts"
PUBLIC_DIR="${PUBLIC_DIR:-/public}"
PRIVATE_ENC_DIR="${PRIVATE_ENC_DIR:-/private-encrypted}"

LIB_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib"
source "${LIB_DIR}/helpers/parse.sh"
source "${LIB_DIR}/helpers/dn.sh"
source "${LIB_DIR}/helpers/x509.sh"
source "${LIB_DIR}/cmd_generate_cert.sh"
source "${LIB_DIR}/cmd_revoke_cert.sh"
source "${LIB_DIR}/cmd_renew_crl.sh"
source "${LIB_DIR}/cmd_save.sh"
source "${LIB_DIR}/cmd_load.sh"
source "${LIB_DIR}/cmd_view_cert_list.sh"
source "${LIB_DIR}/cmd_view_cert_show.sh"
source "${LIB_DIR}/cmd_view_ca_status.sh"

usage() {
    echo "Usage: ishiori-ca <command> [options]"
    echo ""
    echo "Commands:"
    echo "  generate cert --cn <cn> --server|--client  Generate and sign a certificate"
    echo "    --no-passphrase                           Generate private key without passphrase"
    echo "    --expires-in <days>                       Certificate validity in days (default: CA config)"
    echo ""
    echo "  view cert list               List all certificates from CA database"
    echo "    --valid                    Show only valid certificates"
    echo "    --revoked                  Show only revoked certificates"
    echo "    --filter <text>            Filter by Common Name (case-insensitive substring)"
    echo "    --sort-by <field>          Sort descending by: serial (default), expiry, revoked-date"
    echo ""
    echo "  view cert show --serial <serial>   View certificate details by serial number"
    echo "  view cert show --cn <CN>           View certificate details by Common Name"
    echo "    --short                          Show only important fields (subject, issuer, validity, SANs)"
    echo ""
    echo "  view ca status                     Show CA certificate info, database summary, and CRL status"
    echo ""
    echo "  revoke cert --cn <cn>              Revoke a certificate by Common Name"
    echo "  revoke cert --serial <serial>      Revoke a certificate by serial number"
    echo "    --reason <reason>                Revocation reason (default: cessationOfOperation)"
    echo ""
    echo "  renew crl                          Regenerate the Certificate Revocation List"
    echo ""
    echo "  save                               Save CA files to public/ and encrypt private keys to private-encrypted/"
    echo "  load                               Restore CA files from public/ and decrypt private keys from private-encrypted/"
}

# Main
case "$1" in
    generate)
        shift
        case "$1" in
            cert) shift; cmd_generate_cert "$@" ;;
            *)
                echo "Unknown generate subcommand: $1"
                usage
                exit 1
                ;;
        esac
        ;;
    save) shift; cmd_save "$@" ;;
    load) shift; cmd_load "$@" ;;
    renew)
        shift
        case "$1" in
            crl) shift; cmd_renew_crl "$@" ;;
            *)
                echo "Unknown renew subcommand: $1"
                usage
                exit 1
                ;;
        esac
        ;;
    revoke)
        shift
        case "$1" in
            cert) shift; cmd_revoke_cert "$@" ;;
            *)
                echo "Unknown revoke subcommand: $1"
                usage
                exit 1
                ;;
        esac
        ;;
    view)
        shift
        case "$1" in
            cert)
                shift
                case "$1" in
                    list)  shift; cmd_view_cert_list "$@" ;;
                    show)  shift; cmd_view_cert_show "$@" ;;
                    *)
                        echo "Unknown cert subcommand: $1"
                        usage
                        exit 1
                        ;;
                esac
                ;;
            ca)
                shift
                case "$1" in
                    status) shift; cmd_view_ca_status "$@" ;;
                    *)
                        echo "Unknown ca subcommand: $1"
                        usage
                        exit 1
                        ;;
                esac
                ;;
            *)
                echo "Unknown view target: $1"
                usage
                exit 1
                ;;
        esac
        ;;
    *)
        usage
        exit 1
        ;;
esac

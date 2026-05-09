# pca-cm

Private CA Certificate Manager. A Dockerized bash CLI for managing a self-hosted root CA — issuing, revoking, and maintaining certificates without exposing private keys.

## Layout

| Path | Purpose |
|---|---|
| `public/` | CA database, config, and cert files (safe to commit) |
| `private-encrypted/` | age-encrypted private keys (safe to commit) |
| `data/` | Live CA working directory (mounted into container, **do not commit**) |

## Usage

```bash
PUID=$(id -u) PGID=$(id -g) docker compose run pca-cm
```

Inside the container, use `ishiori-ca`:

```
ishiori-ca load                              # restore CA from public/ and private-encrypted/
ishiori-ca generate cert --cn <cn> --server  # issue a server cert (SAN inferred from CN)
ishiori-ca generate cert --cn <cn> --client  # issue a client cert
ishiori-ca view cert list                    # list all certs
ishiori-ca view cert show --cn <cn>          # show cert details
ishiori-ca view ca status                    # CA health summary
ishiori-ca revoke cert --cn <cn>             # revoke a cert (regenerates CRL)
ishiori-ca renew crl                         # regenerate CRL
ishiori-ca save                              # persist CA state back to public/ and private-encrypted/
```

Run `ishiori-ca` with no arguments for full usage.

## Backup model

`save` flattens CA files into `public/` (plaintext) and encrypts private keys into `private-encrypted/` with an age public key. Both directories are designed to be committed to git. `load` reverses this — reconstruct the live CA on any machine by providing the corresponding age secret key.

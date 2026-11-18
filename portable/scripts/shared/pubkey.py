"""Load the admin public key: from a local file when given, otherwise downloaded from the configured URL."""

import urllib.request


def load_pubkey(url: str, local_file: str, error_cls: type = RuntimeError) -> str:
    """A local file (ADMIN_PUBKEY_FILE) wins, so the run works offline; a failed download names that escape hatch."""
    if local_file:
        try:
            with open(local_file, encoding="utf-8") as f:
                return f.read()
        except OSError as exc:
            raise error_cls(f"Cannot read admin public key file {local_file}: {exc}") from exc
    try:
        with urllib.request.urlopen(url, timeout=30) as response:  # downloaded now, installed later
            return response.read().decode("utf-8")
    except (OSError, ValueError) as exc:  # URLError, timeouts and HTTPError are all OSError
        raise error_cls(
            f"Could not download the admin public key from {url}: {exc}\n"
            "Offline? Copy the key to this machine and re-run with ADMIN_PUBKEY_FILE=/path/to/key.pub "
            "(after sudo, like the other overrides).") from exc

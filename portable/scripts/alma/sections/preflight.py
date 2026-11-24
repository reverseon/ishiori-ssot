"""Every input check runs here, before the first change to the system, so a bad value aborts a clean run."""

import os
import socket
import subprocess
import tempfile
from dataclasses import replace

import netcheck
from actions import out
from base_config import infer_hostname
from config import Config
from pubkey import load_pubkey


class PreflightError(RuntimeError):
    pass


def live_dns(iface: str) -> list[str]:
    return out("nmcli", "-g", "IP4.DNS", "device", "show", iface).replace(",", " ").split()


def _live_connection(iface: str) -> str:
    name = out("nmcli", "-g", "GENERAL.CONNECTION", "device", "show", iface)
    return "" if name in ("", "--") else name


def resolve_network(c: Config) -> Config:
    """The shared decision (netcheck), plus the NetworkManager connection that DNS-only changes apply to."""
    c = netcheck.resolve_network(c, live_dns, PreflightError)
    if c.net_action != "dns":
        return c
    conn = _live_connection(c.static_iface)
    if not conn:
        raise PreflightError(f"No active NetworkManager connection on {c.static_iface} to set DNS on")
    return replace(c, net_connection=conn)


def check_pubkey(key_text: str) -> None:
    """sshd accepts only ed25519 and password auth is off, so any other key type would lock the admin out."""
    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write(key_text)
    try:
        result = subprocess.run(["ssh-keygen", "-l", "-f", f.name], text=True, capture_output=True)
    finally:
        os.unlink(f.name)
    info = result.stdout.strip()
    if result.returncode != 0 or not info or any(not line.endswith("(ED25519)") for line in info.splitlines()):
        raise PreflightError(f"Admin public key must be ssh-ed25519 only, got:\n{info or result.stderr.strip()}")


def run(c: Config) -> Config:
    """Return the config with network values resolved and the validated admin public key loaded."""
    c = infer_hostname(c, socket.gethostname(), PreflightError)
    c = resolve_network(c)
    key_text = load_pubkey(c.admin_pubkey_url, c.admin_pubkey_file, PreflightError)
    check_pubkey(key_text)
    return replace(c, admin_pubkey=key_text)

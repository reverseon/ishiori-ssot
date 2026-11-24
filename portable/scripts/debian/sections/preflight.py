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


def check_os(path: str = "/etc/os-release") -> None:
    """This script targets Debian 13 only: apt, netplan, pam-auth-update and the service names are not portable."""
    fields = {}
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        for line in lines:
            key, sep, value = line.partition("=")
            if sep:
                fields[key] = value.strip().strip('"')
    except OSError as exc:
        raise PreflightError(f"Cannot read {path}: {exc}") from exc
    if fields.get("ID") != "debian" or fields.get("VERSION_ID") != "13":
        raise PreflightError(
            f"This script targets Debian 13, found {fields.get('PRETTY_NAME') or fields.get('ID') or 'unknown'}")


def live_dns(iface: str) -> list[str]:
    """resolvectl prints 'Link N (iface): server server'; no servers gives an empty list."""
    _, _, servers = out("resolvectl", "dns", iface).partition(":")
    return servers.split()


def resolve_network(c: Config) -> Config:
    return netcheck.resolve_network(c, live_dns, PreflightError)


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
    check_os()
    c = infer_hostname(c, socket.gethostname(), PreflightError)
    c = resolve_network(c)
    key_text = load_pubkey(c.admin_pubkey_url, c.admin_pubkey_file, PreflightError)
    check_pubkey(key_text)
    return replace(c, admin_pubkey=key_text)

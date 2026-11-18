"""Every input check runs here, before the first change to the system, so a bad value aborts a clean run."""

import json
import os
import re
import subprocess
import tempfile
from dataclasses import replace

from actions import sh
from config import Config
from netcheck import check_static_network
from pubkey import load_pubkey

CIDR_RE = re.compile(r"^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$")


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


def _default_route(*extra: str) -> dict:
    routes = json.loads(sh("ip", "-j", "-4", "route", "show", "default", *extra).stdout or "[]")
    return routes[0] if routes else {}


def resolve_network(c: Config) -> Config:
    """Validate STATIC_IP and fill in the interface and gateway of the current default route when unset."""
    if not c.static_ip:
        return c
    if not CIDR_RE.match(c.static_ip):
        raise PreflightError(f"STATIC_IP must be IPv4 CIDR (e.g. 192.168.1.50/24), got: {c.static_ip}")
    iface = c.static_iface or _default_route().get("dev", "")
    if not iface:
        raise PreflightError("Could not detect the default-route interface, set STATIC_IFACE")
    gateway = c.static_gateway or _default_route("dev", iface).get("gateway", "")
    if not gateway:
        raise PreflightError(f"Could not detect the default gateway on {iface}, set STATIC_GATEWAY")
    check_static_network(c.static_ip, iface, gateway, PreflightError)
    return replace(c, static_iface=iface, static_gateway=gateway)


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
    c = resolve_network(c)
    key_text = load_pubkey(c.admin_pubkey_url, c.admin_pubkey_file, PreflightError)
    check_pubkey(key_text)
    return replace(c, admin_pubkey=key_text)

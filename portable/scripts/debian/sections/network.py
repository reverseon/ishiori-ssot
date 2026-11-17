"""Static IPv4 through netplan (systemd-networkd renderer). Activated as the very last step of the whole
script: the address change drops an SSH session on the old address, so nothing may run after it."""

import json

import texts
from actions import Cmd, WriteFile, out
from config import MIDFIX, Config


def write(c: Config):
    if not c.static_ip:
        return []
    return [
        # netplan warns about (and newer versions refuse) config files that are readable by others
        WriteFile(
            path=c.netplan_conf,
            text=texts.netplan_yaml(c),
            mode=0o600,
        ),
        # Parses every netplan file and renders the backend config, without applying anything
        Cmd(
            name="netplan generate",
            argv=["netplan", "generate"],
        ),
    ]


def _active(c: Config) -> bool:
    """The wanted address is configured on the interface."""
    addresses = json.loads(out("ip", "-j", "-4", "addr", "show", "dev", c.static_iface) or "[]")
    wanted = c.static_ip.split("/")[0]
    return any(a.get("local") == wanted for entry in addresses for a in entry.get("addr_info", []))


def activate(c: Config):
    """Delayed via a transient systemd unit so the script exits cleanly first."""
    if not c.static_ip:
        return []
    return [
        Cmd(
            name=f"netplan apply in {c.static_apply_delay} (an SSH session on the old address will drop)",
            argv=[
                "systemd-run",
                f"--unit={MIDFIX}-static-ip-apply",
                f"--on-active={c.static_apply_delay}",
                "netplan", "apply",
            ],
            done=lambda: _active(c),
        ),
    ]

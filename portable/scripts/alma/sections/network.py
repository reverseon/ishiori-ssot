"""Static IPv4 as a NetworkManager keyfile. Written before AIDE (so the baseline includes it) but
activated as the very last step of the whole script: the address change drops an SSH session on the
old address, so nothing may run after it."""

import texts
from actions import Cmd, WriteFile, out
from config import MIDFIX, Config


def write(c: Config):
    if not c.static_ip:
        return []
    return [
        WriteFile(
            path=c.nm_conf,
            text=texts.nm_keyfile(c),
            mode=0o600,
            relabel=True,
        ),
        Cmd(
            name="reload NetworkManager",
            argv=["nmcli", "connection", "reload"],
        ),
    ]


def _active(c: Config) -> bool:
    return c.nm_connection in out("nmcli", "-t", "-f", "NAME", "connection", "show", "--active").splitlines()


def activate(c: Config):
    """Delayed via a transient systemd unit so the script exits cleanly first."""
    if not c.static_ip:
        return []
    return [
        Cmd(
            name=f"activate {c.nm_connection} in {c.static_apply_delay} (an SSH session on the old address will drop)",
            argv=[
                "systemd-run",
                f"--unit={MIDFIX}-static-ip-apply",
                f"--on-active={c.static_apply_delay}",
                "nmcli", "connection", "up", c.nm_connection,
            ],
            done=lambda: _active(c),
        ),
    ]

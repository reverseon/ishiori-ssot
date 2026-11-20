"""The network change decided by preflight.resolve_network. A static address is written as a NetworkManager keyfile;
a DNS-only change is applied to the live connection and leaves the address alone. Both are written before AIDE (so
the baseline includes them). A static address is activated as the very last step of the whole script: the address
change drops an SSH session on the old address, so nothing may run after it."""

import texts
from actions import Cmd, WriteFile, out
from config import MIDFIX, Config


def _wanted_dns(c: Config) -> list[str]:
    return sorted(c.static_dns.split())


def _configured_dns(c: Config) -> bool:
    """The connection's ipv4.dns holds the wanted servers."""
    return sorted(out("nmcli", "-g", "ipv4.dns", "connection", "show", c.net_connection).replace(",", " ").split()) \
        == _wanted_dns(c)


def _applied_dns(c: Config) -> bool:
    """The device is using the wanted servers."""
    return sorted(out("nmcli", "-g", "IP4.DNS", "device", "show", c.static_iface).replace(",", " ").split()) \
        == _wanted_dns(c)


def write(c: Config):
    if c.net_action == "static":
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
    if c.net_action == "dns":
        return [
            Cmd(
                name=f"set DNS on {c.net_connection} to {c.static_dns}",
                argv=["nmcli", "connection", "modify", c.net_connection,
                      "ipv4.dns", ",".join(c.static_dns.split()),
                      # DHCP-supplied DNS would be merged in otherwise
                      "ipv4.ignore-auto-dns", "yes" if c.net_dhcp else "no"],
                done=lambda: _configured_dns(c),
            ),
        ]
    return []


def _active(c: Config) -> bool:
    return c.nm_connection in out("nmcli", "-t", "-f", "NAME", "connection", "show", "--active").splitlines()


def activate(c: Config):
    if c.net_action == "dns":
        # No address change, so nothing to delay: re-apply the DNS to the device directly
        return [
            Cmd(
                name=f"apply DNS on {c.static_iface} (address unchanged)",
                argv=["nmcli", "device", "reapply", c.static_iface],
                done=lambda: _applied_dns(c),
            ),
        ]
    if c.net_action == "static":
        # Delayed via a transient systemd unit so the script exits cleanly first
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
                # The change lands after this script has exited, so there is nothing to verify here
                verify_after_run=False,
            ),
        ]
    return []

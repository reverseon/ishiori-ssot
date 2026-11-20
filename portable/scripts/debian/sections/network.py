"""The network change decided by preflight.resolve_network, through netplan (systemd-networkd renderer). A static
address goes in 90-, the nameservers in 91- (merged over it and the cloud-init profile). A DNS-only change writes only
91- and leaves the address alone. A static address is activated as the very last step of the whole script: the
address change drops an SSH session on the old address, so nothing may run after it."""

import json

import texts
from actions import Cmd, WriteFile, out
from config import MIDFIX, Config


def write(c: Config):
    if c.net_action not in ("static", "dns"):
        return []
    files = []
    if c.net_action == "static":
        # netplan warns about (and newer versions refuse) config files that are readable by others
        files.append(WriteFile(path=c.netplan_conf, text=texts.netplan_yaml(c), mode=0o600))
    # Written in both modes so a stale nameserver file from an earlier run cannot override the current DNS
    files.append(WriteFile(path=c.netplan_dns_conf, text=texts.netplan_dns_yaml(c), mode=0o600))
    return files + [
        # Parses every netplan file and renders the backend config, without applying anything
        Cmd(
            name="netplan generate",
            argv=["netplan", "generate"],
        ),
    ]


def _active(c: Config) -> bool:
    """The whole wanted config is live: address (static, not a DHCP lease), default route via the gateway, and every
    DNS server on the link. The address alone is not enough, it may come from another network manager (ifupdown)
    that sets no DNS; and a DHCP lease on the same address is not the static config, so it must not count."""
    addresses = json.loads(out("ip", "-j", "-4", "addr", "show", "dev", c.static_iface) or "[]")
    wanted = c.static_ip.split("/")[0]
    if not any(a.get("local") == wanted and not a.get("dynamic")
               for entry in addresses for a in entry.get("addr_info", [])):
        return False
    routes = json.loads(out("ip", "-j", "-4", "route", "show", "default", "dev", c.static_iface) or "[]")
    if not any(r.get("gateway") == c.static_gateway for r in routes):
        return False
    live_dns = out("resolvectl", "dns", c.static_iface).partition(":")[2].split()
    return all(d in live_dns for d in c.static_dns.split())


def _applied_dns(c: Config) -> bool:
    """resolved is using the wanted servers on this link."""
    _, _, servers = out("resolvectl", "dns", c.static_iface).partition(":")
    return sorted(servers.split()) == sorted(c.static_dns.split())


def activate(c: Config):
    if c.net_action == "dns":
        # No address change, so nothing to delay
        return [
            Cmd(
                name=f"netplan apply for DNS on {c.static_iface} (address unchanged)",
                argv=["netplan", "apply"],
                done=lambda: _applied_dns(c),
            ),
        ]
    if c.net_action == "static":
        # Delayed via a transient systemd unit so the script exits cleanly first
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
                # The change lands after this script has exited, so there is nothing to verify here
                verify_after_run=False,
            ),
        ]
    return []

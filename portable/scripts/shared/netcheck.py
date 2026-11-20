"""Network settings shared by both distros: checks on STATIC_* values, and the decision of what to change.

A value left unset keeps its live setting. Nothing is written unless STATIC_IP, STATIC_GATEWAY, STATIC_DNS or
STATIC_IFACE is set. STATIC_IP or STATIC_GATEWAY makes the address static (a DHCP address is frozen as it is);
STATIC_DNS alone changes only the DNS and leaves the address, DHCP or static, as it is.
"""

import ipaddress
import json
import logging
import os
import re
from dataclasses import replace
from typing import Callable, TypeVar

from base_actions import out, sh

C = TypeVar("C")

CIDR_RE = re.compile(r"^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$")


def check_static_network(static_ip: str, iface: str, gateway: str, error_cls: type = RuntimeError) -> None:
    """The generated config describes a plain ethernet with an on-link gateway; refuse anything else up front."""
    if any(os.path.exists(f"/sys/class/net/{iface}/{kind}") for kind in ("bridge", "bonding")):
        raise error_cls(
            f"{iface} is a bridge/bond, but the config written here describes a plain ethernet. "
            f"Set STATIC_IFACE to the physical NIC, or manage {iface} yourself and leave STATIC_IP unset")
    network = ipaddress.ip_interface(static_ip).network
    if ipaddress.ip_address(gateway) not in network:
        raise error_cls(
            f"Gateway {gateway} is outside {network} (from STATIC_IP {static_ip}), "
            f"fix STATIC_GATEWAY or the prefix length")


def is_cidr(value: str) -> bool:
    """Shape and octet range: the regex alone accepts 192.168.1.300/24."""
    if not CIDR_RE.match(value):
        return False
    try:
        ipaddress.IPv4Interface(value)
    except ValueError:
        return False
    return True


def check_ipv4(value: str, name: str, error_cls: type = RuntimeError) -> None:
    try:
        ipaddress.IPv4Address(value)
    except ValueError:
        raise error_cls(f"{name} must be an IPv4 address, got: {value}") from None


def default_route(*extra: str) -> dict:
    routes = json.loads(sh("ip", "-j", "-4", "route", "show", "default", *extra).stdout or "[]")
    return routes[0] if routes else {}


def live_ipv4(iface: str) -> dict:
    """First IPv4 address on iface as iproute2 reports it (local, prefixlen, dynamic); {} if none."""
    for entry in json.loads(out("ip", "-j", "-4", "addr", "show", "dev", iface) or "[]"):
        for addr in entry.get("addr_info", []):
            return addr
    return {}


def resolve_network(c: C, live_dns: Callable[[str], list[str]], error_cls: type = RuntimeError) -> C:
    """Decide the network change for config c. live_dns(iface) gives the DNS servers in use on iface."""
    if not any((c.static_ip, c.static_gateway, c.static_dns, c.static_iface)):
        return c
    if c.static_ip and not is_cidr(c.static_ip):
        raise error_cls(f"STATIC_IP must be IPv4 CIDR (e.g. 192.168.1.50/24), got: {c.static_ip}")
    if c.static_gateway:
        check_ipv4(c.static_gateway, "STATIC_GATEWAY", error_cls)
    for server in c.static_dns.split():
        check_ipv4(server, "STATIC_DNS", error_cls)
    iface = c.static_iface or default_route().get("dev", "")
    if not iface:
        raise error_cls("Could not detect the default-route interface, set STATIC_IFACE")
    if c.static_ip or c.static_gateway:
        return _static_address(c, iface, live_dns, error_cls)
    if c.static_dns:
        return replace(c, static_iface=iface, net_action="dns", net_dhcp=bool(live_ipv4(iface).get("dynamic")))
    logging.warning("STATIC_IFACE alone changes nothing; set STATIC_IP, STATIC_GATEWAY or STATIC_DNS as well")
    return replace(c, static_iface=iface)


def _static_address(c: C, iface: str, live_dns: Callable[[str], list[str]], error_cls: type) -> C:
    live = live_ipv4(iface)
    if c.static_ip:
        ip = c.static_ip
    elif live:
        ip = f"{live['local']}/{live['prefixlen']}"
        if live.get("dynamic"):
            logging.warning("STATIC_IP not set: the current DHCP address %s on %s becomes a static address", ip, iface)
    else:
        raise error_cls(f"{iface} has no IPv4 address to keep, set STATIC_IP")
    gateway = c.static_gateway or default_route("dev", iface).get("gateway", "")
    if not gateway:
        raise error_cls(f"Could not detect the default gateway on {iface}, set STATIC_GATEWAY")
    check_static_network(ip, iface, gateway, error_cls)
    dns = c.static_dns or " ".join(live_dns(iface))
    if not dns:
        logging.warning("No DNS servers set or found on %s: the static config will have none", iface)
    return replace(c, static_iface=iface, static_ip=ip, static_gateway=gateway, static_dns=dns, net_action="static")

"""Sanity checks on STATIC_* values, shared by both distros' preflight."""

import ipaddress
import os


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

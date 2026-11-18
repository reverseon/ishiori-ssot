"""Settings of alma-setup: the shared ones (shared/base_config.py) plus the AlmaLinux specifics.

Run-time overrides come from the environment (put them AFTER sudo, which resets it):
    sudo SYSTEM_HOSTNAME=foo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 python3 alma-setup/main.py
Everything else is plain configuration: edit it in place.
"""

from __future__ import annotations

from dataclasses import dataclass

from base_config import MIDFIX, Config as BaseConfig  # noqa: F401  (MIDFIX is re-exported for the sections)


@dataclass(frozen=True)
class Config(BaseConfig):
    keymap: str = "jp106"     # console keymap (Japanese JIS); empty keeps the current one
    admin_group: str = "wheel"

    # --- network ---
    nm_priority: int = 100  # above the stock profile (0) so this one wins

    # --- authselect ---
    authselect_profile: str = "local"
    authselect_features: tuple[str, ...] = ("without-nullok", "with-faillock")

    packages: tuple[str, ...] = (
        "curl", "wget", "git", "vim-enhanced", "htop", "tmux", "gcc", "make", "python3", "python3-pip",
        "qemu-guest-agent", "nftables", "dnf-automatic", "dnf-plugins-core", "audit", "audit-rules",
        "chrony", "cronie", "at", "rsyslog", "logrotate",
    )

    dnf_dropin_dir: str = "/etc/systemd/system/dnf-automatic.service.d"

    # --- derived: hostname ---
    @property
    def static_hostname(self) -> str:
        """The FQDN if there is one (RHEL convention), else the short name."""
        return self.fqdn or self.hostname

    @property
    def hosts_line(self) -> str:
        return f"127.0.1.1 {' '.join(f'{self.fqdn} {self.hostname}'.split())} {self.hosts_marker}"

    # --- derived: paths ---
    @property
    def nm_conf(self) -> str:
        return f"/etc/NetworkManager/system-connections/{MIDFIX}-static.nmconnection"

    @property
    def nm_connection(self) -> str:
        return f"{MIDFIX}-static"

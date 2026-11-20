"""Settings of debian-setup: the shared ones (shared/base_config.py) plus the Debian specifics.

Run-time overrides come from the environment (put them AFTER sudo, which resets it):
    sudo SYSTEM_HOSTNAME=foo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 python3 debian/main.py
Everything else is plain configuration: edit it in place.
"""

from __future__ import annotations

from dataclasses import dataclass

from base_config import MIDFIX, Config as BaseConfig, env_help  # noqa: F401  (MIDFIX is re-exported for the sections)

# Shown by `main.py --help`. Keep in step with the config fields and from_env in base_config.py.
ENV_HELP = env_help("XKB layout (default: jp); empty keeps the current one")


@dataclass(frozen=True)
class Config(BaseConfig):
    keymap: str = "jp"        # XKB layout for console and X11 (Japanese); empty keeps the current one
    keyboard_model: str = "jp106"  # XKB model (Japanese JIS 106-key)
    admin_group: str = "sudo"

    packages: tuple[str, ...] = (
        "sudo", "openssh-server", "iproute2", "procps", "netplan.io", "systemd-resolved", "nftables",
        "keyboard-configuration", "console-setup", "unattended-upgrades", "needrestart",
        "curl", "wget", "git", "vim", "htop", "tmux", "gcc", "make", "python3", "python3-pip",
        "qemu-guest-agent", "auditd", "chrony", "cron", "at", "rsyslog", "logrotate",
    )

    apt_dropin_dir: str = "/etc/systemd/system/apt-daily-upgrade.service.d"

    # --- derived: hostname ---
    @property
    def static_hostname(self) -> str:
        """The short name (Debian convention: /etc/hostname is not the FQDN; the FQDN lives in /etc/hosts)."""
        return self.hostname or self.fqdn.partition(".")[0]

    @property
    def hosts_line(self) -> str:
        return f"127.0.1.1 {' '.join(f'{self.fqdn} {self.static_hostname}'.split())} {self.hosts_marker}"

    # --- derived: paths ---
    @property
    def netplan_conf(self) -> str:
        # 90- sorts after cloud-init's 50-cloud-init.yaml, so these values win over the DHCP profile
        return f"/etc/netplan/90-{MIDFIX}-static.yaml"

    @property
    def netplan_dns_conf(self) -> str:
        # 91- merges over 90- and the cloud-init profile: nameservers only, so the address config is left alone
        return f"/etc/netplan/91-{MIDFIX}-dns.yaml"

    @property
    def keyboard_conf(self) -> str:
        return "/etc/default/keyboard"

    @property
    def pam_faillock_preauth(self) -> str:
        return f"{MIDFIX}-faillock-preauth"

    @property
    def pam_faillock_authfail(self) -> str:
        return f"{MIDFIX}-faillock-authfail"

    @property
    def unattended_conf(self) -> str:
        return f"/etc/apt/apt.conf.d/52{MIDFIX}-unattended-upgrades"

    @property
    def nft_main_conf(self) -> str:
        return "/etc/nftables.conf"

"""All settings of alma-setup in one place (the variable block of the bash script).

Run-time overrides come from the environment (put them AFTER sudo, which resets it):
    sudo SYSTEM_HOSTNAME=foo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 python3 alma-setup/main.py
Everything else is plain configuration: edit it in place.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

MIDFIX = "from-setup"


@dataclass(frozen=True)
class Config:
    # --- run-time overrides (see from_env) ---
    hostname: str = ""        # short name; used for the /etc/hosts alias and to derive fqdn
    domain: str = ""
    fqdn: str = ""            # derived as <lowercased hostname>.<domain> when both are set
    static_ip: str = ""       # IPv4 CIDR; empty keeps the current network config
    static_gateway: str = ""  # empty = gateway of the current default route
    static_dns: str = ""      # space-separated
    static_iface: str = ""    # empty = interface of the current default route
    prune_dry_run: bool = False
    sudo_user: str = ""       # never pruned
    admin_pubkey: str = ""    # filled in by preflight

    # --- accounts ---
    admin_user: str = "devola"
    service_user: str = "popola"
    admin_group: str = "wheel"
    admin_shell: str = "/bin/bash"
    service_shell: str = "/usr/sbin/nologin"
    service_comment: str = "Service Account"
    # Pre-hashed passwords. Generate with: openssl passwd -6 'your_password_here'
    root_password_hash: str = "$6$N2iKTCTMzAmc51w4$Ohp2YKKOQbHmGezRtJSJYg1BdsirMy70L4mUjRg/o5M9xSj45UHf.2w.CHTcSmCh4c2KsrDxnEhoYj3RsQCb71" # intentional, password is high entropy.
    admin_password_hash: str = "$6$TsJ5LrQMrfwVrUJi$pdbXq3DnZZ1e6PJy8ex.xesPUHmWzmuth5RhWlSrKzYKe1jsrvaWrIidZLOD7AwJZuVMNKAIbTuNlf85H4.oU." # intentional, password is high entropy.
    admin_pubkey_url: str = "https://raw.githubusercontent.com/reverseon/ishiori-ssot/refs/heads/main/portable/files/ishiori-master-key.pub"

    # --- sudo / su ---
    sudo_log: str = "/var/log/sudo.log"
    su_bin: str = "/usr/bin/su"
    su_mode: int = 0o4750  # group-owned, setuid kept, other users get no execute

    # --- ssh ---
    ssh_port: int = 22

    # --- network ---
    nm_priority: int = 100  # above the stock profile (0) so this one wins
    static_apply_delay: str = "5s"

    # --- attack surface ---
    masked_services: tuple[str, ...] = ("cups", "avahi-daemon", "bluetooth")
    # squashfs (snap, AppImage, container tooling) and udf (Azure and hypervisor config disks) are deliberately not listed
    blacklisted_modules: tuple[str, ...] = ("usb-storage", "cramfs", "freevxfs", "hfs", "hfsplus", "jffs2")
    shm_remount_opts: str = "noexec,nosuid,nodev"

    # --- authselect ---
    authselect_profile: str = "local"
    authselect_features: tuple[str, ...] = ("without-nullok", "with-faillock")

    packages: tuple[str, ...] = (
        "curl", "wget", "git", "vim-enhanced", "htop", "tmux", "gcc", "make", "python3", "python3-pip",
        "qemu-guest-agent", "nftables", "dnf-automatic", "dnf-plugins-core", "audit", "audit-rules",
        "chrony", "aide", "cronie", "at", "rsyslog", "logrotate",
    )

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Config":
        env = os.environ if env is None else env
        hostname, domain, fqdn = env.get("SYSTEM_HOSTNAME", ""), env.get("SYSTEM_DOMAIN", ""), env.get("SYSTEM_FQDN", "")
        if not fqdn and hostname and domain:
            fqdn = f"{hostname.lower()}.{domain}"
        return cls(
            hostname=hostname, domain=domain, fqdn=fqdn,
            static_ip=env.get("STATIC_IP", ""), static_gateway=env.get("STATIC_GATEWAY", ""),
            static_dns=env.get("STATIC_DNS", ""), static_iface=env.get("STATIC_IFACE", ""),
            prune_dry_run=env.get("PRUNE_DRY_RUN", "0") == "1",
            sudo_user=env.get("SUDO_USER", ""),
        )

    # --- derived: hostname ---
    @property
    def static_hostname(self) -> str:
        """The FQDN if there is one (RHEL convention), else the short name."""
        return self.fqdn or self.hostname

    @property
    def hosts_file(self) -> str:
        return "/etc/hosts"

    @property
    def hosts_marker(self) -> str:
        return f"# {MIDFIX}-hostname"

    @property
    def hosts_line(self) -> str:
        return f"127.0.1.1 {' '.join(f'{self.fqdn} {self.hostname}'.split())} {self.hosts_marker}"

    # --- derived: paths (all named after MIDFIX so they are recognisably ours) ---
    @property
    def nm_conf(self) -> str:
        return f"/etc/NetworkManager/system-connections/{MIDFIX}-static.nmconnection"

    @property
    def nm_connection(self) -> str:
        return f"{MIDFIX}-static"

    @property
    def ssh_conf(self) -> str:
        # 00- prefix: sshd keeps the first value per option, so this must sort before the other drop-ins
        return f"/etc/ssh/sshd_config.d/00-{MIDFIX}-ssh.conf"

    @property
    def ssh_banner(self) -> str:
        return f"/etc/ssh/banner-{MIDFIX}.net"

    @property
    def admin_ssh_dir(self) -> str:
        return f"/home/{self.admin_user}/.ssh"

    @property
    def admin_authorized_keys(self) -> str:
        return f"{self.admin_ssh_dir}/authorized_keys"

    @property
    def sudoers_dir(self) -> str:
        return "/etc/sudoers.d"

    @property
    def sudo_conf(self) -> str:
        return f"{self.sudoers_dir}/99-{MIDFIX}-sudo"

    @property
    def admin_sudoers_conf(self) -> str:
        return f"{self.sudoers_dir}/99-{MIDFIX}-{self.admin_user}"

    @property
    def service_sudoers_conf(self) -> str:
        return f"{self.sudoers_dir}/99-{MIDFIX}-{self.service_user}"

    @property
    def cron_allowed_users(self) -> tuple[str, str]:
        return (self.admin_user, self.service_user)

    # su guard
    @property
    def su_guard_bin(self) -> str:
        return f"/usr/local/sbin/{MIDFIX}-su-guard"

    @property
    def su_guard_service(self) -> str:
        return f"{MIDFIX}-su-guard.service"

    @property
    def su_guard_path(self) -> str:
        return f"{MIDFIX}-su-guard.path"

    @property
    def su_guard_timer(self) -> str:
        return f"{MIDFIX}-su-guard.timer"

    # logging
    @property
    def nft_log(self) -> str:
        return f"/var/log/nftables-{MIDFIX}.log"

    @property
    def popola_log(self) -> str:
        return f"/var/log/popola-switch-{MIDFIX}.log"

    # AIDE / reboot-check
    aide_db: str = "/var/lib/aide/aide.db.gz"
    aide_db_new: str = "/var/lib/aide/aide.db.new.gz"
    aide_log_dir: str = "/var/log/aide"
    aide_drift_flag: str = "/var/lib/aide/drift-unreviewed"
    aide_dnf_dropin_dir: str = "/etc/systemd/system/dnf-automatic.service.d"

    @property
    def aide_helper(self) -> str:
        return f"/usr/local/sbin/{MIDFIX}-aide"

    @property
    def aide_log(self) -> str:
        return f"{self.aide_log_dir}/check.log"

    @property
    def aide_tag(self) -> str:
        return f"{MIDFIX}-aide"

    @property
    def reboot_notice_file(self) -> str:
        return f"/run/motd.d/50-{MIDFIX}-reboot-required"

    @property
    def reboot_check_bin(self) -> str:
        return f"/usr/local/sbin/{MIDFIX}-reboot-check"

    @property
    def nft_rules_conf(self) -> str:
        return f"/etc/nftables/{MIDFIX}-inet-filter.nft"

    @property
    def nft_include(self) -> str:
        return f'include "{self.nft_rules_conf}"'

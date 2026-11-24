"""Settings common to all distro setup scripts; each distro's config.py subclasses Config and adds its own.

Run-time overrides come from the environment (put them AFTER sudo, which resets it):
    sudo SYSTEM_HOSTNAME=foo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 python3 <distro>/main.py
Everything else is plain configuration: edit it in place.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, replace

MIDFIX = "from-setup"

_UNUSABLE_HOSTNAMES = {"", "localhost", "localhost.localdomain", "(none)"}
_HOST_LABEL = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")


def env_help(keymap_line: str) -> str:
    """The environment variables both distros read. Shown by `main.py --help`; keep in step with from_env."""
    return f"""\
environment (put them AFTER sudo, which resets the environment). Any value left unset keeps its current setting:
  SYSTEM_HOSTNAME  short hostname; used for the /etc/hosts alias and to derive the FQDN
  SYSTEM_DOMAIN    domain; derives the FQDN as <hostname>.<domain>, using the current short hostname if
                   SYSTEM_HOSTNAME is not set
  SYSTEM_FQDN      FQDN override (default: derived as above)
  STATIC_IP        IPv4 CIDR, e.g. 192.168.1.50/24; makes the address static (default: current address)
  STATIC_GATEWAY   IPv4 gateway; makes the address static (default: current default-route gateway)
  STATIC_DNS       space-separated DNS servers (default: current). Alone, changes only DNS, address untouched
  STATIC_IFACE     interface (default: interface of the current default route)
  KEYMAP           {keymap_line}
  ADMIN_PUBKEY_FILE  local file with the admin public key (ed25519); default: download it from GitHub
  SUDO_USER        set by sudo, not by you: this account is removed too, once admin and service accounts are ready
"""


def infer_hostname(c: "Config", current: str, error_cls: type = ValueError) -> "Config":
    """SYSTEM_DOMAIN without SYSTEM_HOSTNAME: keep the machine's current short name and add the domain to it.

    `current` is the machine's hostname as the OS reports it. A generic name (localhost, empty) would be baked into
    the FQDN, so it is refused and the caller is asked for SYSTEM_HOSTNAME.
    """
    if c.hostname or not c.domain or c.fqdn:
        return c
    short = current.partition(".")[0].lower()
    if short in _UNUSABLE_HOSTNAMES or not _HOST_LABEL.match(short):
        raise error_cls(
            f"SYSTEM_DOMAIN is set but the machine's current hostname {current!r} cannot be used for it; "
            "set SYSTEM_HOSTNAME")
    return replace(c, hostname=short, fqdn=f"{short}.{c.domain}")


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
    admin_pubkey: str = ""    # filled in by preflight
    admin_pubkey_file: str = ""  # local key file; when set, nothing is downloaded (works offline)
    keymap: str = ""          # console keymap; empty keeps the current one (distro config sets the default)
    sudo_user: str = ""       # account that ran sudo; pruned only once admin and service accounts are ready
    # --- network change, decided by preflight.resolve_network; leave at the defaults ---
    net_action: str = ""      # "" = no change, "dns" = DNS only (address untouched), "static" = write a static address
    net_dhcp: bool = False    # the address on static_iface is DHCP-supplied, so DHCP DNS must be ignored

    # --- accounts ---
    admin_user: str = "devola"
    service_user: str = "popola"
    admin_group: str = ""     # set by the distro (wheel / sudo)
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
    static_apply_delay: str = "5s"

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Config":
        env = os.environ if env is None else env
        hostname, domain, fqdn = env.get("SYSTEM_HOSTNAME", ""), env.get("SYSTEM_DOMAIN", ""), env.get("SYSTEM_FQDN", "")
        if not fqdn and hostname and domain:
            fqdn = f"{hostname.lower()}.{domain}"
        return cls(
            hostname=hostname, domain=domain, fqdn=fqdn, keymap=env.get("KEYMAP", cls.keymap),
            sudo_user=env.get("SUDO_USER", ""), admin_pubkey_file=env.get("ADMIN_PUBKEY_FILE", ""),
            static_ip=env.get("STATIC_IP", ""), static_gateway=env.get("STATIC_GATEWAY", ""),
            static_dns=env.get("STATIC_DNS", ""), static_iface=env.get("STATIC_IFACE", ""),
        )

    # --- derived: hostname ---
    @property
    def hosts_file(self) -> str:
        return "/etc/hosts"

    @property
    def hosts_marker(self) -> str:
        return f"# {MIDFIX}-hostname"

    # --- derived: paths (all named after MIDFIX so they are recognisably ours) ---
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

    # reboot-check
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

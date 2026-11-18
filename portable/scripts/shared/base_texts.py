"""Texts shared by all distro setup scripts: sudo, su-guard, ssh, motd, PAM limits, firewall rules, reboot-check units.

Bodies full of shell `${...}` use @@NAME@@ placeholders (see `render`) instead of f-strings.
Every body ends with a trailing newline.
"""

from __future__ import annotations

import re

import art
from base_config import MIDFIX, Config

def render(template: str, **values: object) -> str:
    return re.sub(r"@@(\w+)@@", lambda m: str(values[m.group(1)]), template)


def daily_timer(description: str) -> str:
    return render("""\
[Unit]
Description=@@desc@@

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
""", desc=description)


def sudo_conf(c: Config) -> str:
    return f"""\
Defaults use_pty
Defaults timestamp_timeout=15
Defaults umask=0022
Defaults umask_override
Defaults log_host,logfile="{c.sudo_log}"
"""


def admin_sudoers(c: Config) -> str:
    return f"{c.admin_user} ALL=(ALL) ALL\n"


def service_sudoers(c: Config) -> str:
    # The admin may open a login shell as the service user without a password
    return f"{c.admin_user} ALL=({c.service_user}) NOPASSWD: /bin/bash -l\n"


def su_guard_bin(c: Config) -> str:
    # Only writes on drift, otherwise its own chmod would retrigger the path unit in a loop
    return f"""\
#!/bin/sh
set -eu
[ "$(stat -c '%a %G' "{c.su_bin}")" = "{c.su_mode:o} {c.admin_group}" ] && exit 0
chgrp "{c.admin_group}" "{c.su_bin}"
chmod "{c.su_mode:o}" "{c.su_bin}"
logger -t {MIDFIX}-su-guard "restored {c.su_bin} to {c.su_mode:o} {c.admin_group}"
"""


def su_guard_service(c: Config) -> str:
    return f"""\
[Unit]
Description=Re-apply restricted permissions on {c.su_bin}

[Service]
Type=oneshot
ExecStart={c.su_guard_bin}
"""


def su_guard_path(c: Config) -> str:
    return f"""\
[Unit]
Description=Watch {c.su_bin} for permission resets

[Path]
PathChanged={c.su_bin}
Unit={c.su_guard_service}

[Install]
WantedBy=multi-user.target
"""


def su_guard_timer(c: Config) -> str:
    # Fallback in case inotify misses the package manager replacing the file
    return f"""\
[Unit]
Description=Periodically re-apply restricted permissions on {c.su_bin}

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Unit={c.su_guard_service}

[Install]
WantedBy=timers.target
"""


def ssh_banner() -> str:
    return art.BANNER + "\n"  # bash: printf '%s\n'


def motd(c: Config) -> str:
    # Note under the art: the service user has no direct login
    popola_note = f'  - To switch to the {c.service_user} service user, run "sudo -u {c.service_user} /bin/bash -l".\n'
    return f"{art.MOTD}\n\nNotes:\n{popola_note}"


FAILLOCK_CONF = """\
deny = 5
unlock_time = 900
"""


# Not readonly (override with TMOUT=0); skipped inside tmux/screen, where idle panes are expected
TIMEOUT_CONF = """\
if [ -z "${TMUX:-}" ] && [ -z "${STY:-}" ]; then
  export TMOUT=900
fi
"""


# Not applied to root. The sudo config sets "umask=0022" + "umask_override" so files created
# under sudo don't inherit 027 (sudo ORs the caller's umask) and stay readable by services
UMASK_CONF = """\
if [ "$(id -u)" -ne 0 ]; then
  umask 027
fi
"""


def ssh_conf(c: Config) -> str:
    return f"""\
Port {c.ssh_port}
PermitRootLogin no
AllowUsers {c.admin_user}
AuthenticationMethods publickey
PubkeyAuthentication yes
PubkeyAcceptedAlgorithms ssh-ed25519,sk-ssh-ed25519@openssh.com
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
MaxSessions 4
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
Banner {c.ssh_banner}
"""


def sshd_expected(c: Config) -> tuple[str, ...]:
    """Effective `sshd -T` lines that must hold (an earlier drop-in could silently override ours)."""
    return (
        "permitrootlogin no", "passwordauthentication no", "kbdinteractiveauthentication no",
        "permitemptypasswords no", "pubkeyauthentication yes", "authenticationmethods publickey",
        f"allowusers {c.admin_user}", "pubkeyacceptedalgorithms ssh-ed25519,sk-ssh-ed25519@openssh.com",
        "maxauthtries 3", "x11forwarding no", "allowagentforwarding no", "allowtcpforwarding no",
    )


def nft_rules(c: Config) -> str:
    return render("""\
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;

    # Accept loopback traffic
    iif lo accept

    # Drop invalid connection state packets
    ct state invalid drop

    # Accept established/related connections
    ct state established,related accept

    # Rate limit new SSH connections per source address (IPv4 and IPv6)
    tcp dport @@port@@ ct state new meter ssh-v4 { ip saddr limit rate 5/second } accept
    tcp dport @@port@@ ct state new meter ssh-v6 { ip6 saddr limit rate 5/second } accept

    # Accept ICMP for diagnostics (IPv4)
    icmp type echo-request accept

    # Accept ICMPv6 needed for IPv6 to function (ND, path MTU discovery, MLD) and diagnostics
    icmpv6 type { echo-request, destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, nd-router-solicit, nd-redirect, mld-listener-query, mld-listener-report, mld2-listener-report } accept

    # Accept DHCPv6 replies (no conntrack match when the request was multicast)
    ip6 saddr fe80::/10 udp sport 547 udp dport 546 accept

    # Accept DHCPv4 replies (broadcast offers/acks and rebinds don't match conntrack)
    udp sport 67 udp dport 68 accept

    # Log (rate limited) and drop everything else
    limit rate 1/second log prefix "[nftables] DROP: " flags all
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
""", port=c.ssh_port)


def reboot_check_service(c: Config) -> str:
    return f"""\
[Unit]
Description=Check whether a reboot is required

[Service]
Type=oneshot
ExecStart={c.reboot_check_bin}
"""

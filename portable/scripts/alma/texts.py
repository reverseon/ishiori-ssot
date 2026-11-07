"""File bodies written by alma-setup (the heredocs of the bash script).

Every body ends exactly as the bash heredoc did (a trailing newline), so the files are byte-identical.
Bodies full of shell `${...}` use @@NAME@@ placeholders (see `render`) instead of f-strings.
"""

from __future__ import annotations

import re

import art
from config import MIDFIX, Config


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


# ---- sudo / su ----------------------------------------------------------------------------------

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


# ---- login experience -----------------------------------------------------------------------------

def ssh_banner() -> str:
    return art.BANNER + "\n"  # bash: printf '%s\n'


def motd(c: Config) -> str:
    # Notes under the art: a manual dnf update looks like drift to AIDE, and the service user has no direct login
    aide_note = (f'  - After a manual "dnf update", review the AIDE drift in {c.aide_log},\n'
                 f'    then run "sudo {c.aide_helper} accept". Until then, dnf-automatic will not refresh the AIDE baseline.\n')
    popola_note = f'  - To switch to the {c.service_user} service user, run "sudo -u {c.service_user} /bin/bash -l".\n'
    return f"{art.MOTD}\n\nNotes:\n{aide_note}{popola_note}"


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


# ---- updates, kernel, audit -------------------------------------------------------------------------

DNF_AUTOMATIC_CONF = """\
[commands]
upgrade_type = security
random_sleep = 0
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio
"""

SYSCTL_HARDENING = """\
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
"""

# Auditing: identity, sudo and sshd config files, and the use of su/sudo
AUDIT_RULES = """\
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/ -p wa -k sshd_config
-w /usr/bin/su -p x -k priv_cmd
-w /usr/bin/sudo -p x -k priv_cmd
"""

LIMITS_NOCORE = "* hard core 0\n"
SYSCTL_NOCORE = "fs.suid_dumpable = 0\n"

# /tmp is left alone: on the stock layout it lives on the root filesystem and a noexec /tmp breaks dnf scriptlets
SHM_DROPIN = """\
[Mount]
Options=mode=1777,nosuid,nodev,noexec
"""


def modprobe_blacklist(c: Config) -> str:
    # "install ... /bin/false" also blocks an explicit modprobe
    return "".join(f"blacklist {m}\ninstall {m} /bin/false\n" for m in c.blacklisted_modules)


def allow_list(c: Config) -> str:
    return "".join(f"{u}\n" for u in c.cron_allowed_users)


# ---- logging ---------------------------------------------------------------------------------------

def rsyslog_nft(c: Config) -> str:
    return f':msg, contains, "[nftables] DROP:" {c.nft_log}\n& stop\n'


def rsyslog_popola(c: Config) -> str:
    # Matched on sudo's own syslog line (root-written, unforgeable by the service user); no "& stop",
    # so the line still reaches /var/log/secure.
    return f':msg, contains, "USER={c.service_user} ; COMMAND=" {c.popola_log}\n'


def logrotate(log: str, frequency: str, rotate: int, *, compress: bool = True, reload_rsyslog: bool = False) -> str:
    """One stanza per log (logrotate rejects a file that appears in more than one)."""
    lines = [f"{log} {{", f"  {frequency}", f"  rotate {rotate}", "  missingok", "  notifempty"]
    if compress:
        lines += ["  compress", "  delaycompress"]
    if reload_rsyslog:
        lines += ["  postrotate", "    systemctl reload rsyslog > /dev/null 2>&1 || true", "  endscript"]
    return "\n".join(lines + ["}"]) + "\n"


# ---- firewall --------------------------------------------------------------------------------------

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


# ---- network ---------------------------------------------------------------------------------------

def nm_keyfile(c: Config) -> str:
    dns_line = f"dns={c.static_dns.replace(' ', ';')};" if c.static_dns else ""
    return f"""\
[connection]
id={c.nm_connection}
type=ethernet
interface-name={c.static_iface}
autoconnect=true
autoconnect-priority={c.nm_priority}

[ipv4]
method=manual
address1={c.static_ip},{c.static_gateway}
{dns_line}

[ipv6]
method=auto

"""  # bash printf adds a second newline


# ---- reboot notice ---------------------------------------------------------------------------------

def reboot_check_bin(c: Config) -> str:
    return render("""\
#!/bin/bash
set -u
dnf needs-restarting -r > /dev/null 2>&1
rc=$?
if [ "${rc}" -eq 1 ]; then
  if [ ! -e "@@notice@@" ]; then
    mkdir -p "$(dirname "@@notice@@")"
    printf '%s\\n' '  - Reboot required: updates changed the kernel or core libraries. Run "sudo reboot" when convenient.' > "@@notice@@"
    chmod 0644 "@@notice@@"
    logger -t @@midfix@@-reboot-check -p authpriv.warning "reboot required to finish applying updates"
  fi
elif [ "${rc}" -eq 0 ]; then
  rm -f "@@notice@@"
fi
exit 0
""", notice=c.reboot_notice_file, midfix=MIDFIX)


def reboot_check_service(c: Config) -> str:
    return f"""\
[Unit]
Description=Check whether a reboot is required

[Service]
Type=oneshot
ExecStart={c.reboot_check_bin}
"""


def reboot_dnf_dropin(c: Config) -> str:
    return f"[Service]\nExecStartPost=-{c.reboot_check_bin}\n"


# ---- AIDE ------------------------------------------------------------------------------------------

def aide_helper(c: Config) -> str:
    """One wrapper for all modes. aide exits 1-7 on differences and 8+ on errors; differences are a finding,
    not a unit failure, so only errors exit non-zero. Findings go to a log file and to syslog (authpriv).

    "check" only reports. "update" refreshes the baseline; dnf-automatic runs check BEFORE its transaction
    (findings are real) and update AFTER (package changes are expected). If the pre-check found drift,
    "update" leaves the baseline alone (drift flag) so the daily check keeps reporting until an admin
    reviews and runs "accept" (refresh baseline, clear the flag). All modes share a lock.
    """
    return render("""\
#!/bin/bash
set -u
mode="${1:-check}"
mkdir -p "@@log_dir@@"
exec 9> "/run/@@midfix@@-aide.lock"
flock 9
report="$(mktemp)"
trap 'rm -f "${report}"' EXIT
# A refresh would absorb existing drift, so "update" refuses while @@flag@@ exists.
# "check" sets it on drift or error and clears it only on a clean run.
if [ "${mode}" = "update" ] && [ -e "@@flag@@" ]; then
  echo "=== $(date -Is) aide update skipped: unreviewed drift, baseline NOT refreshed ===" >> "@@log@@"
  logger -t @@tag@@ -p authpriv.err "baseline NOT refreshed: unreviewed drift since last clean check, see @@log@@; review then run: @@helper@@ accept"
  exit 0
fi
case "${mode}" in
  check) aide --check > "${report}" 2>&1 ;;
  update|accept) aide --update > "${report}" 2>&1 ;;
  *) echo "usage: $0 check|update|accept" >&2; exit 2 ;;
esac
rc=$?
{ echo "=== $(date -Is) aide ${mode} rc=${rc} ==="; cat "${report}"; } >> "@@log@@"
if [ "${rc}" -ge 8 ]; then
  [ "${mode}" = "check" ] && touch "@@flag@@"
  logger -t @@tag@@ -p authpriv.err "aide ${mode} failed (rc=${rc}), see @@log@@"
  exit "${rc}"
fi
if [ "${mode}" = "update" ]; then
  mv -f "@@db_new@@" "@@db@@"
  logger -t @@tag@@ -p authpriv.info "baseline refreshed after package update (rc=${rc})"
elif [ "${mode}" = "accept" ]; then
  mv -f "@@db_new@@" "@@db@@"
  rm -f "@@flag@@"
  logger -t @@tag@@ -p authpriv.notice "baseline accepted by admin, drift flag cleared (rc=${rc})"
elif [ "${rc}" -eq 0 ]; then
  rm -f "@@flag@@"
  logger -t @@tag@@ -p authpriv.info "no changes since baseline"
else
  touch "@@flag@@"
  logger -t @@tag@@ -p authpriv.warning "changes since baseline (rc=${rc}), see @@log@@"
fi
exit 0
""", log_dir=c.aide_log_dir, midfix=MIDFIX, flag=c.aide_drift_flag, log=c.aide_log, tag=c.aide_tag,
        helper=c.aide_helper, db=c.aide_db, db_new=c.aide_db_new)


def aide_service(c: Config) -> str:
    return f"""\
[Unit]
Description=AIDE integrity check

[Service]
Type=oneshot
ExecStart={c.aide_helper} check
"""


def aide_dnf_dropin(c: Config) -> str:
    # Report drift just before dnf-automatic changes files, refresh the baseline just after.
    # The leading "-" keeps an AIDE failure from blocking or failing the update run.
    return f"[Service]\nExecStartPre=-{c.aide_helper} check\nExecStartPost=-{c.aide_helper} update\n"

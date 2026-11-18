"""File bodies written by alma-setup (the heredocs of the bash script).

Every body ends exactly as the bash heredoc did (a trailing newline), so the files are byte-identical.
Bodies full of shell `${...}` use @@NAME@@ placeholders (see `render`) instead of f-strings.
"""

from __future__ import annotations

import art
from base_texts import *  # noqa: F401,F403
from base_texts import render
from config import MIDFIX, Config


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


def reboot_dnf_dropin(c: Config) -> str:
    return f"[Service]\nExecStartPost=-{c.reboot_check_bin}\n"


# ---- AIDE ------------------------------------------------------------------------------------------

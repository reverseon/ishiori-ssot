"""File bodies written by debian-setup.

Every body ends with a trailing newline.
Bodies full of shell `${...}` use @@NAME@@ placeholders (see `render`) instead of f-strings.
"""

from __future__ import annotations

import art
from base_texts import *  # noqa: F401,F403
from base_texts import render
from config import MIDFIX, Config


# ---- updates, keyboard, PAM -------------------------------------------------------------------------

AUTO_UPGRADES_CONF = """\
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
"""


def unattended_conf() -> str:
    # `#clear` drops the stock origins (which include non-security point-release updates), so only the
    # security archive is applied unattended. Reboots stay manual: the reboot notice covers them.
    return """\
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
"""


def keyboard_conf(c: Config) -> str:
    return f"""\
# KEYBOARD CONFIGURATION FILE (managed by debian-setup)
XKBMODEL="{c.keyboard_model}"
XKBLAYOUT="{c.keymap}"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
"""


def pam_faillock_preauth() -> str:
    # Runs before pam_unix (higher priority): refuses a locked account before the password is even checked
    return """\
Name: Faillock preauth (debian-setup)
Default: yes
Priority: 1024
Auth-Type: Primary
Auth:
\trequisite\t\t\tpam_faillock.so preauth
"""


def pam_faillock_authfail() -> str:
    # After pam_unix (lower priority): counts the failure; the account phase resets the counter on success
    return """\
Name: Faillock authfail (debian-setup)
Default: yes
Priority: 128
Auth-Type: Primary
Auth:
\t[default=die]\t\t\tpam_faillock.so authfail
Account-Type: Primary
Account:
\trequired\t\t\tpam_faillock.so
"""


# ---- firewall --------------------------------------------------------------------------------------


def nft_main(c: Config) -> str:
    # Debian's nftables.service loads this file; flush first so the stock ruleset cannot collide with ours
    return f"""\
#!/usr/sbin/nft -f
flush ruleset
{c.nft_include}
"""


# ---- network ---------------------------------------------------------------------------------------

def netplan_yaml(c: Config) -> str:
    """Static address (90-). DNS lives in netplan_dns_yaml so one file owns it in every mode."""
    return f"""\
network:
  version: 2
  ethernets:
    {c.static_iface}:
      dhcp4: false
      addresses: [{c.static_ip}]
      routes:
        - to: default
          via: {c.static_gateway}
"""


def netplan_dns_yaml(c: Config) -> str:
    """Nameservers (91-), merged over the address config. With a DHCP address, DHCP-supplied DNS is switched off
    so only the wanted servers are used."""
    dns = [d for d in c.static_dns.split() if d]
    if not dns and not c.net_dhcp:
        return "network:\n  version: 2\n"
    lines = ["network:", "  version: 2", "  ethernets:", f"    {c.static_iface}:"]
    if c.net_dhcp:
        lines += ["      dhcp4-overrides:", "        use-dns: false"]
    if dns:
        lines += ["      nameservers:", f"        addresses: [{', '.join(dns)}]"]
    return "\n".join(lines) + "\n"


# ---- reboot notice ---------------------------------------------------------------------------------

def reboot_check_bin(c: Config) -> str:
    # Needed when a package asked for it (/run/reboot-required) or a newer kernel is installed than the one running
    return render("""\
#!/bin/bash
set -u
needed=0
[ -e /run/reboot-required ] && needed=1
if command -v needrestart > /dev/null 2>&1 && needrestart -b -k 2> /dev/null | grep -q '^NEEDRESTART-KSTA: 3'; then
  needed=1
fi
if [ "${needed}" -eq 1 ]; then
  if [ ! -e "@@notice@@" ]; then
    mkdir -p "$(dirname "@@notice@@")"
    printf '%s\\n' '  - Reboot required: updates changed the kernel or core libraries. Run "sudo reboot" when convenient.' > "@@notice@@"
    chmod 0644 "@@notice@@"
    logger -t @@midfix@@-reboot-check -p authpriv.warning "reboot required to finish applying updates"
  fi
else
  rm -f "@@notice@@"
fi
exit 0
""", notice=c.reboot_notice_file, midfix=MIDFIX)


def reboot_apt_dropin(c: Config) -> str:
    return f"[Service]\nExecStartPost=-{c.reboot_check_bin}\n"

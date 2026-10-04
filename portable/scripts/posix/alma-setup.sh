#!/bin/bash
# AlmaLinux setup and hardening script. Run as root (sudo); safe to re-run.
#
# Variables you can override from the environment (put them AFTER sudo, which resets the environment):
#   sudo SYSTEM_HOSTNAME=foo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 bash alma-setup.sh
#
#   SYSTEM_HOSTNAME  Short hostname. Used for the /etc/hosts alias and to derive SYSTEM_FQDN.
#   SYSTEM_DOMAIN    Domain appended to the lowercased hostname to derive SYSTEM_FQDN.
#   SYSTEM_FQDN      Static hostname set via hostnamectl. Derived as <hostname>.<domain> when both are set.
#                    If no FQDN results, the short hostname is used. With none of the three set, the
#                    hostname and /etc/hosts are left untouched.
#   STATIC_IP        Static IPv4 address in CIDR form, e.g. 192.168.1.50/24. Unset keeps the current
#                    network config; otherwise a NetworkManager keyfile is written and activated last.
#   STATIC_GATEWAY   IPv4 gateway. Empty (default) = gateway of the current default route on STATIC_IFACE.
#   STATIC_DNS       Space-separated DNS servers, e.g. "1.1.1.1 9.9.9.9". Optional.
#   STATIC_IFACE     Interface to configure. Empty (default) = interface of the current default route.
#   PRUNE_DRY_RUN    1 = only list the login users that would be removed, remove nothing (default: 0).
#
# Everything else below (accounts, SSH, firewall, packages, ...) is plain configuration: edit it in place.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: this script must be run as root (try: sudo $0)" >&2
  exit 1
fi

FILE_MIDFIX="from-setup"

# Hostname: short name and FQDN, mirroring cloud-init's local-hostname / hostname in meta-data
# (not named HOSTNAME, which is a bash builtin variable). Nothing is changed unless a variable is set.
# SYSTEM_FQDN, if empty and both SYSTEM_HOSTNAME and SYSTEM_DOMAIN are set, becomes <lowercased hostname>.<domain>.
# Override at run time: sudo SYSTEM_HOSTNAME=myhost SYSTEM_DOMAIN=example.net bash alma-setup.sh
SYSTEM_HOSTNAME="${SYSTEM_HOSTNAME-}"
SYSTEM_DOMAIN="${SYSTEM_DOMAIN-}"
SYSTEM_FQDN="${SYSTEM_FQDN-}"
if [ -z "${SYSTEM_FQDN}" ] && [ -n "${SYSTEM_HOSTNAME}" ] && [ -n "${SYSTEM_DOMAIN}" ]; then
  SYSTEM_FQDN="${SYSTEM_HOSTNAME,,}.${SYSTEM_DOMAIN}"
fi
# Static hostname: the FQDN if there is one (RHEL convention), else the short name
SYSTEM_STATIC_HOSTNAME="${SYSTEM_FQDN:-${SYSTEM_HOSTNAME}}"
HOSTS_FILE="/etc/hosts"
HOSTS_MARKER="# ${FILE_MIDFIX}-hostname"

# Static IPv4 (empty STATIC_IP leaves the network config alone), applied as a NetworkManager keyfile
# Override at run time: sudo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 bash alma-setup.sh
STATIC_IP="${STATIC_IP-}"            # CIDR, e.g. 192.168.1.50/24
STATIC_GATEWAY="${STATIC_GATEWAY-}"  # empty = gateway of the current default route
STATIC_DNS="${STATIC_DNS-}"          # space-separated, e.g. "1.1.1.1 9.9.9.9"
STATIC_IFACE="${STATIC_IFACE-}"      # empty = interface of the current default route
# Priority above the stock profile (0) so this one wins; the existing profiles and cloud-init config are not touched
STATIC_NM_PRIORITY=100
STATIC_NM_CONF="/etc/NetworkManager/system-connections/${FILE_MIDFIX}-static.nmconnection"
STATIC_APPLY_DELAY="5s"

# Accounts
ADMIN_USER="devola"
SERVICE_USER="popola"
ADMIN_GROUP="wheel"

# Sudo
SUDO_LOG="/var/log/sudo.log"

# SSH
SSH_PORT=22
# 00- prefix: sshd keeps the first value per option, so this must sort before the other drop-ins
SSH_CONF="/etc/ssh/sshd_config.d/00-${FILE_MIDFIX}-ssh.conf"
SSH_BANNER="/etc/ssh/banner-${FILE_MIDFIX}.net"
IFS= read -r -d '' SSH_BANNER_TEXT << 'BANNER_EOF' || true
 ___     _     _            _   _   _ _____ _____ 
|_ _|___| |__ (_) ___  _ __(_) | \ | | ____|_   _|
 | |/ __| '_ \| |/ _ \| '__| | |  \| |  _|   | |  
 | |\__ \ | | | | (_) | |  | |_| |\  | |___  | |  
|___|___/_| |_|_|\___/|_|  |_(_)_| \_|_____| |_|  
BANNER_EOF

# MOTD
MOTD_PATH="/etc/motd"
IFS= read -r -d '' MOTD_TEXT << 'MOTD_EOF' || true
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣤⣤⣤⣤⣄⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⠶⣻⠝⠋⠠⠔⠛⠁⡀⠀⠈⢉⡙⠓⠶⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⢋⣴⡮⠓⠋⠀⠀⢄⠀⠀⠉⠢⣄⠀⠈⠁⠀⡀⠙⢶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⢁⣔⠟⠁⠀⠀⠀⠀⠀⠈⡆⠀⠀⠀⠈⢦⡀⠀⠀⠘⢯⢢⠙⢦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡼⠃⠀⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠸⠀⠀⠀⠀⠀⢳⣦⡀⠀⠀⢯⠀⠈⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⠆⡄⢠⢧⠀⣸⠀⠀⠀⠀⠀⠀⠀⢰⠀⣄⠀⠀⠀⠀⢳⡈⢶⡦⣿⣷⣿⢉⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣿⣯⣿⣁⡟⠈⠣⡇⠀⠀⢸⠀⠀⠀⠀⢸⡄⠘⡄⠀⠀⠀⠈⢿⢾⣿⣾⢾⠙⠻⣾⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⡿⣮⠇⢙⠷⢄⣸⡗⡆⠀⢘⠀⠀⠀⠀⢸⠧⠀⢣⠀⠀⠀⡀⡸⣿⣿⠘⡎⢆⠈⢳⣽⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⢠⡟⢻⢷⣄⠀⠀⠀⠀⠀⠀⣾⣳⡿⡸⢀⣿⠀⠀⢸⠙⠁⠀⠼⠀⠀⠀⠀⢸⣇⠠⡼⡤⠴⢋⣽⣱⢿⣧⠀⢳⠈⢧⠀⢻⣿⣧⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⢀⡿⣠⡣⠃⣿⠃⠀⠀⠀⠀⣸⣳⣿⠇⣇⢸⣿⢸⣠⠼⠀⠀⠀⡇⠀⡀⠉⠒⣾⢾⣆⢟⣳⡶⠓⠶⠿⢼⣿⣇⠈⡇⠘⢆⠈⢿⡘⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠈⢷⣍⣤⡶⣿⡄⠀⠀⠀⢠⣿⠃⣿⠀⡏⢸⣿⣿⠀⢸⠀⠀⢠⡗⢀⠇⠀⢠⡟⠀⠻⣾⣿⠀⠀⠀⠀⡏⣿⣿⡀⢹⡀⠈⢦⠈⢷⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢁⣤⣄⠁⠀⠀⠀⣼⡏⢰⣟⠀⣇⠘⣿⣿⣾⣾⣆⢀⣾⠃⣼⢠⣶⣿⣭⣷⣶⣾⣿⣤⠀⠀⠀⡇⡯⣍⣧⠀⣷⠄⠈⢳⡀⢻⡁⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠺⣿⡿⠀⠀⠀⠀⡿⢀⣾⣧⠀⡗⡄⢿⣿⡙⣽⣿⣟⠛⠚⠛⠙⠉⢹⣿⣿⣦⠀⢸⡿⠀⠀⠀⢰⡯⣌⢻⡀⢸⢠⢰⡄⠹⡷⣿⣦⣤⠤⣶⡇⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⠀⠀⣇⣾⣿⢸⢠⣧⢧⠘⣿⡇⠸⣿⢿⡆⠀⠀⠀⠀⠘⣯⠇⣿⠂⣸⢰⠀⠀⢀⣸⡧⣊⣼⡇⢸⣼⣸⣷⢣⢻⣄⠉⠙⠛⠉⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣳⣤⣴⣿⣏⣿⣾⢸⣿⡘⣧⣘⢿⣀⡙⣞⠁⠀⠀⠀⠀⢀⡬⢀⣉⢠⣧⡏⠀⠀⡎⣿⣿⣿⣿⠃⣸⡏⣿⣿⡎⢿⡘⡆⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⣠⣼⣿⣿⣿⣼⣿⣧⢿⣿⣿⣯⡻⠟⠀⠀⠀⠀⠀⠐⢯⠣⡽⢟⣽⠀⠀⢘⡇⣿⣿⣿⡟⣴⣿⣷⣿⣿⣧⣿⣷⡽⠀⠀⠀⠀⠀⠀⠀
⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣼⣹⣿⣇⣸⣿⣿⣿⣻⣚⣿⡿⣿⣿⣦⣤⣀⡉⠃⠀⢀⣀⣤⡶⠛⡏⠀⢀⣼⢸⣿⣿⣿⣿⣿⣿⣿⢋⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀
⣿⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠒⠒⠒⢭⢻⣽⣿⣿⣿⣿⣿⣿⢿⠿⣿⡏⠀⡼⠁⣀⣾⣿⣿⣿⣿⡿⣿⣿⣟⡻⣿⣿⡿⠣⠟⠀⠀⠀⠀⠀⠀⠀⠀
⠸⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢧⢿⣯⡽⠿⠛⠋⣵⢟⣋⣿⣶⣞⣤⣾⣿⣿⡟⢉⡿⢋⠻⢯⡉⢻⡟⢿⡅⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⢻⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⡞⣿⣆⡀⠀⡼⡏⠉⠚⠭⢉⣠⠬⠛⠛⢁⡴⣫⠖⠁⠀⠀⣩⠟⠁⣸⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠈⢷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⣽⣿⣿⣾⠳⡙⣦⡤⠜⠊⠁⠀⣀⡴⠯⠾⠗⠒⠒⠛⠛⠛⠛⠛⠓⠿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠘⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠰⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢷⣻⣿⣿⠔⢪⠓⠬⢍⠉⣩⣽⢻⣤⣶⣦⠀⠀⠀⢀⣀⣤⣴⣾⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠹⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣾⡏⢦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣯⣿⣿⠀⠀⣇⠀⣠⠎⠁⢹⡎⡟⡏⣷⣶⠿⠛⡟⠛⠛⣫⠟⠉⢿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⢻⡄⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⣷⠈⢷⡤⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⣾⣷⡀⣀⣀⣷⡅⠀⠀⠈⣷⢳⡇⣿⠀⠀⣸⠁⢠⡾⣟⣛⣻⣟⡿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢯⢻⣏⡵⠿⠿⢤⣄⠀⢀⣿⢸⣹⣿⣀⣴⣿⣴⣿⣛⠋⠉⠉⡉⠛⣿⣧⡀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠘⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⡎⣿⣥⣶⠖⢉⣿⡿⣿⣿⡿⣿⣟⠿⠿⣿⣿⣿⡯⠻⣿⣿⣿⣷⡽⣿⡗⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠸⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⡘⣿⣩⠶⣛⣋⡽⠿⣷⢬⣙⣻⣿⣿⣿⣯⣛⠳⣤⣬⡻⣿⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀
⠀⣿⣛⣻⣿⡿⠿⠟⠗⠶⠶⠶⠶⠤⠤⢤⠤⡤⢤⣤⣤⣤⣤⣄⣀⣀⣀⣀⣀⣀⣀⣀⣣⢹⣷⣶⣿⣿⣦⣴⣟⣛⣯⣤⣿⣿⣿⣿⣿⣷⣌⣿⣿⣿⣿⣿⣿⣿⣤⣤⣤⣤⣤⣤⣄
⠀⠉⠙⠛⠛⠛⠛⠛⠻⠿⠿⠿⠷⠶⠶⢶⣶⣶⣶⣶⣤⣤⣤⣤⣤⣥⣬⣭⣭⣉⣩⣍⣙⣏⣉⣏⣽⣶⣶⣶⣤⣤⣬⣤⣤⣾⣿⠶⠾⠿⠿⠿⠿⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠛⠃
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠉⠉⠉⠛⠛⠛⠛⠛⠛⠋⠉⠉⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
MOTD_EOF

# Logging
NFT_LOG="/var/log/nftables-${FILE_MIDFIX}.log"

# SSH public key authorized for the admin user
ADMIN_PUBKEY_URL="https://raw.githubusercontent.com/reverseon/ishiori-ssot/refs/heads/main/portable/files/ishiori-master-key.pub"

# Pre-hashed passwords
# Generate hash with: openssl passwd -6 'your_password_here'
ROOT_PASSWORD_HASH='$6$N2iKTCTMzAmc51w4$Ohp2YKKOQbHmGezRtJSJYg1BdsirMy70L4mUjRg/o5M9xSj45UHf.2w.CHTcSmCh4c2KsrDxnEhoYj3RsQCb71'
DEVOLA_PASSWORD_HASH='$6$TsJ5LrQMrfwVrUJi$pdbXq3DnZZ1e6PJy8ex.xesPUHmWzmuth5RhWlSrKzYKe1jsrvaWrIidZLOD7AwJZuVMNKAIbTuNlf85H4.oU.'

# Attack surface reduction
MASKED_SERVICES=(cups avahi-daemon bluetooth)
# squashfs (snap, AppImage, container tooling) and udf (Azure and hypervisor config disks) are deliberately not listed
BLACKLISTED_MODULES=(usb-storage cramfs freevxfs hfs hfsplus jffs2)
CRON_ALLOWED_USERS=("${ADMIN_USER}" "${SERVICE_USER}")
CRON_ALLOW_FILE="/etc/cron.allow"
AT_ALLOW_FILE="/etc/at.allow"
MODPROBE_BLACKLIST_CONF="/etc/modprobe.d/99-${FILE_MIDFIX}-blacklist.conf"

# Packages
PACKAGES=(
  curl
  wget
  git
  vim
  htop
  tmux
  gcc
  make
  python3
  python3-pip
  qemu-guest-agent
  nftables
  dnf-automatic
  dnf-plugins-core
  audit
  audit-rules
  chrony
  aide
  cronie
  at
  rsyslog
  logrotate
)

# User shells and account details
ADMIN_SHELL="/bin/bash"
SERVICE_SHELL="/usr/sbin/nologin"
SERVICE_COMMENT="Service Account"
ADMIN_SSH_DIR="/home/${ADMIN_USER}/.ssh"
ADMIN_AUTHORIZED_KEYS="${ADMIN_SSH_DIR}/authorized_keys"

# Sudoers files
SUDOERS_DIR="/etc/sudoers.d"
SUDO_CONF="${SUDOERS_DIR}/99-${FILE_MIDFIX}-sudo"
ADMIN_SUDOERS_CONF="${SUDOERS_DIR}/99-${FILE_MIDFIX}-${ADMIN_USER}"
SERVICE_SUDOERS_CONF="${SUDOERS_DIR}/99-${FILE_MIDFIX}-${SERVICE_USER}"
IFS= read -r -d '' SUDO_CONF_TEXT << EOF || true
Defaults use_pty
Defaults timestamp_timeout=15
Defaults umask=0022
Defaults umask_override
Defaults log_host,logfile="${SUDO_LOG}"
EOF
ADMIN_SUDOERS_TEXT="${ADMIN_USER} ALL=(ALL) ALL"
# The admin may open a login shell as the service user without a password
SERVICE_SUDOERS_TEXT="${ADMIN_USER} ALL=(${SERVICE_USER}) NOPASSWD: /bin/bash -l"

# su restriction: group-owned, setuid kept, other users get no execute
SU_BIN="/usr/bin/su"
SU_MODE="4750"

# A util-linux update restores the packaged su mode, so a path unit and a timer re-apply it.
# The helper only writes on drift, otherwise its own chmod would retrigger the path unit in a loop.
SU_GUARD_BIN="/usr/local/sbin/${FILE_MIDFIX}-su-guard"
SU_GUARD_SERVICE="${FILE_MIDFIX}-su-guard.service"
SU_GUARD_PATH="${FILE_MIDFIX}-su-guard.path"
SU_GUARD_TIMER="${FILE_MIDFIX}-su-guard.timer"
IFS= read -r -d '' SU_GUARD_BIN_TEXT << EOF || true
#!/bin/sh
set -eu
[ "\$(stat -c '%a %G' "${SU_BIN}")" = "${SU_MODE} ${ADMIN_GROUP}" ] && exit 0
chgrp "${ADMIN_GROUP}" "${SU_BIN}"
chmod "${SU_MODE}" "${SU_BIN}"
logger -t ${FILE_MIDFIX}-su-guard "restored ${SU_BIN} to ${SU_MODE} ${ADMIN_GROUP}"
EOF
IFS= read -r -d '' SU_GUARD_SERVICE_TEXT << EOF || true
[Unit]
Description=Re-apply restricted permissions on ${SU_BIN}

[Service]
Type=oneshot
ExecStart=${SU_GUARD_BIN}
EOF
IFS= read -r -d '' SU_GUARD_PATH_TEXT << EOF || true
[Unit]
Description=Watch ${SU_BIN} for permission resets

[Path]
PathChanged=${SU_BIN}
Unit=${SU_GUARD_SERVICE}

[Install]
WantedBy=multi-user.target
EOF
# Fallback in case inotify misses the package manager replacing the file
IFS= read -r -d '' SU_GUARD_TIMER_TEXT << EOF || true
[Unit]
Description=Periodically re-apply restricted permissions on ${SU_BIN}

[Timer]
OnBootSec=2min
OnUnitActiveSec=1h
Unit=${SU_GUARD_SERVICE}

[Install]
WantedBy=timers.target
EOF

# Authselect profile
AUTHSELECT_PROFILE="local"
AUTHSELECT_FEATURES=(without-nullok with-faillock)

# Faillock
FAILLOCK_CONF="/etc/security/faillock.conf"
IFS= read -r -d '' FAILLOCK_CONF_TEXT << EOF || true
deny = 5
unlock_time = 900
EOF

# Session timeout
TIMEOUT_CONF="/etc/profile.d/${FILE_MIDFIX}-timeout.sh"
# Not readonly (override with TMOUT=0); skipped inside tmux/screen, where idle panes are expected
IFS= read -r -d '' TIMEOUT_CONF_TEXT << 'EOF' || true
if [ -z "${TMUX:-}" ] && [ -z "${STY:-}" ]; then
  export TMOUT=900
fi
EOF

# SSH server config
IFS= read -r -d '' SSH_CONF_TEXT << EOF || true
Port ${SSH_PORT}
PermitRootLogin no
AllowUsers ${ADMIN_USER}
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
Banner ${SSH_BANNER}
EOF

# Automatic updates (whole-file config, owned by this script)
DNF_AUTOMATIC_CONF="/etc/dnf/automatic.conf"
IFS= read -r -d '' DNF_AUTOMATIC_CONF_TEXT << 'EOF' || true
[commands]
upgrade_type = security
random_sleep = 0
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio
EOF

# Kernel hardening (sysctl)
SYSCTL_HARDENING_CONF="/etc/sysctl.d/99-${FILE_MIDFIX}-hardening.conf"
IFS= read -r -d '' SYSCTL_HARDENING_TEXT << 'EOF' || true
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
EOF

# Auditing: identity, sudo and sshd config files, and the use of su/sudo
AUDIT_RULES_CONF="/etc/audit/rules.d/99-${FILE_MIDFIX}.rules"
IFS= read -r -d '' AUDIT_RULES_TEXT << 'EOF' || true
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers
-w /etc/ssh/ -p wa -k sshd_config
-w /usr/bin/su -p x -k priv_cmd
-w /usr/bin/sudo -p x -k priv_cmd
EOF

# Restrictive default permissions for interactive shells
UMASK_CONF="/etc/profile.d/99-${FILE_MIDFIX}-umask.sh"
# Not applied to root. The sudo config sets "umask=0022" + "umask_override" so files created
# under sudo don't inherit 027 (sudo ORs the caller's umask) and stay readable by services
IFS= read -r -d '' UMASK_CONF_TEXT << 'EOF' || true
if [ "$(id -u)" -ne 0 ]; then
  umask 027
fi
EOF

# Core dumps
LIMITS_NOCORE_CONF="/etc/security/limits.d/99-${FILE_MIDFIX}-nocore.conf"
LIMITS_NOCORE_TEXT="* hard core 0"
SYSCTL_NOCORE_CONF="/etc/sysctl.d/99-${FILE_MIDFIX}-nocore.conf"
SYSCTL_NOCORE_TEXT="fs.suid_dumpable = 0"

# /dev/shm mount options (unit drop-in)
# (/tmp is left alone: on the stock layout it lives on the root filesystem and a noexec /tmp breaks dnf scriptlets)
SHM_DROPIN_DIR="/etc/systemd/system/dev-shm.mount.d"
SHM_DROPIN_CONF="${SHM_DROPIN_DIR}/99-${FILE_MIDFIX}.conf"
SHM_REMOUNT_OPTS="noexec,nosuid,nodev"
IFS= read -r -d '' SHM_DROPIN_TEXT << 'EOF' || true
[Mount]
Options=mode=1777,nosuid,nodev,noexec
EOF

# rsyslog: nftables drops go to a dedicated file
RSYSLOG_NFT_CONF="/etc/rsyslog.d/99-${FILE_MIDFIX}-nftables.conf"
IFS= read -r -d '' RSYSLOG_NFT_TEXT << EOF || true
:msg, contains, "[nftables] DROP:" ${NFT_LOG}
& stop
EOF

# rsyslog: passwordless switches to the service user get their own log file.
# Matched on sudo's own syslog line (root-written, unforgeable by the service user); no "& stop",
# so the line still reaches /var/log/secure.
POPOLA_LOG="/var/log/popola-switch-${FILE_MIDFIX}.log"
RSYSLOG_POPOLA_CONF="/etc/rsyslog.d/99-${FILE_MIDFIX}-popola-switch.conf"
IFS= read -r -d '' RSYSLOG_POPOLA_TEXT << EOF || true
:msg, contains, "USER=${SERVICE_USER} ; COMMAND=" ${POPOLA_LOG}
EOF
LOGROTATE_POPOLA_CONF="/etc/logrotate.d/99-${FILE_MIDFIX}-popola-switch"
IFS= read -r -d '' LOGROTATE_POPOLA_TEXT << EOF || true
${POPOLA_LOG} {
  weekly
  rotate 52
  missingok
  notifempty
  compress
  delaycompress
  postrotate
    systemctl reload rsyslog > /dev/null 2>&1 || true
  endscript
}
EOF

# logrotate: one stanza per log (logrotate rejects a file that appears in more than one)
LOGROTATE_SUDO_CONF="/etc/logrotate.d/99-${FILE_MIDFIX}-sudo"
IFS= read -r -d '' LOGROTATE_SUDO_TEXT << EOF || true
${SUDO_LOG} {
  daily
  rotate 30
  missingok
  notifempty
  compress
  delaycompress
}
EOF
LOGROTATE_NFT_CONF="/etc/logrotate.d/99-${FILE_MIDFIX}-nftables"
IFS= read -r -d '' LOGROTATE_NFT_TEXT << EOF || true
${NFT_LOG} {
  daily
  rotate 7
  missingok
  notifempty
  postrotate
    systemctl reload rsyslog > /dev/null 2>&1 || true
  endscript
}
EOF

# nftables firewall
NFT_DIR="/etc/nftables"
NFT_RULES_CONF="${NFT_DIR}/${FILE_MIDFIX}-inet-filter.nft"
NFT_SYSCONFIG="/etc/sysconfig/nftables.conf"
NFT_INCLUDE="include \"${NFT_RULES_CONF}\""
IFS= read -r -d '' NFT_RULES_TEXT << EOF || true
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
    tcp dport ${SSH_PORT} ct state new meter ssh-v4 { ip saddr limit rate 5/second } accept
    tcp dport ${SSH_PORT} ct state new meter ssh-v6 { ip6 saddr limit rate 5/second } accept

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
EOF

# File integrity (AIDE)
AIDE_DB="/var/lib/aide/aide.db.gz"
AIDE_DB_NEW="/var/lib/aide/aide.db.new.gz"
AIDE_SERVICE_UNIT="/etc/systemd/system/aide-check.service"
AIDE_TIMER_UNIT="/etc/systemd/system/aide-check.timer"
AIDE_HELPER="/usr/local/sbin/${FILE_MIDFIX}-aide"
AIDE_LOG_DIR="/var/log/aide"
AIDE_LOG="${AIDE_LOG_DIR}/check.log"
AIDE_TAG="${FILE_MIDFIX}-aide"
AIDE_DRIFT_FLAG="/var/lib/aide/drift-unreviewed"
# One wrapper for all modes. aide exits 1-7 on differences and 8+ on errors; differences are a
# finding, not a unit failure, so only errors exit non-zero. Findings go to a log file and to
# syslog (authpriv -> /var/log/secure).
# "check" only reports. "update" refreshes the baseline; dnf-automatic runs check BEFORE its
# transaction (findings are real) and update AFTER (package changes are expected). If the
# pre-check found drift, "update" leaves the baseline alone (AIDE_DRIFT_FLAG) so the daily check
# keeps reporting until an admin reviews and runs "accept" (refresh baseline, clear the flag).
# All modes share a lock.
IFS= read -r -d '' AIDE_HELPER_TEXT << EOF || true
#!/bin/bash
set -u
mode="\${1:-check}"
mkdir -p "${AIDE_LOG_DIR}"
exec 9> "/run/${FILE_MIDFIX}-aide.lock"
flock 9
report="\$(mktemp)"
trap 'rm -f "\${report}"' EXIT
# A refresh would absorb existing drift, so "update" refuses while ${AIDE_DRIFT_FLAG} exists.
# "check" sets it on drift or error and clears it only on a clean run.
if [ "\${mode}" = "update" ] && [ -e "${AIDE_DRIFT_FLAG}" ]; then
  echo "=== \$(date -Is) aide update skipped: unreviewed drift, baseline NOT refreshed ===" >> "${AIDE_LOG}"
  logger -t ${AIDE_TAG} -p authpriv.err "baseline NOT refreshed: unreviewed drift since last clean check, see ${AIDE_LOG}; review then run: ${AIDE_HELPER} accept"
  exit 0
fi
case "\${mode}" in
  check) aide --check > "\${report}" 2>&1 ;;
  update|accept) aide --update > "\${report}" 2>&1 ;;
  *) echo "usage: \$0 check|update|accept" >&2; exit 2 ;;
esac
rc=\$?
{ echo "=== \$(date -Is) aide \${mode} rc=\${rc} ==="; cat "\${report}"; } >> "${AIDE_LOG}"
if [ "\${rc}" -ge 8 ]; then
  [ "\${mode}" = "check" ] && touch "${AIDE_DRIFT_FLAG}"
  logger -t ${AIDE_TAG} -p authpriv.err "aide \${mode} failed (rc=\${rc}), see ${AIDE_LOG}"
  exit "\${rc}"
fi
if [ "\${mode}" = "update" ]; then
  mv -f "${AIDE_DB_NEW}" "${AIDE_DB}"
  logger -t ${AIDE_TAG} -p authpriv.info "baseline refreshed after package update (rc=\${rc})"
elif [ "\${mode}" = "accept" ]; then
  mv -f "${AIDE_DB_NEW}" "${AIDE_DB}"
  rm -f "${AIDE_DRIFT_FLAG}"
  logger -t ${AIDE_TAG} -p authpriv.notice "baseline accepted by admin, drift flag cleared (rc=\${rc})"
elif [ "\${rc}" -eq 0 ]; then
  rm -f "${AIDE_DRIFT_FLAG}"
  logger -t ${AIDE_TAG} -p authpriv.info "no changes since baseline"
else
  touch "${AIDE_DRIFT_FLAG}"
  logger -t ${AIDE_TAG} -p authpriv.warning "changes since baseline (rc=\${rc}), see ${AIDE_LOG}"
fi
exit 0
EOF
IFS= read -r -d '' AIDE_SERVICE_TEXT << EOF || true
[Unit]
Description=AIDE integrity check

[Service]
Type=oneshot
ExecStart=${AIDE_HELPER} check
EOF
# dnf-automatic: report drift just before it changes files, refresh the baseline just after.
# The leading "-" keeps an AIDE failure from blocking or failing the update run.
AIDE_DNF_DROPIN_DIR="/etc/systemd/system/dnf-automatic.service.d"
AIDE_DNF_DROPIN_CONF="${AIDE_DNF_DROPIN_DIR}/99-${FILE_MIDFIX}-aide.conf"
IFS= read -r -d '' AIDE_DNF_DROPIN_TEXT << EOF || true
[Service]
ExecStartPre=-${AIDE_HELPER} check
ExecStartPost=-${AIDE_HELPER} update
EOF
# Shown under the MOTD art: a manual dnf update looks like drift to AIDE and blocks the unattended refresh
IFS= read -r -d '' MOTD_AIDE_NOTE << EOF || true
  - After a manual "dnf update", review the AIDE drift in ${AIDE_LOG},
    then run "sudo ${AIDE_HELPER} accept". Until then, dnf-automatic will not refresh the AIDE baseline.
EOF
# Shown under the MOTD art: the service user has no direct login, so say how to reach it
IFS= read -r -d '' MOTD_POPOLA_NOTE << EOF || true
  - To switch to the ${SERVICE_USER} service user, run "sudo -u ${SERVICE_USER} /bin/bash -l".
EOF
LOGROTATE_AIDE_CONF="/etc/logrotate.d/99-${FILE_MIDFIX}-aide"
IFS= read -r -d '' LOGROTATE_AIDE_TEXT << EOF || true
${AIDE_LOG} {
  weekly
  rotate 12
  missingok
  notifempty
  compress
  delaycompress
}
EOF
IFS= read -r -d '' AIDE_TIMER_TEXT << 'UNIT' || true
[Unit]
Description=Daily AIDE integrity check

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Reboot notice: unattended updates can replace the kernel or core libraries, but nothing reboots the VM.
# "dnf needs-restarting -r" exits 1 when a reboot is needed; the helper then drops a world-readable
# note into /run/motd.d (shown by pam_motd; cleared on reboot). Only exit 1 counts; other failures leave the note as is.
REBOOT_NOTICE_FILE="/run/motd.d/50-${FILE_MIDFIX}-reboot-required"
REBOOT_CHECK_BIN="/usr/local/sbin/${FILE_MIDFIX}-reboot-check"
REBOOT_CHECK_SERVICE="${FILE_MIDFIX}-reboot-check.service"
REBOOT_CHECK_TIMER="${FILE_MIDFIX}-reboot-check.timer"
REBOOT_DNF_DROPIN_CONF="${AIDE_DNF_DROPIN_DIR}/98-${FILE_MIDFIX}-reboot-check.conf"
IFS= read -r -d '' REBOOT_CHECK_BIN_TEXT << EOF || true
#!/bin/bash
set -u
dnf needs-restarting -r > /dev/null 2>&1
rc=\$?
if [ "\${rc}" -eq 1 ]; then
  if [ ! -e "${REBOOT_NOTICE_FILE}" ]; then
    mkdir -p "\$(dirname "${REBOOT_NOTICE_FILE}")"
    printf '%s\n' '  - Reboot required: updates changed the kernel or core libraries. Run "sudo reboot" when convenient.' > "${REBOOT_NOTICE_FILE}"
    chmod 0644 "${REBOOT_NOTICE_FILE}"
    logger -t ${FILE_MIDFIX}-reboot-check -p authpriv.warning "reboot required to finish applying updates"
  fi
elif [ "\${rc}" -eq 0 ]; then
  rm -f "${REBOOT_NOTICE_FILE}"
fi
exit 0
EOF
IFS= read -r -d '' REBOOT_CHECK_SERVICE_TEXT << EOF || true
[Unit]
Description=Check whether a reboot is required

[Service]
Type=oneshot
ExecStart=${REBOOT_CHECK_BIN}
EOF
# Daily as well, so a manual "dnf update" is noticed too (dnf-automatic runs the helper right after its own transaction)
IFS= read -r -d '' REBOOT_CHECK_TIMER_TEXT << 'UNIT' || true
[Unit]
Description=Daily reboot-required check

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
UNIT
IFS= read -r -d '' REBOOT_DNF_DROPIN_TEXT << EOF || true
[Service]
ExecStartPost=-${REBOOT_CHECK_BIN}
EOF

# == PRE-FLIGHT CHECKS ==
# Every input check runs here, before the first change to the system, so a bad value aborts a clean run.
if [ -n "${STATIC_IP}" ]; then
  [[ "${STATIC_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || { echo "STATIC_IP must be IPv4 CIDR (e.g. 192.168.1.50/24), got: ${STATIC_IP}" >&2; exit 1; }
  if [ -z "${STATIC_IFACE}" ]; then
    STATIC_IFACE="$(ip -4 route show default | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
  fi
  [ -n "${STATIC_IFACE}" ] || { echo "Could not detect the default-route interface, set STATIC_IFACE" >&2; exit 1; }
  if [ -z "${STATIC_GATEWAY}" ]; then
    STATIC_GATEWAY="$(ip -4 route show default dev "${STATIC_IFACE}" | awk '{for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}}')"
  fi
  [ -n "${STATIC_GATEWAY}" ] || { echo "Could not detect the default gateway on ${STATIC_IFACE}, set STATIC_GATEWAY" >&2; exit 1; }
fi

# Admin public key: download and validate now, installed later
KEY_TMP="$(mktemp)"
trap 'rm -f "${KEY_TMP}"' EXIT
curl -fsSL "${ADMIN_PUBKEY_URL}" -o "${KEY_TMP}"
KEY_INFO="$(ssh-keygen -l -f "${KEY_TMP}")"
# sshd accepts only ed25519 and password auth is off, so any other key type would lock the admin out
if [ -z "${KEY_INFO}" ] || grep -qv '(ED25519)$' <<< "${KEY_INFO}"; then
  echo "Admin public key must be ssh-ed25519 only, got:" >&2
  echo "${KEY_INFO}" >&2
  exit 1
fi

# == HOSTNAME ==
if [ -n "${SYSTEM_STATIC_HOSTNAME}" ]; then
  hostnamectl set-hostname "${SYSTEM_STATIC_HOSTNAME}"
  # Self-resolution without DNS: one marked line, rewritten on every run
  sed -i "\|${HOSTS_MARKER}\$|d" "${HOSTS_FILE}"
  hosts_names="$(xargs <<< "${SYSTEM_FQDN} ${SYSTEM_HOSTNAME}")"
  echo "127.0.1.1 ${hosts_names} ${HOSTS_MARKER}" >> "${HOSTS_FILE}"
fi

# == PACKAGE INSTALLATION ==
# Security updates only (same policy as dnf-automatic), then base tooling
dnf upgrade --security -y
# htop ships in EPEL, which can depend on CodeReady Builder (crb), so enable that first
dnf install -y dnf-plugins-core
dnf config-manager --set-enabled crb
dnf install -y epel-release
dnf install -y "${PACKAGES[@]}"

# == TIME SYNC ==
systemctl enable --now chronyd

# == JOB SCHEDULERS ==
systemctl enable --now crond
systemctl enable --now atd

# == AUTOMATIC UPDATES ==
printf '%s' "${DNF_AUTOMATIC_CONF_TEXT}" > "${DNF_AUTOMATIC_CONF}"
chmod 0644 "${DNF_AUTOMATIC_CONF}"
systemctl enable --now dnf-automatic.timer

# Reboot notice: after every dnf-automatic transaction and daily
printf '%s' "${REBOOT_CHECK_BIN_TEXT}" > "${REBOOT_CHECK_BIN}"
chmod 0755 "${REBOOT_CHECK_BIN}"
restorecon "${REBOOT_CHECK_BIN}" 2>/dev/null || true
printf '%s' "${REBOOT_CHECK_SERVICE_TEXT}" > "/etc/systemd/system/${REBOOT_CHECK_SERVICE}"
printf '%s' "${REBOOT_CHECK_TIMER_TEXT}" > "/etc/systemd/system/${REBOOT_CHECK_TIMER}"
chmod 0644 "/etc/systemd/system/${REBOOT_CHECK_SERVICE}" "/etc/systemd/system/${REBOOT_CHECK_TIMER}"
mkdir -p "${AIDE_DNF_DROPIN_DIR}"
printf '%s' "${REBOOT_DNF_DROPIN_TEXT}" > "${REBOOT_DNF_DROPIN_CONF}"
chmod 0644 "${REBOOT_DNF_DROPIN_CONF}"
systemctl daemon-reload
systemctl enable --now "${REBOOT_CHECK_TIMER}"

# == KERNEL HARDENING (sysctl) ==
printf '%s' "${SYSCTL_HARDENING_TEXT}" > "${SYSCTL_HARDENING_CONF}"
chmod 0644 "${SYSCTL_HARDENING_CONF}"
sysctl --system > /dev/null

# == AUDITING ==
printf '%s' "${AUDIT_RULES_TEXT}" > "${AUDIT_RULES_CONF}"
chmod 0640 "${AUDIT_RULES_CONF}"
systemctl enable --now auditd
augenrules --load || echo "WARNING: could not load audit rules now (they apply on next boot)" >&2

# == ATTACK SURFACE REDUCTION ==
# Mask unused services (missing ones are ignored)
for svc in "${MASKED_SERVICES[@]}"; do
  systemctl disable --now "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done

# Blacklist unused kernel modules ("install ... /bin/false" also blocks explicit modprobe)
{
  for mod in "${BLACKLISTED_MODULES[@]}"; do
    echo "blacklist ${mod}"
    echo "install ${mod} /bin/false"
  done
} > "${MODPROBE_BLACKLIST_CONF}"
chmod 0644 "${MODPROBE_BLACKLIST_CONF}"

# Unload already-loaded modules; ones in use are left for the next reboot.
# lsmod is captured first: piping into `grep -q` under pipefail can SIGPIPE and misreport.
loaded_modules="$(lsmod | awk 'NR>1 {print $1}')"
for mod in "${BLACKLISTED_MODULES[@]}"; do
  lsmod_name="${mod//-/_}"
  if grep -qx "${lsmod_name}" <<< "${loaded_modules}"; then
    rmmod "${lsmod_name}" 2>/dev/null || echo "WARN: ${lsmod_name} is loaded and in use, blacklist applies after reboot" >&2
  fi
done

# Allow-list for cron and at: only these users (root is always allowed by cronie)
printf '%s\n' "${CRON_ALLOWED_USERS[@]}" > "${CRON_ALLOW_FILE}"
printf '%s\n' "${CRON_ALLOWED_USERS[@]}" > "${AT_ALLOW_FILE}"
chmod 0600 "${CRON_ALLOW_FILE}" "${AT_ALLOW_FILE}"

# Restrictive default permissions for interactive shells
printf '%s' "${UMASK_CONF_TEXT}" > "${UMASK_CONF}"
chmod 0644 "${UMASK_CONF}"

# Disable core dumps
printf '%s\n' "${LIMITS_NOCORE_TEXT}" > "${LIMITS_NOCORE_CONF}"
chmod 0644 "${LIMITS_NOCORE_CONF}"
printf '%s\n' "${SYSCTL_NOCORE_TEXT}" > "${SYSCTL_NOCORE_CONF}"
chmod 0644 "${SYSCTL_NOCORE_CONF}"
sysctl --system > /dev/null

# Mount /dev/shm noexec,nosuid,nodev via a unit drop-in
mkdir -p "${SHM_DROPIN_DIR}"
printf '%s' "${SHM_DROPIN_TEXT}" > "${SHM_DROPIN_CONF}"
chmod 0644 "${SHM_DROPIN_CONF}"
systemctl daemon-reload
mount -o "remount,${SHM_REMOUNT_OPTS}" /dev/shm || true

# == SECURITY & IAM HARDENING ==

# MOTD
printf '%s\n\nNotes:\n%s%s' "${MOTD_TEXT}" "${MOTD_AIDE_NOTE}" "${MOTD_POPOLA_NOTE}" > "${MOTD_PATH}"
chmod 0644 "${MOTD_PATH}"

# Sudo configuration via sudoers.d
mkdir -p "${SUDOERS_DIR}"

# install_validated MODE DEST TEXT VALIDATOR...
# Runs "VALIDATOR <tmpfile>" on TEXT and installs it only if it passes. Goes via DEST.new
# (ignored by sudo and sshd) and is then renamed, so a bad file never goes live.
install_validated() {
  local mode="$1" dest="$2" text="$3" tmp
  shift 3
  tmp="$(mktemp)"
  printf '%s' "${text}" > "${tmp}"
  if ! "$@" "${tmp}"; then
    rm -f "${tmp}"
    echo "Validation failed for ${dest}, not installed" >&2
    return 1
  fi
  install -m "${mode}" -o root -g root "${tmp}" "${dest}.new"
  rm -f "${tmp}"
  mv -f "${dest}.new" "${dest}"
  restorecon "${dest}" 2>/dev/null || true
}

install_validated 0440 "${SUDO_CONF}" "${SUDO_CONF_TEXT}" visudo -c -f

# Set root password
echo "root:${ROOT_PASSWORD_HASH}" | chpasswd -e

# Disallow empty passwords via authselect
authselect select "${AUTHSELECT_PROFILE}" "${AUTHSELECT_FEATURES[@]}" --force

# Limit password guessing with faillock (stock file is comments only, so we own it whole)
printf '%s' "${FAILLOCK_CONF_TEXT}" > "${FAILLOCK_CONF}"
chmod 0644 "${FAILLOCK_CONF}"

# Session timeout (15 minutes idle); a default, not a hard control (see TIMEOUT_CONF_TEXT)
printf '%s' "${TIMEOUT_CONF_TEXT}" > "${TIMEOUT_CONF}"
chmod 0644 "${TIMEOUT_CONF}"

# Create the admin user
id -u "${ADMIN_USER}" &>/dev/null || useradd -m -s "${ADMIN_SHELL}" "${ADMIN_USER}"
echo "${ADMIN_USER}:${DEVOLA_PASSWORD_HASH}" | chpasswd -e
usermod -aG "${ADMIN_GROUP}" "${ADMIN_USER}"

# Restrict su to the admin group (re-applied by the SU_GUARD_* units after package updates)
chgrp "${ADMIN_GROUP}" "${SU_BIN}"
chmod "${SU_MODE}" "${SU_BIN}"
printf '%s' "${SU_GUARD_BIN_TEXT}" > "${SU_GUARD_BIN}"
chmod 0755 "${SU_GUARD_BIN}"
printf '%s' "${SU_GUARD_SERVICE_TEXT}" > "/etc/systemd/system/${SU_GUARD_SERVICE}"
printf '%s' "${SU_GUARD_PATH_TEXT}" > "/etc/systemd/system/${SU_GUARD_PATH}"
printf '%s' "${SU_GUARD_TIMER_TEXT}" > "/etc/systemd/system/${SU_GUARD_TIMER}"
chmod 0644 "/etc/systemd/system/${SU_GUARD_SERVICE}" "/etc/systemd/system/${SU_GUARD_PATH}" "/etc/systemd/system/${SU_GUARD_TIMER}"
restorecon "${SU_GUARD_BIN}" 2>/dev/null || true
systemctl daemon-reload
systemctl enable --now "${SU_GUARD_PATH}" "${SU_GUARD_TIMER}"

# Admin sudo access (password required)
install_validated 0440 "${ADMIN_SUDOERS_CONF}" "${ADMIN_SUDOERS_TEXT}"$'\n' visudo -c -f

# Authorize the master public key for the admin user
install -d -m 0700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "${ADMIN_SSH_DIR}"
install -m 0600 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "${KEY_TMP}" "${ADMIN_AUTHORIZED_KEYS}"
restorecon -R "${ADMIN_SSH_DIR}" 2>/dev/null || true

# SSH hardening via sshd_config.d, only after the admin key is in place so a failed download cannot lock everyone out
mkdir -p /etc/ssh/sshd_config.d

# Banner (written first, the drop-in references it)
printf '%s\n' "${SSH_BANNER_TEXT}" > "${SSH_BANNER}"
chmod 0644 "${SSH_BANNER}"

# The drop-in is syntax-checked standalone, then installed
install_validated 0644 "${SSH_CONF}" "${SSH_CONF_TEXT}" sshd -t -f

# Check the installed result as a whole before restarting
sshd -t

# Port accumulates instead of first-value-wins, so another Port directive would make sshd listen on both.
# Comment those out (backup beside the file; a non-.conf name is not read by the include).
SSH_PORT_RE='^[[:space:]]*port[[:space:]=]'
for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [[ -f "${f}" && "${f}" != "${SSH_CONF}" ]] || continue
  grep -qiE "${SSH_PORT_RE}" "${f}" || continue
  cp -p "${f}" "${f}.setup.bak"
  sed -i -E "/${SSH_PORT_RE}/I s|^|# disabled by setup (Port is set in ${SSH_CONF}): |" "${f}"
  echo "Disabled Port directive in ${f} (backup: ${f}.setup.bak)"
done
sshd -t

# sshd -t does not warn when an earlier drop-in overrides our values, so check the effective config
SSHD_EFFECTIVE="$(sshd -T)"
for expected in \
  "permitrootlogin no" \
  "passwordauthentication no" \
  "kbdinteractiveauthentication no" \
  "permitemptypasswords no" \
  "pubkeyauthentication yes" \
  "authenticationmethods publickey" \
  "allowusers ${ADMIN_USER}" \
  "pubkeyacceptedalgorithms ssh-ed25519,sk-ssh-ed25519@openssh.com" \
  "maxauthtries 3" \
  "x11forwarding no" \
  "allowagentforwarding no" \
  "allowtcpforwarding no"; do
  grep -qixF "${expected}" <<< "${SSHD_EFFECTIVE}" || { echo "sshd effective config mismatch: expected '${expected}'" >&2; exit 1; }
done

# Our port must be the only one left
SSHD_PORTS="$(awk 'tolower($1)=="port"{print $2}' <<< "${SSHD_EFFECTIVE}")"
[[ "${SSHD_PORTS}" == "${SSH_PORT}" ]] || { echo "sshd listens on unexpected port(s): $(tr '\n' ' ' <<< "${SSHD_PORTS}")(expected only ${SSH_PORT})" >&2; exit 1; }

systemctl restart sshd

# Service user: no direct login (nologin shell, locked password), reachable only via sudo from the admin.
# No home directory (-M, /nonexistent).
id -u "${SERVICE_USER}" &>/dev/null || useradd -M -d /nonexistent -s "${SERVICE_SHELL}" -c "${SERVICE_COMMENT}" "${SERVICE_USER}"

passwd -l "${SERVICE_USER}"

# Passwordless login shell as the service user. Runs bash directly: sudo -i would use the
# nologin shell and su would ask for the locked password.
install_validated 0440 "${SERVICE_SUDOERS_CONF}" "${SERVICE_SUDOERS_TEXT}"$'\n' visudo -c -f

# == REMOVE OTHER LOGIN USERS ==
# Runs last among the account steps. Only regular accounts (UID_MIN..UID_MAX from login.defs) are candidates.
# Preview only: PRUNE_DRY_RUN=1 bash alma-setup.sh
PRUNE_DRY_RUN="${PRUNE_DRY_RUN:-0}"
LOGIN_UID_MIN="$(awk '$1=="UID_MIN"{print $2}' /etc/login.defs)"
LOGIN_UID_MAX="$(awk '$1=="UID_MAX"{print $2}' /etc/login.defs)"
LOGIN_UID_MIN="${LOGIN_UID_MIN:-1000}"
LOGIN_UID_MAX="${LOGIN_UID_MAX:-60000}"
KEEP_USERS=("${ADMIN_USER}" "${SERVICE_USER}" "${SUDO_USER:-}")
while IFS= read -r stale_user; do
  for keep in "${KEEP_USERS[@]}"; do
    [[ "${stale_user}" == "${keep}" ]] && continue 2
  done
  if [[ "${PRUNE_DRY_RUN}" == "1" ]]; then
    echo "DRY RUN: would remove user ${stale_user}"
    continue
  fi
  echo "Removing user ${stale_user}"
  usermod -L -s /sbin/nologin "${stale_user}"
  pkill -KILL -u "${stale_user}" || true
  # userdel refuses while processes remain: wait up to ~10s
  for _ in $(seq 1 50); do
    pgrep -u "${stale_user}" > /dev/null || break
    sleep 0.2
  done
  # Drop sudoers grants that name this user (e.g. cloud-init's 90-cloud-init-users)
  { grep -lE "^${stale_user}[[:space:]]" "${SUDOERS_DIR}"/* 2>/dev/null || true; } | xargs -r rm -f
  userdel -r "${stale_user}" || echo "WARNING: could not fully remove ${stale_user}" >&2
done < <(awk -F: -v min="${LOGIN_UID_MIN}" -v max="${LOGIN_UID_MAX}" '$3>=min && $3<=max {print $1}' /etc/passwd)

# == LOGGING ==

# rsyslog: nftables drops
mkdir -p "$(dirname "${RSYSLOG_NFT_CONF}")"
printf '%s' "${RSYSLOG_NFT_TEXT}" > "${RSYSLOG_NFT_CONF}"
chmod 0644 "${RSYSLOG_NFT_CONF}"

# rsyslog: service-user switches
printf '%s' "${RSYSLOG_POPOLA_TEXT}" > "${RSYSLOG_POPOLA_CONF}"
chmod 0644 "${RSYSLOG_POPOLA_CONF}"

systemctl restart rsyslog

# Sudo log (30 days)
mkdir -p "$(dirname "${LOGROTATE_SUDO_CONF}")"
printf '%s' "${LOGROTATE_SUDO_TEXT}" > "${LOGROTATE_SUDO_CONF}"
chmod 0644 "${LOGROTATE_SUDO_CONF}"

# nftables log (postrotate reloads rsyslog to reopen the file)
printf '%s' "${LOGROTATE_NFT_TEXT}" > "${LOGROTATE_NFT_CONF}"
chmod 0644 "${LOGROTATE_NFT_CONF}"

# Service-user switch log (a year)
printf '%s' "${LOGROTATE_POPOLA_TEXT}" > "${LOGROTATE_POPOLA_CONF}"
chmod 0644 "${LOGROTATE_POPOLA_CONF}"

# == NETWORK HARDENING ==

mkdir -p "${NFT_DIR}"
printf '%s' "${NFT_RULES_TEXT}" > "${NFT_RULES_CONF}"
chmod 0644 "${NFT_RULES_CONF}"

# Include the ruleset in the main nftables config so it persists across reboots
grep -qxF "${NFT_INCLUDE}" "${NFT_SYSCONFIG}" || echo "${NFT_INCLUDE}" >> "${NFT_SYSCONFIG}"

# nftables is the only firewall manager: mask firewalld so it cannot load a second ruleset
systemctl disable --now firewalld 2>/dev/null || true
systemctl mask firewalld 2>/dev/null || true

systemctl enable nftables
systemctl restart nftables

# == STATIC IP ==
# Written as a NetworkManager keyfile here (before AIDE, so the baseline includes it).
# Activated as the last step of the script, see STATIC IP ACTIVATION.
if [ -n "${STATIC_IP}" ]; then
  STATIC_DNS_LINE=""
  if [ -n "${STATIC_DNS}" ]; then
    STATIC_DNS_LINE="dns=${STATIC_DNS// /;};"
  fi
  IFS= read -r -d '' STATIC_NM_TEXT << EOF || true
[connection]
id=${FILE_MIDFIX}-static
type=ethernet
interface-name=${STATIC_IFACE}
autoconnect=true
autoconnect-priority=${STATIC_NM_PRIORITY}

[ipv4]
method=manual
address1=${STATIC_IP},${STATIC_GATEWAY}
${STATIC_DNS_LINE}

[ipv6]
method=auto
EOF
  printf '%s\n' "${STATIC_NM_TEXT}" > "${STATIC_NM_CONF}"
  chmod 0600 "${STATIC_NM_CONF}"
  restorecon "${STATIC_NM_CONF}" 2>/dev/null || true
  nmcli connection reload
fi

# == FILE INTEGRITY (AIDE) ==
# Daily integrity check via systemd timer (see AIDE_HELPER_TEXT)
printf '%s' "${AIDE_HELPER_TEXT}" > "${AIDE_HELPER}"
chmod 0755 "${AIDE_HELPER}"
restorecon "${AIDE_HELPER}" 2>/dev/null || true
printf '%s' "${AIDE_SERVICE_TEXT}" > "${AIDE_SERVICE_UNIT}"
printf '%s' "${AIDE_TIMER_TEXT}" > "${AIDE_TIMER_UNIT}"
chmod 0644 "${AIDE_SERVICE_UNIT}" "${AIDE_TIMER_UNIT}"
printf '%s' "${LOGROTATE_AIDE_TEXT}" > "${LOGROTATE_AIDE_CONF}"
chmod 0644 "${LOGROTATE_AIDE_CONF}"

# Keep the baseline in step with unattended package updates
mkdir -p "${AIDE_DNF_DROPIN_DIR}"
printf '%s' "${AIDE_DNF_DROPIN_TEXT}" > "${AIDE_DNF_DROPIN_CONF}"
chmod 0644 "${AIDE_DNF_DROPIN_CONF}"
systemctl daemon-reload
# Enable now but start after the baseline exists, so the timer cannot fire against a missing DB
systemctl enable aide-check.timer

# Build the baseline last so the AIDE files above aren't reported as new (which would set
# AIDE_DRIFT_FLAG and block "update"). Skipped if one exists.
if [ ! -f "${AIDE_DB}" ]; then
  aide --init
  mv "${AIDE_DB_NEW}" "${AIDE_DB}"
fi
systemctl start aide-check.timer

# == STATIC IP ACTIVATION ==
# Last step: the address change drops an SSH session on the old address, so nothing may run after it.
# Delayed via a transient systemd unit so this script exits cleanly first.
if [ -n "${STATIC_IP}" ]; then
  systemd-run --unit="${FILE_MIDFIX}-static-ip-apply" --on-active="${STATIC_APPLY_DELAY}" \
    nmcli connection up "${FILE_MIDFIX}-static" > /dev/null
  echo "Static IP ${STATIC_IP} on ${STATIC_IFACE} will activate in ${STATIC_APPLY_DELAY}; an SSH session on the old address will drop"
fi

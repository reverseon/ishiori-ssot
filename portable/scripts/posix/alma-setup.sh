#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: this script must be run as root (try: sudo $0)" >&2
  exit 1
fi

FILE_MIDFIX="from-setup"

# Accounts
ADMIN_USER="devola"
SERVICE_USER="popola"
ADMIN_GROUP="wheel"

# Sudo (log path is shared with the logrotate stanza)
SUDO_LOG="/var/log/sudo.log"

# SSH (port is shared with the firewall rules; banner path with the sshd config)
SSH_PORT=22
# 00- prefix on purpose: sshd keeps the first value per option and reads the drop-ins alphabetically,
# so this must sort before 01-permitrootlogin.conf, 50-redhat.conf and 50-cloud-init.conf
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
  audit
  chrony
  aide
  cronie
  at
  rsyslog
  logrotate
  sssd
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

# A util-linux update (dnf-automatic applies these unattended) restores the packaged su mode,
# so a path unit and a timer re-apply it. The helper only writes when the mode drifted, otherwise
# its own chmod would fire the path unit again in a loop.
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
AUTHSELECT_PROFILE="sssd"
AUTHSELECT_FEATURES=(without-nullok with-faillock)

# Faillock
FAILLOCK_CONF="/etc/security/faillock.conf"
IFS= read -r -d '' FAILLOCK_CONF_TEXT << EOF || true
deny = 5
unlock_time = 900
EOF

# Session timeout
TIMEOUT_CONF="/etc/profile.d/${FILE_MIDFIX}-timeout.sh"
# Not readonly, so a long job can be run with "TMOUT=0"; skipped inside tmux/screen, where an idle
# pane is expected and the timeout would kill the multiplexer's shells
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
# Not applied to root's own shells. Commands run via sudo from a 027 shell would inherit that umask
# (sudo ORs the caller's umask with the sudoers one), so the sudo config sets "umask=0022" plus
# "umask_override" to keep files created under sudo (pip install, config, build output) readable by services
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

# rsyslog: every passwordless switch to the service user gets its own log file.
# Matched on sudo's own syslog line (written by root, so the service user cannot forge it) and
# without "& stop", so the line still reaches /var/log/secure. Point a forwarder or a log
# watcher at this file to get notified.
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

# logrotate: one self-contained stanza per managed log
# (a shared /var/log/*.log glob would overlap these files, and logrotate
# rejects a log file that appears in more than one stanza)
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

    # Accept ICMPv6 for diagnostics and for IPv6 to function (neighbor discovery, redirects,
    # error messages needed for path MTU discovery, MLD so multicast/ND keeps working)
    icmpv6 type { echo-request, destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, nd-router-solicit, nd-redirect, mld-listener-query, mld-listener-report, mld2-listener-report } accept

    # Accept DHCPv6 replies (server -> client port 546, link-local source); these do not
    # match conntrack when the request was sent to a multicast address
    ip6 saddr fe80::/10 udp sport 547 udp dport 546 accept

    # Accept DHCPv4 replies (server -> client port 68); broadcast offers/acks and T2 rebinds
    # do not match conntrack, so without this lease renewals can fail
    udp sport 67 udp dport 68 accept

    # Log and drop everything else (rate limited to 1 per second to prevent log flooding)
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
# One wrapper for both modes. aide exits 1-7 when it found differences (a bitmask of new/removed/changed)
# and 8 or more on real errors; differences are a finding, not a unit failure, so only errors exit non-zero.
# Findings go to a log file and to syslog (authpriv, so they land in /var/log/secure), not just the journal.
# "check" only reports. "update" refreshes the baseline and is run by dnf-automatic around its transaction:
# check BEFORE the update (anything found there is a real finding), update AFTER (package changes are expected).
# If that pre-check found drift, "update" leaves the baseline alone (see AIDE_DRIFT_FLAG), so the daily check
# keeps reporting it until an admin reviews it and runs "accept" (refresh baseline and clear the flag).
# All modes share a lock so the daily timer cannot overlap an update.
IFS= read -r -d '' AIDE_HELPER_TEXT << EOF || true
#!/bin/bash
set -u
mode="\${1:-check}"
mkdir -p "${AIDE_LOG_DIR}"
exec 9> "/run/${FILE_MIDFIX}-aide.lock"
flock 9
report="\$(mktemp)"
trap 'rm -f "\${report}"' EXIT
# A refresh would absorb whatever drift exists, so "update" refuses while ${AIDE_DRIFT_FLAG} exists.
# "check" sets it on any drift or error and clears it only on a clean run, so drift found by the pre-update
# check keeps alerting on every daily check until an admin reviews it and runs "accept".
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

NOTE: after a manual "dnf update", review the AIDE drift in ${AIDE_LOG},
then run "sudo ${AIDE_HELPER} accept". Until then, dnf-automatic will not refresh the AIDE baseline.
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

# == PACKAGE INSTALLATION ==
# Update system packages and install base tooling
dnf update -y
dnf install -y "${PACKAGES[@]}"

# == TIME SYNC ==
systemctl enable --now chronyd

# == JOB SCHEDULERS ==
systemctl enable --now crond
systemctl enable --now atd

# == AUTOMATIC UPDATES ==
# Security-only updates, applied by dnf-automatic.timer (whole-file config, owned by this script)
printf '%s' "${DNF_AUTOMATIC_CONF_TEXT}" > "${DNF_AUTOMATIC_CONF}"
chmod 0644 "${DNF_AUTOMATIC_CONF}"
systemctl enable --now dnf-automatic.timer

# == KERNEL HARDENING (sysctl) ==
printf '%s' "${SYSCTL_HARDENING_TEXT}" > "${SYSCTL_HARDENING_CONF}"
chmod 0644 "${SYSCTL_HARDENING_CONF}"
sysctl --system > /dev/null

# == AUDITING ==
# Watch identity, sudo and sshd config files, and the use of su/sudo
printf '%s' "${AUDIT_RULES_TEXT}" > "${AUDIT_RULES_CONF}"
chmod 0640 "${AUDIT_RULES_CONF}"
systemctl enable --now auditd
augenrules --load || echo "WARNING: could not load audit rules now (they apply on next boot)" >&2

# == ATTACK SURFACE REDUCTION ==
# Mask unused services (ignore ones the image does not ship)
for svc in "${MASKED_SERVICES[@]}"; do
  systemctl disable --now "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done

# Blacklist unused kernel modules; "install ... /bin/false" also blocks explicit modprobe
{
  for mod in "${BLACKLISTED_MODULES[@]}"; do
    echo "blacklist ${mod}"
    echo "install ${mod} /bin/false"
  done
} > "${MODPROBE_BLACKLIST_CONF}"
chmod 0644 "${MODPROBE_BLACKLIST_CONF}"

# The blacklist only stops future loads, so unload any of these that are already loaded.
# rmmod fails if the module is in use (e.g. usb-storage backing a mounted disk); that is left for the next reboot.
# Capture lsmod first: piping into `grep -q` under pipefail can SIGPIPE and report a false "not loaded".
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

# MOTD (Message of the Day) displayed after login
printf '%s\n%s' "${MOTD_TEXT}" "${MOTD_AIDE_NOTE}" > "${MOTD_PATH}"
chmod 0644 "${MOTD_PATH}"

# Sudo configuration via sudoers.d
# Enables PTY mode, sets auth cache timeout, and enables audit logging
mkdir -p "${SUDOERS_DIR}"

# install_validated MODE DEST TEXT VALIDATOR...
# Writes TEXT to a temp file and runs "VALIDATOR <tmpfile>" on it. Only a file that passes is installed,
# so a bad sudoers file or sshd drop-in never reaches its live directory. The install goes to DEST.new
# first (ignored by sudo and sshd, which skip names with a dot / not ending in .conf) and is then renamed.
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


# Set root password (pre-hashed, see ROOT_PASSWORD_HASH at top)
echo "root:${ROOT_PASSWORD_HASH}" | chpasswd -e

# Prevent empty passwords via authselect
# Ensures all user accounts require non-empty passwords
authselect select "${AUTHSELECT_PROFILE}" "${AUTHSELECT_FEATURES[@]}" --force

# Limit password guessing (console, sudo) with faillock
# The stock faillock.conf is comments only, so this script owns the whole file
printf '%s' "${FAILLOCK_CONF_TEXT}" > "${FAILLOCK_CONF}"
chmod 0644 "${FAILLOCK_CONF}"

# Session timeout (15 minutes of inactivity)
# Automatically logs out inactive shells to prevent unattended sessions
# Users can override it (TMOUT=0) and tmux/screen sessions are exempt, so this is a default, not a hard control
printf '%s' "${TIMEOUT_CONF_TEXT}" > "${TIMEOUT_CONF}"
chmod 0644 "${TIMEOUT_CONF}"

# Create devola user with sudo access (password hash: DEVOLA_PASSWORD_HASH at top)
id -u "${ADMIN_USER}" &>/dev/null || useradd -m -s "${ADMIN_SHELL}" "${ADMIN_USER}"
echo "${ADMIN_USER}:${DEVOLA_PASSWORD_HASH}" | chpasswd -e
usermod -aG "${ADMIN_GROUP}" "${ADMIN_USER}"

# Restrict su to the admin group by locking the binary (setuid kept, other users get no execute)
# A package update of util-linux can reset this, so a path unit + timer re-apply it (see SU_GUARD_*)
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

# Add admin user to sudoers with password requirement (already configured via timestamp_timeout)
install_validated 0440 "${ADMIN_SUDOERS_CONF}" "${ADMIN_SUDOERS_TEXT}"$'\n' visudo -c -f

# Configure admin user SSH public key authentication
# Download the Ishiori master public key and authorize it for the admin user
install -d -m 0700 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "${ADMIN_SSH_DIR}"
KEY_TMP="$(mktemp)"
trap 'rm -f "${KEY_TMP}"' EXIT
curl -fsSL "${ADMIN_PUBKEY_URL}" -o "${KEY_TMP}"
# Abort before touching sshd if the download is not a valid public key
KEY_INFO="$(ssh-keygen -l -f "${KEY_TMP}")"
# sshd only accepts ed25519 keys (PubkeyAcceptedAlgorithms) and password auth is off,
# so any other key type would lock the admin out. ssh-keygen -l prints "<bits> <fp> <comment> (<TYPE>)" per key.
if [ -z "${KEY_INFO}" ] || grep -qv '(ED25519)$' <<< "${KEY_INFO}"; then
  echo "Admin public key must be ssh-ed25519 only, got:" >&2
  echo "${KEY_INFO}" >&2
  exit 1
fi
install -m 0600 -o "${ADMIN_USER}" -g "${ADMIN_USER}" "${KEY_TMP}" "${ADMIN_AUTHORIZED_KEYS}"
restorecon -R "${ADMIN_SSH_DIR}" 2>/dev/null || true

# SSH hardening via sshd_config.d
# Applied only after the admin key is in place, so a failed key download cannot lock everyone out.
# Disables root login and password auth, requires SSH keys only
mkdir -p /etc/ssh/sshd_config.d

# SSH login banner with legal notice (written first, the drop-in references it)
printf '%s\n' "${SSH_BANNER_TEXT}" > "${SSH_BANNER}"
chmod 0644 "${SSH_BANNER}"

# The drop-in is syntax-checked standalone in a temp file and only then installed
install_validated 0644 "${SSH_CONF}" "${SSH_CONF_TEXT}" sshd -t -f

# Check the installed result as a whole before restarting
sshd -t

# Port is the exception to first-value-wins: it accumulates, so an explicit Port in the main config
# or another drop-in would make sshd listen on both. Comment those out (backup kept beside the file;
# a name not ending in .conf is not read by the sshd_config.d include).
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

# Safety net: after the cleanup above our port must be the only one left
SSHD_PORTS="$(awk 'tolower($1)=="port"{print $2}' <<< "${SSHD_EFFECTIVE}")"
[[ "${SSHD_PORTS}" == "${SSH_PORT}" ]] || { echo "sshd listens on unexpected port(s): $(tr '\n' ' ' <<< "${SSHD_PORTS}")(expected only ${SSH_PORT})" >&2; exit 1; }

systemctl restart sshd

# Create popola service-level user
# Cannot login directly (nologin shell, locked password), only reachable via
# sudo from the admin user: sudo -u popola /bin/bash -l
id -u "${SERVICE_USER}" &>/dev/null || useradd -m -s "${SERVICE_SHELL}" -c "${SERVICE_COMMENT}" "${SERVICE_USER}"

# Lock the account (no password login)
passwd -l "${SERVICE_USER}"

# Allow admin user to open a login shell as the service user without a password.
# Runs bash directly, because su/sudo -i would use the nologin shell and su would ask for the locked password.
install_validated 0440 "${SERVICE_SUDOERS_CONF}" "${SERVICE_SUDOERS_TEXT}"$'\n' visudo -c -f

# == LOGGING ==

# Configure rsyslog to send nftables logs to dedicated file
mkdir -p "$(dirname "${RSYSLOG_NFT_CONF}")"
printf '%s' "${RSYSLOG_NFT_TEXT}" > "${RSYSLOG_NFT_CONF}"
chmod 0644 "${RSYSLOG_NFT_CONF}"

# Switches to the service user (sudo -u popola) get a dedicated log
printf '%s' "${RSYSLOG_POPOLA_TEXT}" > "${RSYSLOG_POPOLA_CONF}"
chmod 0644 "${RSYSLOG_POPOLA_CONF}"

# Restart rsyslog to apply configuration
systemctl restart rsyslog

# Sudo logs (kept longer for audit trail, compressed)
mkdir -p "$(dirname "${LOGROTATE_SUDO_CONF}")"
printf '%s' "${LOGROTATE_SUDO_TEXT}" > "${LOGROTATE_SUDO_CONF}"
chmod 0644 "${LOGROTATE_SUDO_CONF}"

# nftables logs (postrotate reloads rsyslog so it reopens the file)
printf '%s' "${LOGROTATE_NFT_TEXT}" > "${LOGROTATE_NFT_CONF}"
chmod 0644 "${LOGROTATE_NFT_CONF}"

# Service-user switch log (kept a year, compressed)
printf '%s' "${LOGROTATE_POPOLA_TEXT}" > "${LOGROTATE_POPOLA_CONF}"
chmod 0644 "${LOGROTATE_POPOLA_CONF}"

# == NETWORK HARDENING ==

# Configure nftables firewall rules
mkdir -p "${NFT_DIR}"

# Create main nftables ruleset
printf '%s' "${NFT_RULES_TEXT}" > "${NFT_RULES_CONF}"
chmod 0644 "${NFT_RULES_CONF}"

# Add include statement to main nftables config for persistence on reboot
grep -qxF "${NFT_INCLUDE}" "${NFT_SYSCONFIG}" || echo "${NFT_INCLUDE}" >> "${NFT_SYSCONFIG}"

# nftables is the only firewall manager: stop and mask firewalld if the image ships it,
# so it cannot load its own ruleset alongside ours
systemctl disable --now firewalld 2>/dev/null || true
systemctl mask firewalld 2>/dev/null || true

# Enable nftables service to persist rules on reboot
systemctl enable nftables

# Load nftables rules by restarting the service
systemctl restart nftables

# == FILE INTEGRITY (AIDE) ==
# Daily integrity check via systemd timer; findings go to ${AIDE_LOG} and syslog (see AIDE_HELPER_TEXT)
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
# Enable now (creates the wants symlink) but start after the baseline exists, so the timer cannot fire against a missing DB
systemctl enable aide-check.timer

# Build the baseline last, after every AIDE-related file above is in place, so the first check does not
# report them as new (which would set AIDE_DRIFT_FLAG and block "update"). Skipped if one already exists.
if [ ! -f "${AIDE_DB}" ]; then
  aide --init
  mv "${AIDE_DB_NEW}" "${AIDE_DB}"
fi
systemctl start aide-check.timer

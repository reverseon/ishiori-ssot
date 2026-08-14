#! /bin/bash
# POSIX-compliant script for initial setup of freshly cloud-init initialized Linux instances. 

set -euo pipefail

usage() {
	echo "Usage: DEVOLA_PASSWORD=<password> POPOLA_PASSWORD=<password> $0 --hostname <hostname> [--fqdn <fqdn>] [--tz <timezone>] [--locale <locale>] [--keymap <keymap>] [--addr <ip/prefix>] [--gateway <ip>]" >&2
	exit 1
}

detect_pkg_mgr() {
	for mgr in apt-get dnf yum zypper pacman apk; do
		if command -v "$mgr" >/dev/null 2>&1; then
			echo "$mgr"
			return 0
		fi
	done
	return 1
}

HOSTNAME_ARG=""
FQDN_ARG=""
TZ_ARG=""
LOCALE_ARG=""
KEYMAP_ARG=""
ADDR_ARG=""
GATEWAY_ARG=""

while [ $# -gt 0 ]; do
	case "$1" in
	--hostname)
		[ $# -ge 2 ] || usage
		HOSTNAME_ARG="$2"
		shift 2
		;;
	--fqdn)
		[ $# -ge 2 ] || usage
		FQDN_ARG="$2"
		shift 2
		;;
	--tz)
		[ $# -ge 2 ] || usage
		TZ_ARG="$2"
		shift 2
		;;
	--locale)
		[ $# -ge 2 ] || usage
		LOCALE_ARG="$2"
		shift 2
		;;
	--keymap)
		[ $# -ge 2 ] || usage
		KEYMAP_ARG="$2"
		shift 2
		;;
	--addr)
		[ $# -ge 2 ] || usage
		ADDR_ARG="$2"
		shift 2
		;;
	--gateway)
		[ $# -ge 2 ] || usage
		GATEWAY_ARG="$2"
		shift 2
		;;
	*)
		usage
		;;
	esac
done

CURRENT_USER="$(id -un)"
if [ "$CURRENT_USER" != "sysinit" ] && [ "$CURRENT_USER" != "root" ]; then
	echo "This script must be run as the sysinit user or root" >&2
	exit 1
fi

[ -n "$HOSTNAME_ARG" ] || usage
[ -n "${DEVOLA_PASSWORD:-}" ] && [ -n "${POPOLA_PASSWORD:-}" ] || usage

if [ -z "$FQDN_ARG" ]; then
	FQDN_ARG="${HOSTNAME_ARG}.node.ishiori.net"
fi

if [ -z "$TZ_ARG" ]; then
	TZ_ARG="Asia/Tokyo"
fi

if [ -z "$LOCALE_ARG" ]; then
	LOCALE_ARG="ja_JP.UTF-8"
fi

if [ -z "$KEYMAP_ARG" ]; then
	KEYMAP_ARG="jp106"
fi

PKG_MGR="$(detect_pkg_mgr)" || {
	echo "No supported package manager found" >&2
	exit 1
}

case "$PKG_MGR" in
apt-get)
	sudo apt-get update
	sudo apt-get upgrade -y
	;;
dnf)
	sudo dnf upgrade --refresh -y
	;;
yum)
	sudo yum update -y
	;;
zypper)
	sudo zypper refresh
	sudo zypper update -y
	;;
pacman)
	sudo pacman -Syu --noconfirm
	;;
apk)
	sudo apk update
	sudo apk upgrade
	;;
esac

case "$PKG_MGR" in
dnf)
	sudo dnf install -y epel-release
	sudo dnf install -y curl wget vim git htop tmux unzip ca-certificates gnupg2 jq rsync lsof tree bind-utils net-tools bash-completion less
	;;
yum)
	sudo yum install -y epel-release
	sudo yum install -y curl wget vim git htop tmux unzip ca-certificates gnupg2 jq rsync lsof tree bind-utils net-tools bash-completion less
	;;
esac

case "$PKG_MGR" in
apt-get)
	sudo apt-get install -y curl wget vim git htop tmux unzip ca-certificates gnupg jq rsync lsof tree dnsutils net-tools bash-completion less
	;;
zypper)
	sudo zypper install -y curl wget vim git htop tmux unzip ca-certificates gpg2 jq rsync lsof tree bind-utils net-tools bash-completion less
	;;
pacman)
	sudo pacman -S --noconfirm --needed curl wget vim git htop tmux unzip ca-certificates gnupg jq rsync lsof tree bind bash-completion less
	;;
apk)
	sudo apk add curl wget vim git htop tmux unzip ca-certificates gnupg jq rsync lsof tree bind-tools net-tools bash-completion less
	;;
esac

if [ ! -f /swapfile ] && ! swapon --show=NAME --noheadings 2>/dev/null | grep -q .; then
	sudo fallocate -l 2G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
	sudo chmod 600 /swapfile
	sudo mkswap /swapfile
	sudo swapon /swapfile
fi

if ! grep -qE '^\S*/swapfile\s' /etc/fstab; then
	printf '/swapfile none swap sw 0 0\n' | sudo tee -a /etc/fstab >/dev/null
fi

sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-size-cap.conf >/dev/null <<-'EOF'
	[Journal]
	SystemMaxUse=500M
EOF
sudo systemctl restart systemd-journald 2>/dev/null || true

sudo mkdir -p /etc/sysctl.d
sudo tee /etc/sysctl.d/99-hardening.conf >/dev/null <<-'EOF'
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

	fs.suid_dumpable = 0
EOF
sudo sysctl --system >/dev/null 2>&1 || sudo sysctl -p /etc/sysctl.d/99-hardening.conf >/dev/null

sudo hostnamectl set-hostname "$FQDN_ARG"

if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
	sudo sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${FQDN_ARG} ${HOSTNAME_ARG}/" /etc/hosts
else
	printf '127.0.1.1\t%s %s\n' "$FQDN_ARG" "$HOSTNAME_ARG" | sudo tee -a /etc/hosts >/dev/null
fi

if [ -n "$ADDR_ARG" ] && [ -n "$GATEWAY_ARG" ]; then
	DNS_SERVERS="$GATEWAY_ARG 8.8.8.8 8.8.4.4"

	if command -v nmcli >/dev/null 2>&1; then
		CONN_NAME="$(nmcli -t -f NAME,DEVICE connection show | awk -F: -v d=eth0 '$2==d{print $1; exit}')"

		if [ -z "$CONN_NAME" ]; then
			sudo nmcli connection add type ethernet ifname eth0 con-name eth0
			CONN_NAME="eth0"
		fi

		sudo nmcli connection modify "$CONN_NAME" \
			ipv4.method manual \
			ipv4.addresses "$ADDR_ARG" \
			ipv4.gateway "$GATEWAY_ARG" \
			ipv4.dns "$DNS_SERVERS" \
			ipv6.method auto

		sudo nmcli connection up "$CONN_NAME"
	else
		ADDR_IP="${ADDR_ARG%%/*}"
		ADDR_PREFIX="${ADDR_ARG##*/}"

		BEGIN_MARKER="# BEGIN ishiori-ssot static eth0"
		END_MARKER="# END ishiori-ssot static eth0"

		sudo touch /etc/network/interfaces
		if grep -qF "$BEGIN_MARKER" /etc/network/interfaces; then
			sudo sed -i "/$BEGIN_MARKER/,/$END_MARKER/d" /etc/network/interfaces
		fi

		{
			echo "$BEGIN_MARKER"
			echo "auto eth0"
			echo "iface eth0 inet static"
			echo "    address ${ADDR_IP}"
			echo "    netmask ${ADDR_PREFIX}"
			echo "    gateway ${GATEWAY_ARG}"
			echo "    dns-nameservers ${DNS_SERVERS}"
			echo "iface eth0 inet6 auto"
			echo "$END_MARKER"
		} | sudo tee -a /etc/network/interfaces >/dev/null

		sudo systemctl restart networking 2>/dev/null || sudo rc-service networking restart 2>/dev/null || true
	fi
else
	echo "Skipping network configuration (--addr and --gateway both required)" >&2
fi

if command -v timedatectl >/dev/null 2>&1; then
	sudo timedatectl set-timezone "$TZ_ARG"

	case "$PKG_MGR" in
	apt-get)
		sudo apt-get install -y chrony
		;;
	dnf)
		sudo dnf install -y chrony
		;;
	yum)
		sudo yum install -y chrony
		;;
	zypper)
		sudo zypper install -y chrony
		;;
	pacman)
		sudo pacman -S --noconfirm --needed chrony
		;;
	esac

	if command -v chronyc >/dev/null 2>&1; then
		sudo systemctl enable --now chronyd 2>/dev/null || sudo systemctl enable --now chrony
	fi

	sudo timedatectl set-ntp true
else
	sudo ln -sf "/usr/share/zoneinfo/${TZ_ARG}" /etc/localtime

	if [ "$PKG_MGR" = "apk" ]; then
		sudo apk add chrony
		sudo rc-update add chronyd default
		sudo rc-service chronyd restart
	fi
fi

LOCALE_LANG="${LOCALE_ARG%%_*}"

case "$PKG_MGR" in
apt-get)
	if grep -qE "^# *${LOCALE_ARG} UTF-8" /etc/locale.gen; then
		sudo sed -i "s/^# *${LOCALE_ARG} UTF-8/${LOCALE_ARG} UTF-8/" /etc/locale.gen
	elif ! grep -qE "^${LOCALE_ARG} UTF-8" /etc/locale.gen; then
		printf '%s UTF-8\n' "$LOCALE_ARG" | sudo tee -a /etc/locale.gen >/dev/null
	fi
	sudo locale-gen
	sudo update-locale "LANG=${LOCALE_ARG}"
	;;
dnf)
	sudo dnf install -y "glibc-langpack-${LOCALE_LANG}"
	sudo localectl set-locale "LANG=${LOCALE_ARG}"
	;;
yum)
	sudo yum install -y "glibc-langpack-${LOCALE_LANG}"
	sudo localectl set-locale "LANG=${LOCALE_ARG}"
	;;
zypper)
	sudo zypper install -y glibc-locale
	sudo localectl set-locale "LANG=${LOCALE_ARG}"
	;;
pacman)
	if grep -qE "^# *${LOCALE_ARG} UTF-8" /etc/locale.gen; then
		sudo sed -i "s/^# *${LOCALE_ARG} UTF-8/${LOCALE_ARG} UTF-8/" /etc/locale.gen
	elif ! grep -qE "^${LOCALE_ARG} UTF-8" /etc/locale.gen; then
		printf '%s UTF-8\n' "$LOCALE_ARG" | sudo tee -a /etc/locale.gen >/dev/null
	fi
	sudo locale-gen
	sudo localectl set-locale "LANG=${LOCALE_ARG}"
	;;
apk)
	echo "musl libc (Alpine) has no locale-gen; skipping locale configuration" >&2
	;;
esac

if command -v localectl >/dev/null 2>&1; then
	sudo localectl set-keymap "$KEYMAP_ARG"
elif [ "$PKG_MGR" = "apk" ]; then
	echo "KEYMAP=${KEYMAP_ARG}" | sudo tee /etc/conf.d/keymaps >/dev/null
	sudo rc-service keymaps restart 2>/dev/null || true
else
	echo "No systemd/localectl available; skipping console keymap configuration" >&2
fi

case "$PKG_MGR" in
apt-get)
	sudo apt-get install -y nftables
	NFT_CONF="/etc/nftables.conf"
	;;
dnf)
	sudo dnf install -y nftables
	NFT_CONF="/etc/sysconfig/nftables.conf"
	;;
yum)
	sudo yum install -y nftables
	NFT_CONF="/etc/sysconfig/nftables.conf"
	;;
zypper)
	sudo zypper install -y nftables
	NFT_CONF="/etc/nftables.conf"
	;;
pacman)
	sudo pacman -S --noconfirm --needed nftables
	NFT_CONF="/etc/nftables.conf"
	;;
apk)
	sudo apk add nftables
	NFT_CONF="/etc/nftables.nft"
	;;
esac

sudo mkdir -p /etc/nftables.d
if [ -z "$(sudo find /etc/nftables.d -name '*.nft' -print -quit)" ]; then
	sudo tee /etc/nftables.d/00-placeholder.nft >/dev/null <<-EOF
		# Drop-in nftables rules go here (e.g. 10-http.nft with: tcp dport 80 accept).
		# Included into both the ip and ip6 input chains. Do not remove this file;
		# it keeps the include glob in the main ruleset from matching zero files.
	EOF
fi

sudo tee "$NFT_CONF" >/dev/null <<-EOF
	#!/usr/sbin/nft -f

	flush ruleset

	table ip filter {
		chain input {
			type filter hook input priority 0; policy drop;

			iif lo accept
			ct state established,related accept
			ct state invalid drop

			icmp type echo-request drop

			tcp dport 22 accept

			include "/etc/nftables.d/*.nft"
		}

		chain forward {
			type filter hook forward priority 0; policy drop;
		}

		chain output {
			type filter hook output priority 0; policy accept;
		}
	}

	table ip6 filter {
		chain input {
			type filter hook input priority 0; policy drop;

			iif lo accept
			ct state established,related accept
			ct state invalid drop

			icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert, packet-too-big, nd-redirect, parameter-problem, time-exceeded } accept
			icmpv6 type echo-request drop

			include "/etc/nftables.d/*.nft"
		}

		chain forward {
			type filter hook forward priority 0; policy drop;
		}

		chain output {
			type filter hook output priority 0; policy accept;
		}
	}
EOF

sudo nft -f "$NFT_CONF"

if command -v systemctl >/dev/null 2>&1; then
	sudo systemctl enable --now nftables
elif [ "$PKG_MGR" = "apk" ]; then
	sudo rc-update add nftables default
	sudo rc-service nftables restart
fi

sudo mkdir -p /etc/ssh/sshd_config.d

if ! grep -qE '^Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
	sudo sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

for keytype in rsa ecdsa dsa; do
	sudo sed -i -E "s|^(HostKey[[:space:]]+/etc/ssh/ssh_host_${keytype}_key)|#\1|" /etc/ssh/sshd_config
done

sudo tee /etc/issue.net >/dev/null <<-'EOF'

⣿⣿⣿⣿⣿⣷⣿⣿⣿⡅⡹⢿⠆⠙⠋⠉⠻⠿⣿⣿⣿⣿⣿⣿⣮⠻⣦⡙⢷⡑⠘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣌⠡⠌⠂⣙⠻⣛⠻⠷⠐⠈⠛⢱⣮⣷⣽⣿
⣿⣿⣿⣿⡇⢿⢹⣿⣶⠐⠁⠀⣀⣠⣤⠄⠀⠀⠈⠙⠻⣿⣿⣿⣦⣵⣌⠻⣷⢝⠦⠚⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢟⣻⣿⣊⡃⠀⣙⠿⣿⣿⣿⣎⢮⡀⢮⣽⣿⣿
⢿⣿⣿⣿⣧⡸⡎⡛⡩⠖⠀⣴⣿⣿⣿⠀⠀⠀⠀⠸⠇⠀⠙⢿⣿⣿⣿⣷⣌⢷⣑⢷⣄⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⣫⠶⠛⠉⠀⠁⠀⠈⠈⠀⠠⠜⠻⣿⣆⢿⣼⣿⣿⣿
⢐⣿⣿⣿⣿⣧⢧⣧⢻⣦⢀⣹⣿⣿⣿⣇⠀⠄⠀⠀⠀⡀⠀⠈⢻⣿⣿⣿⣿⣷⣝⢦⡹⠷⡙⢿⣿⣿⣿⣿⣿⣿⣿⣿⠈⠁⠀⠀⠀⠁⠀⠀⠀⠱⣶⣄⡀⠀⠈⠛⠜⣿⣿⣿⣿
⠀⠊⢫⣿⣏⣿⡌⣼⣄⢫⡌⣿⣿⣿⣿⣿⣦⡈⠲⣄⣤⣤⡡⢀⣠⣿⣿⣿⣿⣿⣿⣷⣼⣍⢬⣦⡙⣿⣿⣿⣿⣿⣯⢁⡄⠀⡀⡀⠀⠄⢈⣠⢪⠀⣿⣿⣿⣦⠀⢉⢂⠹⡿⣿⣿
⠀⠀⠄⢹⢃⢻⣟⠙⣿⣦⠱⢻⣿⣿⣿⣿⣿⣿⣷⣬⣍⣭⣥⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⡙⢿⣼⡿⣿⣿⣿⣿⣿⣷⣄⠘⣱⢦⣤⡴⡿⢈⣼⣿⣿⣿⣇⣴⣶⣮⣅⢻⣿⡏
⠀⠀⠈⠹⣇⢡⢿⡆⠻⣿⣷⠀⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣍⡻⣿⣟⣻⣿⣿⣿⣿⣷⣦⣥⣬⣤⣴⣾⣿⣿⣿⣿⣷⣿⣿⣿⣿⣷⡜⠃
⠀⠀⠀⢀⣘⠈⢂⠃⣧⡹⣿⣷⡄⠙⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣮⣅⡙⢿⣟⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠋⡕⠂
⠀⠀⠀⠀⠀⠀⠛⢷⣜⢷⡌⠻⣿⣿⣦⣝⣻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣯⣹⣷⣦⣹⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠉⠃⠀

EOF

sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<-'EOF'
	HostKey /etc/ssh/ssh_host_ed25519_key

	PermitRootLogin no
	PasswordAuthentication no
	PermitEmptyPasswords no
	KbdInteractiveAuthentication no
	Protocol 2

	MaxAuthTries 5
	MaxStartups 50
	LoginGraceTime 30

	X11Forwarding no
	AllowAgentForwarding yes
	AllowTcpForwarding yes

	ClientAliveInterval 300
	ClientAliveCountMax 2

	Banner /etc/issue.net
EOF

sudo sshd -t

if [ "$PKG_MGR" = "apt-get" ]; then
	SSH_SVC="ssh"
else
	SSH_SVC="sshd"
fi

if command -v systemctl >/dev/null 2>&1; then
	sudo systemctl reload "$SSH_SVC" 2>/dev/null || sudo systemctl restart "$SSH_SVC"
elif [ "$PKG_MGR" = "apk" ]; then
	sudo rc-service "$SSH_SVC" restart
fi

case "$PKG_MGR" in
apt-get)
	sudo apt-get install -y sudo bash
	;;
dnf)
	sudo dnf install -y sudo bash
	;;
yum)
	sudo yum install -y sudo bash
	;;
zypper)
	sudo zypper install -y sudo bash
	;;
pacman)
	sudo pacman -S --noconfirm --needed sudo bash
	;;
apk)
	sudo apk add sudo bash
	;;
esac

BASH_PATH="$(command -v bash)"

for entry in "devola:${DEVOLA_PASSWORD}" "popola:${POPOLA_PASSWORD}"; do
	user="${entry%%:*}"
	pass="${entry#*:}"

	if ! id -u "$user" >/dev/null 2>&1; then
		sudo useradd -m -s "$BASH_PATH" "$user"
	fi

	printf '%s:%s\n' "$user" "$pass" | sudo chpasswd

	printf '%s ALL=(ALL:ALL) ALL\n' "$user" | sudo tee "/etc/sudoers.d/${user}" >/dev/null
	sudo chmod 0440 "/etc/sudoers.d/${user}"
	sudo visudo -cf "/etc/sudoers.d/${user}"
done

case "$PKG_MGR" in
apt-get)
	sudo apt-get install -y unattended-upgrades

	sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<-'EOF'
		APT::Periodic::Update-Package-Lists "1";
		APT::Periodic::Download-Upgradeable-Packages "1";
		APT::Periodic::AutocleanInterval "7";
		APT::Periodic::Unattended-Upgrade "1";
	EOF

	sudo tee /etc/apt/apt.conf.d/52auto-reboot >/dev/null <<-'EOF'
		Unattended-Upgrade::Automatic-Reboot "true";
		Unattended-Upgrade::Automatic-Reboot-Time "04:00";
	EOF

	sudo systemctl enable --now unattended-upgrades
	;;
dnf)
	sudo dnf install -y dnf-automatic dnf-utils

	sudo sed -i \
		-e 's/^apply_updates.*/apply_updates = yes/' \
		-e 's/^upgrade_type.*/upgrade_type = security/' \
		/etc/dnf/automatic.conf

	sudo systemctl enable --now dnf-automatic.timer
	;;
yum)
	sudo yum install -y yum-cron yum-utils

	sudo sed -i \
		-e 's/^apply_updates.*/apply_updates = yes/' \
		-e 's/^update_cmd.*/update_cmd = security/' \
		/etc/yum/yum-cron.conf

	sudo systemctl enable --now yum-cron
	;;
zypper)
	sudo zypper install -y cron

	sudo tee /etc/cron.daily/zypper-security-updates >/dev/null <<-'EOF'
		#!/bin/sh
		zypper --non-interactive patch --category security
	EOF
	sudo chmod 0755 /etc/cron.daily/zypper-security-updates

	sudo systemctl enable --now cron 2>/dev/null || sudo systemctl enable --now crond
	;;
pacman)
	# Arch has no separate security-only channel; this applies full updates daily.
	sudo tee /etc/systemd/system/pacman-upgrade.service >/dev/null <<-'EOF'
		[Unit]
		Description=Automatic system upgrade

		[Service]
		Type=oneshot
		ExecStart=/usr/bin/pacman -Syu --noconfirm
	EOF
	sudo tee /etc/systemd/system/pacman-upgrade.timer >/dev/null <<-'EOF'
		[Unit]
		Description=Daily automatic system upgrade

		[Timer]
		OnCalendar=daily
		Persistent=true

		[Install]
		WantedBy=timers.target
	EOF

	sudo systemctl daemon-reload
	sudo systemctl enable --now pacman-upgrade.timer
	;;
apk)
	# Alpine has no separate security-only channel; this applies full updates daily.
	sudo tee /etc/periodic/daily/apk-upgrade >/dev/null <<-'EOF'
		#!/bin/sh
		apk update && apk upgrade
	EOF
	sudo chmod 0755 /etc/periodic/daily/apk-upgrade

	sudo rc-update add crond default
	sudo rc-service crond restart
	;;
esac

if [ "$PKG_MGR" != "apt-get" ]; then
	sudo tee /usr/local/sbin/ishiori-auto-reboot.sh >/dev/null <<-'EOF'
		#!/bin/sh
		if [ -f /var/run/reboot-required ]; then
			NEED_REBOOT=1
		elif command -v needs-restarting >/dev/null 2>&1; then
			if needs-restarting -r >/dev/null 2>&1; then
				NEED_REBOOT=0
			else
				NEED_REBOOT=1
			fi
		elif command -v zypper >/dev/null 2>&1; then
			zypper needs-rebooting >/dev/null 2>&1
			if [ $? -eq 102 ]; then
				NEED_REBOOT=1
			else
				NEED_REBOOT=0
			fi
		else
			NEED_REBOOT=1
		fi

		if [ "$NEED_REBOOT" = "1" ]; then
			systemctl reboot 2>/dev/null || reboot
		fi
	EOF
	sudo chmod 0755 /usr/local/sbin/ishiori-auto-reboot.sh

	if command -v systemctl >/dev/null 2>&1; then
		sudo tee /etc/systemd/system/ishiori-auto-reboot.service >/dev/null <<-'EOF'
			[Unit]
			Description=Reboot if required after automatic updates

			[Service]
			Type=oneshot
			ExecStart=/usr/local/sbin/ishiori-auto-reboot.sh
		EOF
		sudo tee /etc/systemd/system/ishiori-auto-reboot.timer >/dev/null <<-'EOF'
			[Unit]
			Description=Daily check to reboot if required

			[Timer]
			OnCalendar=*-*-* 04:00:00
			Persistent=true

			[Install]
			WantedBy=timers.target
		EOF

		sudo systemctl daemon-reload
		sudo systemctl enable --now ishiori-auto-reboot.timer
	elif [ "$PKG_MGR" = "apk" ]; then
		if ! sudo grep -qF /usr/local/sbin/ishiori-auto-reboot.sh /etc/crontabs/root 2>/dev/null; then
			printf '0 4 * * * /usr/local/sbin/ishiori-auto-reboot.sh\n' | sudo tee -a /etc/crontabs/root >/dev/null
		fi
		sudo rc-service crond restart
	fi
fi

SYSINIT_USER="sysinit"

if id -u "$SYSINIT_USER" >/dev/null 2>&1; then
	CLEANUP_CMD="pkill -KILL -u ${SYSINIT_USER}; userdel -r -f ${SYSINIT_USER}; rm -f /etc/sudoers.d/*${SYSINIT_USER}*"

	if command -v systemd-run >/dev/null 2>&1; then
		sudo systemd-run --on-active=10 --unit="${SYSINIT_USER}-cleanup" \
			--description="Remove bootstrap ${SYSINIT_USER} user" \
			/bin/sh -c "$CLEANUP_CMD"
	else
		sudo sh -c "setsid nohup sh -c 'sleep 10; ${CLEANUP_CMD}' >/dev/null 2>&1 </dev/null &"
	fi

	echo "${SYSINIT_USER} user scheduled for removal in ~10s (this will kill the session running this script if invoked as ${SYSINIT_USER})" >&2
fi

"""Unattended security updates (unattended-upgrades), plus a reboot-required notice after every
apt-daily-upgrade run and daily."""

import subprocess

import texts
from actions import Cmd, EnsureDir, Systemctl, WriteFile
from config import MIDFIX, Config

UNITS = "/etc/systemd/system"
NOTHING_PENDING = "No packages found that can be upgraded unattended"


def _no_security_updates() -> bool:
    """unattended-upgrade --dry-run -d logs to stderr; it names the empty case explicitly."""
    try:
        result = subprocess.run(["unattended-upgrade", "--dry-run", "-d"], text=True, capture_output=True)
    except FileNotFoundError:
        return False
    return NOTHING_PENDING in result.stdout + result.stderr


def actions(c: Config):
    service, timer = f"{MIDFIX}-reboot-check.service", f"{MIDFIX}-reboot-check.timer"
    return [
        WriteFile(
            path="/etc/apt/apt.conf.d/20auto-upgrades",
            text=texts.AUTO_UPGRADES_CONF,
        ),
        WriteFile(
            path=c.unattended_conf,
            text=texts.unattended_conf(),
        ),
        Systemctl(
            verb="enable_now",
            units=["apt-daily.timer", "apt-daily-upgrade.timer"],
        ),
        # Apply what is pending now (security archive only, per the config above)
        Cmd(
            name="unattended-upgrade (security only)",
            argv=["unattended-upgrade"],
            done=_no_security_updates,
        ),
        WriteFile(
            path=c.reboot_check_bin,
            text=texts.reboot_check_bin(c),
            mode=0o755,
        ),
        WriteFile(
            path=f"{UNITS}/{service}",
            text=texts.reboot_check_service(c),
        ),
        # Daily as well, so a manual "apt upgrade" is noticed too
        WriteFile(
            path=f"{UNITS}/{timer}",
            text=texts.daily_timer("Daily reboot-required check"),
        ),
        EnsureDir(
            path=c.apt_dropin_dir,
        ),
        WriteFile(
            path=f"{c.apt_dropin_dir}/98-{MIDFIX}-reboot-check.conf",
            text=texts.reboot_apt_dropin(c),
        ),
        Systemctl(
            verb="daemon_reload",
            units=[service, timer, "apt-daily-upgrade.service"],
        ),
        Systemctl(
            verb="enable_now",
            units=[timer],
        ),
    ]

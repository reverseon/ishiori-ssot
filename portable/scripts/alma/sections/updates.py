"""Unattended security updates, plus a reboot-required notice after every dnf-automatic run and daily."""

import texts
from actions import EnsureDir, Systemctl, WriteFile
from config import MIDFIX, Config

UNITS = "/etc/systemd/system"


def actions(c: Config):
    service, timer = f"{MIDFIX}-reboot-check.service", f"{MIDFIX}-reboot-check.timer"
    return [
        WriteFile(
            path="/etc/dnf/automatic.conf",
            text=texts.DNF_AUTOMATIC_CONF,
        ),
        Systemctl(
            verb="enable_now",
            units=["dnf-automatic.timer"],
        ),
        WriteFile(
            path=c.reboot_check_bin,
            text=texts.reboot_check_bin(c),
            mode=0o755,
            relabel=True,
        ),
        WriteFile(
            path=f"{UNITS}/{service}",
            text=texts.reboot_check_service(c),
        ),
        # Daily as well, so a manual "dnf update" is noticed too
        WriteFile(
            path=f"{UNITS}/{timer}",
            text=texts.daily_timer("Daily reboot-required check"),
        ),
        EnsureDir(
            path=c.aide_dnf_dropin_dir,
        ),
        WriteFile(
            path=f"{c.aide_dnf_dropin_dir}/98-{MIDFIX}-reboot-check.conf",
            text=texts.reboot_dnf_dropin(c),
        ),
        Systemctl(
            verb="daemon_reload",
        ),
        Systemctl(
            verb="enable_now",
            units=[timer],
        ),
    ]

"""File integrity (AIDE): daily check via systemd timer, baseline kept in step with unattended updates."""

import os
import shutil

import texts
from actions import EnsureDir, Func, Systemctl, WriteFile, sh
from config import MIDFIX, Config

UNITS = "/etc/systemd/system"


def _init_baseline(c: Config) -> None:
    sh("aide", "--init")
    shutil.move(c.aide_db_new, c.aide_db)


def actions(c: Config):
    return [
        WriteFile(
            path=c.aide_helper,
            text=texts.aide_helper(c),
            mode=0o755,
            relabel=True,
        ),
        WriteFile(
            path=f"{UNITS}/aide-check.service",
            text=texts.aide_service(c),
        ),
        WriteFile(
            path=f"{UNITS}/aide-check.timer",
            text=texts.daily_timer("Daily AIDE integrity check"),
        ),
        WriteFile(
            path=f"/etc/logrotate.d/99-{MIDFIX}-aide",
            text=texts.logrotate(c.aide_log, "weekly", 12),
        ),
        # Keep the baseline in step with unattended package updates
        EnsureDir(
            path=c.aide_dnf_dropin_dir,
        ),
        WriteFile(
            path=f"{c.aide_dnf_dropin_dir}/99-{MIDFIX}-aide.conf",
            text=texts.aide_dnf_dropin(c),
        ),
        Systemctl(
            verb="daemon_reload",
        ),
        # Enable now but start after the baseline exists, so the timer cannot fire against a missing DB
        Systemctl(
            verb="enable",
            units=["aide-check.timer"],
        ),
        # Built last so the AIDE files above aren't reported as new (which would set the drift flag and
        # block "update"). Skipped if one exists.
        Func(
            name="build AIDE baseline",
            run=lambda: _init_baseline(c),
            pre=lambda: os.path.isfile(c.aide_db),
            post=lambda: os.path.isfile(c.aide_db),
        ),
        Systemctl(
            verb="start",
            units=["aide-check.timer"],
        ),
    ]

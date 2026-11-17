"""Base tooling, then time sync and job schedulers. Security updates are applied in updates.py, once
unattended-upgrades is installed and configured to the security archive only."""

import time
from pathlib import Path

from actions import AptInstall, Cmd, Systemctl
from config import Config

LISTS = Path("/var/lib/apt/lists")


def _lists_fresh(max_age: int = 86400) -> bool:
    files = [f for f in LISTS.glob("*") if f.is_file() and f.name != "lock"] if LISTS.is_dir() else []
    return bool(files) and time.time() - max(f.stat().st_mtime for f in files) < max_age


def actions(c: Config):
    return [
        Cmd(
            name="apt-get update",
            argv=["apt-get", "update"],
            done=_lists_fresh,
        ),
        AptInstall(
            packages=c.packages,
        ),
        Systemctl(
            verb="enable_now",
            units=["chrony"],
        ),
        Systemctl(
            verb="enable_now",
            units=["cron"],
        ),
        Systemctl(
            verb="enable_now",
            units=["atd"],
        ),
    ]

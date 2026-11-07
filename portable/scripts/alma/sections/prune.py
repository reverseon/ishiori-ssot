"""Remove every other regular login user. Runs last among the account steps.

Only regular accounts (UID_MIN..UID_MAX from login.defs) are candidates. Preview: PRUNE_DRY_RUN=1.
"""

import logging
import re
import time
from pathlib import Path

from actions import Func, ok, sh
from config import Config

log = logging.getLogger(__name__)


def _uid_range() -> tuple[int, int]:
    values = {}
    for line in Path("/etc/login.defs").read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("UID_MIN", "UID_MAX"):
            values[parts[0]] = int(parts[1])
    return values.get("UID_MIN", 1000), values.get("UID_MAX", 60000)


def stale_users(c: Config) -> list[str]:
    import pwd
    low, high = _uid_range()
    keep = {c.admin_user, c.service_user, c.sudo_user}
    return [u.pw_name for u in pwd.getpwall() if low <= u.pw_uid <= high and u.pw_name not in keep]


def _remove(c: Config, user: str) -> None:
    log.info("Removing user %s", user)
    sh("usermod", "-L", "-s", "/sbin/nologin", user)
    sh("pkill", "-KILL", "-u", user, check=False)
    for _ in range(50):  # userdel refuses while processes remain: wait up to ~10s
        if not ok("pgrep", "-u", user):
            break
        time.sleep(0.2)
    # Drop sudoers grants that name this user (e.g. cloud-init's 90-cloud-init-users)
    pattern = re.compile(rf"^{re.escape(user)}\s", re.MULTILINE)
    for f in Path(c.sudoers_dir).iterdir():
        if f.is_file() and pattern.search(f.read_text(errors="replace")):
            f.unlink()
    if sh("userdel", "-r", user, check=False).returncode != 0:
        log.warning("could not fully remove %s", user)


def _run(c: Config) -> None:
    for user in stale_users(c):
        if c.prune_dry_run:
            log.info("DRY RUN: would remove user %s", user)
        else:
            _remove(c, user)


def actions(c: Config):
    return [
        Func(
            name="remove other login users",
            run=lambda: _run(c),
            pre=lambda: not stale_users(c),
            post=lambda: c.prune_dry_run or not stale_users(c),
        ),
    ]

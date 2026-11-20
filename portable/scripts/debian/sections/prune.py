"""Remove every other regular login user. Runs last among the account steps.

Only regular accounts (UID_MIN..UID_MAX from login.defs) are candidates. Preview: the default check run lists who would be removed.
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


def _accounts_ready(c: Config) -> bool:
    """The admin and service accounts exist, the admin is in the admin group, and the admin key is installed."""
    import grp
    import pwd
    try:
        pwd.getpwnam(c.admin_user)
        pwd.getpwnam(c.service_user)
        if c.admin_user not in grp.getgrnam(c.admin_group).gr_mem:
            return False
    except KeyError:
        return False
    fields = c.admin_pubkey.split()
    if len(fields) < 2:
        return False
    try:
        return fields[1] in Path(c.admin_authorized_keys).read_text()
    except OSError:
        return False


def stale_users(c: Config) -> list[str]:
    import pwd
    low, high = _uid_range()
    keep = {c.admin_user, c.service_user}
    # The account that ran sudo goes too, but only once admin and service accounts are in place
    if c.sudo_user and not _accounts_ready(c):
        keep.add(c.sudo_user)
    return [u.pw_name for u in pwd.getpwall() if low <= u.pw_uid <= high and u.pw_name not in keep]


def _remove(c: Config, user: str) -> None:
    log.info("Removing user %s", user)
    sh("usermod", "-L", "-s", "/usr/sbin/nologin", user)
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
    if c.sudo_user and not _accounts_ready(c):
        log.warning("keeping %s (the account that ran sudo): admin and service accounts are not ready", c.sudo_user)
    for user in stale_users(c):
        _remove(c, user)


def actions(c: Config):
    def pre() -> bool:
        users = stale_users(c)
        action.precheck_detail = f"would remove: {', '.join(users)}" if users else ""  # shown by the check run
        return not users

    action = Func(
        name="remove other login users",
        run=lambda: _run(c),
        pre=pre,
        post=lambda: not stale_users(c),
    )
    return [action]

"""Attack surface reduction: unused services/modules, cron/at allow-lists, umask, core dumps, /dev/shm."""

import logging

import texts
from actions import Cmd, EnsureDir, Func, Systemctl, WriteFile, out, sh
from config import MIDFIX, Config

log = logging.getLogger(__name__)


def _loaded(c: Config) -> list[str]:
    with open("/proc/modules", encoding="utf-8") as f:
        names = {line.split()[0] for line in f}
    return [m.replace("-", "_") for m in c.blacklisted_modules if m.replace("-", "_") in names]


def _unload(c: Config) -> None:
    # Ones in use are left for the next reboot
    for name in _loaded(c):
        if sh("rmmod", name, check=False).returncode != 0:
            log.warning("%s is loaded and in use, blacklist applies after reboot", name)


def _shm_remounted(c: Config) -> bool:
    current = out("findmnt", "-no", "OPTIONS", "/dev/shm").split(",")
    return all(opt in current for opt in c.shm_remount_opts.split(","))


def actions(c: Config):
    shm_dir = "/etc/systemd/system/dev-shm.mount.d"
    acts = []
    # Mask unused services (missing ones are ignored)
    for svc in c.masked_services:
        acts += [
            Systemctl(
                verb="disable_now",
                units=[svc],
                continue_on_error=True,
            ),
            Systemctl(
                verb="mask",
                units=[svc],
                continue_on_error=True,
            ),
        ]
    acts += [
        WriteFile(
            path=f"/etc/modprobe.d/99-{MIDFIX}-blacklist.conf",
            text=texts.modprobe_blacklist(c),
        ),
        Func(
            name="unload blacklisted modules",
            run=lambda: _unload(c),
            pre=lambda: not _loaded(c),
            continue_on_error=True,
        ),
        # Allow-list for cron and at: only these users (root is always allowed by cronie)
        WriteFile(
            path="/etc/cron.allow",
            text=texts.allow_list(c),
            mode=0o600,
        ),
        WriteFile(
            path="/etc/at.allow",
            text=texts.allow_list(c),
            mode=0o600,
        ),
        # Restrictive default permissions for interactive shells
        WriteFile(
            path=f"/etc/profile.d/99-{MIDFIX}-umask.sh",
            text=texts.UMASK_CONF,
        ),
        # Disable core dumps
        WriteFile(
            path=f"/etc/security/limits.d/99-{MIDFIX}-nocore.conf",
            text=texts.LIMITS_NOCORE,
        ),
        WriteFile(
            path=f"/etc/sysctl.d/99-{MIDFIX}-nocore.conf",
            text=texts.SYSCTL_NOCORE,
        ),
        Cmd(
            name="apply sysctl",
            argv=["sysctl", "--system"],
        ),
        # Mount /dev/shm noexec,nosuid,nodev via a unit drop-in
        EnsureDir(
            path=shm_dir,
        ),
        WriteFile(
            path=f"{shm_dir}/99-{MIDFIX}.conf",
            text=texts.SHM_DROPIN,
        ),
        Systemctl(
            verb="daemon_reload",
        ),
        Cmd(
            name="remount /dev/shm",
            argv=["mount", "-o", f"remount,{c.shm_remount_opts}", "/dev/shm"],
            done=lambda: _shm_remounted(c),
            continue_on_error=True,
        ),
    ]
    return acts

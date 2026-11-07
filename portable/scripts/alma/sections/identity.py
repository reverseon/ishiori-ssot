"""Accounts and local access policy: MOTD, sudo, passwords, faillock, admin user, su restriction, admin SSH key."""

import os

import texts
from actions import Cmd, EnsureDir, Func, Systemctl, WriteFile, ok, out, sh
from config import MIDFIX, Config

UNITS = "/etc/systemd/system"


def password(user: str, hash_: str) -> Cmd:
    def current() -> bool:
        fields = out("getent", "shadow", user).split(":")
        return len(fields) > 1 and fields[1] == hash_
    return Cmd(
        name=f"password for {user}",
        argv=["chpasswd", "-e"],
        input=f"{user}:{hash_}\n",
        done=current,
    )


def _su_ok(c: Config) -> bool:
    import grp
    st = os.stat(c.su_bin)
    return (st.st_mode & 0o7777) == c.su_mode and grp.getgrgid(st.st_gid).gr_name == c.admin_group


def _su_restrict(c: Config) -> None:
    sh("chgrp", c.admin_group, c.su_bin)
    os.chmod(c.su_bin, c.su_mode)


def _authselect_ok(c: Config) -> bool:
    current = out("authselect", "current", "-r").split()
    return bool(current) and current[0] == c.authselect_profile and set(c.authselect_features) <= set(current[1:])


def actions(c: Config):
    return [
        WriteFile(
            path="/etc/motd",
            text=texts.motd(c),
        ),
        EnsureDir(
            path=c.sudoers_dir,
        ),
        WriteFile(
            path=c.sudo_conf,
            text=texts.sudo_conf(c),
            mode=0o440,
            validator=["visudo", "-c", "-f"],
        ),
        password("root", c.root_password_hash),
        # Disallow empty passwords via authselect
        Cmd(
            name="authselect profile",
            argv=["authselect", "select", c.authselect_profile, *c.authselect_features, "--force"],
            done=lambda: _authselect_ok(c),
        ),
        # Limit password guessing (stock file is comments only, so we own it whole)
        WriteFile(
            path="/etc/security/faillock.conf",
            text=texts.FAILLOCK_CONF,
        ),
        # Session timeout (15 minutes idle); a default, not a hard control
        WriteFile(
            path=f"/etc/profile.d/{MIDFIX}-timeout.sh",
            text=texts.TIMEOUT_CONF,
        ),
        # Admin user
        Cmd(
            name=f"create {c.admin_user}",
            argv=["useradd", "-m", "-s", c.admin_shell, c.admin_user],
            done=lambda: ok("id", "-u", c.admin_user),
        ),
        password(c.admin_user, c.admin_password_hash),
        Cmd(
            name=f"{c.admin_user} in {c.admin_group}",
            argv=["usermod", "-aG", c.admin_group, c.admin_user],
            done=lambda: c.admin_group in out("id", "-nG", c.admin_user).split(),
        ),
        # Restrict su to the admin group (re-applied by the su-guard units after package updates)
        Func(
            name=f"restrict {c.su_bin}",
            run=lambda: _su_restrict(c),
            pre=lambda: _su_ok(c),
            post=lambda: _su_ok(c),
        ),
        WriteFile(
            path=c.su_guard_bin,
            text=texts.su_guard_bin(c),
            mode=0o755,
            relabel=True,
        ),
        WriteFile(
            path=f"{UNITS}/{c.su_guard_service}",
            text=texts.su_guard_service(c),
        ),
        WriteFile(
            path=f"{UNITS}/{c.su_guard_path}",
            text=texts.su_guard_path(c),
        ),
        WriteFile(
            path=f"{UNITS}/{c.su_guard_timer}",
            text=texts.su_guard_timer(c),
        ),
        Systemctl(
            verb="daemon_reload",
        ),
        Systemctl(
            verb="enable_now",
            units=[c.su_guard_path, c.su_guard_timer],
        ),
        # Admin sudo access (password required)
        WriteFile(
            path=c.admin_sudoers_conf,
            text=texts.admin_sudoers(c),
            mode=0o440,
            validator=["visudo", "-c", "-f"],
        ),
        # Authorize the master public key for the admin user
        EnsureDir(
            path=c.admin_ssh_dir,
            mode=0o700,
            owner=c.admin_user,
            group=c.admin_user,
            relabel=True,
        ),
        WriteFile(
            path=c.admin_authorized_keys,
            text=c.admin_pubkey,
            mode=0o600,
            owner=c.admin_user,
            group=c.admin_user,
            relabel=True,
        ),
    ]

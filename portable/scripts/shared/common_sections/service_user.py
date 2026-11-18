"""Service user: no direct login (nologin shell, locked password), reachable only via sudo from the admin."""

import texts
from actions import Cmd, WriteFile, ok, out
from config import Config


def _locked(user: str) -> bool:
    fields = out("passwd", "-S", user).split()
    return len(fields) > 1 and fields[1] in ("L", "LK")


def actions(c: Config):
    return [
        # No home directory (-M, /nonexistent)
        Cmd(
            name=f"create {c.service_user}",
            argv=["useradd", "-M", "-d", "/nonexistent", "-s", c.service_shell, "-c", c.service_comment, c.service_user],
            done=lambda: ok("id", "-u", c.service_user),
        ),
        Cmd(
            name=f"lock {c.service_user}",
            argv=["passwd", "-l", c.service_user],
            done=lambda: _locked(c.service_user),
        ),
        # Runs bash directly: sudo -i would use the nologin shell and su would ask for the locked password
        WriteFile(
            path=c.service_sudoers_conf,
            text=texts.service_sudoers(c),
            mode=0o440,
            validator=["visudo", "-c", "-f"],
        ),
    ]

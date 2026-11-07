"""Kernel hardening (sysctl) and auditing."""

import texts
from actions import Cmd, Systemctl, WriteFile
from config import MIDFIX, Config


def actions(c: Config):
    return [
        WriteFile(
            path=f"/etc/sysctl.d/99-{MIDFIX}-hardening.conf",
            text=texts.SYSCTL_HARDENING,
        ),
        Cmd(
            name="apply sysctl",
            argv=["sysctl", "--system"],
        ),
        WriteFile(
            path=f"/etc/audit/rules.d/99-{MIDFIX}.rules",
            text=texts.AUDIT_RULES,
            mode=0o640,
        ),
        Systemctl(
            verb="enable_now",
            units=["auditd"],
        ),
        # Rules apply on next boot if they cannot be loaded now
        Cmd(
            name="load audit rules",
            argv=["augenrules", "--load"],
            continue_on_error=True,
        ),
    ]

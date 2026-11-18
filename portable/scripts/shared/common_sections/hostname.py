"""Hostname and self-resolution. Nothing changes unless SYSTEM_HOSTNAME/DOMAIN/FQDN is set."""

from actions import Cmd, EnsureLine, out
from config import Config


def actions(c: Config):
    if not c.static_hostname:
        return []
    return [
        Cmd(
            name=f"set hostname {c.static_hostname}",
            argv=["hostnamectl", "set-hostname", c.static_hostname],
            done=lambda: out("hostnamectl", "--static") == c.static_hostname,
        ),
        # Self-resolution without DNS: one marked line, rewritten on every run
        EnsureLine(
            path=c.hosts_file,
            line=c.hosts_line,
            marker=c.hosts_marker,
        ),
    ]

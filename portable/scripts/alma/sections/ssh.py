"""SSH hardening via sshd_config.d. Must run only after the admin key is installed, so a failed
key download can never lock everyone out."""

import glob
import logging
import re
import shutil
from pathlib import Path

import texts
from actions import Cmd, EnsureDir, Func, Systemctl, WriteFile, sh
from config import Config

log = logging.getLogger(__name__)

# Port accumulates instead of first-value-wins, so another Port directive would make sshd listen on both.
PORT_RE = re.compile(r"^[ \t]*port[ \t=]", re.IGNORECASE | re.MULTILINE)


def _other_configs(c: Config) -> list[Path]:
    files = ["/etc/ssh/sshd_config", *sorted(glob.glob("/etc/ssh/sshd_config.d/*.conf"))]
    return [Path(f) for f in files if f != c.ssh_conf and Path(f).is_file()]


def _with_port(c: Config) -> list[Path]:
    return [f for f in _other_configs(c) if PORT_RE.search(f.read_text(encoding="utf-8"))]


def _disable_other_ports(c: Config) -> None:
    """Comment out the other Port directives (backup beside the file; a non-.conf name is not read by the include)."""
    prefix = f"# disabled by setup (Port is set in {c.ssh_conf}): "
    for f in _with_port(c):
        shutil.copy2(f, f"{f}.setup.bak")
        text = re.sub(r"^(?=[ \t]*port[ \t=])", prefix, f.read_text(encoding="utf-8"),
                      flags=re.IGNORECASE | re.MULTILINE)
        f.write_text(text, encoding="utf-8")
        log.info("Disabled Port directive in %s (backup: %s.setup.bak)", f, f)


def _verify_effective(c: Config) -> None:
    """sshd -t does not warn when an earlier drop-in overrides our values, so check the effective config."""
    effective = sh("sshd", "-T").stdout.lower().splitlines()
    for expected in texts.sshd_expected(c):
        if expected.lower() not in effective:
            raise RuntimeError(f"sshd effective config mismatch: expected '{expected}'")
    ports = [line.split()[1] for line in effective if line.split()[:1] == ["port"]]
    if ports != [str(c.ssh_port)]:
        raise RuntimeError(f"sshd listens on unexpected port(s): {' '.join(ports)} (expected only {c.ssh_port})")


def actions(c: Config):
    return [
        EnsureDir(
            path="/etc/ssh/sshd_config.d",
        ),
        # Banner first, the drop-in references it
        WriteFile(
            path=c.ssh_banner,
            text=texts.ssh_banner(),
        ),
        # The drop-in is syntax-checked standalone, then installed
        WriteFile(
            path=c.ssh_conf,
            text=texts.ssh_conf(c),
            mode=0o644,
            validator=["sshd", "-t", "-f"],
        ),
        # Check the installed result as a whole before restarting
        Cmd(
            name="sshd -t",
            argv=["sshd", "-t"],
        ),
        Func(
            name="disable other Port directives",
            run=lambda: _disable_other_ports(c),
            pre=lambda: not _with_port(c),
            post=lambda: not _with_port(c),
        ),
        Cmd(
            name="sshd -t (after Port cleanup)",
            argv=["sshd", "-t"],
        ),
        Func(
            name="verify effective sshd config",
            run=lambda: _verify_effective(c),
        ),
        Systemctl(
            verb="restart",
            units=["sshd"],
        ),
    ]

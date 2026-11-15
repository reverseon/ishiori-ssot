"""Security updates, repositories and base tooling, then time sync and job schedulers."""

from actions import Cmd, DnfInstall, Systemctl, out, sh
from config import Config


def _no_security_updates() -> bool:
    """`dnf check-update` exits 0 when nothing is pending, 100 when updates exist, 1 on error."""
    return sh("dnf", "check-update", "--security", "-q", check=False).returncode == 0


def _crb_enabled() -> bool:
    return any(line.split()[:1] == ["crb"] for line in out("dnf", "repolist", "--enabled", "-q").splitlines())


def actions(c: Config):
    return [
        # Security updates only (same policy as dnf-automatic), then base tooling
        Cmd(
            name="dnf upgrade --security",
            argv=["dnf", "upgrade", "--security", "-y"],
            done=_no_security_updates,
        ),
        # Both come from the stock repos, so one transaction. Everything after needs EPEL's metadata,
        # which only exists once epel-release is installed, so c.packages must be a separate transaction.
        DnfInstall(
            packages=["dnf-plugins-core", "epel-release"],
        ),
        # EPEL packages can depend on CodeReady Builder (crb); config-manager comes from dnf-plugins-core
        Cmd(
            name="enable crb repo",
            argv=["dnf", "config-manager", "--set-enabled", "crb"],
            done=_crb_enabled,
        ),
        DnfInstall(
            packages=c.packages,
        ),
        Systemctl(
            verb="enable_now",
            units=["chronyd"],
        ),
        Systemctl(
            verb="enable_now",
            units=["crond"],
        ),
        Systemctl(
            verb="enable_now",
            units=["atd"],
        ),
    ]

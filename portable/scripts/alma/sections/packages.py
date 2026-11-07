"""Security updates, repositories and base tooling, then time sync and job schedulers."""

from actions import Cmd, DnfInstall, Systemctl
from config import Config


def actions(c: Config):
    return [
        # Security updates only (same policy as dnf-automatic), then base tooling
        Cmd(
            name="dnf upgrade --security",
            argv=["dnf", "upgrade", "--security", "-y"],
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

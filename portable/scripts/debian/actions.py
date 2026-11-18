"""Actions for debian-setup: the shared ones plus the package installer for this distro."""

from __future__ import annotations

from typing import Sequence

from action import Action
from base_actions import *  # noqa: F401,F403
from base_actions import ok, out, sh


class AptInstall(Action):
    def __init__(self, packages: Sequence[str]):
        super().__init__(f"apt install {' '.join(packages)}")
        self.packages = list(packages)

    @staticmethod
    def _installed(package: str) -> bool:
        return out("dpkg-query", "-W", "-f=${db:Status-Status}", package) == "installed"

    def precheck(self) -> bool:
        missing = [p for p in self.packages if not self._installed(p)]
        self.precheck_detail = f"not installed: {' '.join(missing)}" if missing else ""
        return not missing

    def run(self) -> None:
        sh("env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", *self.packages)

    def postcheck(self) -> bool:
        held = self.precheck()
        self.postcheck_detail = f"still {self.precheck_detail} after apt-get install" if not held else ""
        return held

"""Actions for alma-setup: the shared ones plus the package installer for this distro."""

from __future__ import annotations

from typing import Sequence

from action import Action
from base_actions import *  # noqa: F401,F403
from base_actions import ok, out, sh


class DnfInstall(Action):
    def __init__(self, packages: Sequence[str]):
        super().__init__(f"dnf install {' '.join(packages)}")
        self.packages = list(packages)

    def precheck(self) -> bool:
        if ok("rpm", "-q", *self.packages):
            self.precheck_detail = ""
            return True
        missing = [p for p in self.packages if not ok("rpm", "-q", p)]
        self.precheck_detail = f"not installed: {' '.join(missing)}"
        return False

    def run(self) -> None:
        sh("dnf", "install", "-y", *self.packages)

    def postcheck(self) -> bool:
        held = self.precheck()
        self.postcheck_detail = f"still {self.precheck_detail} after dnf install" if not held else ""
        return held

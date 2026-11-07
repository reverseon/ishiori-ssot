"""Concrete, reusable Actions for the setup scripts (files, services, packages, commands).

Each one answers "is this already done?" in precheck(), so re-running a script only touches what drifted.
`pwd`/`grp` are imported lazily so the module (and its tests) also load on a non-POSIX dev box.
"""

from __future__ import annotations

import logging
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Callable, Sequence

from action import Action, ActionError  # from ../shared (see main.py sys.path)

log = logging.getLogger(__name__)

Check = Callable[[], bool]


def sh(*argv: str, check: bool = True, input: str | None = None) -> subprocess.CompletedProcess[str]:
    """Run a command, capturing output. When check is set, a failure raises with the command's output attached."""
    result = subprocess.run(argv, check=False, input=input, text=True, capture_output=True)
    if check and result.returncode != 0:
        detail = "\n".join(s for s in (result.stdout.strip(), result.stderr.strip()) if s)
        tail = "\n".join(detail.splitlines()[-20:])
        raise RuntimeError(f"`{' '.join(argv)}` exited {result.returncode}" + (f":\n{tail}" if tail else ""))
    return result


def ok(*argv: str) -> bool:
    """True when the command exits 0 (a missing binary counts as False)."""
    try:
        return sh(*argv, check=False).returncode == 0
    except FileNotFoundError:
        return False


def out(*argv: str) -> str:
    """Stripped stdout of a command, or '' if it fails."""
    try:
        return sh(*argv, check=False).stdout.strip()
    except FileNotFoundError:
        return ""


def restorecon(path: str | Path, recursive: bool = False) -> None:
    """Best-effort SELinux relabel (bash: `restorecon ... 2>/dev/null || true`)."""
    try:
        sh("restorecon", *(["-R"] if recursive else []), str(path), check=False)
    except FileNotFoundError:
        pass


class Func(Action):
    """Ad-hoc action from callables, for one-off steps that don't deserve a class."""

    def __init__(self, name: str, run: Callable[[], None], pre: Check | None = None,
                 post: Check | None = None, continue_on_error: bool = False):
        super().__init__(name)
        self._run, self._pre, self._post = run, pre, post
        self.continue_on_error = continue_on_error

    def precheck(self) -> bool:
        return self._pre() if self._pre else False

    def run(self) -> None:
        self._run()

    def verifiable(self) -> bool:
        return self._post is not None

    def postcheck(self) -> bool:
        return self._post() if self._post else True


class Cmd(Action):
    """Run a command. `done` (if given) says whether the desired state holds, before and after."""

    def __init__(self, name: str, argv: Sequence[str], done: Check | None = None, input: str | None = None,
                 continue_on_error: bool = False):
        super().__init__(name)
        self.argv, self.done, self.input = list(argv), done, input
        self.continue_on_error = continue_on_error

    def precheck(self) -> bool:
        return self.done() if self.done else False

    def run(self) -> None:
        sh(*self.argv, input=self.input)

    def verifiable(self) -> bool:
        return self.done is not None

    def postcheck(self) -> bool:
        return self.done() if self.done else True


class EnsureDir(Action):
    def __init__(self, path: str | Path, mode: int | None = 0o755, owner: str | None = "root",
                 group: str | None = "root", relabel: bool = False):
        super().__init__(f"dir {path}")
        self.path, self.mode, self.owner, self.group, self.relabel = Path(path), mode, owner, group, relabel

    def precheck(self) -> bool:
        if not self.path.is_dir():
            self.precheck_detail = "directory missing"
            return False
        self.precheck_detail = _meta_diff(self.path, self.mode, self.owner, self.group)
        return not self.precheck_detail

    def run(self) -> None:
        self.path.mkdir(parents=True, exist_ok=True)
        _apply_meta(self.path, self.mode, self.owner, self.group)
        if self.relabel:
            restorecon(self.path, recursive=True)

    def postcheck(self) -> bool:
        held = self.precheck()
        self.postcheck_detail = self.precheck_detail
        return held


class WriteFile(Action):
    """Whole-file write: skipped when content, mode and ownership already match.

    With `validator` (e.g. ["visudo", "-c", "-f"]) the text is validated from a temp file first and goes live
    via `<path>.new` + rename, so a bad file never takes effect (bash: install_validated).
    """

    def __init__(self, path: str | Path, text: str, mode: int | None = 0o644, owner: str | None = "root",
                 group: str | None = "root", relabel: bool = False, validator: Sequence[str] | None = None):
        super().__init__(f"file {path}")
        self.path, self.text, self.mode = Path(path), text, mode
        self.owner, self.group, self.relabel, self.validator = owner, group, relabel, validator

    def precheck(self) -> bool:
        if not self.path.is_file():
            self.precheck_detail = "file missing"
        elif self.path.read_text(encoding="utf-8") != self.text:
            self.precheck_detail = "content differs"
        else:
            self.precheck_detail = _meta_diff(self.path, self.mode, self.owner, self.group)
        return not self.precheck_detail

    def run(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if self.validator:
            self._validate()
        new = self.path.with_name(self.path.name + ".new")
        new.write_text(self.text, encoding="utf-8")
        _apply_meta(new, self.mode, self.owner, self.group)
        os.replace(new, self.path)
        if self.relabel:
            restorecon(self.path)

    def _validate(self) -> None:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as tmp:
            tmp.write(self.text)
        try:
            result = sh(*self.validator, tmp.name, check=False)
        finally:
            os.unlink(tmp.name)
        if result.returncode != 0:
            raise ActionError(
                action=self,
                message=f"validation failed, not installed: {result.stderr.strip() or result.stdout.strip()}",
            )

    def postcheck(self) -> bool:
        held = self.precheck()
        self.postcheck_detail = self.precheck_detail
        return held


class EnsureLine(Action):
    """Append `line` to a file unless present. With `marker`, replace any line ending in it (one managed line)."""

    def __init__(self, path: str | Path, line: str, marker: str | None = None):
        super().__init__(f"line in {path}")
        self.path, self.line, self.marker = Path(path), line, marker

    def _lines(self) -> list[str]:
        return self.path.read_text(encoding="utf-8").splitlines() if self.path.exists() else []

    def precheck(self) -> bool:
        lines = self._lines()
        if self.marker is None:
            return self.line in lines
        return [l for l in lines if l.endswith(self.marker)] == [self.line]

    def run(self) -> None:
        lines = self._lines()
        if self.marker is not None:
            lines = [l for l in lines if not l.endswith(self.marker)]
        lines.append(self.line)
        self.path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def postcheck(self) -> bool:
        held = self.precheck()
        self.postcheck_detail = self.precheck_detail
        return held


# verb -> (argv template, precheck state, postcheck state). No precheck state means the verb always runs;
# no postcheck state means it ends UNVERIFIED. restart always runs but must leave the unit active.
_SYSTEMCTL = {
    "enable_now": (["enable", "--now"], "enabled+active", "enabled+active"),
    "enable": (["enable"], "enabled", "enabled"),
    "start": (["start"], "active", "active"),
    "restart": (["restart"], None, "active"),
    "mask": (["mask"], "masked", "masked"),
    "disable_now": (["disable", "--now"], "disabled+inactive", "disabled+inactive"),
    "daemon_reload": (["daemon-reload"], None, None),
}


class Systemctl(Action):
    def __init__(self, verb: str, units: Sequence[str] = (), continue_on_error: bool = False):
        super().__init__(f"systemctl {verb.replace('_', '-')} {' '.join(units)}".strip())
        self.args, self.pre_state, self.post_state = _SYSTEMCTL[verb]
        self.units = list(units)
        self.continue_on_error = continue_on_error

    def _holds(self, state: str | None) -> tuple[bool, str]:
        """(holds, why-not) for every unit; why-not names the units that miss the state."""
        if state is None:
            return False, ""
        checks = {
            "enabled": lambda u: ok("systemctl", "is-enabled", "--quiet", u),
            "active": lambda u: ok("systemctl", "is-active", "--quiet", u),
            "enabled+active": lambda u: ok("systemctl", "is-enabled", "--quiet", u) and ok("systemctl", "is-active", "--quiet", u),
            "masked": lambda u: out("systemctl", "is-enabled", u) == "masked",
            "disabled+inactive": lambda u: not ok("systemctl", "is-enabled", "--quiet", u) and not ok("systemctl", "is-active", "--quiet", u),
        }
        bad = [u for u in self.units if not checks[state](u)]
        return not bad, f"not {state}: {' '.join(bad)}" if bad else ""

    def precheck(self) -> bool:
        held, self.precheck_detail = self._holds(self.pre_state)
        return held

    def run(self) -> None:
        sh("systemctl", *self.args, *self.units)

    def verifiable(self) -> bool:
        return self.post_state is not None

    def postcheck(self) -> bool:
        if not self.post_state:
            return True
        held, self.postcheck_detail = self._holds(self.post_state)
        return held


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


def _meta_diff(path: Path, mode: int | None, owner: str | None, group: str | None) -> str:
    """What differs from the wanted mode/owner/group, or '' when it all matches."""
    st = path.stat()
    if mode is not None and (st.st_mode & 0o7777) != mode:
        return f"mode is {st.st_mode & 0o7777:04o}, want {mode:04o}"
    if owner is not None:
        import pwd
        actual = pwd.getpwuid(st.st_uid).pw_name
        if actual != owner:
            return f"owner is {actual}, want {owner}"
    if group is not None:
        import grp
        actual = grp.getgrgid(st.st_gid).gr_name
        if actual != group:
            return f"group is {actual}, want {group}"
    return ""


def _apply_meta(path: Path, mode: int | None, owner: str | None, group: str | None) -> None:
    if owner is not None or group is not None:
        import grp, pwd
        uid = pwd.getpwnam(owner).pw_uid if owner is not None else -1
        gid = grp.getgrnam(group).gr_gid if group is not None else -1
        os.chown(path, uid, gid)
    if mode is not None:
        os.chmod(path, mode)

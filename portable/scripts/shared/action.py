"""Building blocks for converting the bash setup scripts into readable, re-runnable steps.

An Action is one unit of change with three phases:

    precheck()   True if the desired state already holds (run is skipped)
    run()        make the change
    postcheck()  True if the desired state now holds (False aborts)

Like `set -e`, a failure stops the runner unless the action opts in via continue_on_error
(the equivalent of a bash `|| true`).
"""

from __future__ import annotations

import enum
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Iterable

log = logging.getLogger(__name__)


class Status(enum.Enum):
    SKIPPED = "skipped"  # precheck passed, nothing to do
    CHANGED = "changed"  # run executed and postcheck passed
    UNVERIFIED = "unverified"  # run executed, but the action defines no postcheck
    FAILED = "failed"    # only seen for continue_on_error actions


class ActionError(RuntimeError):
    """An action failed in run() or its postcheck()."""

    def __init__(self, action: "Action", message: str):
        super().__init__(f"{action.name}: {message}")
        self.action = action


@dataclass(frozen=True)
class Result:
    action: "Action"
    status: Status
    error: BaseException | None = None


class Action(ABC):
    #: Set True for steps that mirror a bash `|| true`: a failure is logged, not raised.
    continue_on_error: bool = False
    #: Label shown in log lines; set by whoever assembles the action list.
    section: str = ""
    #: A precheck() that returns False may set this to say what is off; it is logged and shown by --check.
    precheck_detail: str = ""
    #: A postcheck() that returns False may set this to say why; it is appended to the failure message.
    postcheck_detail: str = ""

    def __init__(self, name: str):
        self.name = name

    @abstractmethod
    def precheck(self) -> bool:
        """Return True when the desired state already holds, so run() is skipped."""

    @abstractmethod
    def run(self) -> None:
        """Apply the change. Raise on failure."""

    @abstractmethod
    def postcheck(self) -> bool:
        """Return True when the desired state holds after run()."""

    def verifiable(self) -> bool:
        """False when this action has nothing to check after run(); it then ends UNVERIFIED, not CHANGED."""
        return True

    def _log(self, phase: str, message: str = "", level: int = logging.INFO) -> None:
        tag = f"[{self.section or '-'}][{phase}]"
        log.log(level, "%-22s %s%s", tag, self.name, f" -> {message}" if message else "")

    def execute(self) -> Result:
        """Run the precheck -> run -> postcheck sequence for this action."""
        phase = "Precheck"
        try:
            satisfied = self.precheck()
            if satisfied:
                self._log("Precheck", "satisfied, skipping")
                return Result(
                    action=self,
                    status=Status.SKIPPED,
                )
            self._log("Precheck", f"not satisfied: {self.precheck_detail}" if self.precheck_detail else "not satisfied")
            phase = "Run"
            self._log("Run")
            self.run()
            if not self.verifiable():
                self._log("Postcheck", "skipped (no check defined)")
                return Result(
                    action=self,
                    status=Status.UNVERIFIED,
                )
            phase = "Postcheck"
            if not self.postcheck():
                raise ActionError(
                    action=self,
                    message="postcheck failed after run"
                    + (f": {self.postcheck_detail}" if self.postcheck_detail else ""),
                )
            self._log("Postcheck", "ok")
        except Exception as exc:
            if self.continue_on_error:
                self._log(phase, f"FAILED (ignored): {exc}", logging.WARNING)
                return Result(
                    action=self,
                    status=Status.FAILED,
                    error=exc,
                )
            self._log(phase, f"FAILED: {exc}", logging.ERROR)
            if isinstance(exc, ActionError):
                raise
            raise ActionError(
                action=self,
                message=str(exc),
            ) from exc
        return Result(
            action=self,
            status=Status.CHANGED,
        )

    def __repr__(self) -> str:
        return f"{type(self).__name__}({self.name!r})"


def run_actions(actions: Iterable[Action]) -> list[Result]:
    """Execute actions in order, stopping at the first non-ignorable failure. Logs a summary at the end."""
    results: list[Result] = []
    try:
        for action in actions:
            results.append(action.execute())
    finally:
        counts = {s: sum(r.status is s for r in results) for s in Status}
        log.info("Summary: %d changed, %d unverified, %d skipped, %d failed (ignored)",
                 counts[Status.CHANGED], counts[Status.UNVERIFIED], counts[Status.SKIPPED], counts[Status.FAILED])
    return results

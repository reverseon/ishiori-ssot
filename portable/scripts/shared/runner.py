"""Shared command-line runner for the distro setup scripts: logging, --list, --check, the root check, run_actions."""

import argparse
import logging
import os
import secrets
import string
import sys
from datetime import datetime
from pathlib import Path

from action import ActionError, run_actions


def expand(plan, c):
    """Call each (section, make) pair of `plan` with the config; tag every resulting action with its section."""
    actions = []
    for name, make in plan:
        for action in make(c):
            action.section = name
            actions.append(action)
    return actions


def setup_logging(name: str) -> Path | None:
    """Console (INFO/WARNING to stdout, ERROR to stderr) plus a timestamped file in log_dir.

    Returns the log file path, or None if the file could not be created (console logging still works).
    """
    log_dir = Path("/var/log") / name
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    out = logging.StreamHandler(sys.stdout)
    out.addFilter(lambda r: r.levelno < logging.ERROR)
    err = logging.StreamHandler(sys.stderr)
    err.setLevel(logging.ERROR)
    for h in (out, err):
        h.setFormatter(logging.Formatter("%(message)s"))
        root.addHandler(h)

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    suffix = "".join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(10))
    path = log_dir / f"{name}-{stamp}-{suffix}.log"
    try:
        log_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))  # private: may hold command output
        handler = logging.FileHandler(path, encoding="utf-8")
    except OSError as exc:
        logging.warning("WARNING: cannot write a log file in %s: %s", log_dir, exc)
        return None
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)-7s %(message)s"))
    root.addHandler(handler)
    return path


def run(c, check: bool, name: str, build, preflight_run) -> int:
    c = preflight_run(c)
    actions = build(c)
    if check:
        for a in actions:
            done = a.precheck()
            why = f"  ({a.precheck_detail})" if not done and a.precheck_detail else ""
            logging.info("%s [%s] %s%s", "ok  " if done else "RUN ", a.section, a.name, why)
        return 0
    try:
        run_actions(actions)
    except ActionError as exc:
        logging.error("ERROR: %s", exc)
        return 1
    logging.info("%s finished", name)
    return 0


def main(name: str, doc: str, config_cls, build, preflight_run, argv=None) -> int:
    """Shared CLI: --list / --check / run. `build(c)` returns the ordered actions, each tagged with .section."""
    parser = argparse.ArgumentParser(description=doc, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--list", action="store_true", help="print the steps and exit")
    mode.add_argument("--check", action="store_true", help="report which steps would run, change nothing")
    args = parser.parse_args(argv)

    c = config_cls.from_env()
    if args.list:
        for a in build(c):
            print(f"[{a.section}] {a.name}")
        return 0
    if os.geteuid() != 0:
        print(f"ERROR: this script must be run as root (try: sudo {sys.argv[0]})", file=sys.stderr)
        return 1
    log_path = setup_logging(name)
    try:
        return run(c, args.check, name, build, preflight_run)
    finally:
        if log_path:
            logging.info("log saved to: %s", log_path)


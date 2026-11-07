#!/usr/bin/env python3
"""AlmaLinux setup and hardening. Run as root (sudo); safe to re-run: steps already in place are skipped.

    sudo SYSTEM_HOSTNAME=foo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 python3 alma-setup/main.py
    python3 alma-setup/main.py --list     # print the steps, change nothing
    sudo python3 alma-setup/main.py --check   # report which steps would run, change nothing

Settings and the environment variables they read: config.py. Step order below matters.
"""

import argparse
import logging
import os
import secrets
import string
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent / "shared")]

from action import ActionError, run_actions  # noqa: E402
from config import Config  # noqa: E402
from sections import (aide, attack_surface, firewall, hostname, identity, kernel, logs, network,  # noqa: E402
                      packages, preflight, prune, service_user, ssh, updates)


def build(c: Config):
    """The full ordered step list. Constraints that must hold:
    - the admin key is installed (identity) before sshd is restarted (ssh)
    - users are pruned only after admin and service users exist
    - the AIDE baseline is built last, so the files above are part of it
    - static IP activation is the very last step: it drops SSH sessions on the old address
    """
    plan = [
        ("hostname", hostname.actions), ("packages", packages.actions), ("updates", updates.actions),
        ("kernel", kernel.actions), ("attack-surface", attack_surface.actions), ("identity", identity.actions),
        ("ssh", ssh.actions), ("service-user", service_user.actions), ("prune", prune.actions),
        ("logs", logs.actions), ("firewall", firewall.actions), ("network", network.write),
        ("aide", aide.actions), ("network", network.activate),
    ]
    actions = []
    for name, make in plan:
        for action in make(c):
            action.section = name
            actions.append(action)
    return actions


LOG_DIR = Path("/var/log/alma-setup")


def setup_logging(log_dir: Path = LOG_DIR) -> Path | None:
    """Console (INFO/WARNING to stdout, ERROR to stderr) plus a timestamped file in log_dir.

    Returns the log file path, or None if the file could not be created (console logging still works).
    """
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
    path = log_dir / f"alma-setup-{stamp}-{suffix}.log"
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


def run(c: Config, check: bool) -> int:
    c = preflight.run(c)
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
    logging.info("alma-setup finished")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--list", action="store_true", help="print the steps and exit")
    mode.add_argument("--check", action="store_true", help="report which steps would run, change nothing")
    args = parser.parse_args(argv)

    c = Config.from_env()
    if args.list:
        for a in build(c):
            print(f"[{a.section}] {a.name}")
        return 0
    if os.geteuid() != 0:
        print(f"ERROR: this script must be run as root (try: sudo {sys.argv[0]})", file=sys.stderr)
        return 1
    log_path = setup_logging()
    try:
        return run(c, args.check)
    finally:
        if log_path:
            logging.info("log saved to: %s", log_path)


if __name__ == "__main__":
    sys.exit(main())

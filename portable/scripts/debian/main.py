#!/usr/bin/env python3
"""Debian 13 first-start setup: only what Ansible needs to take over. Run as root (sudo); safe to re-run: steps
already in place are skipped. Hardening beyond this (kernel, attack surface, logs, file integrity) is left to Ansible.

    sudo python3 debian/main.py          # report which steps would run, change nothing
    sudo SYSTEM_HOSTNAME=foo STATIC_IP=192.168.1.50/24 STATIC_GATEWAY=192.168.1.1 python3 debian/main.py --exec
    python3 debian/main.py --list        # print the steps, change nothing
    python3 debian/main.py --help        # the environment variables

Settings and the environment variables they read: config.py. Step order below matters.
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent / "shared")]

import runner  # noqa: E402
from config import ENV_HELP, Config  # noqa: E402
from common_sections import hostname, service_user  # noqa: E402
from sections import (firewall, identity, keyboard, network, packages, preflight,  # noqa: E402
                      prune, ssh, updates)


def build(c: Config):
    """The full ordered step list. Constraints that must hold:
    - keyboard and updates need the packages (console-setup, unattended-upgrades) installed first
    - the admin key is installed (identity) before sshd is restarted (ssh)
    - the service user's sudoers rule is granted from the admin, so it comes after identity
    - users are pruned only after admin and service users exist
    - static IP activation is the very last step: it drops SSH sessions on the old address
    """
    plan = [
        ("hostname", hostname.actions), ("packages", packages.actions), ("keyboard", keyboard.actions),
        ("updates", updates.actions),
        ("identity", identity.actions), ("ssh", ssh.actions), ("service-user", service_user.actions),
        ("prune", prune.actions), ("firewall", firewall.actions), ("network", network.write),
        ("network", network.activate),
    ]
    return runner.expand(plan, c)


def main(argv=None) -> int:
    return runner.main("debian-setup", __doc__, Config, build, preflight.run, argv, epilog=ENV_HELP)


if __name__ == "__main__":
    sys.exit(main())

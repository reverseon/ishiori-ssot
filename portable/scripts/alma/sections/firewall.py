"""nftables as the only firewall manager."""

import texts
from actions import EnsureDir, EnsureLine, Systemctl, WriteFile
from config import Config


def actions(c: Config):
    return [
        EnsureDir(
            path="/etc/nftables",
        ),
        WriteFile(
            path=c.nft_rules_conf,
            text=texts.nft_rules(c),
        ),
        # Include the ruleset in the main nftables config so it persists across reboots
        EnsureLine(
            path="/etc/sysconfig/nftables.conf",
            line=c.nft_include,
        ),
        # Mask firewalld so it cannot load a second ruleset
        Systemctl(
            verb="disable_now",
            units=["firewalld"],
            continue_on_error=True,
        ),
        Systemctl(
            verb="mask",
            units=["firewalld"],
            continue_on_error=True,
        ),
        Systemctl(
            verb="enable",
            units=["nftables"],
        ),
        Systemctl(
            verb="restart",
            units=["nftables"],
        ),
    ]

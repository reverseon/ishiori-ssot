"""nftables as the only firewall manager."""

import texts
from actions import EnsureDir, Systemctl, WriteFile
from config import Config


def actions(c: Config):
    return [
        EnsureDir(
            path="/etc/nftables",
        ),
        WriteFile(
            path=c.nft_rules_conf,
            text=texts.nft_rules(c),
            validator=["nft", "-c", "-f"],
        ),
        # Debian's nftables.service loads /etc/nftables.conf at boot; own it whole and include our ruleset
        WriteFile(
            path=c.nft_main_conf,
            text=texts.nft_main(c),
            mode=0o755,
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

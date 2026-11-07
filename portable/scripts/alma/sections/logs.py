"""rsyslog routing and logrotate for the logs this script creates."""

import texts
from actions import Systemctl, WriteFile
from config import MIDFIX, Config


def actions(c: Config):
    return [
        WriteFile(
            path=f"/etc/rsyslog.d/99-{MIDFIX}-nftables.conf",
            text=texts.rsyslog_nft(c),
        ),
        WriteFile(
            path=f"/etc/rsyslog.d/99-{MIDFIX}-popola-switch.conf",
            text=texts.rsyslog_popola(c),
        ),
        Systemctl(
            verb="restart",
            units=["rsyslog"],
        ),
        # Sudo log (30 days)
        WriteFile(
            path=f"/etc/logrotate.d/99-{MIDFIX}-sudo",
            text=texts.logrotate(c.sudo_log, "daily", 30),
        ),
        # nftables log (postrotate reloads rsyslog to reopen the file)
        WriteFile(
            path=f"/etc/logrotate.d/99-{MIDFIX}-nftables",
            text=texts.logrotate(c.nft_log, "daily", 7, compress=False, reload_rsyslog=True),
        ),
        # Service-user switch log (a year)
        WriteFile(
            path=f"/etc/logrotate.d/99-{MIDFIX}-popola-switch",
            text=texts.logrotate(c.popola_log, "weekly", 52, reload_rsyslog=True),
        ),
    ]

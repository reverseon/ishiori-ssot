"""Console and X11 keyboard layout (Japanese JIS by default). Set KEYMAP to change; empty leaves it alone.

Debian reads /etc/default/keyboard (keyboard-configuration/console-setup, installed by packages), not
/etc/vconsole.conf, so this step must run after packages.
"""

from pathlib import Path

import texts
from actions import Cmd, WriteFile
from config import Config

CACHE = Path("/etc/console-setup/cached_setup_keyboard.sh")


def _cache_current(c: Config) -> bool:
    conf = Path(c.keyboard_conf)
    return CACHE.is_file() and conf.is_file() and CACHE.stat().st_mtime >= conf.stat().st_mtime


def actions(c: Config):
    if not c.keymap:
        return []
    return [
        WriteFile(
            path=c.keyboard_conf,
            text=texts.keyboard_conf(c),
        ),
        # Regenerate the console keymap cache (applied at boot); --save-only leaves the live console alone
        Cmd(
            name=f"console keymap {c.keymap}",
            argv=["setupcon", "--save-only"],
            done=lambda: _cache_current(c),
        ),
    ]

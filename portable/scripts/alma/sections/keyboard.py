"""Console and X11 keyboard layout (Japanese JIS by default). Set KEYMAP to change; empty leaves it alone."""

from actions import Cmd, out
from config import Config


def _current() -> str:
    for line in out("localectl", "status").splitlines():
        key, _, value = line.partition(":")
        if key.strip() == "VC Keymap":
            return value.strip()
    return ""


def actions(c: Config):
    if not c.keymap:
        return []
    return [
        # localectl writes /etc/vconsole.conf and derives the matching X11 layout from the console keymap
        Cmd(
            name=f"set keymap {c.keymap}",
            argv=["localectl", "set-keymap", c.keymap],
            done=lambda: _current() == c.keymap,
        ),
    ]

#!/usr/bin/env python3
"""Bundle <distro>/main.py plus its modules and ../shared into one file: ../build/<distro>-setup.py.

    pip install stickytape
    python shared/build.py alma|debian [output-path]
"""

import subprocess
import sys
from pathlib import Path

SHARED = Path(__file__).resolve().parent
ROOT = SHARED.parent
DISTROS = ("alma", "debian")

CALL = (
    "import sys; from stickytape.main import main; "
    "sys.argv = ['stickytape'] + sys.argv[1:]; main()"
)


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in DISTROS:
        print(f"usage: build.py {{{'|'.join(DISTROS)}}} [output-path]", file=sys.stderr)
        return 2
    distro = sys.argv[1]
    here = ROOT / distro
    out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT / "build" / f"{distro}-setup.py"
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        sys.executable, "-c", CALL,
        str(here / "main.py"),
        "--add-python-path", str(here),
        "--add-python-path", str(SHARED),
        "--output-file", str(out),
    ]
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        return e.returncode
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

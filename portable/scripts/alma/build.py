#!/usr/bin/env python3
"""Bundle main.py plus its modules and ../shared into one file: ../build/alma-setup.py.

    pip install stickytape
    python alma/build.py [output-path]
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHARED = HERE.parent / "shared"
DEFAULT_OUT = HERE.parent / "build" / "alma-setup.py"

CALL = (
    "import sys; from stickytape.main import main; "
    "sys.argv = ['stickytape'] + sys.argv[1:]; main()"
)


def main() -> int:
    out = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT_OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        sys.executable, "-c", CALL,
        str(HERE / "main.py"),
        "--add-python-path", str(HERE),
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

# utils

Each utility lives in its own directory: `utils/<name>/`.

## Directory structure

```
utils/<name>/
├── main.sh          # Entry point — globals, sources, main dispatch
└── lib/
    ├── helpers/     # Shared internal functions
    │   └── *.sh
    └── cmd_*.sh     # One file per user-facing command
```

## Conventions

**`main.sh`** declares global variables, sources all lib files, defines `usage()`, and dispatches based on `$@`.

**`lib/cmd_*.sh`** — one file per command, named after the full command path with words joined by underscores (e.g. `view cert list` → `cmd_view_cert_list.sh`). Each file contains exactly one function matching its filename.

**`lib/helpers/*.sh`** — shared utilities called by command functions, not invoked directly by the user.

**Command structure** follows `<verb> <object> [<operation>]`. All non-positional inputs are flags (`--cn`, `--serial`, etc.), even logically required ones. Flags always come after all positional words so the dispatcher can consume words from the front of `$@` without flag-awareness.

**Global variables** are declared in `main.sh`, treated as read-only by lib files, and default to in-container paths but can be overridden via env vars.

**Error exits** print `"Error: ..."` and exit 1. `usage` is included only when the error is structural (wrong command shape, missing flag) — not when the operation itself fails.

#!/bin/sh
# Run the controller without global environment changes.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if command -v node >/dev/null 2>&1; then
  if node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
    exec node "$ROOT/tools/fairpane.mjs" "$@"
  fi
fi
if command -v bun >/dev/null 2>&1; then
  exec bun "$ROOT/tools/fairpane.mjs" "$@"
fi
printf '%s\n' 'The controller needs Node 22 or newer, or Bun.' >&2
exit 1

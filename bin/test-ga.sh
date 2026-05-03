#!/usr/bin/env bash
# bin/test-ga.sh — shim to run the Python ga test suite.
#
# Prefers the vendored venv (which has google-ads + PyYAML installed),
# falls back to system python3 (in CI we ensure PyYAML is present).
# bin/test-ga.py stubs the google-ads library at sys.modules level so it
# runs in either mode without network or full library install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${GOOGLE_ADS_COPILOT_VENV:-$HOME/.local/share/google-ads-copilot/.venv}"

if [[ -x "$VENV_DIR/bin/python3" ]]; then
  exec "$VENV_DIR/bin/python3" "$SCRIPT_DIR/test-ga.py"
fi

if ! command -v python3 >/dev/null; then
  echo "test-ga.sh: python3 not on PATH" >&2
  exit 1
fi

if ! python3 -c "import yaml" 2>/dev/null; then
  echo "test-ga.sh: PyYAML missing — install via the venv (bin/setup) or 'pip install --user pyyaml'" >&2
  exit 1
fi

exec python3 "$SCRIPT_DIR/test-ga.py"

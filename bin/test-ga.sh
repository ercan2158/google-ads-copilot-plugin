#!/usr/bin/env bash
# bin/test-ga.sh — bash assertion suite for bin/ga.
# Mocks `composio` via PATH override so we test wiring without hitting any
# real API.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GA="$SCRIPT_DIR/ga"
FAIL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS $name"
  else
    echo "  FAIL $name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ---- Setup mock PATH ----------------------------------------------------
MOCKDIR=$(mktemp -d)
trap 'rm -rf "$MOCKDIR"' EXIT

cat > "$MOCKDIR/composio" <<'EOF'
#!/usr/bin/env bash
# Mock composio: handles `execute GOOGLEADS_QUERY` and `proxy <url> ...`.
case "${1:-}" in
  execute)
    if [[ "${2:-}" == "GOOGLEADS_QUERY" ]]; then
      echo '{"data":"[{\"campaign\":{\"id\":\"42\"}}]","successful":true}'
      exit 0
    fi
    ;;
  proxy)
    # Sanity-check: second arg is a googleads URL, --toolkit googleads is
    # present, developer-token header is supplied.
    url="${2:-}"
    if [[ "$url" != *"googleads.googleapis.com"* ]]; then
      echo '{"error":"mock proxy: bad url"}' >&2
      exit 1
    fi
    saw_toolkit=0; saw_dev_token=0
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --toolkit) [[ "${2:-}" == "googleads" ]] && saw_toolkit=1; shift 2 ;;
        -H)        [[ "${2:-}" == developer-token:* ]] && saw_dev_token=1; shift 2 ;;
        *)         shift ;;
      esac
    done
    if [[ $saw_toolkit -eq 0 || $saw_dev_token -eq 0 ]]; then
      echo "{\"error\":\"mock proxy: missing toolkit ($saw_toolkit) or dev-token ($saw_dev_token)\"}" >&2
      exit 1
    fi
    echo '{"results":[{"resourceName":"customers/123/campaigns/42"}]}'
    exit 0
    ;;
esac
echo '{"data":null,"successful":false,"error":"unknown mock command"}' >&2
exit 1
EOF
chmod +x "$MOCKDIR/composio"
export PATH="$MOCKDIR:$PATH"

# Mock get-secret.sh — ga proxy reads the dev token through it.
cat > "$MOCKDIR/get-secret.sh" <<'EOF'
#!/usr/bin/env bash
case "$1:$2" in
  google-ads:DEVELOPER_TOKEN) echo "mock-dev-token-12345" ;;
  *) echo "mock-unknown-$1-$2" ;;
esac
EOF
chmod +x "$MOCKDIR/get-secret.sh"
export SECRETS_HELPER="$MOCKDIR/get-secret.sh"

# ---- Tests --------------------------------------------------------------
echo "test-ga.sh"

# Test 1: `ga query` unwraps Composio's {data,successful} envelope to plain JSON
out=$("$GA" query "SELECT campaign.id FROM campaign" | jq -c .)
assert_eq "ga query unwraps envelope" '[{"campaign":{"id":"42"}}]' "$out"

# Test 2: `ga query` requires a query argument (exits non-zero with no args)
if "$GA" query 2>/dev/null; then
  echo "  FAIL ga query without args should exit non-zero"
  FAIL=$((FAIL + 1))
else
  echo "  PASS ga query without args exits non-zero"
fi

# Test 3: `ga proxy` invokes `composio proxy` with toolkit + dev-token, passes raw response
out=$("$GA" proxy GET /v23/customers:listAccessibleCustomers | jq -c .)
assert_eq "ga proxy passes through composio proxy output" '{"results":[{"resourceName":"customers/123/campaigns/42"}]}' "$out"

# Test 4: unknown subcommand exits non-zero
if "$GA" wat 2>/dev/null; then
  echo "  FAIL unknown subcommand should exit non-zero"
  FAIL=$((FAIL + 1))
else
  echo "  PASS unknown subcommand exits non-zero"
fi

if [[ $FAIL -gt 0 ]]; then
  echo
  echo "$FAIL test(s) failed"
  exit 1
fi
echo
echo "all tests passed"

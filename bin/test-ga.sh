#!/usr/bin/env bash
# bin/test-ga.sh — bash assertion suite for bin/ga.
# Mocks `composio` and `curl` via PATH override so we test wiring without
# hitting Google or Composio.

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
# Mock composio: returns a canned envelope based on first arg.
if [[ "${1:-}" == "execute" && "${2:-}" == "GOOGLEADS_QUERY" ]]; then
  echo '{"data":"[{\"campaign\":{\"id\":\"42\"}}]","successful":true}'
  exit 0
fi
echo '{"data":null,"successful":false,"error":"unknown mock command"}' >&2
exit 1
EOF

cat > "$MOCKDIR/curl" <<'EOF'
#!/usr/bin/env bash
# Mock curl: echo a canned proxy_execute success body.
echo '{"data":"{\"results\":[{\"resourceName\":\"customers/123/campaigns/42\"}]}","successful":true}'
EOF

chmod +x "$MOCKDIR/composio" "$MOCKDIR/curl"
export PATH="$MOCKDIR:$PATH"

# Mock get-secret.sh too, since ga proxy reads dev_token + api_key
mkdir -p "$MOCKDIR/secrets"
cat > "$MOCKDIR/secrets/get-secret.sh" <<'EOF'
#!/usr/bin/env bash
# Mock secrets helper. ga proxy calls: get-secret.sh google-ads DEVELOPER_TOKEN
case "$1:$2" in
  google-ads:DEVELOPER_TOKEN) echo "mock-dev-token-12345" ;;
  composio:COMPOSIO_API_KEY)  echo "mock-api-key-67890" ;;
  *) echo "mock-unknown-$1-$2" ;;
esac
EOF
chmod +x "$MOCKDIR/secrets/get-secret.sh"
export SECRETS_HELPER="$MOCKDIR/secrets/get-secret.sh"

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

# Test 3: `ga proxy` accepts METHOD ENDPOINT BODY and returns unwrapped data
out=$("$GA" proxy POST /v18/customers/123/campaigns:mutate '{"operations":[]}' | jq -c .)
assert_eq "ga proxy unwraps envelope" '{"results":[{"resourceName":"customers/123/campaigns/42"}]}' "$out"

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

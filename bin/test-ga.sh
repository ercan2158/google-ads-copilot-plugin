#!/usr/bin/env bash
# bin/test-ga.sh — bash assertion suite for bin/ga.
# Mocks `curl` + the secrets helper via PATH/env override. Creates a temp
# workspace.json so find_workspace() resolves. No real network calls.

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

# ---- Setup mock workspace + PATH ---------------------------------------
WORKDIR=$(mktemp -d)
MOCKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR" "$MOCKDIR"' EXIT

cat > "$WORKDIR/workspace.json" <<EOF
{
  "schema_version": 1,
  "name": "test",
  "account": {
    "customer_id": "1234567890",
    "manager_customer_id": "9999999999",
    "currency": "EUR",
    "timezone": "Europe/Berlin"
  }
}
EOF

# Mock curl:
#  - POST to oauth2.googleapis.com/token returns {"access_token":"mock-tok"}
#  - Anything else returns a canned Google Ads response, captures the URL+body+headers
#    into a sidecar file so tests can inspect them.
cat > "$MOCKDIR/curl" <<'EOF'
#!/usr/bin/env bash
# Mock curl. Determines token-vs-api by URL; logs invocation for inspection.
LOG="${MOCK_CURL_LOG:-/tmp/mock-curl.log}"
url=""; method="GET"; body=""
hdrs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -sS) shift ;;
    -X)  method="$2"; shift 2 ;;
    -H)  hdrs+=( "$2" ); shift 2 ;;
    -d)  body="$2"; shift 2 ;;
    --data-urlencode) body="${body}${body:+&}$2"; shift 2 ;;
    -*)  shift ;;
    *)   url="$1"; shift ;;
  esac
done
{
  echo "URL=$url"
  echo "METHOD=$method"
  echo "BODY=$body"
  for h in "${hdrs[@]}"; do echo "HEADER=$h"; done
  echo "---"
} >> "$LOG"
case "$url" in
  *oauth2.googleapis.com/token*)
    echo '{"access_token":"mock-access-tok","expires_in":3599,"token_type":"Bearer"}'
    ;;
  *googleads.googleapis.com*)
    echo '{"results":[{"campaign":{"id":"42","name":"Brand"}}]}'
    ;;
  *)
    echo "{\"error\":\"mock curl: unexpected url $url\"}" >&2
    exit 22
    ;;
esac
EOF
chmod +x "$MOCKDIR/curl"

# Mock secrets helper
cat > "$MOCKDIR/get-secret.sh" <<'EOF'
#!/usr/bin/env bash
case "$1:$2" in
  google-ads:CLIENT_ID)        echo "mock-client-id" ;;
  google-ads:CLIENT_SECRET)    echo "mock-client-secret" ;;
  google-ads:REFRESH_TOKEN)    echo "mock-refresh-token" ;;
  google-ads:DEVELOPER_TOKEN)  echo "mock-dev-token" ;;
  *) echo "mock-unknown-$1-$2" ;;
esac
EOF
chmod +x "$MOCKDIR/get-secret.sh"

export PATH="$MOCKDIR:$PATH"
export SECRETS_HELPER="$MOCKDIR/get-secret.sh"
export MOCK_CURL_LOG="$MOCKDIR/curl.log"

# Run tests from inside the workspace dir so find_workspace() picks it up.
cd "$WORKDIR"

# ---- Tests --------------------------------------------------------------
echo "test-ga.sh"

# Test 1: `ga query` POSTs to googleAds:search with the GAQL in the body
: > "$MOCK_CURL_LOG"
out=$("$GA" query "SELECT campaign.id FROM campaign" | jq -c .)
assert_eq "ga query returns Google Ads response" '{"results":[{"campaign":{"id":"42","name":"Brand"}}]}' "$out"

# Verify the api request used the right URL + body + auth header
grep -q "URL=https://googleads.googleapis.com/v23/customers/1234567890/googleAds:search" "$MOCK_CURL_LOG" \
  && echo "  PASS ga query hit /v23/customers/{id}/googleAds:search" \
  || { echo "  FAIL ga query did not POST to expected URL"; FAIL=$((FAIL + 1)); }

grep -q 'BODY={"query":"SELECT campaign.id FROM campaign"}' "$MOCK_CURL_LOG" \
  && echo "  PASS ga query sent the GAQL in the JSON body" \
  || { echo "  FAIL ga query body was wrong"; FAIL=$((FAIL + 1)); }

grep -q "HEADER=Authorization: Bearer mock-access-tok" "$MOCK_CURL_LOG" \
  && echo "  PASS ga query attached Authorization: Bearer header" \
  || { echo "  FAIL ga query missing Authorization header"; FAIL=$((FAIL + 1)); }

grep -q "HEADER=developer-token: mock-dev-token" "$MOCK_CURL_LOG" \
  && echo "  PASS ga query attached developer-token header" \
  || { echo "  FAIL ga query missing developer-token"; FAIL=$((FAIL + 1)); }

grep -q "HEADER=login-customer-id: 9999999999" "$MOCK_CURL_LOG" \
  && echo "  PASS ga query attached login-customer-id from workspace.json" \
  || { echo "  FAIL ga query missing login-customer-id"; FAIL=$((FAIL + 1)); }

# Test 2: `ga query` requires a query argument (exits non-zero with no args)
if "$GA" query 2>/dev/null; then
  echo "  FAIL ga query without args should exit non-zero"
  FAIL=$((FAIL + 1))
else
  echo "  PASS ga query without args exits non-zero"
fi

# Test 3: `ga proxy` GET /v23/customers:listAccessibleCustomers
: > "$MOCK_CURL_LOG"
out=$("$GA" proxy GET /v23/customers:listAccessibleCustomers | jq -c .)
assert_eq "ga proxy returns Google Ads response" '{"results":[{"campaign":{"id":"42","name":"Brand"}}]}' "$out"

grep -q "URL=https://googleads.googleapis.com/v23/customers:listAccessibleCustomers" "$MOCK_CURL_LOG" \
  && echo "  PASS ga proxy hit the right URL" \
  || { echo "  FAIL ga proxy URL was wrong"; FAIL=$((FAIL + 1)); }

grep -q "METHOD=GET" "$MOCK_CURL_LOG" \
  && echo "  PASS ga proxy used GET" \
  || { echo "  FAIL ga proxy method was wrong"; FAIL=$((FAIL + 1)); }

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

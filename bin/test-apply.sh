#!/usr/bin/env bash
# bin/test-apply.sh — assertions for bin/apply + bin/validate-proposal.
# Mocks bin/ga via PATH override; creates a temp workspace; runs apply
# against synthetic proposals through every gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPLY="$SCRIPT_DIR/apply"
VALIDATE="$SCRIPT_DIR/validate-proposal"
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

assert_grep() {
  local name="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qE "$pattern"; then
    echo "  PASS $name"
  else
    echo "  FAIL $name"
    echo "    pattern: $pattern"
    echo "    in:      $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# ---- Setup mock workspace + mock ga -----------------------------------------
WORKDIR=$(mktemp -d)
MOCKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR" "$MOCKDIR"' EXIT

mkdir -p "$WORKDIR/workspace/proposals/applied"
mkdir -p "$WORKDIR/workspace/change-log"

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

# Mock ga: scriptable per-call via MOCK_GA_SCRIPT (one line per call).
# Format: <type>:<json>
#   ok:<json>     → echo json, exit 0
#   error:<json>  → echo json with .error to stdout, exit 0 (Google rejection)
#   fail:<msg>    → echo msg to stderr, exit 1 (transport failure)
cat > "$MOCKDIR/ga" <<'EOF'
#!/usr/bin/env bash
# Mock ga. NOTE: must NOT read stdin — bin/apply passes request bodies via
# argv ($3), and consuming stdin here would eat the operator's read -rp
# input on explicit_yes-confirmation kinds, hanging the test.
LOG="${MOCK_GA_LOG:-/tmp/mock-ga.log}"
SCRIPT="${MOCK_GA_SCRIPT:-}"
COUNTER="${MOCK_GA_COUNTER:-/tmp/mock-ga-counter}"
echo "ARGS=$*" >> "$LOG"
if [[ -n "$SCRIPT" && -f "$SCRIPT" ]]; then
  n=$(cat "$COUNTER" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$COUNTER"
  line=$(sed -n "${n}p" "$SCRIPT")
  if [[ -n "$line" ]]; then
    type="${line%%:*}"; payload="${line#*:}"
    case "$type" in
      ok)    printf '%s\n' "$payload"; exit 0 ;;
      error) printf '%s\n' "$payload"; exit 0 ;;
      fail)  printf '%s\n' "$payload" >&2; exit 1 ;;
    esac
  fi
fi
echo '{"results":[{"resourceName":"customers/1234567890/foo/1"}]}'
exit 0
EOF
chmod +x "$MOCKDIR/ga"

# Override the GA path inside bin/apply by symlinking next to apply
# (bin/apply uses "$REPO_DIR/bin/ga" — we shadow it via a temp REPO_DIR).
TEST_REPO=$(mktemp -d)
mkdir -p "$TEST_REPO/bin"
ln -sf "$MOCKDIR/ga" "$TEST_REPO/bin/ga"
cp "$APPLY" "$TEST_REPO/bin/apply"
cp "$VALIDATE" "$TEST_REPO/bin/validate-proposal"
APPLY_TEST="$TEST_REPO/bin/apply"
VALIDATE_TEST="$TEST_REPO/bin/validate-proposal"

cd "$WORKDIR"

echo "test-apply.sh"

# ============================================================================
# Section A: bin/validate-proposal
# ============================================================================

echo
echo "[validate-proposal]"

# A1: valid minimal proposal
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/campaignCriteria:mutate","operations":[{"create":{"x":1}}]}' | "$VALIDATE_TEST" 2>&1; echo "exit=$?")
assert_grep "validate accepts well-formed proposal" 'exit=0' "$out"

# A2: missing required field
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"1234567890"}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects missing method" 'missing required field: method' "$out"

# A3: non-numeric account_id
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"abc123","method":"POST","endpoint":"/v23/customers/abc/foo:mutate","operations":[{}]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects non-numeric account_id" 'numeric string' "$out"

# A4: invalid method
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"1234567890","method":"FETCH","endpoint":"/v23/customers/1234567890/foo:mutate","operations":[{}]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects invalid method" 'method must be one of' "$out"

# A5: endpoint missing leading slash
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"1234567890","method":"POST","endpoint":"v23/customers/foo:mutate","operations":[{}]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects endpoint without leading /" 'endpoint must start with /' "$out"

# A6: both operations and body present
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/foo:mutate","operations":[{}],"body":{"x":1}}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects proposals with BOTH operations and body" 'BOTH operations' "$out"

# A7: empty operations array
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/foo:mutate","operations":[]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects empty operations array" 'operations array is empty' "$out"

# A8: unknown kind warns but doesn't fail
out=$(echo '{"proposal_id":"x","kind":"experimental-thing","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/foo:mutate","operations":[{}]}' | "$VALIDATE_TEST" 2>&1; echo "exit=$?")
assert_grep "validate WARN-only on unknown kind, exits 0" 'WARN — kind' "$out"
assert_grep "validate exits 0 on unknown kind" 'exit=0' "$out"

# A9: parameterless body (neither operations nor body) accepted (e.g. :run)
out=$(echo '{"proposal_id":"x","kind":"customer-match-upload","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/offlineUserDataJobs/1:run"}' | "$VALIDATE_TEST" 2>&1; echo "exit=$?")
assert_grep "validate accepts parameterless body (e.g. :run)" 'exit=0' "$out"

# A10: new shared-list kinds are recognized (no WARN on known kind)
out=$(echo '{"proposal_id":"x","kind":"negative-list-create","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/sharedSets:mutate","operations":[{"create":{"name":"x","type":"NEGATIVE_KEYWORDS"}}]}' | "$VALIDATE_TEST" 2>&1; echo "exit=$?")
if echo "$out" | grep -q 'WARN — kind'; then
  echo "  FAIL validate should recognize negative-list-create as known kind"
  FAIL=$((FAIL + 1))
else
  echo "  PASS validate recognizes negative-list-create as known kind"
fi

# A11: PMax asset-group kinds are recognized
out=$(echo '{"proposal_id":"x","kind":"asset-group-asset-link","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/assetGroupAssets:mutate","operations":[{"create":{"assetGroup":"x","asset":"y","fieldType":"HEADLINE"}}]}' | "$VALIDATE_TEST" 2>&1; echo "exit=$?")
if echo "$out" | grep -q 'WARN — kind'; then
  echo "  FAIL validate should recognize asset-group-asset-link as known kind"
  FAIL=$((FAIL + 1))
else
  echo "  PASS validate recognizes asset-group-asset-link as known kind"
fi

# A12: high-blast kinds REJECTED without confirmation_required: explicit_yes
out=$(echo '{"proposal_id":"x","kind":"negative-list-delete","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/sharedSets:mutate","operations":[{"remove":"customers/1234567890/sharedSets/1"}]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects negative-list-delete without explicit_yes flag" 'requires confirmation_required' "$out"

out=$(echo '{"proposal_id":"x","kind":"asset-group-create","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/assetGroups:mutate","operations":[{"create":{"campaign":"x","name":"y","status":"PAUSED"}}]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects asset-group-create without explicit_yes flag" 'requires confirmation_required' "$out"

out=$(echo '{"proposal_id":"x","kind":"brand-list-create","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/assetSets:mutate","operations":[{"create":{"name":"x","type":"BRAND_LIST"}}]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects brand-list-create without explicit_yes flag" 'requires confirmation_required' "$out"

# A13: high-blast kind WITH explicit_yes is accepted
out=$(echo '{"proposal_id":"x","kind":"negative-list-delete","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/sharedSets:mutate","confirmation_required":"explicit_yes","operations":[{"remove":"customers/1234567890/sharedSets/1"}]}' | "$VALIDATE_TEST" 2>&1; echo "exit=$?")
assert_grep "validate accepts negative-list-delete with explicit_yes flag" 'exit=0' "$out"

# A14: confirmation_required must be omitted or "explicit_yes" — anything else rejected
out=$(echo '{"proposal_id":"x","kind":"negatives","account_id":"1234567890","method":"POST","endpoint":"/v23/customers/1234567890/campaignCriteria:mutate","confirmation_required":"yolo","operations":[{"create":{"x":1}}]}' | "$VALIDATE_TEST" 2>&1 || true)
assert_grep "validate rejects invalid confirmation_required value" 'must be omitted or set to' "$out"

# ============================================================================
# Section B: bin/apply
# ============================================================================

echo
echo "[apply]"

# B1: missing proposal-id arg → usage exit 64
set +e
"$APPLY_TEST" 2>/dev/null; rc=$?
set -e
assert_eq "apply without args exits 64" "64" "$rc"

# B2: nonexistent proposal → error
out=$("$APPLY_TEST" 2026-01-01-nope-99 2>&1 || true)
assert_grep "apply complains when proposal file missing" 'proposal not found' "$out"

# B3: account-ID mismatch → REFUSED
cat > "$WORKDIR/workspace/proposals/2026-05-03-test-mismatch.md" <<'PMD'
# Mismatch test

## Executable

```json
{
  "proposal_id": "2026-05-03-test-mismatch",
  "kind": "negatives",
  "account_id": "9999999999",
  "method": "POST",
  "endpoint": "/v23/customers/9999999999/campaignCriteria:mutate",
  "validate_first": true,
  "operations": [{"create": {"campaign": "x"}}]
}
```
PMD
out=$("$APPLY_TEST" 2026-05-03-test-mismatch --confirm 2>&1 || true)
assert_grep "apply refuses on account-ID mismatch" 'REFUSED' "$out"

# B4: dry-run rejection → leaves proposal in place, exits non-zero
cat > "$WORKDIR/workspace/proposals/2026-05-03-test-dryrun-fail.md" <<'PMD'
# Dry-run fail test

```json
{
  "proposal_id": "2026-05-03-test-dryrun-fail",
  "kind": "negatives",
  "account_id": "1234567890",
  "method": "POST",
  "endpoint": "/v23/customers/1234567890/campaignCriteria:mutate",
  "validate_first": true,
  "operations": [{"create": {"campaign": "x"}}]
}
```
PMD
SCRIPT="$MOCKDIR/script-dryrun-fail"
COUNTER="$MOCKDIR/counter-dryrun-fail"
rm -f "$COUNTER"
echo 'error:{"error":{"code":400,"message":"INVALID_FIELD"}}' > "$SCRIPT"
set +e
out=$(MOCK_GA_SCRIPT="$SCRIPT" MOCK_GA_COUNTER="$COUNTER" "$APPLY_TEST" 2026-05-03-test-dryrun-fail --confirm 2>&1)
rc=$?
set -e
assert_grep "apply prints Google's error on dry-run rejection" 'INVALID_FIELD' "$out"
[[ -f "$WORKDIR/workspace/proposals/2026-05-03-test-dryrun-fail.md" ]] \
  && echo "  PASS apply leaves proposal in place after dry-run rejection" \
  || { echo "  FAIL proposal moved despite dry-run rejection"; FAIL=$((FAIL + 1)); }
[[ "$rc" -ne 0 ]] && echo "  PASS apply exits non-zero on dry-run rejection" \
  || { echo "  FAIL apply exited zero on dry-run rejection"; FAIL=$((FAIL + 1)); }

# B5: happy path with --confirm — applies, logs, moves to applied/
cat > "$WORKDIR/workspace/proposals/2026-05-03-test-happy.md" <<'PMD'
# Happy path

```json
{
  "proposal_id": "2026-05-03-test-happy",
  "kind": "negatives",
  "account_id": "1234567890",
  "method": "POST",
  "endpoint": "/v23/customers/1234567890/campaignCriteria:mutate",
  "validate_first": true,
  "operations": [{"create": {"campaign": "x"}}]
}
```
PMD
SCRIPT="$MOCKDIR/script-happy"
COUNTER="$MOCKDIR/counter-happy"
rm -f "$COUNTER"
{
  echo 'ok:{"results":[]}'   # dry-run pass
  echo 'ok:{"results":[{"resourceName":"customers/1234567890/campaignCriteria/55"}]}'  # live
} > "$SCRIPT"
out=$(MOCK_GA_SCRIPT="$SCRIPT" MOCK_GA_COUNTER="$COUNTER" "$APPLY_TEST" 2026-05-03-test-happy --confirm 2>&1)
assert_grep "apply prints applied confirmation" 'applied. 1 operation' "$out"
[[ -f "$WORKDIR/workspace/proposals/applied/2026-05-03-test-happy.md" ]] \
  && echo "  PASS apply moves proposal to applied/ on success" \
  || { echo "  FAIL proposal not moved"; FAIL=$((FAIL + 1)); }
log_line=$(cat "$WORKDIR/workspace/change-log/$(date +%Y-%m-%d).jsonl" 2>/dev/null | tail -1)
assert_grep "change-log records the applied op" '"applied":true' "$log_line"
assert_grep "change-log records the proposal_id" '"proposal_id":"2026-05-03-test-happy"' "$log_line"

# B6: --plan mode runs dry-run only and does NOT mutate
cat > "$WORKDIR/workspace/proposals/2026-05-03-test-plan.md" <<'PMD'
# Plan mode

```json
{
  "proposal_id": "2026-05-03-test-plan",
  "kind": "negatives",
  "account_id": "1234567890",
  "method": "POST",
  "endpoint": "/v23/customers/1234567890/campaignCriteria:mutate",
  "validate_first": true,
  "operations": [{"create": {"campaign": "x"}}]
}
```
PMD
SCRIPT="$MOCKDIR/script-plan"
COUNTER="$MOCKDIR/counter-plan"
rm -f "$COUNTER"
echo 'ok:{"results":[]}' > "$SCRIPT"   # dry-run only
out=$(MOCK_GA_SCRIPT="$SCRIPT" MOCK_GA_COUNTER="$COUNTER" "$APPLY_TEST" 2026-05-03-test-plan --plan 2>&1)
assert_grep "apply --plan prints plan summary" 'Plan summary' "$out"
[[ -f "$WORKDIR/workspace/proposals/2026-05-03-test-plan.md" ]] \
  && echo "  PASS apply --plan does NOT move the proposal" \
  || { echo "  FAIL --plan moved the proposal"; FAIL=$((FAIL + 1)); }
n_calls=$(cat "$COUNTER")
assert_eq "apply --plan calls ga exactly once (dry-run only)" "1" "$n_calls"

# B7: malformed JSON in proposal block
cat > "$WORKDIR/workspace/proposals/2026-05-03-test-bad-json.md" <<'PMD'
# Bad JSON

```json
{ this is not valid json
```
PMD
out=$("$APPLY_TEST" 2026-05-03-test-bad-json --confirm 2>&1 || true)
assert_grep "apply rejects malformed JSON in proposal" 'malformed JSON' "$out"

# B8: schema validation failure (invalid method)
cat > "$WORKDIR/workspace/proposals/2026-05-03-test-bad-method.md" <<'PMD'
# Bad method

```json
{
  "proposal_id": "2026-05-03-test-bad-method",
  "kind": "negatives",
  "account_id": "1234567890",
  "method": "FETCH",
  "endpoint": "/v23/customers/1234567890/foo:mutate",
  "operations": [{}]
}
```
PMD
out=$("$APPLY_TEST" 2026-05-03-test-bad-method --confirm 2>&1 || true)
assert_grep "apply blocks proposals that fail schema validation" 'failed schema validation' "$out"

# B9: resource-name auto-substitution from change-log
# Seed change-log with a prior proposal's response that contains a resourceName.
cat >> "$WORKDIR/workspace/change-log/$(date +%Y-%m-%d).jsonl" <<'JLOG'
{"ts":"2026-05-03T10:00:00Z","proposal_id":"2026-05-03-prior","kind":"assets-add","account_id":"1234567890","request":{},"response":{"results":[{"resourceName":"customers/1234567890/assets/777"}]},"applied":true}
JLOG

cat > "$WORKDIR/workspace/proposals/2026-05-03-test-substitute.md" <<'PMD'
# Substitution test

```json
{
  "proposal_id": "2026-05-03-test-substitute",
  "kind": "assets-link",
  "account_id": "1234567890",
  "method": "POST",
  "endpoint": "/v23/customers/1234567890/customerAssets:mutate",
  "validate_first": true,
  "operations": [
    {"create": {"asset": "<resourceName from proposal 2026-05-03-prior op 1>", "fieldType": "SITELINK"}}
  ]
}
```
PMD
SCRIPT="$MOCKDIR/script-sub"
COUNTER="$MOCKDIR/counter-sub"
GA_LOG="$MOCKDIR/ga-sub.log"
rm -f "$COUNTER" "$GA_LOG"
{
  echo 'ok:{"results":[]}'
  echo 'ok:{"results":[{"resourceName":"customers/1234567890/customerAssets/1~SITELINK"}]}'
} > "$SCRIPT"
MOCK_GA_LOG="$GA_LOG" MOCK_GA_SCRIPT="$SCRIPT" MOCK_GA_COUNTER="$COUNTER" \
  "$APPLY_TEST" 2026-05-03-test-substitute --confirm >/dev/null 2>&1 || true
# Inspect the live-call args; placeholder should have been replaced
if [[ -f "$GA_LOG" ]] && grep -q 'customers/1234567890/assets/777' "$GA_LOG"; then
  echo "  PASS apply substitutes <resourceName from proposal X op N> from change-log"
else
  echo "  FAIL placeholder was not substituted"
  if [[ -f "$GA_LOG" ]]; then
    echo "    ga calls:"
    sed 's/^/      /' "$GA_LOG"
  else
    echo "    ga log not created — apply errored before reaching ga"
  fi
  FAIL=$((FAIL + 1))
fi

# B11: confirmation_required prompts for proposal_id retype, accepts on match
cat > "$WORKDIR/workspace/proposals/2026-05-04-test-explicit-yes.md" <<'PMD'
# Explicit-yes happy path

```json
{
  "proposal_id": "2026-05-04-test-explicit-yes",
  "kind": "negative-list-delete",
  "account_id": "1234567890",
  "method": "POST",
  "endpoint": "/v23/customers/1234567890/sharedSets:mutate",
  "validate_first": true,
  "confirmation_required": "explicit_yes",
  "operations": [{"remove": "customers/1234567890/sharedSets/1"}]
}
```
PMD
SCRIPT="$MOCKDIR/script-explicit-happy"
COUNTER="$MOCKDIR/counter-explicit-happy"
rm -f "$COUNTER"
{
  echo 'ok:{"results":[]}'   # dry-run
  echo 'ok:{"results":[{"resourceName":"customers/1234567890/sharedSets/1"}]}'
} > "$SCRIPT"
# Pipe the proposal_id as stdin; --confirm flag is ignored for explicit_yes (always prompts)
out=$(MOCK_GA_SCRIPT="$SCRIPT" MOCK_GA_COUNTER="$COUNTER" \
  "$APPLY_TEST" 2026-05-04-test-explicit-yes --confirm <<<"2026-05-04-test-explicit-yes" 2>&1 || true)
assert_grep "apply with explicit_yes accepts proper retype" 'applied. 1 operation' "$out"
[[ -f "$WORKDIR/workspace/proposals/applied/2026-05-04-test-explicit-yes.md" ]] \
  && echo "  PASS explicit_yes happy-path moves proposal to applied/" \
  || { echo "  FAIL explicit_yes happy-path didn't move proposal"; FAIL=$((FAIL + 1)); }

# B12: confirmation_required rejects on mismatched retype, even with --confirm
cat > "$WORKDIR/workspace/proposals/2026-05-04-test-explicit-mismatch.md" <<'PMD'
```json
{
  "proposal_id": "2026-05-04-test-explicit-mismatch",
  "kind": "asset-group-create",
  "account_id": "1234567890",
  "method": "POST",
  "endpoint": "/v23/customers/1234567890/assetGroups:mutate",
  "validate_first": true,
  "confirmation_required": "explicit_yes",
  "operations": [{"create": {"campaign": "x", "name": "y", "status": "PAUSED"}}]
}
```
PMD
SCRIPT="$MOCKDIR/script-explicit-mismatch"
COUNTER="$MOCKDIR/counter-explicit-mismatch"
rm -f "$COUNTER"
echo 'ok:{"results":[]}' > "$SCRIPT"   # dry-run only
out=$(MOCK_GA_SCRIPT="$SCRIPT" MOCK_GA_COUNTER="$COUNTER" \
  "$APPLY_TEST" 2026-05-04-test-explicit-mismatch --confirm <<<"y" 2>&1 || true)
assert_grep "apply with explicit_yes rejects single-y answer" 'confirmation token did not match' "$out"
[[ -f "$WORKDIR/workspace/proposals/2026-05-04-test-explicit-mismatch.md" ]] \
  && echo "  PASS explicit_yes mismatch leaves proposal in place" \
  || { echo "  FAIL explicit_yes mismatch moved the proposal"; FAIL=$((FAIL + 1)); }

# B10: substitution failure when the prior proposal isn't in change-log
cat > "$WORKDIR/workspace/proposals/2026-05-03-test-sub-fail.md" <<'PMD'
# Substitution fail test

```json
{
  "proposal_id": "2026-05-03-test-sub-fail",
  "kind": "assets-link",
  "account_id": "1234567890",
  "method": "POST",
  "endpoint": "/v23/customers/1234567890/customerAssets:mutate",
  "validate_first": true,
  "operations": [
    {"create": {"asset": "<resourceName from proposal 2026-01-01-nonexistent op 1>", "fieldType": "SITELINK"}}
  ]
}
```
PMD
out=$("$APPLY_TEST" 2026-05-03-test-sub-fail --confirm 2>&1 || true)
assert_grep "apply errors clearly when placeholder source is missing" 'cannot resolve placeholder' "$out"

if [[ $FAIL -gt 0 ]]; then
  echo
  echo "$FAIL test(s) failed"
  exit 1
fi
echo
echo "all tests passed"

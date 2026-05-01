# ads-copilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin (`ads-copilot`) and a workspace repo (`yamazumi`) so a non-technical SaaS operator can run AI-driven Google Ads operations through `/ads-*` slash commands, with a single mutating command (`/ads-apply`) gating all account changes.

**Architecture:** Two-repo split. The plugin (reusable across SaaS apps) discovers the per-app workspace via cwd walk-up of `workspace.json`. All Google Ads I/O goes through one shell helper `bin/ga` that wraps Composio CLI for whitelisted reads and Composio's `proxy_execute` HTTP endpoint (with `developer-token` header) for mutations.

**Tech stack:** Claude Code plugin (markdown skills/commands/agents), bash + jq + curl + composio CLI, secrets via `~/.config/secrets/get-secret.sh`. No build step, no server, no test framework.

**Spec:** [`docs/specs/2026-04-30-ads-copilot-design.md`](./2026-04-30-ads-copilot-design.md)

---

## File structure (locked in before tasks)

### Plugin repo — `~/dev/personal/ads-copilot/`

```
ads-copilot/
├── .claude-plugin/plugin.json          (manifest)
├── .gitignore
├── README.md                            (~20 lines: install + first-run)
├── agents/
│   └── ads-manager.md                   (single persona)
├── commands/
│   ├── ads-daily.md
│   ├── ads-weekly.md
│   ├── ads-monthly.md
│   ├── ads-search-terms.md
│   ├── ads-budgets.md
│   ├── ads-creative.md
│   ├── ads-bootstrap.md
│   ├── ads-explain.md
│   └── ads-apply.md
├── skills/
│   ├── googleads-gaql/SKILL.md
│   ├── ads-account-audit/SKILL.md
│   ├── ads-search-term-mining/SKILL.md
│   ├── ads-budget-management/SKILL.md
│   ├── ads-creative-management/SKILL.md
│   ├── ads-change-execution/SKILL.md
│   └── ads-explain-to-beginner/SKILL.md
└── bin/
    ├── ga                               (shell wrapper, ~80 lines)
    ├── install                          (symlink + smoke test)
    └── test-ga.sh                       (bash assertion script for bin/ga)
```

### Workspace repo — `~/dev/personal/yamazumi/`

```
yamazumi/
├── workspace.json                       (copied from yamazumi-ads/)
├── README.md                            (~10 lines: cd here, run /ads-daily)
├── .gitignore
└── context/
    ├── icp.md                           (copied from yamazumi-ads/)
    ├── budget-policy.md                 (copied)
    ├── kpi-tree.md                      (copied)
    ├── persona-overrides.md             (copied)
    └── product-positioning.md           (copied)
```

`digests/`, `proposals/`, `change-log/`, `account/snapshots/` are created by the agent on first write — not pre-scaffolded.

### Responsibility per file

- **`bin/ga`** — sole I/O boundary. Two subcommands: `ga query "<GAQL>"` (Composio CLI, unwraps response envelope) and `ga proxy <METHOD> <ENDPOINT> [BODY]` (curl proxy_execute with dev-token header). Skills/commands never call `composio` or `curl` directly.
- **`bin/install`** — `ln -s` the repo into `~/.claude/plugins/ads-copilot/`, then run a one-shot `ga query 'SELECT customer.id FROM customer'` smoke test.
- **`bin/test-ga.sh`** — invokes `bin/ga` with mocked `composio`/`curl` (PATH override) to assert subcommand wiring and JSON unwrapping work.
- **`agents/ads-manager.md`** — persona prompt; reads `workspace.json` + `context/*.md`; loads relevant skill(s) per command; enforces "never mutate directly, write proposal then stop."
- **`skills/<name>/SKILL.md`** — focused knowledge files (~30–60 lines each): GAQL cookbook, mining heuristics, audit templates, budget math, creative rules, jargon translations, proposal protocol.
- **`commands/<name>.md`** — slash-command entry points (~10–25 lines each); each loads the agent + the relevant skill(s) and instructs the task.

---

## Tasks

### Task 1: Scaffold the plugin repo with the manifest

**Files:**
- Create: `~/dev/personal/ads-copilot/.claude-plugin/plugin.json`
- Create: `~/dev/personal/ads-copilot/.gitignore`
- Create: `~/dev/personal/ads-copilot/README.md`

- [ ] **Step 1: Create the directory and initialize git**

```bash
mkdir -p ~/dev/personal/ads-copilot/{.claude-plugin,agents,commands,skills,bin,docs}
cd ~/dev/personal/ads-copilot
git init -b main
```

- [ ] **Step 2: Write `.claude-plugin/plugin.json`**

Create `~/dev/personal/ads-copilot/.claude-plugin/plugin.json`:

```json
{
  "name": "ads-copilot",
  "version": "0.1.0",
  "description": "AI-driven Google Ads operator for non-technical SaaS founders. Slash commands that read the account, propose mutations as files, and apply them only on explicit /ads-apply.",
  "author": {
    "name": "Ercan",
    "email": "ercan.kurtarangil@reev.com"
  },
  "agents": ["./agents"],
  "skills": ["./skills"],
  "commands": ["./commands"]
}
```

- [ ] **Step 3: Write `.gitignore`**

Create `~/dev/personal/ads-copilot/.gitignore`:

```
.DS_Store
*.swp
node_modules/
.idea/
.vscode/
```

- [ ] **Step 4: Write `README.md` (~20 lines)**

Create `~/dev/personal/ads-copilot/README.md`:

```markdown
# ads-copilot

Claude Code plugin for AI-driven Google Ads operations. One operator, one or
many SaaS apps. The AI is the expert; you type slash commands.

## Install

```bash
bin/install
```

This symlinks the plugin into `~/.claude/plugins/ads-copilot/` and runs a
one-shot Composio smoke test to verify connectivity.

## First run

```bash
cd ~/dev/personal/<your-app>     # any folder with a workspace.json
claude
> /ads-daily
```

The plugin walks up from cwd, finds `workspace.json`, and binds to that
account for the session.

## Commands

`/ads-daily`, `/ads-weekly`, `/ads-monthly`, `/ads-search-terms`,
`/ads-budgets`, `/ads-creative`, `/ads-bootstrap`, `/ads-explain`,
`/ads-apply <proposal-id>`. See `commands/` for what each does.

## Safety

`/ads-apply` is the only command that mutates the account. Everything else
is read-only or writes a proposal file you review before shipping.
```

- [ ] **Step 5: Verify and commit**

```bash
cd ~/dev/personal/ads-copilot
ls -la .claude-plugin/plugin.json README.md .gitignore
git add -A
git commit -m "chore: scaffold ads-copilot plugin repo with manifest"
```

Expected: `plugin.json`, `README.md`, `.gitignore` exist; first commit lands on `main`.

---

### Task 2: Scaffold the yamazumi workspace repo (migrate context)

**Files:**
- Create: `~/dev/personal/yamazumi/workspace.json` (copied)
- Create: `~/dev/personal/yamazumi/context/*.md` (5 files, copied)
- Create: `~/dev/personal/yamazumi/README.md`
- Create: `~/dev/personal/yamazumi/.gitignore`

- [ ] **Step 1: Create the directory and initialize git**

```bash
mkdir -p ~/dev/personal/yamazumi/context
cd ~/dev/personal/yamazumi
git init -b main
```

- [ ] **Step 2: Copy `workspace.json` from `yamazumi-ads/`**

```bash
cp ~/dev/personal/yamazumi-ads/workspace.json ~/dev/personal/yamazumi/workspace.json
```

Verify the copy:

```bash
jq -r '.account.customer_id, .composio.user_id' ~/dev/personal/yamazumi/workspace.json
```

Expected output:
```
8191097521
pg-test-92398db6-5153-4968-b3be-66beb5753aaa
```

- [ ] **Step 3: Copy the five context files**

```bash
for f in icp.md budget-policy.md kpi-tree.md persona-overrides.md product-positioning.md; do
  cp ~/dev/personal/yamazumi-ads/workspace/context/$f ~/dev/personal/yamazumi/context/$f
done
ls ~/dev/personal/yamazumi/context/
```

Expected: 5 files listed.

- [ ] **Step 4: Write `README.md`**

Create `~/dev/personal/yamazumi/README.md`:

```markdown
# yamazumi (workspace)

Per-app workspace for the Yamazumi.io Google Ads account
(`customers/8191097521`). Operated by the
[`ads-copilot`](https://github.com/<owner>/ads-copilot) Claude Code plugin.

## Use

```bash
cd ~/dev/personal/yamazumi
claude
> /ads-daily
```

The plugin auto-discovers `workspace.json` walking up from cwd.

## Layout

- `workspace.json` — account ID, currency, Composio binding
- `context/` — human-authored business context (ICP, budget policy, KPIs)
- `digests/`, `proposals/`, `change-log/`, `account/snapshots/` — agent-authored, created on first write
```

- [ ] **Step 5: Write `.gitignore`**

Create `~/dev/personal/yamazumi/.gitignore`:

```
.DS_Store
*.swp
```

- [ ] **Step 6: Verify and commit**

```bash
cd ~/dev/personal/yamazumi
git add -A
git commit -m "chore: scaffold yamazumi workspace, migrate context from yamazumi-ads"
```

Expected: 7 files staged (workspace.json, README.md, .gitignore, 5 context files), first commit on `main`.

---

### Task 3: Implement `bin/ga` with bash tests (TDD)

**Files:**
- Create: `~/dev/personal/ads-copilot/bin/ga`
- Create: `~/dev/personal/ads-copilot/bin/test-ga.sh`

- [ ] **Step 1: Write the failing test for `ga query`**

Create `~/dev/personal/ads-copilot/bin/test-ga.sh`:

```bash
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
```

```bash
chmod +x ~/dev/personal/ads-copilot/bin/test-ga.sh
```

- [ ] **Step 2: Run the test to verify it fails (no `bin/ga` yet)**

```bash
~/dev/personal/ads-copilot/bin/test-ga.sh
```

Expected: fails because `bin/ga` does not exist.

- [ ] **Step 3: Write `bin/ga`**

Create `~/dev/personal/ads-copilot/bin/ga`:

```bash
#!/usr/bin/env bash
# bin/ga — single shell wrapper around Composio CLI + Composio proxy_execute
# for Google Ads. The only file in the plugin that touches `composio` or
# `curl`. If Composio's CLI shape changes, fix here.

set -euo pipefail

SECRETS_HELPER="${SECRETS_HELPER:-$HOME/.config/secrets/get-secret.sh}"
COMPOSIO_API_BASE="${COMPOSIO_API_BASE:-https://backend.composio.dev}"

usage() {
  cat <<EOF >&2
Usage: ga <subcommand> [args]

Subcommands:
  query "<GAQL>"                              Run a read-only GAQL query.
  proxy <METHOD> <ENDPOINT> [<JSON-BODY>]     Proxy an arbitrary Google Ads
                                              REST call (mutations included).

Examples:
  ga query "SELECT campaign.id, campaign.name FROM campaign LIMIT 5"
  ga proxy POST /v18/customers/8191097521/campaignCriteria:mutate '{"operations":[...]}'
EOF
  exit 64
}

unwrap() {
  # Composio returns {"data":"<json-string-or-object>","successful":true}.
  # Unwrap to the inner data on success; emit error on failure.
  jq -e '
    if .successful != true then
      ("composio error: " + (.error // "unknown")) | halt_error(1)
    elif (.data | type) == "string" then
      .data | fromjson
    else
      .data
    end
  '
}

cmd_query() {
  local q="${1:-}"
  [[ -z "$q" ]] && { echo "ga query: missing GAQL string" >&2; exit 64; }
  local payload
  payload=$(jq -nc --arg q "$q" '{query:$q}')
  composio execute GOOGLEADS_QUERY -d "$payload" | unwrap
}

cmd_proxy() {
  local method="${1:-}" endpoint="${2:-}" body="${3:-}"
  [[ -z "$method" || -z "$endpoint" ]] && {
    echo "ga proxy: need METHOD and ENDPOINT" >&2; exit 64
  }
  local dev_token api_key payload
  dev_token=$("$SECRETS_HELPER" google-ads DEVELOPER_TOKEN)
  api_key=$("$SECRETS_HELPER" composio COMPOSIO_API_KEY)
  payload=$(jq -nc \
    --arg m "$method" \
    --arg e "$endpoint" \
    --arg dt "$dev_token" \
    --argjson b "${body:-null}" \
    '{
      toolkit_slug: "googleads",
      endpoint:     $e,
      method:       $m,
      body:         $b,
      parameters:   [{name:"developer-token", value:$dt, type:"header"}]
    }')
  curl -sS -X POST \
    "$COMPOSIO_API_BASE/api/v3/tool_router/session/default/proxy_execute" \
    -H "x-api-key: $api_key" \
    -H "Content-Type: application/json" \
    -d "$payload" | unwrap
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    query) cmd_query "$@" ;;
    proxy) cmd_proxy "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "ga: unknown subcommand: $sub" >&2; usage ;;
  esac
}

main "$@"
```

```bash
chmod +x ~/dev/personal/ads-copilot/bin/ga
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
~/dev/personal/ads-copilot/bin/test-ga.sh
```

Expected output:
```
test-ga.sh
  PASS ga query unwraps envelope
  PASS ga query without args exits non-zero
  PASS ga proxy unwraps envelope
  PASS unknown subcommand exits non-zero

all tests passed
```

- [ ] **Step 5: Commit**

```bash
cd ~/dev/personal/ads-copilot
git add bin/ga bin/test-ga.sh
git commit -m "feat(bin): ga shell wrapper for composio cli + proxy_execute, with tests"
```

---

### Task 4: Implement `bin/install` (symlink + live smoke test)

**Files:**
- Create: `~/dev/personal/ads-copilot/bin/install`

- [ ] **Step 1: Write `bin/install`**

Create `~/dev/personal/ads-copilot/bin/install`:

```bash
#!/usr/bin/env bash
# bin/install — register the plugin with Claude Code and verify connectivity.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="ads-copilot"
TARGET="$HOME/.claude/plugins/$PLUGIN_NAME"

# 1. Symlink the plugin into ~/.claude/plugins/
mkdir -p "$HOME/.claude/plugins"
if [[ -L "$TARGET" || -e "$TARGET" ]]; then
  echo "[install] removing existing $TARGET"
  rm -rf "$TARGET"
fi
ln -s "$REPO_DIR" "$TARGET"
echo "[install] linked $REPO_DIR -> $TARGET"

# 2. Run unit tests for bin/ga
echo "[install] running bin/test-ga.sh"
"$REPO_DIR/bin/test-ga.sh"

# 3. Live smoke test — verify Composio + Google Ads connectivity
echo "[install] live smoke test: composio execute GOOGLEADS_LIST_ACCESSIBLE_CUSTOMERS"
out=$(composio execute GOOGLEADS_LIST_ACCESSIBLE_CUSTOMERS -d '{}' 2>&1) || {
  echo "[install] FAILED — composio call errored:"
  echo "$out"
  echo
  echo "Likely fixes:"
  echo "  - Run \`composio login\` to authenticate the CLI"
  echo "  - Verify Composio googleads toolkit is connected"
  exit 1
}

echo "$out" | jq -e '.successful == true' >/dev/null || {
  echo "[install] FAILED — Composio returned a non-success envelope:"
  echo "$out" | jq .
  exit 1
}

echo "[install] OK. Accessible customers:"
echo "$out" | jq -r '.data | fromjson? // .data'

echo
echo "[install] Done. Open Claude Code in any folder with a workspace.json"
echo "          and run /ads-daily to start."
```

```bash
chmod +x ~/dev/personal/ads-copilot/bin/install
```

- [ ] **Step 2: Run `bin/install` against the live account**

```bash
~/dev/personal/ads-copilot/bin/install
```

Expected: `bin/test-ga.sh` passes, then live Composio call succeeds, listing the accessible customer IDs (should include `customers/8191097521`).

If Composio login is needed, the script tells you. Re-run after `composio login`.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/personal/ads-copilot
git add bin/install
git commit -m "feat(bin): install script with live composio smoke test"
```

---

### Task 5: Write the `ads-manager` agent persona

**Files:**
- Create: `~/dev/personal/ads-copilot/agents/ads-manager.md`

- [ ] **Step 1: Write the agent file**

Create `~/dev/personal/ads-copilot/agents/ads-manager.md`:

```markdown
---
name: ads-manager
description: Senior Google Ads operator persona. Loaded by every /ads-* command. Reads workspace.json + context/, runs reads via bin/ga, never mutates directly — writes proposals to workspace/proposals/ instead.
---

# ads-manager

You are a senior Google Ads operator working for a SaaS founder who has **no
Google Ads background**. You are the expert. They trust you to do the right
thing — and you trust them to read the proposal before any change ships.

## Bind to the account

On every invocation:

1. Find `workspace.json` by walking up from cwd. If not found within 5
   levels, halt and ask the user to `cd` into a workspace folder.
2. Read these fields:
   - `account.customer_id` — the Google Ads customer ID
   - `account.currency`, `account.timezone` — for human-readable numbers
   - `composio.user_id`, `composio.googleads_account_alias` — for `bin/ga`
3. Read every file in `context/`. These are the operator's hand-written
   ICP, budget policy, KPI tree, persona overrides, product positioning.
   They are sacred — you read, you do not silently rewrite.

## Run reads via `bin/ga`

Never call `composio` or `curl` directly. Use:
- `bin/ga query "SELECT ... FROM ... WHERE ..."` for GAQL reads
- `bin/ga proxy <METHOD> <ENDPOINT> [BODY]` for Google Ads REST endpoints
  Composio doesn't expose as a slug

The `googleads-gaql` skill has the query cookbook.

## NEVER mutate directly

You do not call mutate endpoints. You **draft proposals**:

- Write `workspace/proposals/<YYYY-MM-DD>-<kind>-<seq>.md`
- The file has plain-English rationale at the top and an executable JSON
  code block at the bottom. The `ads-change-execution` skill defines the
  exact format.
- Print a short chat summary pointing the operator at the file.
- Stop. The account is untouched until the operator runs `/ads-apply <id>`.

The single exception is `/ads-apply` itself, which reads a proposal you
already drafted and executes it after a `validate_only` dry-run and a
y/n confirmation.

## Plain-English first

The operator does not know Google Ads jargon. Apply the
`ads-explain-to-beginner` skill on every output:

1. Top of every chat reply: a 2–4 line TL;DR in plain English. No jargon.
2. The first time any term ("CTR", "impression share", "quality score",
   "match type", "responsive search ad", "negative keyword", "ad rank",
   "search lost (rank)", …) appears in a session, append a one-line
   parenthetical translation. Track what you've already explained.
3. Numbers always include their currency or unit (€, %, conv).

## Anomaly threshold (for `/ads-daily`)

Write a digest file ONLY if at least one of:
- spend ±20% vs same weekday last week
- conversions ±50% vs same weekday last week
- any newly-disapproved ad
- any campaign that flatlined to zero impressions
- any proposal was drafted in this run

Otherwise, print to chat and exit. Do not create files for boring days.
```

- [ ] **Step 2: Verify and commit**

```bash
cd ~/dev/personal/ads-copilot
ls agents/ads-manager.md
git add agents/
git commit -m "feat(agent): ads-manager persona with binding, mutation safety, plain-English rules"
```

---

### Task 6: Write the `googleads-gaql` and `ads-explain-to-beginner` skills

**Files:**
- Create: `~/dev/personal/ads-copilot/skills/googleads-gaql/SKILL.md`
- Create: `~/dev/personal/ads-copilot/skills/ads-explain-to-beginner/SKILL.md`

- [ ] **Step 1: Write `googleads-gaql/SKILL.md`**

Create `~/dev/personal/ads-copilot/skills/googleads-gaql/SKILL.md`:

```markdown
---
name: googleads-gaql
description: GAQL cookbook for read queries via bin/ga query. Use whenever you need to read account data — campaign performance, search terms, conversion paths, ad assets, account-level diagnostics.
---

# googleads-gaql

Run all reads through `bin/ga query "<GAQL>"`. The output is plain JSON
(envelope already unwrapped). For mutations use `ads-change-execution`.

## Last 24h spend + conversions per campaign

```sql
SELECT
  campaign.id, campaign.name, campaign.status,
  metrics.cost_micros, metrics.conversions, metrics.clicks, metrics.impressions
FROM campaign
WHERE segments.date DURING LAST_DAY
  AND campaign.status != 'REMOVED'
ORDER BY metrics.cost_micros DESC
```

`cost_micros / 1_000_000` to get currency units.

## Last 30d search terms with low/no conversion

```sql
SELECT
  campaign.id, campaign.name,
  ad_group.id, ad_group.name,
  search_term_view.search_term,
  metrics.clicks, metrics.cost_micros, metrics.conversions, metrics.impressions
FROM search_term_view
WHERE segments.date DURING LAST_30_DAYS
  AND metrics.impressions > 50
  AND metrics.conversions < 1
ORDER BY metrics.cost_micros DESC
```

## Disapproved ads

```sql
SELECT
  ad_group_ad.ad.id, ad_group_ad.ad.name, ad_group_ad.policy_summary.approval_status,
  ad_group_ad.policy_summary.policy_topic_entries
FROM ad_group_ad
WHERE ad_group_ad.policy_summary.approval_status IN ('DISAPPROVED', 'AREA_OF_INTEREST_ONLY')
```

## Flatlined campaigns (last 7 days, zero impressions)

```sql
SELECT campaign.id, campaign.name, campaign.status
FROM campaign
WHERE segments.date DURING LAST_7_DAYS
  AND campaign.status = 'ENABLED'
HAVING SUM(metrics.impressions) = 0
```

## Budget pacing (current month)

```sql
SELECT
  campaign.id, campaign.name,
  campaign_budget.amount_micros, campaign_budget.delivery_method,
  metrics.cost_micros
FROM campaign
WHERE segments.date DURING THIS_MONTH
  AND campaign.status = 'ENABLED'
```

Compute pacing: `actual = cost_micros / 1_000_000`,
`expected = (amount_micros / 1_000_000) * days_elapsed_this_month`. Flag
±20% from expected.

## Responsive search ad asset performance

```sql
SELECT
  ad_group.id, ad_group_ad.ad.id, ad_group_ad.ad.name,
  asset.text_asset.text, ad_group_ad_asset_view.performance_label,
  ad_group_ad_asset_view.field_type
FROM ad_group_ad_asset_view
WHERE segments.date DURING LAST_30_DAYS
  AND ad_group_ad_asset_view.field_type IN ('HEADLINE', 'DESCRIPTION')
```

`performance_label`: `BEST`, `GOOD`, `LOW`, `LEARNING`, `PENDING`, `UNKNOWN`.
`LOW` assets are candidates for replacement.

## Account-level KPIs (last 30d)

```sql
SELECT
  customer.id, customer.descriptive_name,
  metrics.cost_micros, metrics.conversions, metrics.conversions_value,
  metrics.clicks, metrics.impressions, metrics.search_impression_share,
  metrics.search_top_impression_share
FROM customer
WHERE segments.date DURING LAST_30_DAYS
```

## Conversion actions

```sql
SELECT
  conversion_action.id, conversion_action.name,
  conversion_action.status, conversion_action.category,
  conversion_action.primary_for_goal
FROM conversion_action
WHERE conversion_action.status != 'REMOVED'
```

## How to call from the agent

```
bin/ga query "SELECT campaign.id, campaign.name FROM campaign WHERE campaign.status = 'ENABLED'"
```

Returns a JSON array. Parse with `jq` or in-context.
```

- [ ] **Step 2: Write `ads-explain-to-beginner/SKILL.md`**

Create `~/dev/personal/ads-copilot/skills/ads-explain-to-beginner/SKILL.md`:

```markdown
---
name: ads-explain-to-beginner
description: UX rules for explaining Google Ads to a non-technical operator. Loaded by every /ads-* command — defines TL;DR shape, jargon translations, anti-jargon rule.
---

# ads-explain-to-beginner

The operator has zero Google Ads background. They trust the AI to do the
work AND to explain it without making them feel dumb.

## TL;DR shape (top of every chat reply)

```
TL;DR: <2–4 lines, no jargon. State what happened, whether it matters,
       and what (if anything) you want to do about it.>
```

Then numbers, then action note. Total chat output: ≤ 15 lines unless the
user explicitly asks for more.

## Jargon translation rule

The first time **any** of these terms appears in a session, append a 1-line
parenthetical translation. After that, no translation. Track per session.

| Term | Plain-English translation |
|---|---|
| CTR | click-through rate — % of people who saw your ad and clicked |
| CPC | cost per click |
| CPA | cost per conversion (sign-up, sale, …) |
| ROAS | return on ad spend — €1 in ads → €X back |
| impression | one time your ad was shown |
| impression share | % of available shows you actually got (the rest went to competitors) |
| search lost (rank) | shows you missed because Google ranked competitors above you |
| search lost (budget) | shows you missed because your budget ran out |
| quality score | Google's 1–10 grade of your ad's relevance + landing page |
| ad rank | what determines whether your ad shows and where |
| match type (broad/phrase/exact) | how loosely Google matches a keyword to a search query |
| negative keyword | a word that, if in the search, prevents your ad from showing |
| RSA / responsive search ad | Google's standard ad format with multiple headlines/descriptions, mixed automatically |
| asset (headline / description) | one of the swappable text pieces inside a responsive search ad |
| conversion | the user action you count as success (sign-up, checkout, demo) |
| conversion action | a specific definition of "what counts as a conversion" |
| campaign / ad group / keyword | bucket → bucket → trigger word, top-down |
| daily budget | average daily cap; Google can spend up to 2x on busy days, less on slow |
| pacing | spend so far this month vs. expected for the days elapsed |
| disapproved ad | Google has blocked the ad (policy violation, broken landing page, …) |
| validate_only | a dry-run that checks if a change would work, without applying it |

If you use a term not in this table, write your own one-line translation
the first time. Don't apologize. Don't say "in plain English."

## Numbers always have units

- Money: `€82` not `82`
- Rates: `3.4%` not `0.034`
- Counts: `12 conv` not `12`

## Surface uncertainty

If a recommendation depends on something you're not sure of, say so.
"I think these negatives are safe, but X is worth a second look because Y."
Beginners trust experts more when the expert admits uncertainty.

## Refuse made-up authority

If asked something Google Ads docs would answer better than your training,
say so and either run a query or point at the official docs path. Never
fabricate threshold numbers, formula details, or product feature claims.
```

- [ ] **Step 3: Verify and commit**

```bash
cd ~/dev/personal/ads-copilot
ls skills/googleads-gaql/SKILL.md skills/ads-explain-to-beginner/SKILL.md
git add skills/
git commit -m "feat(skills): googleads-gaql cookbook + ads-explain-to-beginner UX rules"
```

---

### Task 7: Write `commands/ads-daily.md` and end-to-end smoke test

**Files:**
- Create: `~/dev/personal/ads-copilot/commands/ads-daily.md`

- [ ] **Step 1: Write `commands/ads-daily.md`**

Create `~/dev/personal/ads-copilot/commands/ads-daily.md`:

```markdown
---
description: Daily "anything on fire?" check on the bound Google Ads account. Read-only. Prints a 3–5 line TL;DR in chat. Writes a digest file only on anomaly.
argument-hint: (no arguments)
---

# /ads-daily

Run as the **ads-manager** agent. Load the **googleads-gaql** and
**ads-explain-to-beginner** skills.

## Steps

1. Bind to the workspace (read `workspace.json` + `context/*.md`).
2. Run these reads via `bin/ga query` (see googleads-gaql skill):
   - Last-24h spend + conversions per campaign
   - Disapproved ads
   - Flatlined campaigns over the last 7 days
3. Compute anomalies vs. same weekday last week (spend ±20%, conv ±50%,
   any new disapproval, any new flatline).
4. Print to chat:
   - Line 1: `TL;DR: <plain-English summary, no jargon>`
   - Lines 2–N (max 5 lines): `<campaign>: €X spent, Y conv`
   - Last line: action — none, or "Drafted X proposal — review at <path>"
5. **If and only if** an anomaly fired or a proposal was drafted, write
   `workspace/digests/$(date +%Y-%m-%d)-daily.md` containing:
   - The TL;DR
   - The numbers
   - One paragraph explaining the anomaly (what, vs what baseline, possible causes)
   Do NOT write a digest file on a clean day.
6. Stop. Account untouched.

## Out of scope for this command

- No mutations.
- No proposals beyond passively flagging "you might want to look at X" —
  search-term mining and budget review are `/ads-search-terms` and `/ads-budgets`
  respectively.
```

- [ ] **Step 2: Reinstall and run the live smoke test**

```bash
~/dev/personal/ads-copilot/bin/install
```

Expected: smoke test passes, accessible customers listed.

- [ ] **Step 3: Run `/ads-daily` end-to-end against yamazumi**

In a fresh terminal:

```bash
cd ~/dev/personal/yamazumi
claude
```

Inside Claude Code:

```
/ads-daily
```

Expected behavior:
- Within ~30s, a TL;DR + per-campaign one-liners + action note prints.
- If yesterday was uneventful: no file is written. Verify:
  ```bash
  ls ~/dev/personal/yamazumi/digests/ 2>/dev/null  # likely empty or absent
  ```
- If an anomaly fires: a `digests/YYYY-MM-DD-daily.md` is created.

If the agent calls `composio` or `curl` directly (instead of `bin/ga`), reject
the run, fix `agents/ads-manager.md` to be more forceful about "use bin/ga
only", and retry.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/personal/ads-copilot
git add commands/ads-daily.md
git commit -m "feat(cmd): /ads-daily — anomaly-gated digest, plain-English chat output"
```

---

### Task 8: Write `ads-change-execution` skill (proposal protocol)

**Files:**
- Create: `~/dev/personal/ads-copilot/skills/ads-change-execution/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `~/dev/personal/ads-copilot/skills/ads-change-execution/SKILL.md`:

```markdown
---
name: ads-change-execution
description: Proposal protocol. Loaded any time the agent considers a mutation. Defines the proposal-file format, the /ads-apply contract, the change-log line shape, and the five safety gates between intent and account.
---

# ads-change-execution

Mutations never go straight to the account. The agent drafts a proposal
file; the operator runs `/ads-apply <id>`; and only `/ads-apply` calls
`bin/ga proxy` against the account.

## The five gates

1. **Single mutating command.** Only `/ads-apply` mutates.
2. **Always-propose.** Every mutation = a `.md` file the operator can read.
3. **Account-ID pin.** `/ads-apply` refuses if the proposal's `account_id`
   does not match `workspace.json`'s `account.customer_id`.
4. **`validate_only` dry-run.** `/ads-apply` runs the change with
   `validateOnly:true` first; only proceeds on success.
5. **Append-only change-log.** Every applied operation = one JSON line in
   `workspace/change-log/$(date +%Y-%m-%d).jsonl`.

## Proposal file format

Path: `workspace/proposals/<YYYY-MM-DD>-<kind>-<seq>.md` where:
- `<kind>` ∈ `negatives`, `budget`, `creative-pause`, `creative-add`, …
- `<seq>` is `01`, `02`, … if multiple proposals on the same day

Structure:

````markdown
# <Title> — <YYYY-MM-DD>

## TL;DR

<2–4 lines, plain English. What you want to do, why, what could go wrong.>

## Per-item rationale

- **<thing>** — <why, with numbers>. Risk: <low/medium/high>, because <reason>.
- ...

## Expected impact

<1–2 lines. €X savings, Y% lift, etc. Be honest about uncertainty.>

## Executable

```json
{
  "proposal_id": "<YYYY-MM-DD>-<kind>-<seq>",
  "kind": "<kind>",
  "account_id": "<customer_id from workspace.json>",
  "via": "composio" | "proxy",
  "slug": "<COMPOSIO_SLUG>" | null,
  "endpoint": "<REST endpoint>" | null,
  "validate_first": true,
  "operations": [
    { ...op-specific fields... }
  ]
}
```
````

The fenced ```json block at the bottom is the **executable** part.
`/ads-apply` extracts it with `awk` / `jq` and runs it.

## /ads-apply contract

Pseudo-code for `/ads-apply <id>`:

```
1. Read workspace/proposals/<id>.md, extract last fenced ```json block.
2. Parse JSON. Verify .account_id == workspace.json .account.customer_id.
   On mismatch: print "REFUSED: proposal account_id mismatch" and stop.
3. Build a copy of .operations with validate_only:true (or per-slug equivalent).
   - If .via == "composio":
       bin/ga proxy POST /v18/customers/<id>/<resource>:mutate '<body with validateOnly:true>'
     (most googleads endpoints accept validateOnly).
   - If .via == "proxy" only and the endpoint supports validateOnly: same.
   - If neither supports validateOnly: skip dry-run, note in chat.
4. If dry-run errors: print error, leave proposal in place, stop.
5. Print chat diff: "About to apply <kind>: <summary of operations>. Proceed? (y/n)"
6. On 'y':
   - Run live (validate_only:false).
   - For each op, append to workspace/change-log/$(date +%Y-%m-%d).jsonl:
     {"ts":"<iso>","proposal_id":"<id>","op":"<kind>","request":<op>,"response":<resp>,"applied":true}
   - mv workspace/proposals/<id>.md workspace/proposals/applied/<id>.md
   - Print "Applied. N operations live. Logged to change-log/."
7. On 'n':
   - Leave proposal in place. Print "Skipped. Re-run /ads-apply <id> later."
```

## Change-log line shape

One JSON line per applied operation. Newline-terminated. Append-only.

```json
{
  "ts": "2026-04-30T14:22:01Z",
  "proposal_id": "2026-04-30-negatives-01",
  "op": "add_negative_keyword",
  "account_id": "8191097521",
  "request": { "campaign_id": "...", "text": "...", "match_type": "PHRASE" },
  "response": { "resourceName": "..." },
  "applied": true
}
```

## What "kinds" of proposals exist (v1)

| kind | drafted by | ops |
|---|---|---|
| `negatives` | `/ads-search-terms`, `/ads-weekly` | add negative keywords (campaign-level) |
| `budget` | `/ads-budgets`, `/ads-weekly`, `/ads-monthly` | update `campaign_budget.amount_micros` |
| `creative-pause` | `/ads-creative`, `/ads-monthly` | pause `ad_group_ad` |
| `creative-add` | `/ads-creative` | add headlines/descriptions to RSA |

Out of scope for v1: `campaign-create`, `ad-group-create`, anything structural.
```

- [ ] **Step 2: Verify and commit**

```bash
cd ~/dev/personal/ads-copilot
ls skills/ads-change-execution/SKILL.md
git add skills/ads-change-execution/
git commit -m "feat(skill): ads-change-execution proposal protocol + 5 safety gates"
```

---

### Task 9: Write `commands/ads-apply.md`

**Files:**
- Create: `~/dev/personal/ads-copilot/commands/ads-apply.md`

- [ ] **Step 1: Write the command**

Create `~/dev/personal/ads-copilot/commands/ads-apply.md`:

```markdown
---
description: Apply a previously drafted proposal. The ONLY command that mutates the Google Ads account. Refuses if account-ID doesn't match. Runs validate_only dry-run first, then asks y/n, then logs every op to change-log.
argument-hint: <proposal-id>  e.g. /ads-apply 2026-04-30-negatives-01
---

# /ads-apply

Run as the **ads-manager** agent. Load the **ads-change-execution** skill.

## Required argument

`$1` = proposal ID. The file is at
`workspace/proposals/$1.md`.

If `$1` is missing or empty: print
```
Usage: /ads-apply <proposal-id>

Available pending proposals:
  <list workspace/proposals/*.md basenames here>
```

## Steps

Follow the `/ads-apply` contract in the **ads-change-execution** skill
verbatim. Specifically:

1. Read `workspace/proposals/$1.md`. Extract the last fenced ```json block.
2. Account-ID pin: refuse on mismatch with `workspace.json`.
3. Run validate_only dry-run via `bin/ga proxy`. On error: print error, stop.
4. Print diff in chat (operation summary). Ask "Proceed? (y/n)".
5. On 'y':
   - Live run via `bin/ga proxy`.
   - For each op, append a JSON line to `workspace/change-log/$(date +%Y-%m-%d).jsonl`.
   - `mv` proposal to `workspace/proposals/applied/`.
   - Print "Applied. N operations live."
6. On 'n':
   - Leave proposal in place. Print "Skipped."

## Plain-English chat output rule

Every step that surfaces something to the operator follows
**ads-explain-to-beginner**: TL;DR first, jargon translated on first use,
units on numbers.
```

- [ ] **Step 2: Verify (no live test yet — covered by Task 10)**

```bash
cd ~/dev/personal/ads-copilot
ls commands/ads-apply.md
git add commands/ads-apply.md
git commit -m "feat(cmd): /ads-apply — single mutating command, gated by 5 safety checks"
```

---

### Task 10: Write `ads-search-term-mining` skill + `commands/ads-search-terms.md`, end-to-end mutation test

**Files:**
- Create: `~/dev/personal/ads-copilot/skills/ads-search-term-mining/SKILL.md`
- Create: `~/dev/personal/ads-copilot/commands/ads-search-terms.md`

- [ ] **Step 1: Write `skills/ads-search-term-mining/SKILL.md`**

Create:

```markdown
---
name: ads-search-term-mining
description: Heuristics for turning a 30-day search-terms report into a vetted negative-keyword proposal. Loaded by /ads-search-terms and /ads-weekly.
---

# ads-search-term-mining

Goal: identify search queries that triggered the ads, spent money, and
returned nothing — and propose them as negative keywords at the right match
type, scoped to the right campaign.

## Pull data

Run the "Last 30d search terms with low/no conversion" query from the
**googleads-gaql** skill.

## Classify each row

For each `search_term`:

1. **Off-ICP?** Read `context/icp.md` and `context/persona-overrides.md`.
   If the query is clearly someone outside the target persona (free-tier
   seekers when the product is paid, hobbyists when the product is for
   factories, …) → mark as **negative candidate**.
2. **Brand collision?** If the query contains a competitor's brand name and
   `context/product-positioning.md` says you don't bid on competitors →
   negative candidate.
3. **High spend, zero conv** alone is not enough — there's natural
   variance. Threshold: ≥ €X per query where X = max(€5, daily budget × 0.05),
   or ≥ 100 impressions and 0 conv over 30 days.
4. **Long tail?** If the same theme recurs (e.g. multiple "free X" queries),
   propose a single PHRASE or EXACT negative on the theme word, not 20
   tail variants.

## Pick match type

- **EXACT** — the query is a one-off exact match you want to block ONLY for that wording.
- **PHRASE** — a recurring theme word (e.g. "free", "tutorial") you want to block whenever it appears in any query.
- **BROAD** — almost never. Reserve for clearly off-topic root words.

When in doubt, prefer PHRASE > EXACT > BROAD.

## Scope

Negative keywords go on the **campaign** that triggered the query, not on
all campaigns, unless the same theme appears across multiple campaigns —
then propose a customer-level negative keyword list (out of v1 scope; for
v1, do per-campaign).

## Draft the proposal

Use `ads-change-execution` proposal format. `kind: "negatives"`, `via:
"proxy"`, `endpoint: "/v18/customers/<id>/campaignCriteria:mutate"`.

Each operation:

```json
{
  "create": {
    "campaign": "customers/<id>/campaigns/<campaign-id>",
    "negative": true,
    "keyword": { "text": "<term>", "matchType": "PHRASE" }
  }
}
```

## Cap

Never propose more than 25 negatives in one batch. If the mining returns
more, draft the top 25 by spend; mention the rest in the rationale.
```

- [ ] **Step 2: Write `commands/ads-search-terms.md`**

Create `~/dev/personal/ads-copilot/commands/ads-search-terms.md`:

```markdown
---
description: Mine the last 30 days of search terms and draft a negative-keywords proposal. Read-only against the account; writes ONE file in workspace/proposals/.
argument-hint: (no arguments)
---

# /ads-search-terms

Run as the **ads-manager** agent. Load **googleads-gaql**,
**ads-search-term-mining**, **ads-change-execution**, **ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull search-terms data per the gaql skill.
3. Apply mining heuristics per the search-term-mining skill.
4. If 0 candidates: print "No junk to mine. Account looks clean." and exit.
5. Otherwise: write `workspace/proposals/$(date +%Y-%m-%d)-negatives-NN.md`
   following the change-execution skill format.
6. Print chat:
   - TL;DR (plain English, e.g. "Drafted 14 negatives across 3 campaigns,
     est. €47/mo savings.")
   - Per-campaign one-liner with count
   - Action: "Review at workspace/proposals/<file>.md. Ship: /ads-apply <id>"
7. Stop. Account untouched.
```

- [ ] **Step 3: End-to-end mutation test**

```bash
cd ~/dev/personal/yamazumi
claude
```

```
/ads-search-terms
```

Expected:
- A proposal file appears in `workspace/proposals/`.
- The chat prints a TL;DR with a path and an `/ads-apply` instruction.
- Account is unchanged at this point.

Then test the apply flow with a low-stakes proposal (review the file first; if anything looks wrong, edit the JSON block before applying):

```
/ads-apply 2026-04-30-negatives-01
```

(use the actual proposal ID from the file you just got)

Expected:
- Account-ID pin passes (`8191097521` in proposal == workspace.json).
- `validate_only` dry-run passes (visible in chat).
- Chat asks "Proceed? (y/n)".
- On `y`: live mutation runs, change-log line appended, proposal moved to `proposals/applied/`.
- On `n`: nothing happens, proposal stays.

Verify the change-log:

```bash
cat ~/dev/personal/yamazumi/change-log/$(date +%Y-%m-%d).jsonl | jq .
```

Expected: one JSON object per applied operation, with `applied: true`.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/personal/ads-copilot
git add skills/ads-search-term-mining/ commands/ads-search-terms.md
git commit -m "feat: /ads-search-terms — first end-to-end mutation flow with /ads-apply"
```

---

### Task 11: Write `ads-account-audit` + `ads-budget-management` skills, `/ads-weekly`, `/ads-budgets`

**Files:**
- Create: `~/dev/personal/ads-copilot/skills/ads-account-audit/SKILL.md`
- Create: `~/dev/personal/ads-copilot/skills/ads-budget-management/SKILL.md`
- Create: `~/dev/personal/ads-copilot/commands/ads-weekly.md`
- Create: `~/dev/personal/ads-copilot/commands/ads-budgets.md`

- [ ] **Step 1: Write `ads-account-audit/SKILL.md`**

Create:

```markdown
---
name: ads-account-audit
description: Audit templates for daily, weekly, monthly, and bootstrap reviews. Section structure, query plan, and severity rubric.
---

# ads-account-audit

Audit sections, in priority order:

1. **Spend & pacing** — actual vs. expected at this point in the month, by campaign. Use budget pacing query from `googleads-gaql`.
2. **Conversion health** — total conv last period vs. prior, conversion-action statuses (any "removed but still referenced"?). Conv-action query from gaql skill.
3. **Search terms** — full mining via `ads-search-term-mining` skill.
4. **Creative** — RSA asset performance via gaql skill; flag LOW assets.
5. **Disapprovals** — any disapproved ads.
6. **Structure sanity** — campaign count, ad-group count, keyword count per campaign. Flag campaigns with > 50 keywords (Google's recommended max for Search) or < 3 ads (no A/B coverage).
7. **KPI alignment** — read `context/kpi-tree.md`, compare current 30-day metrics, surface KPI gaps.
8. **Recommendations** — bullet list, ranked by expected € impact, separated into "I'll handle" (proposable) and "you decide" (out of v1 scope, structural).

## Severity rubric

- **🔴 critical** — money is being wasted right now, or required tracking is broken (conv-action removed but still primary).
- **🟡 warning** — drift from policy, but not actively losing money.
- **🟢 healthy** — performing per `context/budget-policy.md` and `context/kpi-tree.md`.

Apply to each section.

## Output target

- `/ads-monthly` writes `workspace/audit/<YYYY-MM>-monthly.md` with all 8 sections.
- `/ads-weekly` covers sections 1, 3, 4, 5 only — quick weekly cycle.
- `/ads-bootstrap` writes `workspace/audit/<YYYY-MM-DD>-bootstrap.md` (full 8 sections) AND `workspace/refactors/<YYYY-MM-DD>-phased-plan.md` with the prioritized fix list as phases.
- `/ads-daily` does NOT call this skill; it has its own narrower checks.
```

- [ ] **Step 2: Write `ads-budget-management/SKILL.md`**

Create:

```markdown
---
name: ads-budget-management
description: Budget pacing math + thresholds for proposing budget shifts. Reads context/budget-policy.md to know what counts as "wildly off."
---

# ads-budget-management

## Pacing formula

For each campaign with `status = ENABLED`:

```
days_in_month  = days in current calendar month
days_elapsed   = today's day-of-month
expected_spend = (campaign_budget.amount_micros / 1_000_000) * days_elapsed
actual_spend   = SUM(metrics.cost_micros) DURING THIS_MONTH / 1_000_000
pacing_ratio   = actual_spend / expected_spend
```

`pacing_ratio == 1.0` is on-target. Read `context/budget-policy.md` for the
operator's tolerance band — assume ±20% if not specified.

## When to propose a budget shift

| Condition | Proposal |
|---|---|
| `pacing_ratio > 1.20` AND CPA < target_cpa from kpi-tree | Increase daily budget — performance is good and we're hitting limits |
| `pacing_ratio > 1.20` AND CPA > target_cpa | DON'T increase. Flag in TL;DR — we're spending too fast at bad efficiency |
| `pacing_ratio < 0.80` | Investigate first (impression share lost-rank? lost-budget? low search volume?) before proposing a decrease |
| Two campaigns: one starving (rank-lost > 30%) and one underperforming | Propose shifting budget from underperformer → starving |

## Proposal shape

`kind: "budget"`, `via: "proxy"`,
`endpoint: "/v18/customers/<id>/campaignBudgets:mutate"`.

Each op:
```json
{
  "update": {
    "resourceName": "customers/<id>/campaignBudgets/<budget-id>",
    "amountMicros": <new amount * 1_000_000>
  },
  "updateMask": "amountMicros"
}
```

## Cap

Never propose a single-step change > 50% of current budget. If the math
says +200%, propose +50% with a note "next week consider another step."
```

- [ ] **Step 3: Write `commands/ads-weekly.md`**

Create:

```markdown
---
description: Weekly review — audit sections 1/3/4/5 + budget pacing review + search-term mining. May draft up to two proposals (negatives, budget shifts).
argument-hint: (no arguments)
---

# /ads-weekly

Run as the **ads-manager** agent. Load **googleads-gaql**,
**ads-account-audit** (focus: spend, search terms, creative, disapprovals),
**ads-search-term-mining**, **ads-budget-management**, **ads-change-execution**,
**ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Run focused audit (sections 1, 3, 4, 5 only — see audit skill).
3. If search terms warrant: draft a `negatives` proposal per
   ads-search-term-mining + ads-change-execution.
4. If budget pacing warrants: draft a `budget` proposal per
   ads-budget-management + ads-change-execution.
5. Print chat:
   - TL;DR (max 4 lines)
   - Numbers (max 5 lines)
   - Action: 0–2 proposals listed with their `/ads-apply` commands.
6. Write `workspace/digests/$(date +%Y-%m-%d)-weekly.md` with the chat
   output + a per-section severity (🔴/🟡/🟢) line. Always write — weekly
   is a structured artifact, not anomaly-gated.
7. Stop.
```

- [ ] **Step 4: Write `commands/ads-budgets.md`**

Create:

```markdown
---
description: Ad-hoc budget pacing review. Drafts a budget proposal if pacing is wildly off; otherwise reports clean.
argument-hint: (no arguments)
---

# /ads-budgets

Run as **ads-manager**. Load **googleads-gaql**, **ads-budget-management**,
**ads-change-execution**, **ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull budget pacing data per gaql skill.
3. Apply ads-budget-management thresholds.
4. If 0 actions: print "Pacing clean. Spend is on track." and exit.
5. Else: draft a `budget` proposal in `workspace/proposals/`.
6. Print TL;DR + per-campaign one-liner + `/ads-apply` instruction.
7. Stop.
```

- [ ] **Step 5: End-to-end test**

```bash
cd ~/dev/personal/yamazumi
claude
```

```
/ads-weekly
```

Expected:
- 0–2 proposals appear in `workspace/proposals/`.
- A weekly digest appears in `workspace/digests/`.
- Chat prints TL;DR + numbers + action.

```
/ads-budgets
```

Expected:
- Either "Pacing clean" or a single `budget` proposal.

If a proposal is drafted, optionally test `/ads-apply <id>` on it. **Be
careful — budget mutations move real money. Inspect the JSON block before
applying.**

- [ ] **Step 6: Commit**

```bash
cd ~/dev/personal/ads-copilot
git add skills/ads-account-audit/ skills/ads-budget-management/ commands/ads-weekly.md commands/ads-budgets.md
git commit -m "feat: /ads-weekly + /ads-budgets with audit + budget skills"
```

---

### Task 12: Write `ads-creative-management` skill, `/ads-creative`, `/ads-monthly`

**Files:**
- Create: `~/dev/personal/ads-copilot/skills/ads-creative-management/SKILL.md`
- Create: `~/dev/personal/ads-copilot/commands/ads-creative.md`
- Create: `~/dev/personal/ads-copilot/commands/ads-monthly.md`

- [ ] **Step 1: Write `ads-creative-management/SKILL.md`**

Create:

```markdown
---
name: ads-creative-management
description: Read RSA asset performance, identify weak assets, draft replacements. Inputs: context/icp.md, context/product-positioning.md.
---

# ads-creative-management

## Read

Run the "Responsive search ad asset performance" query from
**googleads-gaql**. Filter to `performance_label IN ('LOW')`.

## Decide

For each ad with one or more LOW assets:

- If LOW headline count ≥ 2 → propose pause for those headlines AND draft
  replacement headlines.
- If LOW description count ≥ 1 → propose pause AND draft replacement
  descriptions.
- If the ad has < 8 active headlines after pausing the LOW ones → must
  draft replacements (Google requires at least 3, recommends ≥ 8).

## Draft replacements

Read `context/icp.md` and `context/product-positioning.md`. Headlines:

- 30 chars max each
- 8–15 candidates per RSA
- Cover: value prop, persona pain, social proof, CTA, feature highlight, differentiation
- No duplicate first words across the set (Google penalizes)
- Match the existing ad's tone and persona (don't introduce new positioning silently)

Descriptions: 90 chars max, 4 candidates per RSA, expanded value prop.

## Proposal kinds

- `kind: "creative-pause"` — pause specific assets. `via: "proxy"`,
  endpoint: `/v18/customers/<id>/adGroupAdAssets:mutate`.
- `kind: "creative-add"` — add new assets to an existing RSA. Same endpoint,
  `create` operations.

## Scope

Per-RSA, max one proposal per session. If multiple ads need work, draft
the highest-spend one first; note the others in the rationale.
```

- [ ] **Step 2: Write `commands/ads-creative.md`**

Create:

```markdown
---
description: Ad-hoc creative health check. Identifies LOW-performing RSA assets and drafts a paired pause + add proposal for the highest-spend ad.
argument-hint: (no arguments)
---

# /ads-creative

Run as **ads-manager**. Load **googleads-gaql**, **ads-creative-management**,
**ads-change-execution**, **ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull RSA asset performance per gaql skill.
3. Apply creative-management heuristics.
4. If 0 LOW assets: print "Creative health is fine." and exit.
5. Else: pick the highest-spend ad with LOW assets, draft TWO proposals
   (one `creative-pause`, one `creative-add`) with paired IDs (e.g.
   `2026-04-30-creative-01a-pause`, `2026-04-30-creative-01b-add`).
6. Print TL;DR + ad name + counts + `/ads-apply` instructions for both.
7. Stop.
```

- [ ] **Step 3: Write `commands/ads-monthly.md`**

Create:

```markdown
---
description: Full monthly review — all 8 audit sections, with creative + budget deep-dive. Writes a structured monthly audit file. May draft up to 3 proposals.
argument-hint: (no arguments)
---

# /ads-monthly

Run as **ads-manager**. Load **googleads-gaql**, **ads-account-audit**
(full 8-section), **ads-search-term-mining**, **ads-budget-management**,
**ads-creative-management**, **ads-change-execution**,
**ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Run full 8-section audit per audit skill.
3. Per section, decide if a proposal is warranted (using the relevant
   skill's thresholds). Draft at most ONE proposal per section/kind.
4. Write `workspace/audit/$(date +%Y-%m)-monthly.md` with all 8 sections,
   severity emoji per section, and a "Recommendations" tail listing the
   drafted proposals + the items left for the operator.
5. Print chat:
   - TL;DR (≤ 5 lines, plain English summary of the month)
   - One section, one line: `<section> — <severity emoji> <one-liner>`
   - Action: list the proposals drafted with their `/ads-apply` commands.
6. Stop. Account untouched (until operator runs `/ads-apply`).
```

- [ ] **Step 4: End-to-end test**

```
/ads-creative
/ads-monthly
```

Expected: respective files appear (proposals, audit), chat prints TL;DR + action.

- [ ] **Step 5: Commit**

```bash
cd ~/dev/personal/ads-copilot
git add skills/ads-creative-management/ commands/ads-creative.md commands/ads-monthly.md
git commit -m "feat: /ads-creative + /ads-monthly with creative + monthly-audit skills"
```

---

### Task 13: Write `/ads-bootstrap` and `/ads-explain`, full repo smoke test, README polish

**Files:**
- Create: `~/dev/personal/ads-copilot/commands/ads-bootstrap.md`
- Create: `~/dev/personal/ads-copilot/commands/ads-explain.md`

- [ ] **Step 1: Write `commands/ads-bootstrap.md`**

Create:

```markdown
---
description: One-time deep audit + phased refactor plan for a freshly-bound workspace. Read-only. Writes audit + refactors files. Run once per workspace.
argument-hint: (no arguments)
---

# /ads-bootstrap

Run as **ads-manager**. Load every skill the audit needs (gaql, account-audit
full, search-term-mining, budget-management, creative-management,
explain-to-beginner). Do NOT load change-execution — bootstrap doesn't draft
proposals; it produces a plan for the operator to consider.

## Steps

1. Bind to workspace.
2. Run the full 8-section audit per ads-account-audit.
3. Write `workspace/audit/$(date +%Y-%m-%d)-bootstrap.md` with all 8 sections.
4. Write `workspace/refactors/$(date +%Y-%m-%d)-phased-plan.md` containing:
   - Phase 0 (now): things the operator should do manually outside this plugin
     (e.g. fix conversion tracking, link GA4, set up enhanced conversions)
   - Phase 1 (next 1–2 weeks): things `/ads-weekly` and `/ads-monthly` will
     handle once they start running (mining, budget-tuning, creative refresh)
   - Phase 2 (next 1–3 months): structural recommendations the operator
     should review (campaign restructure, new themes) — NOT v1 scope
5. Print TL;DR + section severity emojis + path to both files.
6. Stop.
```

- [ ] **Step 2: Write `commands/ads-explain.md`**

Create:

```markdown
---
description: Plain-English explainer for a Google Ads term, metric, or concept. Read-only, no account access. Just translates jargon.
argument-hint: <term-or-concept>  e.g. /ads-explain impression share
---

# /ads-explain

Run as **ads-manager**. Load **ads-explain-to-beginner**.

## Steps

1. Read `$ARGUMENTS` (the term or concept the operator typed).
2. If empty: print "Usage: /ads-explain <term>" + the table of terms from
   the explain-to-beginner skill.
3. Otherwise:
   - Look up the term in the skill's table. If present: print the 1-line
     translation + a 2–4-line "in context" expansion (when it matters,
     how it's used, what to watch for).
   - If not in the table: write a fresh 1-line translation + 2–4-line
     expansion based on Google Ads documentation. Do not fabricate.
4. Stop. No account access. No mutations.
```

- [ ] **Step 3: Final repo smoke test**

```bash
~/dev/personal/ads-copilot/bin/install
```

Expected: all bin/ga tests pass, live Composio call succeeds.

```bash
cd ~/dev/personal/yamazumi
claude
```

Run each command at least once and verify behavior:

```
/ads-explain impression share
/ads-daily
/ads-weekly
/ads-bootstrap
```

Verify:
- `/ads-explain` works with no account access.
- `/ads-daily` either prints a clean TL;DR (no file) or writes a digest on anomaly.
- `/ads-weekly` writes a digest + 0–2 proposals.
- `/ads-bootstrap` writes audit + refactors files; does NOT write proposals.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/personal/ads-copilot
git add commands/ads-bootstrap.md commands/ads-explain.md
git commit -m "feat: /ads-bootstrap + /ads-explain (last commands), full slash-command surface"
```

- [ ] **Step 5: Tag v0.1.0**

```bash
cd ~/dev/personal/ads-copilot
git tag -a v0.1.0 -m "ads-copilot v0.1.0 — initial single-operator MVP"
```

---

## Self-review

**Spec coverage check (cross-referenced against `2026-04-30-ads-copilot-design.md`):**

| Spec section | Covered by |
|---|---|
| Two-repo shape (`ads-copilot/` + `yamazumi/`) | Tasks 1, 2 |
| Plugin layout (manifest, agents, commands, skills, bin) | Tasks 1, 3–13 |
| Workspace layout (5 dirs, lazy creation) | Task 2 (init), the rest naturally |
| `bin/ga` boundary contract | Task 3 (with tests) |
| `bin/install` smoke test | Task 4 |
| `ads-manager` agent persona | Task 5 |
| Plain-English UX rule | Task 6 (skill) + every command |
| Anomaly trigger for digest writes | Task 5 (agent) + Task 7 (`/ads-daily`) |
| Read flow | Task 7 (`/ads-daily`) |
| Mutation flow (always-propose) | Task 10 (first end-to-end) |
| Apply flow (5 safety gates) | Tasks 8, 9 (skill + command) |
| Account-ID pin | Task 8 (skill), Task 9 (command), Task 10 (test) |
| `validate_only` dry-run | Task 8 (skill), Task 9 (command) |
| Append-only change-log | Task 8 (skill defines shape), Task 10 (test verifies) |
| Migration from `yamazumi-ads/` | Task 2 (copy, archive deferred) |
| All 9 commands | Tasks 7 (daily), 9 (apply), 10 (search-terms), 11 (weekly + budgets), 12 (creative + monthly), 13 (bootstrap + explain) |
| All 7 skills | Tasks 6 (gaql, explain), 8 (change-execution), 10 (search-term-mining), 11 (account-audit, budget-management), 12 (creative-management) |
| Implementation order from spec | Tasks 1–13 follow the spec's 8-phase order |

No gaps.

**Placeholder scan:** every code step has the actual content. No "TBD," no "see above," no "similar to Task X."

**Type/name consistency:**
- Proposal `kind`s — `negatives`, `budget`, `creative-pause`, `creative-add` — used consistently across the change-execution skill (Task 8), search-term-mining (Task 10), budget-management (Task 11), creative-management (Task 12).
- File-path conventions: `workspace/proposals/<YYYY-MM-DD>-<kind>-<seq>.md`, `workspace/change-log/<date>.jsonl`, `workspace/audit/<YYYY-MM-DD>-bootstrap.md` and `<YYYY-MM>-monthly.md` — all consistent.
- `bin/ga query` and `bin/ga proxy` — same signatures used by `bin/install`, every skill, every command.

Plan is ready.

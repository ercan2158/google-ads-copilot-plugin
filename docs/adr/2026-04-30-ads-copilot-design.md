# ads-copilot — Claude Code plugin for AI-driven Google Ads operations

**Status:** Built. v0.2.0 (in progress) on 2026-05-03 after the
google-ads-python pivot (see second addendum below). v0.1.0 tagged
2026-04-30. First architecture pivot 2026-05-01 — Composio dropped,
direct Google Ads REST API. Second pivot 2026-05-03 — bash REST
helper retired in favor of the official google-ads Python client.
**Date:** 2026-04-30 (design), 2026-05-01 (post-Composio addendum),
2026-05-03 (post-Python-migration addendum).
**Supersedes:** parts of `cadenza` (parked, not deleted).

## Addendum 2: 2026-05-03 — bash REST helper → google-ads Python client

The 2026-05-01 pivot left `bin/ga` as a 235-line bash script that hand-
rolled OAuth refresh, retry/backoff on 429+5xx, GAQL pagination via
`nextPageToken`, and structured-error parsing — all things the
official `google-ads` Python client does for free, with Google's own
QA behind it. As the surface area grew (conversion-health,
smart-bidding, pmax, brand-defense audits all added new GAQL queries
and mutation kinds), the bash was nearing its complexity ceiling: the
test harness had to mock curl via PATH override with scripted response
files; pagination's safety cap was hand-tuned; the v23 → v24 path was
"rewrite every endpoint string in every skill."

**Decision:** retire the bash REST layer. `bin/ga` becomes a thin bash
wrapper (~22 lines) that exec's `bin/ga.py` inside a vendored Python
venv. The Python script uses `GoogleAdsClient.load_from_dict()` for
queries and `google.oauth2.credentials` for the proxy mode. The
boundary contract holds — skills, commands, and `bin/apply` still call
`bin/ga query` and `bin/ga proxy` with identical CLI surface and
identical JSON output shape — so nothing above the boundary changed.

**Tradeoff accepted:** ~50MB venv install (`google-ads` + `grpcio` +
`protobuf` + `PyYAML`) on first `bin/setup` run. One-time. Reused
across project workspaces. Pinned via `requirements.txt` so a
breaking library release doesn't break `bin/setup`.

**What we got back:** automatic OAuth refresh + token cache, native
gRPC retry/backoff (no manual budget loop), `search_stream` instead
of pagination cursor management, type-safe enums (`client.enums.*`),
typed proto messages for mutations, structured `GoogleAdsException`
with field paths and request_id, and a one-line API-version bump
(`GOOGLEADS_API_VERSION=v24`). The credentials file format moved from
the custom `KEY=value` shape to the library's native
`google-ads.yaml`; `bin/setup` migrates the legacy file in-place on
first upgrade.

**Mutation safety unchanged.** The five gates of `bin/apply` are still
enforced by deterministic shell — the LLM is not in the safety path.
`bin/apply` calls `bin/ga proxy` for the dry-run + live mutation; the
fact that `bin/ga` is now Python-backed is transparent to it.

**Test coverage rebuilt at the right level.** The bash mock-curl
harness is gone; `bin/test-ga.py` (35 assertions) stubs the
`google-ads` library at `sys.modules` level so it runs in CI without
the full library install — only PyYAML is needed. The `bin/apply`
suite (27 assertions) is unchanged because `bin/apply` is still bash
and its mock target (`bin/ga`) presents the same CLI surface.

The decisions table below predates both pivots; treat the
"Architecture" row as historical and read the body of this addendum +
the README for current state.



## Addendum: architecture pivot 2026-05-01 — drop Composio, hit Google Ads directly

The original design used Composio CLI as an authentication and HTTP-passthrough
layer between the plugin and Google Ads. Live wiring exposed a hard
dependency: Composio's default googleads OAuth client lives in *their* Cloud
project, while the operator's developer token is registered in the
operator's *own* Cloud project. Google Ads requires both to share a Cloud
project. The fix would have been to register a custom OAuth client in
Composio's googleads connection — but at that point Composio was just
acting as a fancy curl with token storage, providing little value over
calling the Google Ads API directly.

**Decision:** drop Composio entirely. `bin/ga` now hits
`googleads.googleapis.com` directly, refreshing an OAuth access token from
the stored refresh_token on every invocation. The plugin's boundary
contract held: `bin/ga` was the only caller of Composio, so skills,
commands, and the agent persona were unchanged in logic — only references
to "Composio" in their prose were scrubbed.

**Tradeoff accepted:** if ads-copilot ever grows to manage Slack + Stripe +
GA4 + Search Console etc., we lose Composio's cross-toolkit auth
normalization and would need to re-introduce a similar layer per toolkit.
For Google-Ads-only, single-operator: this is the simpler answer.

**Auth flow now:** OAuth 2.0 Desktop client in Google Cloud Console (same
project as the developer token) → `bin/oauth-bootstrap` runs the consent
flow via a localhost redirect → refresh_token saved to
`~/.config/secrets/google-ads/credentials`. From there `bin/ga` exchanges
refresh_token → access_token on each call, attaches the Authorization,
developer-token, and login-customer-id headers.

The decisions table below reflects the **current** state of the build, not
the original architecture row.

## Goal

A single-operator Claude Code plugin that runs Google Ads operations on
behalf of a SaaS founder with **no Google Ads background**. The AI is the
expert; the operator types `/ads-daily`, `/ads-weekly`, etc. and reads short
plain-English summaries. The AI never mutates the account silently — every
change goes through a written proposal that the operator must `/ads-apply`.

## Non-goals (v1)

- Scheduled/autonomous runs. Interactive only.
- Structural mutations (creating campaigns, ad groups, keyword themes).
- Experiments (drafts/experiments framework).
- GA4 read integration (deferred — wired to add as a separate skill later).
- Automated undo. Change-log makes manual reversal possible; tooling is v2.
- Multi-user / SaaS distribution. Single operator, local install.

## Decisions (brainstorm output)

| Decision | Choice | Rationale |
|---|---|---|
| Replace, park, or extend Cadenza | Park Cadenza, build new | Cadenza (Kotlin + Spring + MCP server) too heavy for a single non-technical operator. |
| Scope of operations | R + N + B + C | Reporting, Negative keywords, Budgets/bids, Creative. Skip Structure & Experiments. |
| Trigger model | Interactive only | Slash commands you type. No cron, no scheduler. |
| Mutation safety | Always propose, never apply silently | Beginner-mode trust-building. `/ads-apply` is the only command that touches the account. |
| Architecture | Pure plugin, bash + direct Google Ads REST API + OAuth refresh-token flow | Zero build, zero server, zero vendor middleware. Promotable to a TS helper or MCP server later. *(Originally bash + Composio CLI; pivoted 2026-05-01 — see addendum.)* |
| Repo shape | Two repos | Plugin (`ads-copilot/`) reusable across apps; each app gets its own workspace repo. |

## Architecture

Two repos, plugin auto-discovers the workspace via cwd walk-up.

```
~/dev/personal/
├── ads-copilot/                ← THE PLUGIN. Install once.
└── yamazumi/                   ← APP #1 WORKSPACE. Per-account data.
    └── (later) other-app/      ← APP #2, same shape.
```

Runtime: `cd ~/dev/personal/yamazumi && claude`. Plugin walks up from cwd
looking for `workspace.json`; binds to that account for the session.

Boundary contract: skills and commands never touch `curl` directly. They
go through `bin/ga`. If the Google Ads API version bumps or auth flow
changes, one file changes.

## Plugin layout — `ads-copilot/`

```
ads-copilot/
├── .claude-plugin/plugin.json
├── agents/
│   └── ads-manager.md          ← single agent persona for all /ads-* commands
├── commands/
│   ├── ads-bootstrap.md        one-time full audit + refactor plan
│   ├── ads-daily.md            "anything on fire?"
│   ├── ads-weekly.md           search-term mining + budget pacing review
│   ├── ads-monthly.md          deep review + creative health
│   ├── ads-search-terms.md     ad-hoc
│   ├── ads-budgets.md          ad-hoc
│   ├── ads-creative.md         ad-hoc
│   ├── ads-explain.md          jargon translator, read-only
│   └── ads-apply.md            ONLY mutating command. Reads a proposal file.
├── skills/
│   ├── googleads-gaql/SKILL.md          GAQL cookbook + how to call bin/ga query
│   ├── ads-account-audit/SKILL.md       audit templates (daily/weekly/monthly)
│   ├── ads-search-term-mining/SKILL.md
│   ├── ads-budget-management/SKILL.md
│   ├── ads-creative-management/SKILL.md
│   ├── ads-change-execution/SKILL.md    proposal protocol (always-propose-then-apply)
│   └── ads-explain-to-beginner/SKILL.md jargon-translation rules
├── bin/
│   ├── ga                      direct Google Ads REST wrapper (OAuth refresh + headers)
│   ├── oauth-bootstrap         one-time refresh-token capture via loopback redirect
│   ├── test-ga.sh              bash test suite for ga (mocks curl + secrets)
│   └── install                 registers plugin, smoke-tests bin/ga
└── docs/README.md
```

## Workspace layout — `<app>/`

Five directories. Anything else gets added later when there's something to put in it.

```
<app>/
├── workspace.json              account_id, manager_customer_id, currency, timezone
├── context/                    HUMAN-AUTHORED. AI reads, never silently rewrites.
│   ├── icp.md
│   ├── budget-policy.md
│   ├── kpi-tree.md
│   ├── persona-overrides.md
│   └── product-positioning.md
├── digests/                    written ONLY when there's an anomaly or proposal
├── proposals/                  pending mutations awaiting /ads-apply
│   └── applied/                proposals that have been shipped
├── change-log/                 append-only JSONL audit trail of applied ops
└── account/snapshots/          periodic full-account snapshots (json)
```

Created on demand by specific commands (not in the default tree):
- `audit/` — written by `/ads-bootstrap` and `/ads-monthly`
- `refactors/` — written by `/ads-bootstrap` (initial phased plan)

These directories appear when first used, not on init.

### Anomaly trigger (for `digests/` writes)

A `/ads-*` read run writes a digest file ONLY if at least one of:
- spend ±20% vs same weekday last week
- conversions ±50% vs same weekday last week
- any newly-disapproved ad
- any campaign that flatlined to zero impressions
- any proposal was drafted in this run

Otherwise it prints to chat and exits without a file.

## Components

### Agent — `agents/ads-manager.md`

One agent persona, loaded by every `/ads-*` command. Its system prompt:
- "You are a senior Google Ads operator. The user has no Google Ads background."
- "Read `workspace.json` to bind to the account. Read `workspace/context/*.md`
  to understand the business."
- "Never mutate the account directly. Write a proposal to
  `workspace/proposals/` and stop."
- "Apply the jargon-translation rule from `ads-explain-to-beginner`."

### Skills — keep terse

Each `SKILL.md` is ~30–60 lines. Skills are loaded by the agent based on
the slash command. They contain GAQL queries, heuristics, and protocol
rules — not prose.

### Commands

Read-only or proposal-writing **except** `/ads-apply`.

| Command | Mutates? | Output |
|---|---|---|
| `ads-bootstrap` | No | Audit + refactor plan in `workspace/audit/` (created on demand) |
| `ads-daily` | No | Chat-only TL;DR (3–5 lines). Digest file only on anomaly. |
| `ads-weekly` | Proposes | Chat TL;DR + proposal in `workspace/proposals/` if there's something to mine |
| `ads-monthly` | Proposes | Same shape, deeper |
| `ads-search-terms` / `ads-budgets` / `ads-creative` | Proposes | Ad-hoc escape hatches |
| `ads-explain` | No | Plain-English explainer in chat |
| `ads-apply <id>` | **Yes** | The one mutating command |

### `bin/ga` — single shell helper, ~140 lines

```
ga query "SELECT ... FROM campaign WHERE ..."
   POSTs:  https://googleads.googleapis.com/v23/customers/<id>/googleAds:search
   body:   {"query": "<GAQL>"}

ga proxy <METHOD> <PATH> [json-body]
   sends:  <METHOD> https://googleads.googleapis.com<PATH>
   PATH:   path-only string starting with /, e.g. /v23/customers:listAccessibleCustomers

Both attach three headers:
  Authorization:    Bearer <access_token>     ← refreshed on every call
  developer-token:  <token>                   ← from ~/.config/secrets/google-ads
  login-customer-id: <manager_customer_id>    ← from workspace.json (when set)
```

Token refresh uses the OAuth 2.0 `refresh_token` grant against
`https://oauth2.googleapis.com/token`. No caching — fresh refresh per
invocation. ~150–300 ms overhead per call, fine for our usage.

Secrets resolved via `~/.config/secrets/get-secret.sh` (established
convention in this user's environment). Required keys in
`~/.config/secrets/google-ads/credentials`:
`DEVELOPER_TOKEN`, `CLIENT_ID`, `CLIENT_SECRET`, `REFRESH_TOKEN`. The first
three you set manually after creating an OAuth Desktop client; the
refresh_token is captured by `bin/oauth-bootstrap`.

## Data flows

### Read flow — `/ads-daily`

1. Read `workspace.json` → bind account.
2. Read `workspace/context/*.md` → know the business.
3. Load skills: `googleads-gaql`, `ads-account-audit`, `ads-explain-to-beginner`.
4. Run reads via `bin/ga query`: 24h spend, 24h conv, disapprovals, flatlines.
5. Compare to `context/budget-policy.md`.
6. Emit chat output (3–5 lines TL;DR + per-campaign one-liners + action note).
7. Anomaly? Write `workspace/digests/<date>-daily.md`. No anomaly? Exit.

### Mutation flow — `/ads-weekly` (drafts a negatives proposal)

1. Steps 1–3 from above, plus `ads-search-term-mining` + `ads-change-execution`.
2. Pull 30d search terms via `bin/ga query`.
3. Apply mining heuristics (high impressions, zero conv, off-ICP, classify match type).
4. Write `workspace/proposals/<date>-negatives-<seq>.md` — single file with:
   - TL;DR (plain English)
   - Per-term rationale (what, why, risk)
   - Executable JSON in a fenced code block at the bottom
5. Print in chat: "Drafted N negatives. Review at `<path>`. Ship: `/ads-apply <id>`."
6. Stop. Account untouched.

### Apply flow — `/ads-apply <proposal-id>`

1. Read `workspace/proposals/<id>.md`, extract the JSON code block.
2. **Account-ID pin:** verify `proposal.account_id == workspace.json.account.customer_id`.
   Refuse on mismatch.
3. Run Google Ads' `validateOnly:true` first if the endpoint supports it.
4. Show chat diff: "About to add 14 negatives across 3 campaigns. Validation passed. Proceed? (y/n)"
5. On `y`:
   - Execute via `bin/ga`.
   - Append per-op JSON line to `workspace/change-log/<date>.jsonl`:
     `{"ts":"...","op":"...","proposal_id":"...","request":{...},"response":{...},"applied":true}`
   - Move proposal to `workspace/proposals/applied/`.
   - Confirm in chat.
6. On `n`: leave proposal in place, exit.

## Mutation safety model

Five gates between intent and account change:

1. **Single mutating command.** Only `/ads-apply` touches the account.
2. **Always-propose.** Every mutation is a file you can read, edit, or delete.
3. **Account-ID pin.** Cross-app proposal-against-wrong-account is a hard refusal.
4. **`validate_only` dry-run.** Catches malformed ops before money moves.
5. **Append-only change-log.** Every applied op is a JSON line. Manual reversal possible.

## UX rule (one rule, baked into the agent)

The first time any Google Ads term ("CTR", "impression share", "quality score",
"match type", "responsive search ad", …) appears in a session, the agent
appends a one-line parenthetical translation. After that, no translation.
The agent tracks per-session what it has already explained.

## Migration from existing `yamazumi-ads/` (historical)

Day-1 migration was a copy, not a move. The original `yamazumi-ads/` repo
stayed in place during the build; archive whenever ready.

Copied verbatim into `~/dev/personal/yamazumi/`:
- `workspace.json` (with `composio` block subsequently removed during the
  2026-05-01 architecture pivot)
- `workspace/context/{icp,budget-policy,kpi-tree,persona-overrides,product-positioning}.md`

Not copied:
- Agent-authored directories (`audit/`, `decisions/`, `digests/`, etc.) —
  recreated lazily on first write.
- The original `change-log/` (entries referenced the parked Cadenza, no longer applicable).

## Testing

Two layers:

1. **`bin/test-ga.sh`** — bash assertion suite for `bin/ga`. Mocks `curl`
   and the secrets helper via `PATH` override; verifies the URL, method,
   body, and all three required headers (Authorization, developer-token,
   login-customer-id) for both `query` and `proxy` subcommands. ~10
   assertions, no real network calls. Runs as part of `bin/install`.

2. **`bin/install` live smoke test** — `bin/ga proxy GET /v23/customers:listAccessibleCustomers`
   against the real Google Ads API. If that works, every other read works.
   For mutations, the `validateOnly:true` dry-run inside `/ads-apply` is
   the test.

No CI, no test framework; this is one-operator software.

## Open questions

None. All resolved in brainstorming.

## Implementation order (rough)

1. Scaffold `ads-copilot/` — `.claude-plugin/plugin.json`, `bin/ga`, `bin/install`.
2. Scaffold workspace repo `yamazumi/` — copy context files from `yamazumi-ads/`.
3. Implement `googleads-gaql` skill + `ads-explain-to-beginner` skill + the agent.
4. Implement `/ads-daily` (read-only, smallest end-to-end loop).
5. Implement `ads-change-execution` skill + `/ads-apply`.
6. Implement `/ads-search-terms` (first mutation flow).
7. Layer in `/ads-weekly`, `/ads-monthly`, then `/ads-budgets`, `/ads-creative`.
8. Last: `/ads-bootstrap` (full audit), `/ads-explain` (jargon translator).

Detailed implementation plan in a separate doc.

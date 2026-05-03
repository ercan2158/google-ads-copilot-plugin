# google-ads-copilot

[![CI](https://github.com/ercan2158/google-ads-copilot-plugin/actions/workflows/ci.yml/badge.svg)](https://github.com/ercan2158/google-ads-copilot-plugin/actions/workflows/ci.yml)

**A Claude Code plugin that turns Claude into your Google Ads operator —
with mechanically-enforced safety gates so it can never silently change
your account.**

You type plain-English slash commands. The agent reads your account,
drafts changes as proposal files you review, and only mutates the
account when you explicitly approve a proposal — at which point a
deterministic shell script (`bin/apply`) enforces the gates: account-ID
pin, schema validation, `validate_only` dry-run against Google's API,
and an append-only change-log. The LLM is **not** in the safety path.

This is the differentiator: most "AI for Google Ads" tools auto-apply
changes the moment you connect them. This one drafts every change as a
markdown file, runs Google's own dry-run, and only then asks you to
confirm.

## Who this is for (and isn't)

**For:** technical founders, indie hackers, and CTOs running their own
Google Ads on Search-heavy accounts (€500–5k/mo), who already use Claude
Code and want their weekly review cycle automated without giving up
control.

**Not for (yet):** non-technical operators who don't want to wrangle
OAuth, developer tokens, and `jq` on the command line. The setup
friction below is real; you need to be comfortable in a terminal.

## What you'll need

- **Google Ads developer token** — request at the
  [Google Ads API Center](https://ads.google.com/aw/apicenter). **Approval
  can take days.** Start this first.
- **Google Cloud project** with the Google Ads API enabled, in the same
  Cloud project as the developer token.
- **OAuth 2.0 Desktop client** in that Cloud project. Add yourself as a
  **test user** under the OAuth consent screen.
- **CLI tools:** `jq`, `python3` ≥ 3.9, `curl`, `claude` (Claude Code).
  `bin/setup` creates a vendored virtualenv at
  `~/.local/share/google-ads-copilot/.venv/` and installs the official
  [google-ads](https://pypi.org/project/google-ads/) Python client +
  PyYAML inside it (~50MB, one-time).

> ⚠️ **Token-expiry caveat — read this first.** If your OAuth consent
> screen is in **Testing** mode (the default for unverified clients with
> restricted scopes like `adwords`), refresh tokens expire **every 7
> days**. When that happens, re-run `bin/oauth-bootstrap`. To remove
> this constraint long-term, submit the OAuth client for Google's
> verification (separate multi-week process). Until you do, expect to
> re-auth weekly.

## Quickstart

```bash
# 1. Install the plugin
claude plugin marketplace add https://github.com/ercan2158/google-ads-copilot-plugin
claude plugin install google-ads-copilot@google-ads-copilot

# 2. Per-machine setup (once)
#    Clone the repo first if you want to run setup directly:
git clone https://github.com/ercan2158/google-ads-copilot-plugin
cd google-ads-copilot-plugin
bin/setup
#    → checks prereqs, walks through OAuth, runs a live smoke test

# 3. Per-project bootstrap (once per SaaS app)
cd ~/dev/personal/<your-saas-app>
claude
> /google-ads-copilot:bootstrap
#    → first run scaffolds workspace.json + context/ stubs interactively,
#      then runs a deep audit
```

After that, daily/weekly/monthly use just works — no more config.

## Workspace structure

The plugin keeps **all per-account state in your project repo**, not in the
plugin. After `/google-ads-copilot:bootstrap`, your SaaS project has:

```
your-saas-app/
├── workspace.json          # account binding (customer_id, currency, tz)
├── context/                # human-curated docs the agent reads every run
│   ├── icp.md              # ideal customer profile
│   ├── product-positioning.md
│   ├── budget-policy.md
│   ├── kpi-tree.md
│   └── persona-overrides.md
└── workspace/
    ├── proposals/          # drafted mutations (review before applying)
    │   └── applied/        # proposals that have been /google-ads-copilot:apply'd
    ├── change-log/         # append-only JSONL of every applied mutation
    ├── digests/            # daily TL;DR files (only on anomaly)
    ├── audit/              # weekly/monthly/bootstrap audit reports
    └── refactors/          # bootstrap-time phased refactor plans
```

Secrets live separately at
`~/.config/google-ads-copilot/google-ads.yaml` (chmod 600) — the native
config format of the google-ads Python client, never in any project
repo, never in the plugin. Override the location with
`GOOGLE_ADS_COPILOT_CREDENTIALS_FILE`, or set individual fields via env
vars (`GOOGLE_ADS_DEVELOPER_TOKEN`, `GOOGLE_ADS_CLIENT_ID`, etc.) for
CI-style use. If you previously had the legacy `credentials` (KEY=value)
file, `bin/setup` migrates it to yaml automatically on first run.

## Commands

| Command | What it does |
|---|---|
| `/google-ads-copilot:bootstrap` | First-run scaffold + deep audit (per project) |
| `/google-ads-copilot:daily` | Anything-on-fire check; only writes a digest on anomaly |
| `/google-ads-copilot:weekly` | Spend, search-terms, creative, disapprovals; may draft 0–2 proposals |
| `/google-ads-copilot:monthly` | Full 10-section audit (incl. conversion-tracking + Smart Bidding diagnostics + brand defense + URL liveness); may draft up to 3 proposals |
| `/google-ads-copilot:budgets` | Ad-hoc budget pacing review |
| `/google-ads-copilot:creative` | Ad-hoc RSA asset health check |
| `/google-ads-copilot:search-terms` | Mine 30 days of search terms for negative-keyword candidates |
| `/google-ads-copilot:explain <term>` | Plain-English explainer for any Google Ads concept |
| `/google-ads-copilot:recommendations` | Pull Google's pending recommendations, score against your context, draft proposals for the ones worth applying |
| `/google-ads-copilot:changes [days]` | Show the audit trail — what's been applied recently (default 7 days) |
| `/google-ads-copilot:undo <proposal-id>` | Generate the inverse of an applied proposal as a new proposal (rollback) |
| `/google-ads-copilot:apply <proposal-id>` | **The only mutating command.** Applies a drafted proposal |

### Architecture: skills loaded per command

Every command runs as the **`manager`** agent and declares which skills the agent loads. Skills compose: `gaql` and `explain-to-beginner` are foundation skills (one for reading the account, one for output style); `change-execution` is loaded only when a command might draft a mutation; `account-audit` orchestrates the multi-section reviews; `conversion-health` and `smart-bidding` are foundational diagnostics that gate the meaning of every other metric.

| Command | Skills loaded |
|---|---|
| `/google-ads-copilot:bootstrap` | `gaql`, `account-audit` (full 10-section), `conversion-health`, `smart-bidding`, `pmax` (if PMax campaigns exist), `search-term-mining`, `budget-management`, `creative-management`, `explain-to-beginner` |
| `/google-ads-copilot:daily` | `gaql`, `explain-to-beginner` |
| `/google-ads-copilot:weekly` | `gaql`, `account-audit` (sections 1/2-light/3-light/4/5/6), `conversion-health` (light), `smart-bidding` (light), `search-term-mining`, `budget-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:monthly` | `gaql`, `account-audit` (full 10-section), `conversion-health`, `smart-bidding`, `pmax` (if PMax campaigns exist), `search-term-mining`, `budget-management`, `creative-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:budgets` | `gaql`, `budget-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:creative` | `gaql`, `creative-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:search-terms` | `gaql`, `search-term-mining`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:explain` | `explain-to-beginner` |
| `/google-ads-copilot:recommendations` | `gaql`, `change-execution`, `creative-management`, `search-term-mining`, `budget-management`, `smart-bidding`, `conversion-health`, `pmax` (if PMax campaigns exist), `explain-to-beginner` |
| `/google-ads-copilot:changes` | `explain-to-beginner` |
| `/google-ads-copilot:undo` | `change-execution` (incl. `references/apply-contract.md` for inverse-op rules) |
| `/google-ads-copilot:apply` | `change-execution` (incl. `references/apply-contract.md`) |

## Safety model

Five gates between any read-only command and a live mutation. Each one
is enforced by a shell script (`bin/apply` calling `bin/validate-proposal`
calling `bin/ga`), not by the LLM:

1. **One mutating command.** Only `/google-ads-copilot:apply` ever calls
   `bin/apply`, and only `bin/apply` ever sends a `:mutate` request.
2. **Always-propose.** Every potential change is drafted as a `.md` file
   you read before approving.
3. **Account-ID pin.** `bin/apply` refuses if the proposal's `account_id`
   doesn't match your `workspace.json`.
4. **Schema + `validate_only` dry-run.** `bin/validate-proposal` checks
   the envelope shape; `bin/apply` then runs `validateOnly:true` against
   Google's API; only proceeds if both pass.
5. **Append-only change-log.** Every applied operation = one JSON line in
   `workspace/change-log/<date>.jsonl`. Failures (transport or rejection)
   get logged with `applied:false`. Never overwrites.

Plus: **resource-name auto-substitution** for paired proposals. When
proposal B references `<resourceName from proposal X op N>`, `bin/apply`
resolves it from the change-log automatically — no manual editing
between paired applies (e.g. assets-add → assets-link).

### Test coverage

Two offline test suites (no network, no live API call) — total **62
assertions**:

- `bin/test-ga.py` (35 assertions) — yaml/env credential loading,
  customer-ID validation (CRLF + path-injection rejection),
  workspace.json walk-up, `GoogleAdsException` → REST-error envelope
  translation, multi-batch `search_stream` aggregation, `cmd_proxy`
  header construction (Authorization, developer-token,
  login-customer-id), body forwarding, path-shape rejection.
  Stubs `google.ads.googleads.*` at `sys.modules` level so it runs in
  CI without installing the full library.
- `bin/test-apply.sh` (27 assertions) — schema validation, account-ID
  pin, dry-run failure surfacing, change-log line shape, paired-proposal
  resource-name substitution, parameterless body shapes, malformed-JSON
  rejection.

Both run on every push + PR via [GitHub Actions](.github/workflows/ci.yml)
and as part of `bin/setup`. Retry/backoff, pagination via `search_stream`,
and OAuth refresh are now the library's responsibility — covered by
google-ads-python's own test suite, not ours.

## Daily use

```bash
cd ~/dev/personal/<your-saas-app>     # any folder with a workspace.json
claude
> /google-ads-copilot:daily
```

The plugin walks up from cwd, finds `workspace.json`, and binds to that
account for the session. Run any command from anywhere inside the project.

## Troubleshooting

- **`OAuth refresh error` from `bin/setup` or any command.** Refresh token
  expired (7-day rule for unverified Testing-mode clients). Re-run
  `bin/oauth-bootstrap`.
- **`DEVELOPER_TOKEN_PROHIBITED`.** Your developer token's Cloud project
  must match your OAuth client's Cloud project.
- **`PERMISSION_DENIED` from Google Ads.** Likely a developer-token approval
  level (Test/Basic/Standard) gap for the operations you're trying.
- **`workspace.json not found`.** You're outside any project workspace.
  Either `cd` into one, or run `/google-ads-copilot:bootstrap` to scaffold one in the
  current directory.

## License

MIT — see [LICENSE](LICENSE).

## Trademark notice

Not affiliated with or endorsed by Google. "Google Ads" is a trademark of
Google LLC. This plugin is an independent Claude Code integration that
calls the public Google Ads API on the operator's behalf using their own
credentials.

## Architecture

For the original design rationale and the safety-model reasoning, see
[`docs/adr/`](docs/adr/). Those are historical decision records, not
current usage docs.

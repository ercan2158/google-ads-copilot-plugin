# google-ads-copilot

A Claude Code plugin that turns Claude into your Google Ads operator. You
run plain-English slash commands; the agent reads your account, drafts
changes as proposal files you can review, and only ever mutates the account
when you explicitly approve a proposal.

Built for **non-technical SaaS founders** who don't want to hire an agency
but also don't want to learn Google Ads from scratch. The plugin keeps your
account safe: read-only by default, account-ID pinned, every applied change
logged.

## What you'll need

- **Google Ads developer token** — request at the
  [Google Ads API Center](https://ads.google.com/aw/apicenter). **Approval
  can take days.** Start this first.
- **Google Cloud project** with the Google Ads API enabled, in the same
  Cloud project as the developer token.
- **OAuth 2.0 Desktop client** in that Cloud project. Add yourself as a
  **test user** under the OAuth consent screen.
- **CLI tools:** `jq`, `python3`, `curl`, `claude` (Claude Code).

> ⚠️ **Token-expiry warning.** If your OAuth consent screen is in **Testing**
> mode (the default for unverified clients with restricted scopes like
> `adwords`), refresh tokens expire **every 7 days**. When that happens,
> just re-run `bin/oauth-bootstrap`. To remove this constraint long-term,
> submit the OAuth client for Google's verification (separate multi-week
> process).

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

Secrets live separately at `~/.config/google-ads-copilot/credentials` (chmod 600)
— never in any project repo, never in the plugin. Override the location
with `GOOGLE_ADS_COPILOT_CREDENTIALS_FILE`, or set individual fields via env
vars (`GOOGLE_ADS_DEVELOPER_TOKEN`, `GOOGLE_ADS_CLIENT_ID`, etc.) for
CI-style use.

## Commands

| Command | What it does |
|---|---|
| `/google-ads-copilot:bootstrap` | First-run scaffold + deep audit (per project) |
| `/google-ads-copilot:daily` | Anything-on-fire check; only writes a digest on anomaly |
| `/google-ads-copilot:weekly` | Spend, search-terms, creative, disapprovals; may draft 0–2 proposals |
| `/google-ads-copilot:monthly` | Full 8-section audit; may draft up to 3 proposals |
| `/google-ads-copilot:budgets` | Ad-hoc budget pacing review |
| `/google-ads-copilot:creative` | Ad-hoc RSA asset health check |
| `/google-ads-copilot:search-terms` | Mine 30 days of search terms for negative-keyword candidates |
| `/google-ads-copilot:explain <term>` | Plain-English explainer for any Google Ads concept |
| `/google-ads-copilot:recommendations` | Pull Google's pending recommendations, score against your context, draft proposals for the ones worth applying |
| `/google-ads-copilot:changes [days]` | Show the audit trail — what's been applied recently (default 7 days) |
| `/google-ads-copilot:undo <proposal-id>` | Generate the inverse of an applied proposal as a new proposal (rollback) |
| `/google-ads-copilot:apply <proposal-id>` | **The only mutating command.** Applies a drafted proposal |

### Architecture: skills loaded per command

Every command runs as the **`manager`** agent and declares which skills the agent loads. Skills compose: `gaql` and `explain-to-beginner` are foundation skills (one for reading the account, one for output style); `change-execution` is loaded only when a command might draft a mutation; `account-audit` orchestrates the multi-section reviews.

| Command | Skills loaded |
|---|---|
| `/google-ads-copilot:bootstrap` | `gaql`, `account-audit` (full), `search-term-mining`, `budget-management`, `creative-management`, `explain-to-beginner` |
| `/google-ads-copilot:daily` | `gaql`, `explain-to-beginner` |
| `/google-ads-copilot:weekly` | `gaql`, `account-audit` (sections 1/3/4/5), `search-term-mining`, `budget-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:monthly` | `gaql`, `account-audit` (full), `search-term-mining`, `budget-management`, `creative-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:budgets` | `gaql`, `budget-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:creative` | `gaql`, `creative-management`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:search-terms` | `gaql`, `search-term-mining`, `change-execution`, `explain-to-beginner` |
| `/google-ads-copilot:explain` | `explain-to-beginner` |
| `/google-ads-copilot:recommendations` | `gaql`, `change-execution`, `creative-management`, `search-term-mining`, `budget-management`, `explain-to-beginner` |
| `/google-ads-copilot:changes` | `explain-to-beginner` |
| `/google-ads-copilot:undo` | `change-execution` (incl. `references/apply-contract.md` for inverse-op rules) |
| `/google-ads-copilot:apply` | `change-execution` (incl. `references/apply-contract.md`) |

## Safety model

Five gates between any read-only command and a live mutation:

1. **One mutating command.** Only `/google-ads-copilot:apply` ever calls a Google Ads
   `:mutate` endpoint.
2. **Always-propose.** Every potential change is drafted as a `.md` file
   you read before approving.
3. **Account-ID pin.** `/google-ads-copilot:apply` refuses if the proposal's `account_id`
   doesn't match your `workspace.json`.
4. **`validate_only` dry-run.** Every apply runs `validateOnly:true` first;
   only proceeds if Google accepts the dry-run.
5. **Append-only change-log.** Every applied operation = one JSON line in
   `workspace/change-log/<date>.jsonl`. Easy to audit, never overwrites.

The `bin/ga` helper has an offline test suite (`bin/test-ga.sh`, 11 mocked
assertions) that runs as part of `bin/setup` — verifies URL construction,
header injection, and error paths without touching the live API.

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

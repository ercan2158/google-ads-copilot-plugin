# Changelog

All notable changes to google-ads-copilot.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-05-03 — Domain coverage + Python migration

Two big shifts: (a) the audit went from 8 sections to 10 with two
foundational diagnostic skills added, and (b) the bash REST helper
was retired for the official `google-ads` Python client.

### Added — domain coverage

- **`conversion-health` skill (NEW)** — 8-check audit per conversion
  action: category alignment with kpi-tree, counting_type, attribution
  model + DDA status, click-through lookback window vs typical
  conversion latency, primary_for_goal correctness,
  include_in_conversions_metric, value_settings sanity, volume floor
  (<15 / 15-30 / ≥50 conv/30d). Plus customer-level enhanced-conversions
  + accepted-customer-data-terms checks via the customer resource.
  Drafts safe `conversion-action-mod` proposals for fixable fields
  (primary_for_goal, lookback windows, attribution model,
  default_value); refuses to auto-draft category/status/counting_type
  changes (foundational, manual only).
- **`smart-bidding` skill (NEW)** — strategy-vs-kpi-tree alignment,
  full `bidding_strategy_system_status` enum coverage (LEARNING_*,
  LIMITED_*, MISCONFIGURED_*, NOT_ACTIVE), 30/50 conv/30d volume floors
  for tCPA/tROAS, realized vs target hit-rate analysis, recent-target-
  change frequency check. Unblocks the "manual review" verdict on
  `TARGET_CPA_OPT_IN` / `TARGET_ROAS_OPT_IN` /
  `MAXIMIZE_CONVERSIONS_OPT_IN` recommendations.
- **`pmax` skill (NEW)** — volume-floor gate (refuse PMax under 30
  conv/30d), per-campaign asset-group + audience-signal +
  `campaign_search_term_insight` reads, `asset_group.primary_status`
  enum interpretation (`LIMITED` / `LEARNING` / `READY`), limited
  mutation surface (audience-attach, customer-negative-criterion-add).
- **Brand-defense audit** — new gaql queries for branded vs non-
  branded search-term performance using brand terms from
  `context/product-positioning.md`. Targets: branded impression share
  ≥ 90%, branded CPA < 30% of non-branded, dedicated brand campaign
  presence.
- **Geo-targeting footgun audit** — flags campaigns with
  `geo_target_type_setting.positive_geo_target_type =
  PRESENCE_OR_INTEREST` (Google's broadest default) when ICP indicates
  local-only.
- **Final-URL liveness check** in audit Section 6 — catches landing
  pages that 4xx/5xx after a deploy, before Google's own disapproval
  flagging (~24h lag).
- **Ad-strength integration** — pairs `ad_group_ad.ad_strength`
  enum (POOR/AVERAGE/GOOD/EXCELLENT) with per-asset `performance_label`
  for the holistic creative view.
- **Bid-modifier cumulative-effect computation** — before drafting any
  `bid-adjust`, the cumulative multiplier (existing modifiers ×
  proposed) is computed and surfaced in the proposal TL;DR. Cap at
  ±50% cumulative.
- **Day-of-week-weighted pacing formula** in `budget-management` —
  replaces the flat `daily × elapsed` approximation when ≥ 60 days of
  history exist. Stops first-week-of-month false alarms.
- **Conversion-lag-aware reads** — added `lag_days` field to
  `kpi-tree.md` (default 3); subtract from comparison windows; surface
  in TL;DR. Prevents alarming on incomplete conversion data.
- **5 new mutation kinds** — `bidding-strategy-shift`,
  `bidding-target-tune`, `campaign-setting-update`, `audience-attach` /
  `audience-detach`, `customer-negative-criterion-add` (the only
  API-supported way to negative-out a query from a PMax campaign as of
  v23). All inverse rules added to apply-contract.
- **Budget-undo dashboard-drift warning** — `/undo` for `budget`
  detects manual dashboard edits between apply and undo and refuses
  rather than silently overwriting.
- **Close-variants advisory** in `search-term-mining` — flags that
  PHRASE/EXACT negatives don't always block plurals/typos; advises
  explicit variants for theme-critical negatives.

### Changed — domain coverage

- **`account-audit`** rewritten from 8 to 10 sections. Sections 2
  (conversion-tracking) and 3 (smart-bidding) are now *foundational
  gates* — every other section's findings get qualified when these
  are 🔴.
- **`creative-management`** RSA descriptions clarified: target 4, hard
  limit 4 (Google's maximum).
- **`/recommendations`** mapping for `TARGET_CPA_OPT_IN` /
  `TARGET_ROAS_OPT_IN` / `MAXIMIZE_CONVERSIONS_OPT_IN` upgraded from
  "manual review" to gated `bidding-strategy-shift` (gates from
  `smart-bidding`).
- **`/bootstrap`** context-stub prompts now ask for `lag_days`,
  conversion category, and brand terms — all three feed directly into
  the new diagnostic skills.

### Added — technology / safety

- **`bin/apply`** (NEW, deterministic shell script) — closes the
  LLM-as-safety-officer concern. All five mutation gates from
  change-execution are now mechanical: account-ID pin against
  `workspace.json`, schema validation via `bin/validate-proposal`,
  `validate_only` dry-run via `bin/ga`, append-only change-log with
  `applied:true|false` per outcome, mv-to-applied/ only on success.
  Three modes: default interactive (y/n), `--plan` (dry-run only,
  exits before mutation), `--confirm` (skip prompt for agent-driven
  flows).
- **Resource-name auto-substitution** — `bin/apply` resolves
  `<resourceName from proposal X op N>` placeholders from the
  change-log automatically. Eliminates manual hand-editing of paired
  proposals (assets-add → assets-link, customer-match 4-step flow).
- **`bin/validate-proposal`** (NEW) — schema check for proposal
  envelopes: required fields, numeric account_id, valid HTTP method,
  endpoint shape, operations[]-vs-body{} XOR enforcement, empty-array
  rejection, unknown-kind warning. Called inline from `bin/apply`.
- **`bin/validate-workspace`** (NEW) — schema check for
  `workspace.json` (numeric customer_id with 10-digit length, ISO
  4217 currency, IANA timezone). Called from `bin/ga.py` and
  `bin/apply` at every read.
- **GitHub Actions CI** — runs both test suites + lint on every push
  and PR. Lints: markdown fence parity, bash + Python syntax, no
  stale slash-command names, every referenced skill exists.

### Changed — technology (the big migration)

- **`bin/ga`: bash REST helper → google-ads Python client.** The
  235-line bash script is now a 22-line wrapper that exec's
  `bin/ga.py` inside a vendored Python venv. The Python implementation
  uses `GoogleAdsClient.load_from_dict()` for queries (via
  `search_stream`) and `google.oauth2.credentials` for the proxy mode.
  CLI surface unchanged (`query "GAQL"`, `proxy METHOD /path [body]`),
  output shape unchanged (`{"results": [...]}` / `{"error": {...}}`)
  — so skills, `bin/apply`, and the agent persona all work without
  modification.
- **Credentials format**: `~/.config/google-ads-copilot/credentials`
  (KEY=value) → `~/.config/google-ads-copilot/google-ads.yaml`
  (library's native format). `bin/setup` migrates the legacy file
  in-place on first upgrade.
- **Python venv vendored** at `~/.local/share/google-ads-copilot/.venv/`,
  populated from `requirements.txt` (pinned with `~=` compatible-
  release operator). One-time ~50MB install.
- **`bin/oauth-bootstrap`** — rewritten in Python (was bash + inline
  Python). Writes yaml directly; same loopback-redirect flow + state
  parameter check.
- **`agents/manager.md` model**: `sonnet` → `opus`. The audit-driven
  reasoning on conversion-health and smart-bidding scoring against
  kpi-tree benefits from the larger model.

### Tests

- `bin/test-ga.py` (NEW, 35 assertions) — yaml/env credential loading,
  customer-ID validation (CRLF + path-injection rejection),
  workspace.json walk-up, `GoogleAdsException` → REST-error envelope
  translation, multi-batch `search_stream` aggregation, `cmd_proxy`
  header construction (Authorization, developer-token,
  login-customer-id), body forwarding, path-shape rejection.
- `bin/test-apply.sh` (27 assertions, unchanged contract) — schema
  validation, account-ID pin, dry-run failure surfacing, change-log
  line shape, paired-proposal resource-name substitution,
  parameterless body shapes, malformed-JSON rejection.
- **62 mocked assertions, no network**, all green. Both run on every
  push/PR via GitHub Actions and as part of `bin/setup`.

### Deprecated

- `bin/test-ga.sh` (the old curl-mocked bash test harness) — now a
  thin shim that delegates to `bin/test-ga.py`.

### Removed

- Hand-rolled OAuth token refresh + cache TTL math (now in
  google-ads-python).
- Hand-rolled exponential backoff with custom retry budget (now
  google-api-core's gRPC retry).
- `nextPageToken` pagination loop with safety caps (now
  `search_stream`'s gRPC streaming).
- Curl-PATH-mock test harness (now Python sys.modules-stubbed).

### README + persona

- Reframed persona from "non-technical SaaS founders" to "technical
  founders / indie hackers / CTOs running their own Google Ads on
  Search-heavy accounts" — honest about who can actually use this
  today.
- 7-day OAuth-token-expiry caveat moved upfront ("expect to re-auth
  weekly until OAuth verification ships").
- Safety differentiator hammered: "Most AI for Google Ads tools
  auto-apply changes the moment you connect them. This one drafts
  every change as a markdown file you review first, then runs it
  through Google's own dry-run, then asks you to confirm."

## [0.1.0] — 2026-04-30 — Initial release

Original 8-section audit, 7 skills, 9 commands, bash-only REST helper.
See `docs/adr/2026-04-30-ads-copilot-design.md` for the original
design rationale and the post-Composio addendum.

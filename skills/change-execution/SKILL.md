---
name: change-execution
description: Universal mutation protocol. Loaded any time the agent considers a Google Ads mutation — any kind, any endpoint. Defines the proposal-file envelope, the five safety gates, the recipe for adding new kinds, and a documented table of 15 kinds covering search-term mining, budget shifts, creative refresh, asset extensions (sitelinks/callouts/snippets), keyword management, campaign/ad toggles, bid adjustments, conversion-action edits, Customer Match uploads, and Google's own recommendation apply/dismiss. Apply pseudo-code, body-construction rules, and per-kind inverse rules for /undo live at references/apply-contract.md.
---

# change-execution

Mutations never go straight to the account. The agent drafts a proposal
file; the operator runs `/google-ads-copilot:apply <id>`; only that
command calls Google's mutate endpoints.

## The five gates

1. **Single mutating command.** Only `/google-ads-copilot:apply` mutates.
2. **Always-propose.** Every mutation = a `.md` file the operator can read.
3. **Account-ID pin.** `/google-ads-copilot:apply` refuses if the proposal's `account_id` doesn't match `workspace.json`.
4. **`validate_only` dry-run.** Every mutation runs `validateOnly:true` first; only proceeds on success. (Exception: endpoints that don't accept `validateOnly`, like `recommendations:apply` and `recommendations:dismiss` — handled per-kind below.)
5. **Append-only change-log.** Every applied operation = one JSON line in `workspace/change-log/$(date +%Y-%m-%d).jsonl`.

The gates apply to **any** kind. They don't care about the endpoint or operation shape. New kinds inherit them automatically.

## The proposal envelope (universal)

**`bin/ga proxy` is fully generic** — there's no API-level restriction. Any Google Ads REST endpoint can be the target of a proposal. The kinds table below documents kinds with thoroughly-tested drafter heuristics; new kinds extend the table without changing the envelope or the safety gates.

The envelope (one of two shapes depending on the endpoint):

```json
// Shape A — batch :mutate endpoints (most kinds)
{
  "proposal_id": "<YYYY-MM-DD>-<kind>-<seq>",
  "kind": "<documented kind | new kind>",
  "account_id": "<from workspace.json>",
  "method": "POST",
  "endpoint": "/v23/customers/<id>/<resource>:mutate",
  "validate_first": true,
  "operations": [ { ...op... }, { ...op... } ],
  "metadata": { ... }
}

// Shape B — non-batch endpoints (single-object :create, :apply, :run, :dismiss)
{
  "proposal_id": "...",
  "kind": "...",
  "account_id": "...",
  "method": "POST",
  "endpoint": "/v23/customers/<id>/offlineUserDataJobs:create",
  "validate_first": true,
  "body": { ...request body root... },
  "metadata": { ... }
}
```

Apply constructs the request body per the rule documented at
[`references/apply-contract.md`](references/apply-contract.md#request-body-construction):
`operations[]` → wrapped as `{ "operations": [...], "validateOnly": ... }`;
`body` → passed through with `validateOnly` injected at root if
applicable; neither → empty body (for parameterless `:run` etc.).

For multi-step kinds (e.g. `assets-add` → `assets-link`, or
`customer-match-upload`'s 4-step userList flow), draft TWO OR MORE paired
proposals; the apply order is documented per kind. The apply contract
treats paired proposals as ordinary sequential applies — no special
runtime support needed. Use `metadata.depends_on: <previous_proposal_id>`
to make the dependency explicit.

## Proposal file format

Path: `workspace/proposals/<YYYY-MM-DD>-<kind>-<seq>.md`

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
{ ...the envelope above... }
```
````

The fenced ```json block at the bottom is the **executable** part.
`/google-ads-copilot:apply` extracts it with `awk` / `jq` and runs it.

## How to add a new kind

1. **Append a row** to the [Documented kinds](#documented-kinds) table below with: name, draftors (slash commands that invoke), method+endpoint, op shape summary, drafter notes.
2. **For non-trivial kinds**, drop a worked example at `examples/<kind>.md`.
3. **For kinds with classification heuristics**, document them in the relevant skill (e.g. `search-term-mining` for `negatives` / `keyword-add`; `creative-management` for `creative-*`/`assets-*`; `budget-management` for `budget`/`bid-adjust`).
4. The five gates apply automatically — the apply pseudo-code at [`references/apply-contract.md`](references/apply-contract.md) is kind-agnostic.

## Documented kinds

| kind | drafted by | method + endpoint | op shape | heuristic / example |
|---|---|---|---|---|
| `negatives` | `/search-terms`, `/weekly` | POST `campaignCriteria:mutate` | `create` negative keyword | `search-term-mining` |
| `budget` | `/budgets`, `/weekly`, `/monthly`, `/recommendations` | POST `campaignBudgets:mutate` | `update` `amountMicros` + `updateMask: amountMicros` | `budget-management` |
| `creative-pause` | `/creative`, `/monthly` | POST `adGroupAdAssets:mutate` | `remove` link `resourceName` | `creative-management` |
| `creative-add` | `/creative`, `/monthly`, `/recommendations` | POST `adGroupAdAssets:mutate` | `create` link with `adGroupAd`, `asset`, `fieldType` | `creative-management` + [`creative-management/examples/rsa-headlines.md`](../creative-management/examples/rsa-headlines.md) |
| `assets-add` | `/recommendations`, `/monthly` | POST `assets:mutate` | `create` sitelink/callout/snippet/image asset | [`examples/assets-flow.md`](examples/assets-flow.md) |
| `assets-link` | `/recommendations`, `/monthly` | POST `customerAssets:mutate` *or* `campaignAssets:mutate` | `create` link with `asset`, `fieldType` | paired with `assets-add` — see [`examples/assets-flow.md`](examples/assets-flow.md) |
| `assets-unlink` | `/recommendations`, `/monthly` | POST `customerAssets:mutate` *or* `campaignAssets:mutate` | `remove` link `resourceName` | when an extension consistently underperforms |
| `keyword-add` | `/weekly`, `/monthly`, `/recommendations` | POST `adGroupCriteria:mutate` | `create` `keyword: { text, matchType }` with `cpcBidMicros` | [`examples/keyword-management.md`](examples/keyword-management.md) |
| `keyword-pause` | `/weekly`, `/monthly` | POST `adGroupCriteria:mutate` | `update` `status: PAUSED` + `updateMask: status` | [`examples/keyword-management.md`](examples/keyword-management.md) |
| `campaign-toggle` | (operator request) | POST `campaigns:mutate` | `update` `status: ENABLED \| PAUSED` + `updateMask: status` | one campaign per proposal; explicit operator intent |
| `ad-toggle` | `/creative`, `/monthly` | POST `adGroupAds:mutate` | `update` `status: ENABLED \| PAUSED` + `updateMask: status` | when an individual ad consistently underperforms |
| `bid-adjust` | `/weekly`, `/monthly` | POST `campaignCriteria:mutate` | `create` or `update` `bidModifier` for device/geo/schedule criteria | [`examples/bid-adjust.md`](examples/bid-adjust.md) |
| `conversion-action-mod` | `/monthly`, (operator request) | POST `conversionActions:mutate` | `update` `primary_for_goal` / `click_through_lookback_window_days` / `attribution_model_settings.attribution_model` / `value_settings.default_value` | `conversion-health` — **never** auto-drafted for `category` / `status` / `counting_type` (foundational, manual only) |
| `bidding-strategy-shift` | `/monthly`, (operator request) | POST `campaigns:mutate` | `update` `bidding_strategy_type` + matching target_cpa / target_roas / manual_cpc + `updateMask` covering both | `smart-bidding` — strategy-class change, requires explicit operator chat acknowledgment before drafting |
| `bidding-target-tune` | `/weekly`, `/monthly` | POST `campaigns:mutate` *or* `biddingStrategies:mutate` (portfolio) | `update` `target_cpa.target_cpa_micros` / `target_roas.target_roas` + `updateMask` | `smart-bidding` — single-step ±15% cap; one per audit run |
| `campaign-setting-update` | `/monthly`, (operator request) | POST `campaigns:mutate` | `update` `geo_target_type_setting.positive_geo_target_type` (PRESENCE_OR_INTEREST → PRESENCE), `network_settings.*`, etc. + targeted `updateMask` | `account-audit` Section 7 — geo footgun fix; non-status campaign config |
| `customer-match-upload` | `/recommendations`, (operator request) | multi-step (`userLists:mutate` → `offlineUserDataJobs:create` → `:addOperations` → `:run`) | hashed PII upload, 4 paired proposals | [`examples/customer-match.md`](examples/customer-match.md) — **non-invertible** |
| `recommendation-apply` | `/recommendations` | POST `recommendations:apply` | `applyParameters` per rec type | [`examples/recommendation-apply.md`](examples/recommendation-apply.md) — **no validate_only** |
| `recommendation-dismiss` | `/recommendations` | POST `recommendations:dismiss` | just the `resourceName` | when a rec doesn't fit and operator wants to clear noise |
| `audience-attach` | `/monthly`, `/recommendations` (PMax) | POST `assetGroupSignals:mutate` | `create` link with `assetGroup` + `audience: { customAudience \| userList \| ... }` | `pmax` skill — attach a signal in observation mode for PMax; or attach in OBSERVATION on Search ad groups via `adGroupCriteria:mutate` audience criterion |
| `audience-detach` | (paired with attach for /undo) | POST `assetGroupSignals:mutate` | `remove` link `resourceName` | inverse of `audience-attach` |
| `customer-negative-criterion-add` | `/recommendations` (PMax), `/monthly` | POST `customerNegativeCriteria:mutate` | `create` negative keyword / placement / etc. at customer level | the only API-supported way to negative-out a query from a PMax campaign as of v23; affects ALL campaigns (not just PMax) — flag this in TL;DR |

Out of scope for v1 (still): `campaign-create`, `ad-group-create`, `ad-create-from-scratch` — anything that builds new structural entities. The plugin assumes the campaign skeleton exists; it tunes within it.

## /google-ads-copilot:apply contract

The apply command's full pseudo-code, change-log line shape, and
failure-mode reference live at
[`references/apply-contract.md`](references/apply-contract.md). Drafters
loading this skill don't need it; only `/google-ads-copilot:apply` does.

## Rollback / undo

Most kinds are invertible — given an applied proposal in
`workspace/proposals/applied/` and its change-log entry, the inverse
can be drafted as a new proposal. The `/google-ads-copilot:undo
<proposal-id>` command does this; the canonical per-kind inverse rules
live at
[`references/apply-contract.md`](references/apply-contract.md#per-kind-inverse-rules-canonical).
Non-invertible kinds (`recommendation-apply`, `customer-match-upload`)
are flagged in the kinds table and refuse `/undo` with an explanation
plus a manual-recipe pointer.

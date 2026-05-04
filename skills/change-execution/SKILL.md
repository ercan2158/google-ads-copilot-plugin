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
| `negative-list-create` | `/search-terms`, `/weekly`, `/monthly` | POST `sharedSets:mutate` | `create` `{name, type:'NEGATIVE_KEYWORDS'}` | shared negatives flow — first of 3 paired proposals (create → add-keywords → attach) — see [`examples/shared-negatives.md`](examples/shared-negatives.md) |
| `negative-list-add-keyword` | `/search-terms`, `/weekly`, `/monthly` | POST `sharedCriteria:mutate` | `create` `{sharedSet, keyword:{text, matchType}, negative:true}` (one op per keyword) | typically paired with `negative-list-create` via `metadata.depends_on`; can also stand alone to grow an existing list |
| `negative-list-remove-keyword` | (operator request) | POST `sharedCriteria:mutate` | `remove` `<sharedCriterion resourceName>` | rare — pulling a keyword from a shared list affects every attached campaign |
| `negative-list-attach` | `/search-terms`, `/weekly`, `/monthly` | POST `campaignSharedSets:mutate` | `create` `{campaign, sharedSet}` (one op per campaign attachment) | third proposal in the create→add→attach flow; references the sharedSet from `negative-list-create` via `<resourceName from proposal X op N>` |
| `negative-list-detach` | (operator request), `/undo` | POST `campaignSharedSets:mutate` | `remove` `<campaignSharedSet resourceName>` | inverse of `negative-list-attach` |
| `negative-list-delete` | (operator request) | POST `sharedSets:mutate` | `remove` `<sharedSet resourceName>` | high blast radius — cascades through every `shared_criterion` and every `campaign_shared_set` link. **Sets `confirmation_required: explicit_yes` in the envelope** (operator must retype the proposal_id at apply time). **Non-invertible** — recreating an identical list re-issues different resource names. |
| `asset-group-asset-link` | `/monthly`, `/recommendations` (PMax) | POST `assetGroupAssets:mutate` | `create` `{assetGroup, asset, fieldType}` (link an existing asset to a PMax asset group with a field type like HEADLINE / DESCRIPTION / LONG_HEADLINE / MARKETING_IMAGE / LANDSCAPE_LOGO / YOUTUBE_VIDEO) | `pmax` skill — pair with `assets-add` to refresh creative on a POOR/AVERAGE asset group; see [`examples/asset-group-flow.md`](examples/asset-group-flow.md) |
| `asset-group-asset-unlink` | `/monthly`, (operator request) | POST `assetGroupAssets:mutate` | `remove` `<assetGroupAsset resourceName>` | inverse of `asset-group-asset-link`; or pause an underperforming asset on its asset group without deleting the asset entity |
| `asset-group-toggle` | (operator request) | POST `assetGroups:mutate` | `update` `status: ENABLED \| PAUSED` + `updateMask: status` | pause an underperforming PMax asset group; one asset group per proposal |
| `asset-group-create` | (operator request, `/monthly` for theme-split) | POST `assetGroups:mutate` | `create` `{campaign, name, finalUrls, status:'PAUSED'}` (asset linking happens via paired `asset-group-asset-link` proposals) | high blast radius — sets `confirmation_required: explicit_yes`. Always created `PAUSED`; operator manually flips to ENABLED in the dashboard after reviewing the asset linkage. v1 limit: max 1 per audit run |
| `final-url-exclusion-add` | `/monthly`, `/recommendations` | POST `campaignCriteria:mutate` | `create` `{campaign, negative:true, webpage:{conditions:[{operand:'URL', operator:'EQUALS' \| 'CONTAINS', argument:'<url-or-fragment>'}]}}` | block specific URLs from PMax/Display serving (e.g. `/careers`, `/login`, `/legacy/*`); works for any campaign type but most-needed in PMax where keyword-level exclusion isn't available |
| `brand-list-create` | `/monthly`, (operator request) | POST `assetSets:mutate` | `create` `{name, type:'BRAND_LIST'}` followed by paired `assetSetAsset:mutate` ops to populate with `BRAND` assets — multi-step flow, see [`examples/brand-list.md`](examples/brand-list.md) | newer PMax feature (~2024); availability varies by API version. **`confirmation_required: explicit_yes`** since brand-list misconfiguration affects all attached PMax campaigns |
| `brand-list-attach` | `/monthly`, (operator request) | POST `campaignAssetSets:mutate` | `create` `{campaign, assetSet}` linking a brand list to a PMax campaign | paired with `brand-list-create` via `metadata.depends_on` |

Out of scope (still): `campaign-create`, `ad-group-create`,
`ad-create-from-scratch`, listing-group / product-feed structure
(retail PMax) — anything that builds new top-level structural entities
or touches feed shapes. The plugin assumes the campaign skeleton
exists; it tunes within it. `asset-group-create` is the one
exception — added in 0.3.0 because PMax asset groups are the closest
PMax analogue to a Search ad group, and theme-splitting is the only
way to act on `campaign_search_term_insight` category divergence.

## High-blast-radius envelope flag

Some kinds carry irreversible or wide-affecting consequences that
warrant a second-factor gate beyond the standard y/n confirmation.
Drafters add `confirmation_required: "explicit_yes"` to the envelope:

```json
{
  "proposal_id": "...",
  "kind": "negative-list-delete",
  "confirmation_required": "explicit_yes",
  ...
}
```

When `bin/apply --confirm` sees this flag, it requires the operator to
**retype the proposal_id verbatim** instead of accepting a single `y`.
Mistyping aborts. This is a typing-friction safeguard — it doesn't
prevent a determined operator from proceeding, but it stops accidental
applies on high-blast operations.

Kinds that MUST set this flag:
- `negative-list-delete` (cascades through criteria + campaign links)
- `asset-group-create` (creates structural entity in PMax)
- `brand-list-create` (affects every attached PMax campaign once linked)

Drafters MAY set this flag on any other kind when the proposal touches
a high-spend campaign or a customer-level resource. The standard
flow with no flag still requires a y/n confirmation at apply time;
explicit_yes is the upgraded gate for the high-blast subset.

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

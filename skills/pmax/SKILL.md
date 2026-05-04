---
name: pmax
description: Use when the audited account has Performance Max campaigns (advertising_channel_type = PERFORMANCE_MAX). Provides the read protocol (asset groups, audience signals, search-term insights via campaign_search_term_insight per-campaign), the volume-floor gate for whether PMax should run at all, and the limited mutation surface (account-level negative keyword lists, audience signal updates, asset group asset edits — full PMax mutation is mostly UI-only).
---

# pmax

Performance Max is Google's automated campaign type that fans out
across Search, Display, YouTube, Discover, Gmail, and Maps. The API
exposes less control than Search campaigns by design — most operator
levers (audience signals, listing groups, brand exclusions) are
adjustable via the API but in narrower shapes; some (final URL
expansion toggle, asset group A/B testing) are UI-only.

## Volume-floor gate (decide if PMax should run at all)

PMax burns budget at low volume because it's training a model across
many surfaces simultaneously (Search, Display, YouTube, Discover,
Gmail, Maps). The volume floor for PMax is meaningfully higher than
for a single-surface Search campaign on the same strategy — the model
has more dimensions to learn over.

Before recommending PMax expansion or applying a `PERFORMANCE_MAX_OPT_IN`
recommendation:

🔴 **refuse** if account-level conversions < 50/30d (with values for
ROAS-based PMax). The 30-conv floor that works for a Search-only
tCPA campaign isn't enough for PMax — the model spreads thin across
surfaces and shipping budget at this level produces noise, not learning.

🟡 **warning** if 50–100 conv/30d. PMax can work but expect 4–8 weeks
of LEARNING before it stabilizes. Recommend running parallel with
existing Search campaigns rather than shifting budget from them.

🟢 **healthy gate** if ≥ 100 conv/30d AND conversion tracking is healthy
per `conversion-health` AND there's revenue value tracked (PMax leans
heavily on `MAXIMIZE_CONVERSION_VALUE` or `TARGET_ROAS`).

These bands are stricter than the canonical bands in `smart-bidding`
check #3 (which apply to single-surface Search) — PMax's multi-surface
model needs more signal to converge.

## Read each PMax campaign separately

PMax queries that return any meaningful insight require filtering by
a single campaign. Loop over each PMax campaign:

```sql
SELECT
  campaign.id, campaign.name, campaign.advertising_channel_type,
  campaign.bidding_strategy_type,
  campaign.maximize_conversion_value.target_roas,
  campaign.url_expansion_opt_out
FROM campaign
WHERE campaign.advertising_channel_type = 'PERFORMANCE_MAX'
  AND campaign.status = 'ENABLED'
```

Then per campaign:

### 1. Asset groups + asset coverage

```sql
SELECT
  asset_group.id, asset_group.name, asset_group.status,
  asset_group.primary_status, asset_group.primary_status_reasons,
  asset_group.ad_strength
FROM asset_group
WHERE asset_group.campaign = 'customers/<id>/campaigns/<pmax_id>'
  AND asset_group.status = 'ENABLED'
```

`asset_group.ad_strength`: `POOR`/`AVERAGE`/`GOOD`/`EXCELLENT`. Anything
below `GOOD` is a 🟡; combine with `primary_status` (`LIMITED`,
`LEARNING`, `READY`) for the full picture. `primary_status_reasons` is
an array enum that pinpoints the limit (e.g.
`ASSET_GROUP_ADS_NOT_ELIGIBLE`, `BUSINESS_NAME_REQUIRED`,
`AUDIENCE_REQUIRED`).

### 2. Audience signals attached

```sql
SELECT
  asset_group_signal.asset_group, asset_group_signal.audience,
  asset_group_signal.search_theme.text
FROM asset_group_signal
WHERE asset_group_signal.asset_group = 'customers/<id>/assetGroups/<asset_group_id>'
```

🟡 if no audience signals are attached AND the campaign has < 8 weeks
of history — PMax converges much faster with explicit audience signals
(in-market, custom segments, customer-match lists in observation mode)
than with the bare "Google figures it out" path.

### 3. Search-term insights (PMax-specific, category-level only)

```sql
SELECT
  campaign_search_term_insight.id,
  campaign_search_term_insight.category_label,
  metrics.clicks, metrics.impressions,
  metrics.conversions, metrics.conversions_value, metrics.cost_micros
FROM campaign_search_term_insight
WHERE campaign_search_term_insight.campaign_id = '<pmax_id>'
  AND segments.date DURING LAST_30_DAYS
ORDER BY metrics.cost_micros DESC
```

`category_label` is Google's clustered theme (e.g. *"yamazumi
software"*, *"line balancing tools"*) — not the raw query. Individual
queries are not exposed. The audit can flag high-cost categories with
zero conversions; the *only* way to act on them in v1 is via an
account-level negative-keyword list (PMax doesn't accept campaign-level
negatives via the API as of v23).

## Mutation surface (limited)

| What | API path | Plugin kind | Status |
|---|---|---|---|
| Account-level brand exclusion list | `customers/<id>/customerNegativeCriteria:mutate` | `customer-negative-criterion-add` (NEW, see change-execution) | drafted via `/recommendations` when a category is high-spend, zero-conv |
| Audience signal: attach | `assetGroupSignals:mutate` (`create`) | `audience-attach` (NEW) | drafted by `/monthly` when no signals + ≥8w history |
| Audience signal: detach | `assetGroupSignals:mutate` (`remove`) | `audience-detach` (paired with attach for /undo) | n/a |
| Asset group asset add (headline/desc/image) | `assetGroupAssets:mutate` | `assets-add` + `assets-link` shape (existing kinds) | reuse the assets-flow pattern; field type changes per asset |
| Asset group create / restructure | `assetGroups:mutate` | NOT in v1 scope | structural; UI-recommended |
| URL expansion toggle | `campaigns:mutate` `update url_expansion_opt_out` | `campaign-setting-update` (existing kind) | rarely warranted; default off is usually right |
| Bidding target tune | `campaigns:mutate` (target_roas / target_cpa) | `bidding-target-tune` (existing kind) | per `smart-bidding` |

## Out of v1 scope (operator-decision territory)

- Asset group creation from scratch
- Listing-group / product-feed structure changes (Shopping/PMax overlap)
- Final URL expansion changes for ROAS-sensitive accounts
- Brand-list attachment (`brand_guidelines` resource)

For these, the audit surfaces the diagnostic ("LIMITED status because
no audience signal attached"; "category 'free template' is 12% of
spend with 0 conv") and recommends the operator act in the dashboard.

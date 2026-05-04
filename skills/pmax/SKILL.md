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

### 4. Asset coverage check (per asset group)

For each ENABLED asset group, query `asset_group_asset` to count assets
by `field_type`. The plugin floors to clear LIMITED status (per
[`change-execution/examples/asset-group-flow.md`](../change-execution/examples/asset-group-flow.md)):

| Field type | Plugin floor | Google's required min |
|---|---|---|
| HEADLINE (≤30 chars) | ≥ 5 | 3 |
| LONG_HEADLINE (≤90 chars) | ≥ 1 | 1 |
| DESCRIPTION (≤90 chars) | ≥ 4 | 2 |
| BUSINESS_NAME | ≥ 1 | 1 |
| MARKETING_IMAGE | ≥ 4 | 1 |
| SQUARE_MARKETING_IMAGE | ≥ 1 | 1 |
| LOGO | ≥ 1 | 1 |
| YOUTUBE_VIDEO | ≥ 1 | 0 (auto-gen if absent — usually off-brand) |

🔴 if any asset group below Google's required minimum AND ad_strength
is POOR — it's actually-not-serving territory. Drafts an
`assets-add` + `asset-group-asset-link` paired flow per
[`change-execution/examples/asset-group-flow.md`](../change-execution/examples/asset-group-flow.md).

🟡 if assets are above Google's minimum but below the plugin floor —
the asset group serves but ad_strength stays POOR/AVERAGE. Same paired
flow, but operator decides whether to ship.

### 5. Final-URL exclusion coverage

PMax doesn't accept campaign-level negative keywords, but it DOES
accept page-level URL exclusions via `campaign_criterion` of type
`WEBPAGE`. These block specific URLs from PMax's final-URL expansion
(careers, login, support, legacy paths).

```sql
SELECT
  campaign.id, campaign.name,
  campaign_criterion.criterion_id,
  campaign_criterion.webpage.criterion_name,
  campaign_criterion.webpage.conditions,
  campaign_criterion.negative
FROM campaign_criterion
WHERE campaign_criterion.type = 'WEBPAGE'
  AND campaign_criterion.negative = TRUE
  AND campaign.advertising_channel_type = 'PERFORMANCE_MAX'
  AND campaign.status = 'ENABLED'
```

🟡 if a PMax campaign has zero exclusions AND `context/persona-overrides.md`
declares URLs that should never serve (careers, login, /legacy/*,
support pages). Drafts a `final-url-exclusion-add` proposal per the
declared list.

The audit reads `context/persona-overrides.md` for a "URLs that should
never serve" section. If absent, surface a recommendation to add one
during bootstrap rather than auto-drafting.

### 6. Asset-group theme split (operator-decision)

When a single asset group spans conflicting themes (e.g.
"manufacturing software" + "consulting services" in the same asset
group), no single creative can serve both well — Smart Bidding learns
on diluted signal, ad_strength stays AVERAGE.

Detection signal: `campaign_search_term_insight.category_label` clusters
that don't share lexical roots (per audit Section 7's stem-root logic
adapted to category labels).

The fix is splitting into 2+ asset groups via `asset-group-create` and
redistributing audience signals + assets. **High blast radius** — sets
`confirmation_required: explicit_yes`. v1 cap: max 1 split proposal
per audit run. The created asset group is always `PAUSED`; operator
flips to ENABLED in the dashboard after reviewing assets manually
(asset linking happens via paired `asset-group-asset-link` proposals,
which still need the operator to source images/videos that the plugin
can't auto-generate).

## Mutation surface (now expanded for v0.3.0)

| What | API path | Plugin kind | When drafted |
|---|---|---|---|
| Account-level brand exclusion list | `customerNegativeCriteria:mutate` | `customer-negative-criterion-add` | `/recommendations` when a `category_label` is high-spend, zero-conv |
| Audience signal: attach / detach | `assetGroupSignals:mutate` | `audience-attach` / `audience-detach` | `/monthly` when no signals + ≥8w history |
| Asset group asset add (headlines/descriptions/images/videos) | `assets:mutate` + `assetGroupAssets:mutate` | `assets-add` + `asset-group-asset-link` (paired) | check #4 above |
| Asset group asset remove | `assetGroupAssets:mutate` | `asset-group-asset-unlink` | when an asset consistently underperforms |
| Asset group status toggle | `assetGroups:mutate` (`update status`) | `asset-group-toggle` | operator-decision; pause an underperforming asset group |
| Asset group create (theme split) | `assetGroups:mutate` (`create`) | `asset-group-create` | `/monthly` check #6; **`confirmation_required: explicit_yes`** |
| Final URL exclusion | `campaignCriteria:mutate` (`type:WEBPAGE`) | `final-url-exclusion-add` | check #5 above |
| Brand list create + attach | `assetSets:mutate` + `campaignAssetSets:mutate` | `brand-list-create` + `brand-list-attach` (paired) | operator-decision; **`confirmation_required: explicit_yes`** |
| URL expansion toggle | `campaigns:mutate` (`url_expansion_opt_out`) | `campaign-setting-update` | rarely warranted |
| Bidding target tune | `campaigns:mutate` | `bidding-target-tune` | per `smart-bidding` |

## Still out of plugin scope (operator-decision territory)

- **Listing-group / product-feed structure changes** (retail/e-commerce
  PMax with Merchant Center feeds) — materially different mental
  model from B2B SaaS Search; feed shapes are operator territory.
  The plugin can read `asset_group_listing_group_filter` for
  diagnostics but doesn't draft mutations against it.
- **Brand_guidelines resource** (newer than `brand_list` / `assetSet`
  with `type: BRAND_LIST`) — field availability varies by API version;
  if a brand-list-create proposal returns `INVALID_FIELD` on
  `assetSets:mutate`, fall back to the dashboard for now.
- **PMax campaign creation from scratch** — full nested structure
  (campaign → asset groups → assets → audience signals → listing
  group filters for retail) is too much surface area for a
  single proposal; structural setup remains UI work.

For these, the audit surfaces the diagnostic and recommends the
operator act in the dashboard.

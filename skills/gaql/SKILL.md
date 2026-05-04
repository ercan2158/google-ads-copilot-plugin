---
name: gaql
description: GAQL cookbook for read queries via the bundled ga helper. Use whenever you need to read account data — campaign performance, search terms, conversion paths, ad assets, account-level diagnostics.
---

# gaql

Run all reads through `"${CLAUDE_PLUGIN_ROOT}/bin/ga" query "<GAQL>"`. Output is the raw Google Ads
API response — a JSON object with a top-level `results` array on success,
or a top-level `error` object on failure. For mutations use
`change-execution`.

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
  AND metrics.clicks > 0
  AND metrics.conversions < 1
ORDER BY metrics.cost_micros DESC
```

The `clicks > 0` retrieval floor catches every query that actually
spent money, regardless of impression volume. The mining skill then
applies the real classification gate: `cost ≥ target_cpa × 0.3` AND
`clicks ≥ max(10, target_cpa × 0.5 / avg_cpc)`. Anchoring to the
operator's target_cpa rather than impressions or budget-percentage is
how the threshold scales sensibly across €500/mo and €50k/mo accounts.

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

## Conversion actions (basic)

```sql
SELECT
  conversion_action.id, conversion_action.name,
  conversion_action.status, conversion_action.category,
  conversion_action.primary_for_goal
FROM conversion_action
WHERE conversion_action.status != 'REMOVED'
```

## Conversion-action diagnostic (full configuration)

For the `conversion-health` skill — every field that affects whether
Smart Bidding is optimizing on a clean signal.

```sql
SELECT
  conversion_action.id, conversion_action.name,
  conversion_action.status, conversion_action.type, conversion_action.category,
  conversion_action.primary_for_goal,
  conversion_action.include_in_conversions_metric,
  conversion_action.counting_type,
  conversion_action.click_through_lookback_window_days,
  conversion_action.view_through_lookback_window_days,
  conversion_action.attribution_model_settings.attribution_model,
  conversion_action.attribution_model_settings.data_driven_model_status,
  conversion_action.value_settings.default_value,
  conversion_action.value_settings.default_currency_code,
  conversion_action.value_settings.always_use_default_value
FROM conversion_action
WHERE conversion_action.status = 'ENABLED'
```

Pair with 30-day volume per action (via the `customer` resource segmented
by `segments.conversion_action`) so `conversion-health` can apply the
volume floor (#8 in the skill):

```sql
SELECT
  segments.conversion_action,
  segments.conversion_action_name,
  segments.conversion_action_category,
  metrics.all_conversions, metrics.conversions, metrics.conversions_value,
  metrics.clicks
FROM customer
WHERE segments.date DURING LAST_30_DAYS
```

## Conversion-action recent firing (regression check)

For `conversion-health` check #9. Compares the trailing 72h vs the
prior 7d to detect tag-firing regressions independently of the volume
floor in check #8 — a config-clean account whose tag broke last Tuesday
looks identical to a low-volume account through the rest of the audit.

```sql
SELECT
  segments.conversion_action,
  segments.conversion_action_name,
  segments.date,
  metrics.conversions, metrics.all_conversions
FROM customer
WHERE segments.date DURING LAST_14_DAYS
ORDER BY segments.conversion_action, segments.date DESC
```

Bucket dates into `[today-3, today]` (recent) and `[today-10, today-3]`
(prior). Compute daily means per primary action. Flag 🔴 if recent ≈ 0
AND prior > 0; 🟡 if recent < 50% of prior AND prior had ≥ 10 total.

## Customer-level conversion tracking settings

Enhanced conversions and customer-data-terms acceptance live on the
`customer` resource, not on `conversion_action`:

```sql
SELECT
  customer.id, customer.descriptive_name,
  customer.conversion_tracking_setting.accepted_customer_data_terms,
  customer.conversion_tracking_setting.enhanced_conversions_for_leads_enabled,
  customer.conversion_tracking_setting.google_ads_cross_account_conversion_tracking_id,
  customer.conversion_tracking_setting.conversion_tracking_id,
  customer.conversion_tracking_setting.conversion_tracking_status
FROM customer
```

`conversion_tracking_status` ∈ `NOT_CONVERSION_TRACKED`,
`CONVERSION_TRACKING_MANAGED_BY_THIS_MANAGER`,
`CONVERSION_TRACKING_MANAGED_BY_ANOTHER_MANAGER`,
`CONVERSION_TRACKING_MANAGED_BY_SELF_OF_LOSS_OF_PERMISSIONS`. The
conversion-health skill flags `NOT_CONVERSION_TRACKED` 🔴 (no Smart
Bidding can possibly work) and missing accepted data terms 🔴.

## Bidding strategy diagnostic

For the `smart-bidding` skill. One row per ENABLED campaign with strategy
type, system status, the relevant target value, and 30d performance to
compute hit-rate.

```sql
SELECT
  campaign.id, campaign.name, campaign.status,
  campaign.bidding_strategy_type,
  campaign.bidding_strategy_system_status,
  campaign.target_cpa.target_cpa_micros,
  campaign.target_roas.target_roas,
  campaign.maximize_conversions.target_cpa_micros,
  campaign.maximize_conversion_value.target_roas,
  campaign.manual_cpc.enhanced_cpc_enabled,
  metrics.cost_micros, metrics.conversions, metrics.conversions_value,
  metrics.clicks, metrics.impressions
FROM campaign
WHERE segments.date DURING LAST_30_DAYS
  AND campaign.status = 'ENABLED'
ORDER BY metrics.cost_micros DESC
```

`bidding_strategy_type` ∈ `MANUAL_CPC`, `MANUAL_CPM`, `MANUAL_CPV`,
`ENHANCED_CPC`, `MAXIMIZE_CLICKS`, `MAXIMIZE_CONVERSIONS`,
`MAXIMIZE_CONVERSION_VALUE`, `TARGET_CPA`, `TARGET_ROAS`,
`TARGET_IMPRESSION_SHARE`, `TARGET_SPEND`, `COMMISSION`, `FIXED_CPM`,
`PERCENT_CPC`, `INVALID`, `UNKNOWN`.

`bidding_strategy_system_status` enum is documented in the
`smart-bidding` skill (the LEARNING_*, LIMITED_*, MISCONFIGURED_*,
NOT_ACTIVE values drive the audit's severity).

When a campaign uses a *portfolio* (shared) bidding strategy, the
target lives on `bidding_strategy.target_cpa.target_cpa_micros` etc.
not on `campaign`. Pull that separately:

```sql
SELECT
  bidding_strategy.id, bidding_strategy.name, bidding_strategy.type,
  bidding_strategy.target_cpa.target_cpa_micros,
  bidding_strategy.target_roas.target_roas,
  bidding_strategy.status
FROM bidding_strategy
WHERE bidding_strategy.status = 'ENABLED'
```

## Network settings (Search Partners / Display Expansion footgun)

Display Network expansion left enabled on a Search campaign silently
swallows 10–30% of the budget on inventory the operator never intended
to buy. Surface per-campaign:

```sql
SELECT
  campaign.id, campaign.name, campaign.advertising_channel_type,
  campaign.network_settings.target_google_search,
  campaign.network_settings.target_search_network,
  campaign.network_settings.target_content_network,
  campaign.network_settings.target_partner_search_network
FROM campaign
WHERE campaign.status = 'ENABLED'
```

For SEARCH campaigns, `target_content_network = true` is the footgun
— Display expansion. The audit flags 🔴 unless `context/budget-policy.md`
explicitly declares Display participation. Drives a `campaign-setting-update`
proposal flipping it to `false`.

`target_partner_search_network = true` is Search Partners — usually
acceptable but flag 🟡 if conv-tracking can't break out partner perf
and a recent week's spend on partners looks disproportionate.

## Auto-apply recommendations (silent-mutation footgun)

Google can auto-apply recommendations to the account if the operator
left auto-apply on. This bypasses the always-propose safety model
entirely — Google ships changes the plugin never sees a chance to
review.

Auto-apply settings live behind a UI toggle that the v23 API exposes
inconsistently across accounts. Try:

```sql
SELECT
  customer.id,
  customer.optimization_score,
  customer.optimization_score_weight
FROM customer
```

Pair with the dashboard recommendations history (Tools & Settings →
Recommendations → History). If the API path returns `INVALID_FIELD` for
the auto-apply opt-in fields in the operator's API version, the audit
surfaces a manual-check item: "Verify Tools & Settings →
Recommendations → auto-apply is OFF; if any category is opted-in,
disable it before relying on this plugin's review cycle."

Drives a `campaign-setting-update`-style proposal once the API exposes
the toggle reliably; until then, manual UI fix.

## Geo-targeting setting (the LOCATION_OF_PRESENCE footgun)

```sql
SELECT
  campaign.id, campaign.name,
  campaign.geo_target_type_setting.positive_geo_target_type,
  campaign.geo_target_type_setting.negative_geo_target_type,
  campaign.advertising_channel_type
FROM campaign
WHERE campaign.status = 'ENABLED'
```

`positive_geo_target_type` ∈ `PRESENCE_OR_INTEREST` (Google's default —
broadest reach, includes people merely *interested* in your locations),
`PRESENCE` (only people physically in/regularly in target locations),
`SEARCH_INTEREST` (deprecated, no longer settable on new campaigns).

`negative_geo_target_type` ∈ `PRESENCE` (recommended default).

The audit flags `PRESENCE_OR_INTEREST` 🟡 when `context/icp.md` or
`product-positioning.md` indicates a strictly local product (in-person
service, region-locked SaaS, currency-locked product). Most B2B SaaS
operators don't realize this default is showing ads to people abroad
who are *interested* in their target country — a steady source of
unconverting clicks.

## Branded vs non-branded search terms

Google doesn't auto-classify search terms as branded. Pull the
operator's brand terms from `context/product-positioning.md` (the
"brand terms we own" list, or operator's product name if absent), then:

```sql
SELECT
  campaign.id, campaign.name,
  search_term_view.search_term,
  metrics.clicks, metrics.impressions, metrics.cost_micros,
  metrics.conversions, metrics.conversions_value
FROM search_term_view
WHERE segments.date DURING LAST_30_DAYS
  AND (
    search_term_view.search_term LIKE '%<brand_term_1>%'
    OR search_term_view.search_term LIKE '%<brand_term_2>%'
  )
ORDER BY metrics.cost_micros DESC
```

Then run the same query with the inverse filter (`NOT LIKE` for each
brand term) for non-branded performance. Compare:

| Slice | What good looks like |
|---|---|
| Branded CTR | ≥ 8% (high intent, high relevance) |
| Branded CPA | 20–60% of non-branded CPA (B2B SaaS range) |
| Branded impression share | ≥ 90% (you should be dominating your own brand SERP) |

Severity for the CPA ratio: 🟡 if branded CPA > 50% of non-branded
(efficiency degraded — likely creative or landing-page); 🔴 only if
> 100% (brand more expensive than non-brand — actually broken).

🔴 if branded impression share < 70% — competitors are stealing cheap
brand-search conv. The fix is bidding fixes on brand-bearing campaigns,
not necessarily a dedicated brand campaign — see `account-audit`
Section 9 for when isolation actually pays (typically only when brand
spend > 15% of total search spend).

🟡 if no branded clicks observed at all AND the brand has been live
for ≥ 6 months — either the brand has zero search demand (concerning
for SaaS at any maturity) or no campaign is bidding on brand terms.

## Performance Max search terms (PMax)

PMax search terms live on `campaign_search_term_insight`, not
`search_term_view`. Query requires filtering by a single campaign_id
(server returns `REQUIRES_FILTER_BY_SINGLE_RESOURCE` otherwise):

```sql
SELECT
  campaign_search_term_insight.id,
  campaign_search_term_insight.category_label,
  metrics.clicks, metrics.impressions,
  metrics.conversions, metrics.conversions_value
FROM campaign_search_term_insight
WHERE campaign_search_term_insight.campaign_id = '<pmax_campaign_id>'
  AND segments.date DURING LAST_30_DAYS
ORDER BY metrics.clicks DESC
```

`category_label` is Google's clustered theme (e.g. "yamazumi software",
"line balancing tools") rather than the raw query — PMax doesn't expose
individual queries in the API. Loop over each PMax campaign separately;
audit-level analysis aggregates across runs.

PMax search-term mining is currently limited to *category-level*
exclusions via account-level negative keyword lists; per-PMax-campaign
negatives are not supported (Google's design). The audit surfaces
high-spend underperforming categories; mutation is left to the
operator's manual judgment until brand-list / negative-keyword-list
workflows land in v2.

## Geographic performance (last 30d)

```sql
SELECT
  geographic_view.country_criterion_id,
  geographic_view.location_type,
  campaign.id, campaign.name,
  metrics.cost_micros, metrics.conversions, metrics.clicks, metrics.impressions,
  metrics.conversions_value
FROM geographic_view
WHERE segments.date DURING LAST_30_DAYS
  AND campaign.status = 'ENABLED'
ORDER BY metrics.cost_micros DESC
LIMIT 50
```

Useful for spotting countries/regions that are over- or under-converting
relative to spend. Drives `bid-adjust` proposals (bid up in
high-performing geos, bid down in low-performing ones).

## Device performance (last 30d)

```sql
SELECT
  segments.device,
  campaign.id, campaign.name,
  metrics.cost_micros, metrics.conversions, metrics.clicks, metrics.impressions,
  metrics.conversions_value
FROM campaign
WHERE segments.date DURING LAST_30_DAYS
  AND campaign.status = 'ENABLED'
ORDER BY campaign.id, segments.device
```

`segments.device` ∈ `MOBILE`, `TABLET`, `DESKTOP`, `OTHER`,
`CONNECTED_TV`. Compare CPA per device per campaign. Often mobile
converts at a different rate than desktop — drives `bid-adjust` mobile
modifiers.

## Quality score history (last 30d)

```sql
SELECT
  ad_group_criterion.criterion_id,
  ad_group_criterion.keyword.text, ad_group_criterion.keyword.match_type,
  ad_group_criterion.quality_info.quality_score,
  ad_group_criterion.quality_info.creative_quality_score,
  ad_group_criterion.quality_info.search_predicted_ctr,
  ad_group_criterion.quality_info.post_click_quality_score,
  metrics.cost_micros, metrics.impressions, metrics.conversions
FROM keyword_view
WHERE segments.date DURING LAST_30_DAYS
  AND ad_group_criterion.status = 'ENABLED'
  AND ad_group.status = 'ENABLED'
  AND campaign.status = 'ENABLED'
ORDER BY ad_group_criterion.quality_info.quality_score ASC, metrics.cost_micros DESC
```

`quality_score` is 1-10. The three sub-components (`creative_quality_score`,
`search_predicted_ctr`, `post_click_quality_score`) are returned as
enums (`BELOW_AVERAGE`, `AVERAGE`, `ABOVE_AVERAGE`). Low scores ←→
underlying issues:

| Component                    | If low, look at                        |
|---|---|
| `creative_quality_score`     | RSA assets — apply `creative-management` |
| `search_predicted_ctr`       | keyword/ad alignment — possibly `keyword-pause` or restructure |
| `post_click_quality_score`   | landing page experience — out of plugin scope |

Sort by quality score ASC + cost DESC to surface high-spend, low-quality
keywords first — those are the highest-leverage candidates.

## Auction insights (last 30d)

```sql
SELECT
  campaign.name,
  ad_group.name,
  metrics.search_impression_share,
  metrics.search_top_impression_share,
  metrics.search_absolute_top_impression_share,
  metrics.search_rank_lost_impression_share,
  metrics.search_budget_lost_impression_share
FROM campaign
WHERE segments.date DURING LAST_30_DAYS
  AND campaign.status = 'ENABLED'
ORDER BY metrics.search_impression_share ASC
```

Five impression-share metrics tell different stories:

| Metric                                       | Meaning                                                          |
|---|---|
| `search_impression_share`                    | % of available impressions you got                                |
| `search_top_impression_share`                | % of *top-half* impressions you got                              |
| `search_absolute_top_impression_share`       | % of *absolute-top-of-page* impressions you got                  |
| `search_rank_lost_impression_share`          | % missed because Ad Rank was insufficient (rivals outranked you) |
| `search_budget_lost_impression_share`        | % missed because your daily budget ran out                        |

Drives different decisions: high `rank_lost` → `keyword-pause` weak terms or improve creative; high `budget_lost` → `budget` increase if CPA is acceptable.

For competitor-domain comparison (who you're showing alongside):

```sql
SELECT
  campaign.name,
  metrics.search_impression_share,
  metrics.search_outranking_share,
  metrics.search_top_impression_share
FROM campaign
WHERE segments.date DURING LAST_30_DAYS
ORDER BY metrics.search_impression_share DESC
```

(`auction_insight_domain` is the resource for full per-competitor
breakdowns; field availability varies by API version. If queries against
it return `INVALID_FIELD`, fall back to the metrics above.)

## Audience performance (last 30d)

```sql
SELECT
  ad_group.name,
  ad_group_criterion.audience.audience,
  ad_group_criterion.criterion_id,
  metrics.cost_micros, metrics.conversions, metrics.impressions, metrics.clicks
FROM ad_group_audience_view
WHERE segments.date DURING LAST_30_DAYS
ORDER BY metrics.cost_micros DESC
```

Reports performance per attached audience (in-market, custom, remarketing,
Customer Match). Drives `bid-adjust` proposals on audience criteria —
bid up audiences that convert above target; bid down or detach those
that don't.

## Existing bid modifiers (for cumulative-effect computation)

Before drafting a new `bid-adjust`, query existing modifiers on the
target campaign so the `change-execution/examples/bid-adjust.md`
worked example can compute and surface the cumulative multiplier.

```sql
SELECT
  campaign.id, campaign.name,
  campaign_criterion.criterion_id,
  campaign_criterion.type,
  campaign_criterion.bid_modifier,
  campaign_criterion.device.type,
  campaign_criterion.location.geo_target_constant,
  campaign_criterion.ad_schedule.day_of_week,
  campaign_criterion.ad_schedule.start_hour,
  campaign_criterion.ad_schedule.end_hour
FROM campaign_criterion
WHERE campaign_criterion.bid_modifier IS NOT NULL
  AND campaign_criterion.status = 'ENABLED'
  AND campaign.status = 'ENABLED'
ORDER BY campaign.id, campaign_criterion.type
```

Compute cumulative for any (campaign, query intent) cell as the product
of all matching modifiers. Cap proposals at cumulative ±50%.

## Day-of-week historical baseline (for pacing)

Pacing in `budget-management` is more accurate when the expected daily
spend is weighted by historical day-of-week share rather than flat
`daily × elapsed`. Pull the last 60 days segmented by day-of-week:

```sql
SELECT
  campaign.id, campaign.name,
  segments.day_of_week,
  metrics.cost_micros
FROM campaign
WHERE segments.date DURING LAST_60_DAYS
  AND campaign.status = 'ENABLED'
```

Then for each campaign, compute the seven-day weight vector
`w_dow = SUM(cost_dow) / SUM(cost_all)` (sums to 1.0). Expected
spend by day-X-of-month = `monthly_budget × Σ(w_dow over days 1..X)`
where the day-of-week series is materialized for the calendar.
Replaces the flat `daily × days_elapsed` approximation in
`budget-management`.

## Ad-strength (campaign creative health)

Pair `ad_group_ad.ad_strength` with the per-asset `performance_label`
from "Responsive search ad asset performance" for the holistic view:

```sql
SELECT
  campaign.id, campaign.name,
  ad_group.id, ad_group.name,
  ad_group_ad.ad.id, ad_group_ad.ad.name,
  ad_group_ad.ad_strength, ad_group_ad.status,
  metrics.cost_micros, metrics.conversions, metrics.clicks, metrics.impressions
FROM ad_group_ad
WHERE segments.date DURING LAST_30_DAYS
  AND campaign.status = 'ENABLED'
  AND ad_group.status = 'ENABLED'
  AND ad_group_ad.status = 'ENABLED'
ORDER BY metrics.cost_micros DESC
```

`ad_strength` enum: `PENDING`, `NO_ADS`, `POOR`, `AVERAGE`, `GOOD`,
`EXCELLENT`. Flag any high-spend ad with `POOR` or `AVERAGE` —
`creative-management` then drills into specific LOW assets.

## Asset extension coverage (sitelinks / callouts / structured snippets)

RSAs without ≥ 4 attached sitelinks lose roughly 10–15% CTR vs ones
with them. Pull per-campaign extension counts:

```sql
SELECT
  campaign.id, campaign.name,
  campaign_asset.asset, campaign_asset.field_type, campaign_asset.status
FROM campaign_asset
WHERE campaign.status = 'ENABLED'
  AND campaign_asset.status = 'ENABLED'
  AND campaign_asset.field_type IN ('SITELINK', 'CALLOUT', 'STRUCTURED_SNIPPET')
```

Aggregate by `(campaign_id, field_type)`. Pair with account-level
extensions on `customer_asset` so the audit doesn't flag a campaign
whose extensions are inherited from the account:

```sql
SELECT
  customer_asset.asset, customer_asset.field_type, customer_asset.status
FROM customer_asset
WHERE customer_asset.status = 'ENABLED'
  AND customer_asset.field_type IN ('SITELINK', 'CALLOUT', 'STRUCTURED_SNIPPET')
```

Effective coverage per campaign = campaign-level + customer-level.
Flag 🟡 if effective `SITELINK` count < 4 or `CALLOUT` count < 4 on
any ENABLED Search campaign — drives an `assets-add` + `assets-link`
proposal pair (the existing assets flow).

## Ad group keyword cohesion

Junk-drawer ad groups (one ad group, many themes, dozens of keywords)
break RSA pinning and tank quality score because no single ad copy
can be relevant to all themes simultaneously. Pull keywords per ad
group:

```sql
SELECT
  campaign.id, campaign.name,
  ad_group.id, ad_group.name,
  ad_group_criterion.keyword.text, ad_group_criterion.keyword.match_type
FROM keyword_view
WHERE campaign.status = 'ENABLED'
  AND ad_group.status = 'ENABLED'
  AND ad_group_criterion.status = 'ENABLED'
```

Then per ad group: count keywords, stem each text (strip plural,
possessive, common stop-words), count distinct stem-roots. Healthy
themed ad group = 5–15 keywords sharing 1–2 stem roots. The audit
flags > 15 keywords AND > 2 stem roots as 🟡 (junk drawer). The fix
is a manual ad-group split — out of v1 mutation scope; the audit
surfaces the diagnostic.

## Time-of-day & day-of-week performance (last 30d)

```sql
SELECT
  segments.hour, segments.day_of_week,
  campaign.id, campaign.name,
  metrics.cost_micros, metrics.conversions, metrics.clicks, metrics.impressions
FROM campaign
WHERE segments.date DURING LAST_30_DAYS
  AND campaign.status = 'ENABLED'
```

`segments.hour` is 0-23 (advertiser's account timezone).
`segments.day_of_week` is `MONDAY..SUNDAY`. Use to identify dead hours
(low or zero conversions but real spend) — drives `bid-adjust`
day-parting modifiers.

## Pending Google recommendations

```sql
SELECT
  recommendation.resource_name,
  recommendation.type,
  recommendation.dismissed,
  recommendation.campaign,
  recommendation.impact.base_metrics.cost_micros,
  recommendation.impact.base_metrics.conversions,
  recommendation.impact.potential_metrics.cost_micros,
  recommendation.impact.potential_metrics.conversions
FROM recommendation
WHERE recommendation.dismissed = FALSE
```

`recommendation.type` enumerates what Google is suggesting (e.g.
`SITELINK_ASSET`, `CALLOUT_ASSET`, `KEYWORD`, `CAMPAIGN_BUDGET`,
`TARGET_CPA_OPT_IN`, `SEARCH_PARTNERS_OPT_IN`,
`PERFORMANCE_MAX_OPT_IN`, `MAXIMIZE_CONVERSIONS_OPT_IN`,
`OPTIMIZE_TEXT_AD_AND_RSAS`, `KEYWORD_MATCH_TYPE`, `CUSTOMER_MATCH`).
The `/google-ads-copilot:recommendations` command maps each type to a
plugin mutation kind.

`recommendation.impact.potential_metrics.cost_micros` minus
`recommendation.impact.base_metrics.cost_micros` is the projected € lift
(in micros). Divide by `1_000_000`.

## How to call from the agent

```
"${CLAUDE_PLUGIN_ROOT}/bin/ga" query "SELECT campaign.id, campaign.name FROM campaign WHERE campaign.status = 'ENABLED'"
```

Returns a JSON array. Parse with `jq` or in-context.

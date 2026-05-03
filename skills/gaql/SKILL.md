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
  AND metrics.impressions > 100
  AND metrics.conversions < 1
ORDER BY metrics.cost_micros DESC
```

The `> 100` impression floor matches the threshold `search-term-mining`
applies when classifying high-spend-zero-conv candidates — keeping the
retrieval and the action threshold aligned avoids surfacing rows that
mining will silently drop.

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
| Branded CPA | < 30% of non-branded CPA |
| Branded impression share | ≥ 90% (you should be dominating your own brand SERP) |

🔴 if branded impression share < 70% — competitors are stealing cheap
brand-search conv. Recommend a dedicated brand campaign (out of v1
mutation scope, but flag in the audit).

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

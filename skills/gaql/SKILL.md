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

## Conversion actions

```sql
SELECT
  conversion_action.id, conversion_action.name,
  conversion_action.status, conversion_action.category,
  conversion_action.primary_for_goal
FROM conversion_action
WHERE conversion_action.status != 'REMOVED'
```

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

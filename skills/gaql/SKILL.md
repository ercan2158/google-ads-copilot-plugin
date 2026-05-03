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
  AND metrics.impressions > 50
  AND metrics.conversions < 1
ORDER BY metrics.cost_micros DESC
```

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

## How to call from the agent

```
"${CLAUDE_PLUGIN_ROOT}/bin/ga" query "SELECT campaign.id, campaign.name FROM campaign WHERE campaign.status = 'ENABLED'"
```

Returns a JSON array. Parse with `jq` or in-context.

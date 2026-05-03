# Example: Keyword add / pause (kinds = keyword-add, keyword-pause)

The plugin manages keywords through the `adGroupCriteria:mutate`
endpoint with the `KEYWORD` criterion type. Two kinds:

- `keyword-add` — promote a converting search term into a positive keyword
- `keyword-pause` — pause a keyword that consistently underperforms

## When to draft a keyword-add proposal

The inverse of `search-term-mining`'s negative-keyword direction. Pull
the same query (last 30d search terms with low/no conversion) but flip
the threshold:

```sql
-- Last 30d search terms WITH conversion
SELECT
  campaign.id, campaign.name,
  ad_group.id, ad_group.name,
  search_term_view.search_term,
  metrics.clicks, metrics.cost_micros, metrics.conversions
FROM search_term_view
WHERE segments.date DURING LAST_30_DAYS
  AND metrics.conversions >= 3
ORDER BY metrics.conversions DESC
```

For each term:
- **Already a keyword?** Cross-check against the campaign's existing
  keywords. If yes, skip — it's already firing.
- **Off-ICP?** Same check as `search-term-mining`. If the converting term
  is off-ICP (e.g. someone bought who isn't your ICP, low LTV expected),
  don't promote.
- **Promote?** ≥ 3 conversions over 30d AND on-ICP AND not yet a keyword
  → propose as `KEYWORD` with PHRASE match (default), bid set to the
  ad group's existing default CPC.

## Proposal: keyword-add

`workspace/proposals/2026-05-03-keyword-add-01.md`

```json
{
  "proposal_id": "2026-05-03-keyword-add-01",
  "kind": "keyword-add",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/adGroupCriteria:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "adGroup": "customers/8191097521/adGroups/<ad_group_id>",
        "status": "ENABLED",
        "keyword": {
          "text": "line balancing software",
          "matchType": "PHRASE"
        },
        "cpcBidMicros": 1500000
      }
    }
  ],
  "metadata": {
    "from_search_term": "line balancing software",
    "conversions_observed_30d": 4,
    "default_match_type_choice": "PHRASE (broader than EXACT, narrower than BROAD)"
  }
}
```

`cpcBidMicros: 1500000` = €1.50 max CPC. Use the ad group's existing
default if known (read via gaql `ad_group.cpc_bid_micros`).

## When to draft a keyword-pause proposal

Pull current keywords with their 30d performance:

```sql
SELECT
  ad_group_criterion.criterion_id,
  ad_group_criterion.keyword.text, ad_group_criterion.keyword.match_type,
  ad_group_criterion.status,
  metrics.cost_micros, metrics.conversions, metrics.clicks
FROM keyword_view
WHERE segments.date DURING LAST_30_DAYS
  AND ad_group_criterion.status = 'ENABLED'
  AND ad_group.status = 'ENABLED'
  AND campaign.status = 'ENABLED'
ORDER BY metrics.cost_micros DESC
```

Pause heuristic:
- Spend ≥ €X (where X = max(€10, daily_budget × 0.10)) AND
- 0 conversions over the last 60 days AND
- ≥ 100 impressions over those 60 days (otherwise insufficient signal)

## Proposal: keyword-pause

`workspace/proposals/2026-05-03-keyword-pause-01.md`

```json
{
  "proposal_id": "2026-05-03-keyword-pause-01",
  "kind": "keyword-pause",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/adGroupCriteria:mutate",
  "validate_first": true,
  "operations": [
    {
      "update": {
        "resourceName": "customers/8191097521/adGroupCriteria/<ad_group_id>~<criterion_id>",
        "status": "PAUSED"
      },
      "updateMask": "status"
    }
  ],
  "metadata": {
    "keyword_text": "manufacturing analytics tool",
    "spend_60d_eur": 47,
    "conversions_60d": 0,
    "impressions_60d": 312
  }
}
```

The `resourceName` for `adGroupCriteria` is
`customers/<id>/adGroupCriteria/<adGroupId>~<criterionId>`. Get it from
the keyword query above.

## Cap

- `keyword-add`: max 10 promotions per proposal. More than that, draft
  multiple proposals or note in the rationale why a batch is sensible.
- `keyword-pause`: max 25 pauses per proposal. Pausing many at once
  changes match coverage; risk should be reflected in TL;DR.

## Inverse for /undo

- `keyword-add` → `remove` op against the created `adGroupCriterion`
  resource name (read from the change-log).
- `keyword-pause` → `update` op setting `status: ENABLED` and
  `updateMask: status` against the same resource name.

# Example: Apply / dismiss a Google recommendation

When `/google-ads-copilot:recommendations` evaluates a Google rec, it
maps the rec's `type` to a plugin kind. Most asset recs map to
`assets-add` + `assets-link` (operator drafts their own copy, see
[`assets-flow.md`](assets-flow.md)). For recs the operator wants to
accept Google's auto-generated content as-is, the simpler path is the
native `recommendations:apply` endpoint.

## Apply Google's auto-content (kind = `recommendation-apply`)

`workspace/proposals/2026-05-03-recommendation-apply-01.md`

````markdown
# Accept Google's callout recommendation — 2026-05-03

## TL;DR

Google suggested 4 callouts based on our landing-page text. They align
with our positioning ("no setup fee", "14-day pilot", "browser-based",
"Toyota suppliers"). Accepting as-is — they match the
context/product-positioning.md value props.

## Executable

```json
{
  "proposal_id": "2026-05-03-recommendation-apply-01",
  "kind": "recommendation-apply",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/recommendations:apply",
  "validate_first": false,
  "operations": [
    {
      "resourceName": "customers/8191097521/recommendations/<rec_id>",
      "calloutAsset": {
        "calloutAssets": [
          { "calloutAsset": { "calloutText": "No setup fee" } },
          { "calloutAsset": { "calloutText": "14-day pilot" } },
          { "calloutAsset": { "calloutText": "Browser-based, no install" } },
          { "calloutAsset": { "calloutText": "Used by Toyota suppliers" } }
        ]
      }
    }
  ],
  "metadata": {
    "recommendation_type": "CALLOUT_ASSET",
    "expected_impact_pct": 2.4,
    "operator_review": "These callouts align with our 'no friction' positioning. Accepting as-is."
  }
}
```
````

## Important: no validate_only

`recommendations:apply` does **not** accept `validateOnly`. Setting
`validate_first: false` tells the apply contract to skip the dry-run for
this kind. Surface the irreversibility explicitly in the proposal's
TL;DR — this gate is about the operator knowing what's happening.

## API-version note on parameter shapes

The `<type>` field name on each operation (e.g. `calloutAsset` above)
must match Google's current `ApplyRecommendationOperation` schema for
the API version in use. Field names have shifted across versions —
some past versions used names like `callExtension` vs `callAsset`,
`textAd` vs `responsiveSearchAd`. Verify the exact field name for your
target version:

> https://developers.google.com/google-ads/api/reference/rpc/v23/ApplyRecommendationOperation

If a proposal returns `INVALID_FIELD` or `UNKNOWN_FIELD`, swap the
operation's parameter field name to the schema's variant for the
recommendation type. The plugin doesn't auto-correct.

## The applyParameters shape

Each recommendation type has its own `<type>Parameters` field. Common ones:

| recommendation.type           | applyParameters field           |
|---|---|
| `CALLOUT_ASSET`               | `calloutAsset`                   |
| `SITELINK_ASSET`              | `sitelinkAsset`                  |
| `STRUCTURED_SNIPPET_ASSET`    | `structuredSnippetAsset`         |
| `CALL_ASSET`                  | `callAsset`                      |
| `KEYWORD`                     | `keyword`                        |
| `RESPONSIVE_SEARCH_AD`        | `responsiveSearchAd`             |
| `CAMPAIGN_BUDGET`             | `campaignBudget`                 |
| `TARGET_CPA_OPT_IN`           | `targetCpaOptIn`                 |
| `TARGET_ROAS_OPT_IN`          | `targetRoasOptIn`                |
| `MAXIMIZE_CONVERSIONS_OPT_IN` | `maximizeConversionsOptIn`       |
| `KEYWORD_MATCH_TYPE`          | `keywordMatchType`               |

If a parameters field is absent, Google applies the recommendation as
suggested (no operator override). Many extension recs work this way.

## Dismiss a rec (kind = `recommendation-dismiss`)

When the operator decides a rec doesn't fit and wants to stop seeing it:

````markdown
# Dismiss SEARCH_PARTNERS_OPT_IN rec — 2026-05-03

## TL;DR

Google keeps recommending Search Partners opt-in. At our budget level
(~€12/day) and with the audience-quality variance Search Partners brings,
this dilutes spend without proven lift. Dismissing.

## Executable

```json
{
  "proposal_id": "2026-05-03-recommendation-dismiss-01",
  "kind": "recommendation-dismiss",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/recommendations:dismiss",
  "validate_first": false,
  "operations": [
    { "resourceName": "customers/8191097521/recommendations/<rec_id>" }
  ]
}
```
````

Dismissing makes the rec stop appearing in the dashboard until Google
re-surfaces it (typically when conditions change).

## Inverse for /undo

- `recommendation-apply` → **non-invertible**. Google's apply may have
  spawned downstream entities (assets, links, criteria). The plugin's
  `/undo` refuses; the operator must manually unwind via the dashboard
  or by drafting `assets-unlink`/`keyword-pause`/etc. proposals against
  the spawned entities (which are visible in the change-log response).
- `recommendation-dismiss` → invertible. There's no native "undismiss",
  but the rec will resurface naturally when conditions warrant.

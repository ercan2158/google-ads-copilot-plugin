# Example: PMax asset-group creative refresh

A worked example for refreshing creative on a PMax asset group flagged
as POOR or AVERAGE ad_strength. Two-step paired flow: create asset
entities (`assets-add`), then link them into the asset group
(`asset-group-asset-link`).

The pattern is identical to Search RSAs (`assets-add` →
`assets-link`/`customerAssets:mutate`), but the *link target* differs:
- Search RSA: `customerAssets:mutate` or `campaignAssets:mutate`
- PMax asset group: `assetGroupAssets:mutate`

## When to draft this flow

`pmax` skill check #1 surfaces a 🟡:

```
Asset group "ICP — manufacturing engineers" on campaign "PMax-Lead":
  ad_strength: POOR
  primary_status: LIMITED
  primary_status_reasons: [BUSINESS_NAME_REQUIRED, ASSET_GROUP_HEADLINES_NOT_ELIGIBLE]
  Headline count: 3 (Google's required minimum: 5; recommended: 15)
  Description count: 2 (Google's required minimum: 4)
```

The fix is asset-pool expansion: add 2+ headlines and 2+ descriptions
that match the asset group's theme.

## PMax asset count floors (Google's required minimums)

| Field type | Required | Recommended | Plugin floor |
|---|---|---|---|
| HEADLINE (≤ 30 chars) | 3 | 15 | ≥ 5 to clear LIMITED |
| LONG_HEADLINE (≤ 90 chars) | 1 | 5 | ≥ 1 |
| DESCRIPTION (≤ 90 chars) | 2 | 4 | ≥ 4 to clear LIMITED |
| BUSINESS_NAME | 1 | 1 | ≥ 1 (required to serve) |
| MARKETING_IMAGE (1200×628 or similar) | 1 | 4 | ≥ 4 to clear LIMITED |
| SQUARE_MARKETING_IMAGE (1200×1200) | 1 | 4 | ≥ 1 |
| LOGO (1200×1200) | 1 | 5 | ≥ 1 |
| LANDSCAPE_LOGO (1200×300) | 0 | 5 | ≥ 1 if logo set |
| YOUTUBE_VIDEO | 0 (auto-generated if absent) | 1 | ≥ 1 to avoid auto-gen branding miss |
| CALL_TO_ACTION_SELECTION | 0 (defaults) | 1 | n/a |

The plugin drafts to the "Plugin floor" column — enough to clear
LIMITED status without forcing the operator into a 30-asset
shopping-list proposal.

## Proposal A: create the new asset entities

`workspace/proposals/2026-05-04-assets-add-01a.md`

Reuses the existing `assets-add` kind. Each headline / description is
its own asset entity at the customer level (assets are pooled per
customer; the `assetGroupAssets:mutate` link in proposal B is what
makes them serve under a specific PMax asset group).

````markdown
# Refresh PMax asset group "ICP — manufacturing engineers" — 2026-05-04

## TL;DR

Asset group is POOR / LIMITED with 3 headlines + 2 descriptions —
below Google's 5-headline / 4-description floors. Adding 3 headlines
and 2 descriptions aligned to the manufacturing-engineer ICP from
context/icp.md. Risk: low — additive only; nothing existing is
removed.

## Per-item rationale

- Each new headline is concrete + outcome-focused, matching the
  GOOD/BEST patterns in the existing asset group's BEST tier.
- No two headlines start with the same word (Google penalizes).
- Tone matches the existing positioning per
  `context/product-positioning.md`.

## Expected impact

- Clear LIMITED → READY status (Google needs ≥5 headlines and ≥4
  descriptions to serve). Should ship within 24h of apply.
- ad_strength likely to lift POOR → AVERAGE on next refresh; reaching
  GOOD requires the operator to also add the missing image/video
  assets (out of this proposal — image upload is a separate flow).

## Executable

```json
{
  "proposal_id": "2026-05-04-assets-add-01a",
  "kind": "assets-add",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/assets:mutate",
  "validate_first": true,
  "operations": [
    { "create": { "name": "PMax HL — Cut Cycle Time 18% in 90 Days",
                  "textAsset": { "text": "Cut Cycle Time 18% in 90 Days" } } },
    { "create": { "name": "PMax HL — Stop Balancing Lines in Excel",
                  "textAsset": { "text": "Stop Balancing Lines in Excel" } } },
    { "create": { "name": "PMax HL — Used by Toyota Suppliers",
                  "textAsset": { "text": "Used by Toyota Suppliers" } } },
    { "create": { "name": "PMax DESC — Industrial engineers cut takt-time variance in days",
                  "textAsset": { "text": "Industrial engineers cut takt-time variance in days. Free 14-day pilot, no setup fee." } } },
    { "create": { "name": "PMax DESC — Math, not guesswork",
                  "textAsset": { "text": "Math, not guesswork. Replace your line-balancing spreadsheets with software designed for plants." } } }
  ],
  "metadata": {
    "step": "1-of-2",
    "next_proposal": "2026-05-04-asset-group-asset-link-01b",
    "asset_group_resource": "customers/8191097521/assetGroups/<asset_group_id>",
    "for_pmax_campaign": "customers/8191097521/campaigns/<pmax_campaign_id>"
  }
}
```
````

## Proposal B: link the assets to the asset group

`workspace/proposals/2026-05-04-asset-group-asset-link-01b.md`

One link operation per (asset, fieldType) pairing. The fieldType for
the first three is HEADLINE; the last two are DESCRIPTION.

````markdown
## Executable

```json
{
  "proposal_id": "2026-05-04-asset-group-asset-link-01b",
  "kind": "asset-group-asset-link",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/assetGroupAssets:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "assetGroup": "customers/8191097521/assetGroups/<asset_group_id>",
        "asset": "<resourceName from proposal 2026-05-04-assets-add-01a op 1>",
        "fieldType": "HEADLINE"
      }
    },
    {
      "create": {
        "assetGroup": "customers/8191097521/assetGroups/<asset_group_id>",
        "asset": "<resourceName from proposal 2026-05-04-assets-add-01a op 2>",
        "fieldType": "HEADLINE"
      }
    },
    {
      "create": {
        "assetGroup": "customers/8191097521/assetGroups/<asset_group_id>",
        "asset": "<resourceName from proposal 2026-05-04-assets-add-01a op 3>",
        "fieldType": "HEADLINE"
      }
    },
    {
      "create": {
        "assetGroup": "customers/8191097521/assetGroups/<asset_group_id>",
        "asset": "<resourceName from proposal 2026-05-04-assets-add-01a op 4>",
        "fieldType": "DESCRIPTION"
      }
    },
    {
      "create": {
        "assetGroup": "customers/8191097521/assetGroups/<asset_group_id>",
        "asset": "<resourceName from proposal 2026-05-04-assets-add-01a op 5>",
        "fieldType": "DESCRIPTION"
      }
    }
  ],
  "metadata": {
    "step": "2-of-2",
    "depends_on": "2026-05-04-assets-add-01a"
  }
}
```
````

`bin/apply` resolves the placeholders from the change-log entry of
proposal A. Apply order:

```bash
/google-ads-copilot:apply 2026-05-04-assets-add-01a
/google-ads-copilot:apply 2026-05-04-asset-group-asset-link-01b
```

## Variations

- **Image / video assets** — change `textAsset` in proposal A to
  `imageAsset: {data: "<base64>"}` or `youtubeVideoAsset: {youtubeVideoId: "<id>"}`,
  and `fieldType` in proposal B to `MARKETING_IMAGE` /
  `SQUARE_MARKETING_IMAGE` / `YOUTUBE_VIDEO` accordingly.
  Image constraints: ≤ 5120 KB, specific aspect ratios per fieldType.
- **Long headlines** — `textAsset.text` up to 90 chars; `fieldType: LONG_HEADLINE`.
- **Business name / call-to-action** — single-instance assets;
  `fieldType: BUSINESS_NAME` or `CALL_TO_ACTION_SELECTION`.

## Removing an asset from an asset group

Use `asset-group-asset-unlink` against the link's resource_name.
The asset entity itself stays (it might be linked to other asset
groups). To delete the asset entity afterwards, use `assets-add`'s
inverse pattern (`assets:mutate` with `remove` op) — only if the
asset is orphaned.

## Inverse for /undo

- `assets-add` → `remove` op against each created asset (with the
  cascade-aware warning if any are linked elsewhere).
- `asset-group-asset-link` → `asset-group-asset-unlink` against each
  link resource_name from the original response.

For "undo the whole refresh", run `/undo` on B then A in reverse apply
order.

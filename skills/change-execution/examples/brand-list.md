# Example: PMax brand list (create + attach)

A worked example for creating a brand exclusion list and attaching it
to PMax campaigns. Two-step paired flow:

1. `brand-list-create` — creates an `assetSet` of `type: BRAND_LIST`
   and populates it with brand assets (one per brand to exclude or
   include, depending on the brand-list mode).
2. `brand-list-attach` — links the asset set to one or more PMax
   campaigns via `campaignAssetSets:mutate`.

Both proposals carry `confirmation_required: "explicit_yes"` —
brand-list misconfiguration affects every attached PMax campaign and
brand misclassification is hard to detect from inside the dashboard.

## API version note

Brand lists were stabilized in mid-2024. Field availability varies by
API version:
- v23+: `assetSets:mutate` with `type: BRAND_LIST` is supported
- earlier versions used `brand_guidelines` — schema differs

If a `brand-list-create` proposal returns `INVALID_FIELD` on
`assetSets:mutate`, the operator's API version doesn't support this
kind yet — fall back to the dashboard. Surface this in the proposal's
TL;DR before the operator approves the explicit_yes confirmation.

## When to draft this flow

Operator-initiated only — the `pmax` skill audit surfaces the
recommendation but doesn't auto-draft (brand-list is one of the
high-blast-radius kinds where the operator decides). Typical trigger:

- PMax campaign showing impressions on competitor-brand queries via
  `campaign_search_term_insight.category_label` clusters that contain
  competitor brand terms
- Operator wants to enforce "only show on our brand, never on
  competitor brands" — set the brand list to `EXCLUDED` mode
- Or: SMB managing multiple PMax campaigns and wants to constrain
  which brands they advertise for (legal / partnership reasons)

## Proposal A: create the asset set + populate

`workspace/proposals/2026-05-04-brand-list-create-01a.md`

````markdown
# Create competitor-brand exclusion list — 2026-05-04

## ⚠️ HIGH BLAST RADIUS

This proposal carries `confirmation_required: explicit_yes`. Apply
will require retyping the proposal_id to confirm.

## TL;DR

Create a BRAND_LIST asset set named "Competitor exclusions" with 4
competitor brands (Acme Corp, Beta Inc, Gamma LLC, Delta Co). Mode:
EXCLUDED — PMax will avoid serving on these brand-related queries
and audiences once the list is attached (proposal B).

## Per-item rationale

- Competitor brands sourced from `context/product-positioning.md`
  ("brands we don't bid on" section)
- EXCLUDED mode (vs INCLUDED): PMax serves on everything EXCEPT
  these brands. Inverse mode (INCLUDED) would limit serving to
  ONLY these brands — wrong fit for our use case.

## Risk

- High-blast: once attached (proposal B), affects every linked PMax
  campaign immediately
- Brand misclassification: if our own brand is accidentally listed,
  we exclude ourselves — verify the list before applying
- API version sensitivity: if the underlying API path returns
  INVALID_FIELD, this proposal fails the dry-run cleanly without
  shipping anything

## Executable

```json
{
  "proposal_id": "2026-05-04-brand-list-create-01a",
  "kind": "brand-list-create",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/assetSets:mutate",
  "validate_first": true,
  "confirmation_required": "explicit_yes",
  "operations": [
    {
      "create": {
        "name": "Competitor exclusions",
        "type": "BRAND_LIST"
      }
    }
  ],
  "metadata": {
    "step": "1-of-3",
    "next_proposal": "2026-05-04-brand-list-populate-01b",
    "from_positioning": "context/product-positioning.md \"brands we don't bid on\"",
    "mode": "EXCLUDED",
    "brand_count": 4
  }
}
```
````

## Proposal B: populate with brand assets

`workspace/proposals/2026-05-04-brand-list-populate-01b.md`

Each brand is an `asset` of type `BRAND` linked to the asset set via
`assetSetAsset:mutate`. The brand asset itself carries the brand's
domain + display name; multiple campaigns can reference the same
brand asset across different lists.

````markdown
## Executable

```json
{
  "proposal_id": "2026-05-04-brand-list-populate-01b",
  "kind": "brand-list-create",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/assetSetAssets:mutate",
  "validate_first": true,
  "confirmation_required": "explicit_yes",
  "operations": [
    {
      "create": {
        "assetSet": "<resourceName from proposal 2026-05-04-brand-list-create-01a op 1>",
        "asset": "<brand asset resourceName — see brand-asset-create flow>"
      }
    }
  ],
  "metadata": {
    "step": "2-of-3",
    "depends_on": "2026-05-04-brand-list-create-01a",
    "note": "brand assets must already exist; create via assets:mutate with brandAsset before this step"
  }
}
```
````

**Note**: brand assets (the brand entities themselves — domain +
display name pairs) are usually created from Google's curated
brand catalog rather than from scratch. Check
`brand_suggestion:suggestBrands` first to find the canonical brand
asset ID before creating a custom one. Custom brand assets are
allowed but require approval (24-72h) before they take effect.

## Proposal C: attach to PMax campaign(s)

`workspace/proposals/2026-05-04-brand-list-attach-01c.md`

````markdown
## Executable

```json
{
  "proposal_id": "2026-05-04-brand-list-attach-01c",
  "kind": "brand-list-attach",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/campaignAssetSets:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/<pmax_campaign_id>",
        "assetSet": "<resourceName from proposal 2026-05-04-brand-list-create-01a op 1>"
      }
    }
  ],
  "metadata": {
    "step": "3-of-3",
    "depends_on": "2026-05-04-brand-list-create-01a"
  }
}
```
````

## Apply order

```bash
/google-ads-copilot:apply 2026-05-04-brand-list-create-01a   # explicit_yes prompt
/google-ads-copilot:apply 2026-05-04-brand-list-populate-01b # explicit_yes prompt
/google-ads-copilot:apply 2026-05-04-brand-list-attach-01c   # standard y/n
```

The first two require the operator to retype the proposal_id at
apply time (high-blast envelope flag). The attach step is standard
y/n.

## Inverse for /undo

- `brand-list-create` (the asset set) → `remove` op on
  `assetSets:mutate`. **Cascades** through every assetSetAsset and
  every campaignAssetSet link. If campaigns are still attached,
  draft a paired `brand-list-attach` `remove` (detach) proposal first.
- `brand-list-attach` → `remove` op on `campaignAssetSets:mutate`
  against the link resource_name. The asset set itself stays.

## When NOT to use this flow

- Account has only one PMax campaign and operator only wants to
  exclude one or two brands → `customer-negative-criterion-add` with
  the competitor brand terms is simpler. Brand lists are worth the
  multi-step ceremony when there are 5+ brands across 2+ PMax
  campaigns.
- The brand list is for "include only my brand" enforcement (vs
  exclude competitors) — verify the operator actually wants this;
  most B2B SaaS gets more conv volume from being broader, not
  narrower.

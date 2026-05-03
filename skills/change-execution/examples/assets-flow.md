# Example: Adding sitelinks (the assets-add + assets-link flow)

A worked example showing how to add 6 sitelinks to a customer (account-wide)
as a paired proposal. The same flow applies to **callouts**
(`CALLOUT_ASSET`), **structured snippets** (`STRUCTURED_SNIPPET_ASSET`),
**images** (`IMAGE_ASSET`), and **call assets** (`CALL_ASSET`) — change
the asset payload and the field type when linking.

## Why a paired proposal

Sitelinks (and most ad extensions) are split across two Google Ads endpoints:

1. `assets:mutate` — create the asset *entity* (the sitelink, callout, etc.)
2. `customerAssets:mutate` (account-wide) or `campaignAssets:mutate`
   (campaign-scoped) — *link* the asset to where it should serve

So the agent drafts two proposals and the operator applies them in order.
The link proposal references resource names returned by the create proposal.

## Proposal A: create the sitelinks

`workspace/proposals/2026-05-03-assets-add-01a-create.md`

````markdown
# Add 6 sitelinks — 2026-05-03

## TL;DR

Adding 6 sitelinks aligned to our pricing/customers/features pages.
Expected lift +2.9% per Google's recommendation. Risk low — sitelinks
are additive, no existing asset is touched.

## Executable

```json
{
  "proposal_id": "2026-05-03-assets-add-01a-create",
  "kind": "assets-add",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/assets:mutate",
  "validate_first": true,
  "operations": [
    { "create": {
        "name": "Sitelink: See pricing",
        "sitelinkAsset": {
          "linkText": "See pricing",
          "description1": "Browser-based, no install",
          "description2": "Free 14-day pilot, no setup fee"
        },
        "finalUrls": ["https://yamazumi.io/pricing"]
    } },
    { "create": { "name": "Sitelink: Customer stories", "sitelinkAsset": { "linkText": "Customer stories", "description1": "Used by Toyota suppliers", "description2": "Real plant case studies" }, "finalUrls": ["https://yamazumi.io/customers"] } },
    { "create": { "name": "Sitelink: Try for free", "sitelinkAsset": { "linkText": "Try for free", "description1": "No credit card required", "description2": "14-day full access" }, "finalUrls": ["https://yamazumi.io/signup"] } },
    { "create": { "name": "Sitelink: Yamazumi charts", "sitelinkAsset": { "linkText": "Yamazumi charts", "description1": "Interactive in browser", "description2": "Cycle times at a glance" }, "finalUrls": ["https://yamazumi.io/features/charts"] } },
    { "create": { "name": "Sitelink: Real-time collab", "sitelinkAsset": { "linkText": "Real-time collab", "description1": "Invite your team to edit", "description2": "No back-and-forth on files" }, "finalUrls": ["https://yamazumi.io/features/collaboration"] } },
    { "create": { "name": "Sitelink: Excel & PDF export", "sitelinkAsset": { "linkText": "Excel & PDF export", "description1": "One-click export", "description2": "Share with stakeholders fast" }, "finalUrls": ["https://yamazumi.io/features/export"] } }
  ],
  "metadata": {
    "asset_type": "SITELINK_ASSET",
    "use_in_proposal_b": "2026-05-03-assets-add-01b-link",
    "from_recommendation": "customers/8191097521/recommendations/<rec_id>"
  }
}
```
````

After `/google-ads-copilot:apply 2026-05-03-assets-add-01a-create`, Google
returns 6 resource names. The change-log entry records each one. Capture
them; you'll need them in proposal B.

## Proposal B: link the sitelinks to the customer

`workspace/proposals/2026-05-03-assets-add-01b-link.md`

````markdown
# Link 6 sitelinks to customer — 2026-05-03

## TL;DR

Pairing proposal to the create above. Links the 6 freshly-created
sitelinks to the customer (account-wide) so they can serve under any
campaign that's eligible.

## Executable

```json
{
  "proposal_id": "2026-05-03-assets-add-01b-link",
  "kind": "assets-link",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/customerAssets:mutate",
  "validate_first": true,
  "operations": [
    { "create": { "asset": "<resourceName from proposal A op 1>", "fieldType": "SITELINK" } },
    { "create": { "asset": "<resourceName from proposal A op 2>", "fieldType": "SITELINK" } },
    { "create": { "asset": "<resourceName from proposal A op 3>", "fieldType": "SITELINK" } },
    { "create": { "asset": "<resourceName from proposal A op 4>", "fieldType": "SITELINK" } },
    { "create": { "asset": "<resourceName from proposal A op 5>", "fieldType": "SITELINK" } },
    { "create": { "asset": "<resourceName from proposal A op 6>", "fieldType": "SITELINK" } }
  ],
  "metadata": {
    "depends_on": "2026-05-03-assets-add-01a-create",
    "scope": "customer-wide"
  }
}
```
````

**Before applying B**, replace the `<resourceName from proposal A op N>`
placeholders with the actual resource names returned in proposal A's
response (logged at `workspace/change-log/<date>.jsonl`). The
`/google-ads-copilot:apply` command reads the file you point it at — so
the substitution happens in the file, then apply runs cleanly.

## Apply order

```bash
/google-ads-copilot:apply 2026-05-03-assets-add-01a-create
# → reads the change-log line, copies the 6 resource names into proposal B
/google-ads-copilot:apply 2026-05-03-assets-add-01b-link
```

## Variations

- **Callouts** (`CALLOUT_ASSET`): op uses `calloutAsset: { calloutText: "..." }` (≤25 chars). Field type when linking = `CALLOUT`.
- **Structured snippets** (`STRUCTURED_SNIPPET_ASSET`): op uses `structuredSnippetAsset: { header: "...", values: ["...", ...] }`. The `header` must be from Google's preset list (e.g. "Brands", "Models", "Service catalog", "Features"). Field type = `STRUCTURED_SNIPPET`.
- **Images** (`IMAGE_ASSET`): op uses `imageAsset: { data: "<base64-encoded image bytes>" }`. Field type = `IMAGE`. Constraints: ≤5120 KB, specific aspect ratios.
- **Call assets** (`CALL_ASSET`): op uses `callAsset: { phoneNumber: "...", countryCode: "DE" }`. Field type = `CALL`.
- **Campaign-scoped instead of customer-wide**: in proposal B, change endpoint to `campaignAssets:mutate` and add `"campaign": "customers/<id>/campaigns/<cid>"` to each op's `create`.

## Unlinking (kind = `assets-unlink`)

To remove a sitelink without deleting the asset itself (it might be linked elsewhere too):

```json
{
  "proposal_id": "2026-05-04-assets-unlink-01",
  "kind": "assets-unlink",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/customerAssets:mutate",
  "validate_first": true,
  "operations": [
    { "remove": "customers/8191097521/customerAssets/<asset_id>~SITELINK" }
  ]
}
```

The `customerAssets` resource name encodes the asset ID and the field
type after a tilde. Get it from the original link's response in the
change-log.

## Inverse for /undo

- `assets-add` (asset creation) → inverse is `assets:mutate` `remove`
  ops on the resource names in the change-log entry. **But note**: if the
  asset is also linked elsewhere, removing it cascades. Prefer
  `assets-unlink` first, then optionally `assets:mutate remove` if the
  asset is orphaned.
- `assets-link` → inverse is `assets-unlink` against the customerAsset/
  campaignAsset resource names returned by the link operation.
- `assets-unlink` → inverse is `assets-link` (re-create) with the same
  asset + fieldType.

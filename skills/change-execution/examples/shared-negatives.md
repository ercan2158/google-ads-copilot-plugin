# Example: Shared negative-keyword list (3-step flow)

A worked example for the `negative-list-create` →
`negative-list-add-keyword` → `negative-list-attach` paired-proposal
flow. Use this when the negatives sprawl audit (`account-audit`
Section 4) flags 3+ campaigns sharing the same off-ICP terms in their
per-campaign negatives.

## When to draft this flow

`account-audit` Section 4 surfaces a 🟡 finding like:

```
Negatives sprawl detected: "free", "tutorial", "jobs" each appear
as PHRASE negatives across 4 of your 6 enabled Search campaigns.
Recommendation: migrate to a customer-level shared negative list.
```

Threshold: same `(text, match_type)` in ≥ 3 campaigns AND account
has ≥ 5 ENABLED Search campaigns AND not already in a shared list.

## Why three proposals, not one

Google Ads splits the model across three resources:
- `sharedSets:mutate` — create/remove the named container
- `sharedCriteria:mutate` — add/remove keywords inside
- `campaignSharedSets:mutate` — link/unlink the container to campaigns

The plugin drafts three proposals because each step needs the previous
step's response (the shared_set's `resourceName`) before it can run.
`bin/apply` resolves the placeholders automatically via change-log
lookup — no manual editing between applies.

## Proposal A: create the list

`workspace/proposals/2026-05-04-negative-list-create-01a.md`

````markdown
# Migrate off-ICP negatives to a shared list — 2026-05-04

## TL;DR

Three theme words ("free", "tutorial", "jobs") appear as PHRASE
negatives in 4–5 of our 6 enabled Search campaigns. Migrating to a
single shared list reduces maintenance from "edit 6 campaigns when
adding a new off-ICP term" to "edit one list."

## Per-item rationale

- **off-ICP-shared list** — named "Off-ICP — universal block".
  Risk: low. Empty list initially; keywords added via paired proposal B.
- **Affects all campaigns it gets attached to** (proposal C) — not
  account-wide like a `customer-negative-criterion-add`.

## Expected impact

- Future negative additions: 1 mutation instead of 6.
- ~2-4 hours/quarter saved on sprawl maintenance for an account at
  this scale.

## Executable

```json
{
  "proposal_id": "2026-05-04-negative-list-create-01a",
  "kind": "negative-list-create",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/sharedSets:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "name": "Off-ICP — universal block",
        "type": "NEGATIVE_KEYWORDS"
      }
    }
  ],
  "metadata": {
    "step": "1-of-3",
    "next_proposal": "2026-05-04-negative-list-add-keyword-01b",
    "from_audit_finding": "negatives sprawl on (free, tutorial, jobs) across 4-5 campaigns"
  }
}
```
````

## Proposal B: populate with keywords

`workspace/proposals/2026-05-04-negative-list-add-keyword-01b.md`

References the sharedSet from proposal A via the auto-substituted
placeholder. Each keyword is one operation.

````markdown
## Executable

```json
{
  "proposal_id": "2026-05-04-negative-list-add-keyword-01b",
  "kind": "negative-list-add-keyword",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/sharedCriteria:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>",
        "keyword": { "text": "free", "matchType": "PHRASE" },
        "negative": true
      }
    },
    {
      "create": {
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>",
        "keyword": { "text": "tutorial", "matchType": "PHRASE" },
        "negative": true
      }
    },
    {
      "create": {
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>",
        "keyword": { "text": "jobs", "matchType": "PHRASE" },
        "negative": true
      }
    },
    {
      "create": {
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>",
        "keyword": { "text": "careers", "matchType": "PHRASE" },
        "negative": true
      }
    }
  ],
  "metadata": {
    "step": "2-of-3",
    "depends_on": "2026-05-04-negative-list-create-01a",
    "next_proposal": "2026-05-04-negative-list-attach-01c"
  }
}
```
````

`bin/apply` resolves `<resourceName from proposal X op N>` automatically
from the change-log when it runs proposal B — no manual edit.

## Proposal C: attach to campaigns

`workspace/proposals/2026-05-04-negative-list-attach-01c.md`

One operation per campaign attachment. Pulls the campaign IDs from
the audit findings.

````markdown
## TL;DR

Attach the new shared list to the 5 ENABLED Search campaigns.
"PMax-Brand" is excluded — PMax doesn't accept campaign-level shared
sets (use `customer-negative-criterion-add` for PMax).

## Executable

```json
{
  "proposal_id": "2026-05-04-negative-list-attach-01c",
  "kind": "negative-list-attach",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/campaignSharedSets:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/123456",
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>"
      }
    },
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/123457",
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>"
      }
    },
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/123458",
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>"
      }
    },
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/123459",
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>"
      }
    },
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/123460",
        "sharedSet": "<resourceName from proposal 2026-05-04-negative-list-create-01a op 1>"
      }
    }
  ],
  "metadata": {
    "step": "3-of-3",
    "depends_on": "2026-05-04-negative-list-create-01a"
  }
}
```
````

## Apply order

```bash
/google-ads-copilot:apply 2026-05-04-negative-list-create-01a
/google-ads-copilot:apply 2026-05-04-negative-list-add-keyword-01b
/google-ads-copilot:apply 2026-05-04-negative-list-attach-01c
```

After landing, the operator should follow up with a separate
per-campaign cleanup (drafting `negatives` `remove` proposals) to
delete the now-redundant per-campaign negatives. The plugin doesn't
auto-draft this cleanup — verifying that the shared list is actually
serving correctly before deleting the per-campaign safety net is
prudent. Wait 1–2 weeks of data, then run `/search-terms` again with
the audit's "redundant per-campaign negatives" flag to clean up.

## Inverse for /undo

Each step has its own inverse in `apply-contract.md`:

- `negative-list-create` → cascade-aware `remove` (deletes the list
  and every keyword + every campaign attachment automatically).
  Surface the linked-campaign count in the undo TL;DR before the
  operator approves.
- `negative-list-add-keyword` → `remove` against each
  `sharedCriterion` resource name (the list itself stays).
- `negative-list-attach` → `negative-list-detach` against each
  `campaignSharedSet` resource name from the original response.

For "undo all three", the operator runs `/undo` on C, then B, then A
— in reverse apply order.

## When NOT to use this flow

- Account has < 5 ENABLED Search campaigns → per-campaign maintenance
  is cheaper than the shared list's three-step ceremony. The audit
  threshold (≥5 campaigns) gates the recommendation.
- The terms are universally off-ICP across every campaign type (Search
  + PMax + Display) → use `customer-negative-criterion-add` instead;
  shared lists don't apply to PMax campaigns via campaignSharedSets.
- The terms are campaign-specific (e.g. competitor name only relevant
  to one campaign's keyword set) → keep as `negatives` per-campaign.

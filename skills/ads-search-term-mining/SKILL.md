---
name: ads-search-term-mining
description: Heuristics for turning a 30-day search-terms report into a vetted negative-keyword proposal. Loaded by /ads-search-terms and /ads-weekly.
---

# ads-search-term-mining

Goal: identify search queries that triggered the ads, spent money, and
returned nothing — and propose them as negative keywords at the right match
type, scoped to the right campaign.

## Pull data

Run the "Last 30d search terms with low/no conversion" query from the
**googleads-gaql** skill.

## Classify each row

For each `search_term`:

1. **Off-ICP?** Read `context/icp.md` and `context/persona-overrides.md`.
   If the query is clearly someone outside the target persona (free-tier
   seekers when the product is paid, hobbyists when the product is for
   factories, …) → mark as **negative candidate**.
2. **Brand collision?** If the query contains a competitor's brand name and
   `context/product-positioning.md` says you don't bid on competitors →
   negative candidate.
3. **High spend, zero conv** alone is not enough — there's natural
   variance. Threshold: ≥ €X per query where X = max(€5, daily budget × 0.05),
   or ≥ 100 impressions and 0 conv over 30 days.
4. **Long tail?** If the same theme recurs (e.g. multiple "free X" queries),
   propose a single PHRASE or EXACT negative on the theme word, not 20
   tail variants.

## Pick match type

- **EXACT** — the query is a one-off exact match you want to block ONLY for that wording.
- **PHRASE** — a recurring theme word (e.g. "free", "tutorial") you want to block whenever it appears in any query.
- **BROAD** — almost never. Reserve for clearly off-topic root words.

When in doubt, prefer PHRASE > EXACT > BROAD.

## Scope

Negative keywords go on the **campaign** that triggered the query, not on
all campaigns, unless the same theme appears across multiple campaigns —
then propose a customer-level negative keyword list (out of v1 scope; for
v1, do per-campaign).

## Draft the proposal

Use `ads-change-execution` proposal format. `kind: "negatives"`, `via:
"proxy"`, `endpoint: "/v18/customers/<id>/campaignCriteria:mutate"`.

Each operation:

```json
{
  "create": {
    "campaign": "customers/<id>/campaigns/<campaign-id>",
    "negative": true,
    "keyword": { "text": "<term>", "matchType": "PHRASE" }
  }
}
```

## Cap

Never propose more than 25 negatives in one batch. If the mining returns
more, draft the top 25 by spend; mention the rest in the rationale.

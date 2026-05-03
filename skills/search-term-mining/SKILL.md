---
name: search-term-mining
description: Use when finding wasted ad spend, drafting negative keywords, or auditing 30 days of search-term performance. Provides classification heuristics (off-ICP, brand collision, high-spend-zero-conv, long-tail), match-type selection rules (PHRASE > EXACT > BROAD), per-campaign vs customer-level scoping, and the JSON shape for campaignCriteria:mutate. Loaded by /google-ads-copilot:search-terms and /google-ads-copilot:weekly.
---

# search-term-mining

Goal: identify search queries that triggered the ads, spent money, and
returned nothing — and propose them as negative keywords at the right match
type, scoped to the right campaign.

## Pull data

Run the "Last 30d search terms with low/no conversion" query from the
**gaql** skill.

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

   **Conversion-lag adjustment.** Conversions for the last N days are
   still firing in. Read `context/kpi-tree.md` for `lag_days` (default
   3). Apply the conversion threshold against the window
   `[today-30, today-lag_days]` — i.e. exclude the trailing `lag_days`
   from the conversion count. Otherwise borderline candidates that
   converted yesterday get added as negatives today. Spend in the
   trailing `lag_days` window still counts toward the cost threshold —
   spend doesn't lag.
4. **Long tail?** If the same theme recurs (e.g. multiple "free X" queries),
   propose a single PHRASE or EXACT negative on the theme word, not 20
   tail variants.

## Example classifications

A reference table for the patterns above. Substitute `<product>`,
`<competitor>`, `<industry-term>` with the operator's actual context.

| Search term                       | Classification                | Match type             | Scope         | Why                                                                                                                                          |
|---|---|---|---|---|
| `free <product> tool`             | Off-ICP (rule 1)              | PHRASE on `free`       | Per-campaign  | We're paid software; "free" seekers don't convert. PHRASE on the theme word catches `free X tutorial`, `free X download`, etc. in one shot. |
| `<product> vs <competitor>`       | Brand collision (rule 2)      | EXACT                  | Per-campaign  | `context/product-positioning.md` says we don't bid on competitor comparisons. EXACT blocks just this phrasing without affecting unrelated queries. |
| `what is <industry-term>`         | Educational (low intent)      | (skip — no negative)   | —             | Low buying intent but not actively wasteful. Let conversion-tracking surface it later if it accumulates real spend.                          |
| `<product> excel template`        | Product mismatch (rule 1)     | PHRASE on `excel template` | Per-campaign  | We replace Excel; "template" seekers want a workbook, not software. Catches all `excel template X` variants.                                  |
| `<product> jobs` / `<product> careers` | Off-intent (rule 1)      | PHRASE on `jobs`, PHRASE on `careers` | Per-campaign  | Recruitment query; never buying intent. Two narrow PHRASE negatives, not one BROAD.                                                          |

## Pick match type

- **EXACT** — the query is a one-off exact match you want to block ONLY for that wording.
- **PHRASE** — a recurring theme word (e.g. "free", "tutorial") you want to block whenever it appears in any query.
- **BROAD** — almost never. Reserve for clearly off-topic root words.

When in doubt, prefer PHRASE > EXACT > BROAD.

### Close-variants advisory

Google's close-variant matching (since 2018, broadened in 2021) means
PHRASE/BROAD negatives don't always block what you'd expect:

- A PHRASE negative on `free` blocks `"free X"` and `"X free"` but
  may still let `"freebie X"` or `"X freely"` through.
- Plurals/typos may slip past EXACT negatives — Google treats them as
  variants on the positive side but is stricter on the negative side.
  An EXACT negative on `templates` doesn't block `template`.

When the theme is critical (brand-defense, off-ICP categories),
add the singular AND plural AND common typo variants explicitly. For
brand-collision negatives, also add the most-common misspellings of
the competitor's name.

## Scope

Negative keywords go on the **campaign** that triggered the query, not on
all campaigns, unless the same theme appears across multiple campaigns —
then either:

- **Per-campaign batch** (v1 default) — draft one `negatives` proposal
  per affected campaign, each with the same theme word. Audit trail is
  granular but verbose at scale.
- **Customer-level negative criterion** (v1 minimal support via the
  `customer-negative-criterion-add` kind in `change-execution`,
  primarily for PMax mining) — one negative blocks the query across
  **every** campaign in the account. Use only when the operator has
  confirmed the term is universally off-ICP. Surface "this affects all
  campaigns including campaigns we haven't audited" in the proposal
  TL;DR.
- **Customer-level negative-keyword *list*** (multiple keywords managed
  as a named, reusable list) — out of v1 scope (`shared_set` +
  `shared_criterion` + `campaign_shared_set` resources, three-step
  flow). Roadmap for v2 once accounts cross 5+ campaigns and operators
  start managing negatives in bulk.

## Draft the proposal

Use `change-execution` proposal format. `kind: "negatives"`,
`method: "POST"`, `endpoint: "/v23/customers/<id>/campaignCriteria:mutate"`.

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

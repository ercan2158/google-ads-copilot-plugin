---
description: Mine the last 30 days of search terms and draft a negative-keywords proposal. Read-only against the account; writes ONE file in workspace/proposals/.
argument-hint: (no arguments)
---

# /google-ads-copilot:search-terms

Run as the **manager** agent. Load **gaql**,
**search-term-mining**, **change-execution**, **explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull search-terms data per the gaql skill.
3. Apply mining heuristics per the search-term-mining skill.
4. **Cross-campaign sprawl check.** If candidates from step 3 group into
   themes (e.g. multiple "free X" terms) AND the account has ≥ 5
   ENABLED Search campaigns AND the same theme would land in ≥ 3
   campaigns:
   - Pull "Shared negative-keyword lists" from gaql to check whether a
     suitable list already exists.
   - If a matching list exists → draft `negative-list-add-keyword`
     proposals adding the new themes to it (one proposal per list).
   - If no matching list → draft the 3-step
     `negative-list-create` + `-add-keyword` + `-attach` paired flow
     per `change-execution/examples/shared-negatives.md`.
   - For per-campaign-specific candidates (off-ICP only on one
     campaign), still draft regular `negatives` proposals.
5. If 0 candidates: print "No junk to mine. Account looks clean." and exit.
6. Otherwise: write the appropriate proposal file(s) in
   `workspace/proposals/`, following the change-execution skill format.
7. Print chat:
   - TL;DR (plain English, e.g. "Drafted 14 negatives across 3 campaigns,
     est. €47/mo savings." OR "Drafted a shared list with 8 themes
     attached to 5 campaigns — replaces the 40 per-campaign negatives
     we'd otherwise need.")
   - Per-campaign or per-list one-liner with count
   - Action: "Review at workspace/proposals/<file>.md. Ship: /google-ads-copilot:apply <id>"
   - For paired proposals: list the apply order explicitly
8. Stop. Account untouched.

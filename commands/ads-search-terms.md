---
description: Mine the last 30 days of search terms and draft a negative-keywords proposal. Read-only against the account; writes ONE file in workspace/proposals/.
argument-hint: (no arguments)
---

# /ads-search-terms

Run as the **ads-manager** agent. Load **googleads-gaql**,
**ads-search-term-mining**, **ads-change-execution**, **ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull search-terms data per the gaql skill.
3. Apply mining heuristics per the search-term-mining skill.
4. If 0 candidates: print "No junk to mine. Account looks clean." and exit.
5. Otherwise: write `workspace/proposals/$(date +%Y-%m-%d)-negatives-NN.md`
   following the change-execution skill format.
6. Print chat:
   - TL;DR (plain English, e.g. "Drafted 14 negatives across 3 campaigns,
     est. €47/mo savings.")
   - Per-campaign one-liner with count
   - Action: "Review at workspace/proposals/<file>.md. Ship: /ads-apply <id>"
7. Stop. Account untouched.

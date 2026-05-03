---
description: Ad-hoc budget pacing review. Drafts a budget proposal if pacing is wildly off; otherwise reports clean.
argument-hint: (no arguments)
---

# /google-ads-copilot:budgets

Run as **manager**. Load **gaql**, **budget-management**,
**change-execution**, **explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull budget pacing data per gaql skill.
3. Apply budget-management thresholds.
4. If 0 actions: print "Pacing clean. Spend is on track." and exit.
5. Else: draft a `budget` proposal in `workspace/proposals/`.
6. Print TL;DR + per-campaign one-liner + `/google-ads-copilot:apply` instruction.
7. Stop.

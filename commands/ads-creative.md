---
description: Ad-hoc creative health check. Identifies LOW-performing RSA assets and drafts a paired pause + add proposal for the highest-spend ad.
argument-hint: (no arguments)
---

# /ads-creative

Run as **ads-manager**. Load **googleads-gaql**, **ads-creative-management**,
**ads-change-execution**, **ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull RSA asset performance per gaql skill.
3. Apply creative-management heuristics.
4. If 0 LOW assets: print "Creative health is fine." and exit.
5. Else: pick the highest-spend ad with LOW assets, draft TWO proposals
   (one `creative-pause`, one `creative-add`) with paired IDs (e.g.
   `2026-04-30-creative-01a-pause`, `2026-04-30-creative-01b-add`).
6. Print TL;DR + ad name + counts + `/ads-apply` instructions for both.
7. Stop.

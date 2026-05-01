---
description: One-time deep audit + phased refactor plan for a freshly-bound workspace. Read-only. Writes audit + refactors files. Run once per workspace.
argument-hint: (no arguments)
---

# /ads-bootstrap

Run as **ads-manager**. Load every skill the audit needs (gaql, account-audit
full, search-term-mining, budget-management, creative-management,
explain-to-beginner). Do NOT load change-execution — bootstrap doesn't draft
proposals; it produces a plan for the operator to consider.

## Steps

1. Bind to workspace.
2. Run the full 8-section audit per ads-account-audit.
3. Write `workspace/audit/$(date +%Y-%m-%d)-bootstrap.md` with all 8 sections.
4. Write `workspace/refactors/$(date +%Y-%m-%d)-phased-plan.md` containing:
   - Phase 0 (now): things the operator should do manually outside this plugin
     (e.g. fix conversion tracking, link GA4, set up enhanced conversions)
   - Phase 1 (next 1–2 weeks): things `/ads-weekly` and `/ads-monthly` will
     handle once they start running (mining, budget-tuning, creative refresh)
   - Phase 2 (next 1–3 months): structural recommendations the operator
     should review (campaign restructure, new themes) — NOT v1 scope
5. Print TL;DR + section severity emojis + path to both files.
6. Stop.

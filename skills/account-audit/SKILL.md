---
name: account-audit
description: Use when running a Google Ads account audit — daily anomaly checks, weekly tactical reviews, full monthly audits, or first-time bootstrap. Provides the 8-section audit structure (spend, conversion health, search terms, creative, disapprovals, structure, KPI alignment, recommendations), a severity rubric (🔴 critical / 🟡 warning / 🟢 healthy), and which gaql queries to run for each section.
---

# account-audit

Audit sections, in priority order:

1. **Spend & pacing** — actual vs. expected at this point in the month, by campaign. Use budget pacing query from `gaql`.
2. **Conversion health** — total conv last period vs. prior, conversion-action statuses (any "removed but still referenced"?). Conv-action query from gaql skill.
3. **Search terms** — full mining via `search-term-mining` skill.
4. **Creative** — RSA asset performance via gaql skill; flag LOW assets.
5. **Disapprovals** — any disapproved ads.
6. **Structure sanity** — campaign count, ad-group count, keyword count per campaign. Flag campaigns with > 50 keywords (Google's recommended max for Search) or < 3 ads (no A/B coverage).
7. **KPI alignment** — read `context/kpi-tree.md`, compare current 30-day metrics, surface KPI gaps.
8. **Recommendations** — bullet list, ranked by expected € impact, separated into "I'll handle" (proposable) and "you decide" (out of v1 scope, structural).

## Severity rubric

- **🔴 critical** — money is being wasted right now, or required tracking is broken (conv-action removed but still primary).
- **🟡 warning** — drift from policy, but not actively losing money.
- **🟢 healthy** — performing per `context/budget-policy.md` and `context/kpi-tree.md`.

Apply to each section.

## Output target

- `/google-ads-copilot:monthly` writes `workspace/audit/<YYYY-MM>-monthly.md` with all 8 sections.
- `/google-ads-copilot:weekly` covers sections 1, 3, 4, 5 only — quick weekly cycle.
- `/google-ads-copilot:bootstrap` writes `workspace/audit/<YYYY-MM-DD>-bootstrap.md` (full 8 sections) AND `workspace/refactors/<YYYY-MM-DD>-phased-plan.md` with the prioritized fix list as phases.
- `/google-ads-copilot:daily` does NOT call this skill; it has its own narrower checks.

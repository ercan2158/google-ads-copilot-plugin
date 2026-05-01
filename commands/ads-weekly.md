---
description: Weekly review — audit sections 1/3/4/5 + budget pacing review + search-term mining. May draft up to two proposals (negatives, budget shifts).
argument-hint: (no arguments)
---

# /ads-weekly

Run as the **ads-manager** agent. Load **googleads-gaql**,
**ads-account-audit** (focus: spend, search terms, creative, disapprovals),
**ads-search-term-mining**, **ads-budget-management**, **ads-change-execution**,
**ads-explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Run focused audit (sections 1, 3, 4, 5 only — see audit skill).
3. If search terms warrant: draft a `negatives` proposal per
   ads-search-term-mining + ads-change-execution.
4. If budget pacing warrants: draft a `budget` proposal per
   ads-budget-management + ads-change-execution.
5. Print chat:
   - TL;DR (max 4 lines)
   - Numbers (max 5 lines)
   - Action: 0–2 proposals listed with their `/ads-apply` commands.
6. Write `workspace/digests/$(date +%Y-%m-%d)-weekly.md` with the chat
   output + a per-section severity (🔴/🟡/🟢) line. Always write — weekly
   is a structured artifact, not anomaly-gated.
7. Stop.

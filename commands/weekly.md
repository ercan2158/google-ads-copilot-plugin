---
description: Weekly review — audit sections 1/3/4/5 + budget pacing review + search-term mining. May draft up to two proposals (negatives, budget shifts).
argument-hint: (no arguments)
---

# /google-ads-copilot:weekly

Run as the **manager** agent. Load **gaql**,
**account-audit** (focus: sections 1, 2-light, 3-light, 4, 5, 6 — spend,
conversion-tracking-since-last-week, smart-bidding-since-last-week,
search terms, creative, disapprovals + URL liveness), **conversion-health**
(light), **smart-bidding** (light), **search-term-mining**,
**budget-management**, **change-execution**, **explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Run focused audit (sections 1, 3, 4, 5 only — see audit skill).
3. If search terms warrant: draft a `negatives` proposal per
   search-term-mining + change-execution.
4. If budget pacing warrants: draft a `budget` proposal per
   budget-management + change-execution.
5. Print chat:
   - TL;DR (max 4 lines)
   - Numbers (max 5 lines)
   - Action: 0–2 proposals listed with their `/google-ads-copilot:apply` commands.
6. Write `workspace/digests/$(date +%Y-%m-%d)-weekly.md` with the chat
   output + a per-section severity (🔴/🟡/🟢) line. Always write — weekly
   is a structured artifact, not anomaly-gated.
7. Stop.

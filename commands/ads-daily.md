---
description: Daily "anything on fire?" check on the bound Google Ads account. Read-only. Prints a 3–5 line TL;DR in chat. Writes a digest file only on anomaly.
argument-hint: (no arguments)
---

# /ads-daily

Run as the **ads-manager** agent. Load the **googleads-gaql** and
**ads-explain-to-beginner** skills.

## Steps

1. Bind to the workspace (read `workspace.json` + `context/*.md`).
2. Run these reads via `ads-ga query` (see googleads-gaql skill):
   - Last-24h spend + conversions per campaign
   - Disapproved ads
   - Flatlined campaigns over the last 7 days
3. Compute anomalies vs. same weekday last week (spend ±20%, conv ±50%,
   any new disapproval, any new flatline).
4. Print to chat:
   - Line 1: `TL;DR: <plain-English summary, no jargon>`
   - Lines 2–N (max 5 lines): `<campaign>: €X spent, Y conv`
   - Last line: action — none, or "Drafted X proposal — review at <path>"
5. **If and only if** an anomaly fired or a proposal was drafted, write
   `workspace/digests/$(date +%Y-%m-%d)-daily.md` containing:
   - The TL;DR
   - The numbers
   - One paragraph explaining the anomaly (what, vs what baseline, possible causes)
   Do NOT write a digest file on a clean day.
6. Stop. Account untouched.

## Out of scope for this command

- No mutations.
- No proposals beyond passively flagging "you might want to look at X" —
  search-term mining and budget review are `/ads-search-terms` and `/ads-budgets`
  respectively.

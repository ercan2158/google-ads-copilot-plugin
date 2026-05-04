---
description: Daily "anything on fire?" check on the bound Google Ads account. Read-only. Prints a 3–5 line TL;DR in chat. Writes a digest file only on anomaly.
argument-hint: (no arguments)
---

# /google-ads-copilot:daily

Run as the **manager** agent. Load the **gaql** and
**explain-to-beginner** skills.

## Steps

1. Bind to the workspace (read `workspace.json` + `context/*.md`).
2. Run these reads via the ga helper (see gaql skill):
   - Last-24h spend + conversions per campaign
   - Disapproved ads
   - Flatlined campaigns over the last 7 days
   - **Conversion-action recent firing (regression check)** — per ENABLED
     primary action, daily mean conversions for `[today-3, today]` vs
     `[today-10, today-3]`
3. Compute anomalies vs. same weekday last week (spend ±20%, conv ±50%,
   any new disapproval, any new flatline). **Per-action regression
   anomaly**: any primary conversion action where recent ≈ 0 AND prior
   > 0 fires a 🔴 — the tag may have stopped firing on that action.
   This is the highest-priority anomaly: surface first in TL;DR and
   *do not* recommend any other action until investigated.
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
  search-term mining and budget review are `/google-ads-copilot:search-terms` and `/google-ads-copilot:budgets`
  respectively.

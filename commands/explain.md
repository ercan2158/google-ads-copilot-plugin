---
description: Plain-English explainer for a Google Ads term, metric, or concept. Read-only, no account access. Just translates jargon.
argument-hint: <term-or-concept>  e.g. /google-ads-copilot:explain impression share
---

# /google-ads-copilot:explain

Run as **ads-manager**. Load **ads-explain-to-beginner**.

## Steps

1. Read `$ARGUMENTS` (the term or concept the operator typed).
2. If empty: print "Usage: /google-ads-copilot:explain <term>" + the table of terms from
   the explain-to-beginner skill.
3. Otherwise:
   - Look up the term in the skill's table. If present: print the 1-line
     translation + a 2–4-line "in context" expansion (when it matters,
     how it's used, what to watch for).
   - If not in the table: write a fresh 1-line translation + 2–4-line
     expansion based on Google Ads documentation. Do not fabricate.
4. Stop. No account access. No mutations.

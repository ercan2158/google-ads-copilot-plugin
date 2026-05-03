---
description: Full monthly review — all 8 audit sections, with creative + budget deep-dive. Writes a structured monthly audit file. May draft up to 3 proposals.
argument-hint: (no arguments)
---

# /google-ads-copilot:monthly

Run as **manager**. Load **gaql**, **account-audit**
(full 10-section), **conversion-health**, **smart-bidding**, **pmax**
(if any campaign has `advertising_channel_type = PERFORMANCE_MAX`),
**search-term-mining**, **budget-management**, **creative-management**,
**change-execution**, **explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Run full 10-section audit per audit skill.
3. Per section, decide if a proposal is warranted (using the relevant
   skill's thresholds). Draft at most ONE proposal per section/kind.
4. Write `workspace/audit/$(date +%Y-%m)-monthly.md` with all 10 sections,
   severity emoji per section, and a "Recommendations" tail listing the
   drafted proposals + the items left for the operator.
5. Print chat:
   - TL;DR (≤ 5 lines, plain English summary of the month)
   - One section, one line: `<section> — <severity emoji> <one-liner>`
   - Action: list the proposals drafted with their `/google-ads-copilot:apply` commands.
6. Stop. Account untouched (until operator runs `/google-ads-copilot:apply`).

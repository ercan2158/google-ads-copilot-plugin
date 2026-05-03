---
name: smart-bidding
description: Use when auditing or recommending bidding strategy changes. Diagnoses bidding_strategy_type vs kpi-tree alignment, bidding_strategy_system_status (LEARNING / LIMITED / NOT_ACTIVE), conversion-volume floors for tCPA (≥50/30d) and tROAS (≥50/30d with values), target hit-rate vs realized CPA/ROAS. Unblocks the "manual review" verdict on TARGET_CPA_OPT_IN / TARGET_ROAS_OPT_IN / MAXIMIZE_CONVERSIONS_OPT_IN recommendations.
---

# smart-bidding

Goal: tell the operator whether each campaign is on the right bidding
strategy, whether that strategy is in a healthy state, and whether
volume + signal supports staying on it. Mismatches here move the dial
more than search-term mining ever will.

## Pull data

Run the **gaql** query "Bidding strategy diagnostic" (one row per
ENABLED campaign with strategy type, system status, target values,
30-day conversion volume + value, realized CPA/ROAS).

## The five checks

### 1. Strategy type matches kpi-tree intent

Read `context/kpi-tree.md`. Map declared north-star to the right
strategy:

| North-star described as | Right strategy |
|---|---|
| Conversions, signups, leads (no per-conv value tracked) | `MAXIMIZE_CONVERSIONS` (no target) or `TARGET_CPA` |
| Revenue, paid signups, e-commerce sales (per-conv value tracked) | `MAXIMIZE_CONVERSION_VALUE` or `TARGET_ROAS` |
| Visibility / brand presence | `TARGET_IMPRESSION_SHARE` (top of page) |
| Tight cost control, low-volume account | `MANUAL_CPC` + `ENHANCED_CPC` |
| Click volume (rare for SaaS) | `MAXIMIZE_CLICKS` |

🔴 **critical** if `bidding_strategy_type = MAXIMIZE_CLICKS` AND
kpi-tree says conversion-focused — the strategy is buying the cheapest
clicks, ignoring conversion likelihood entirely. Common legacy state
in self-managed accounts.

🔴 **critical** if `bidding_strategy_type = TARGET_ROAS` AND
the relevant conversion action has `default_value = 0` AND
`always_use_default_value = true` (per `conversion-health`) — bidding
toward zero return.

🟡 **warning** if `bidding_strategy_type = TARGET_CPA` AND kpi-tree
declares LTV-aware / value-aware optimization is the goal — should be
on `TARGET_ROAS` with proper value tracking instead.

🟡 **warning** if multiple campaigns share the same goal (e.g. both
"Search-Brand" and "Search-Generic" target SaaS signups) but use
DIFFERENT bidding strategies — strategy fragmentation makes
cross-campaign budget allocation harder.

### 2. System status is healthy

`campaign.bidding_strategy_system_status` enum:

| Status | Meaning | Action |
|---|---|---|
| `ENABLED` | Healthy, no issues | 🟢 |
| `LEARNING_NEW` | Recently created/reactivated; learning | 🟡 if < 14d, 🔴 if > 14d |
| `LEARNING_SETTING_CHANGE` | Recent target/setting change | 🟡 if < 7d, 🔴 if > 7d |
| `LEARNING_BUDGET_CHANGE` | Recent budget change kicked it back to learning | 🟡 short-term; investigate if recurring |
| `LEARNING_CAMPAIGN_KEYWORDS_CHANGE` | Structural change re-triggered learning | 🟡 short-term |
| `LIMITED_BY_BID_CEILING` | Bid ceiling capping the strategy | 🔴 raise the ceiling or accept the loss |
| `LIMITED_BY_BID_FLOOR` | Bid floor capping (rare) | 🔴 lower the floor |
| `MISCONFIGURED_ZERO_ELIGIBILITY` | No conversions in lookback window — strategy can't function | 🔴 revert to MANUAL_CPC + ECPC until volume returns |
| `MISCONFIGURED_CONVERSION_TYPES` | Conv actions misconfigured — see conversion-health | 🔴 fix conv tracking first |
| `NOT_ACTIVE` | No active campaigns/budgets/keywords attached | 🔴 structural issue |

🔴 surfaces these directly in the audit; the operator decides whether
to wait out a learning phase or roll back.

Persistent LEARNING (>14d for `_NEW`, >7d for setting change) often
signals the strategy isn't actually learning because conversion volume
is too low to converge — which is check #3.

### 3. Volume floor for the chosen strategy

`TARGET_CPA` and `MAXIMIZE_CONVERSIONS` need ≥ 30 conv / 30d to
stabilize, ≥ 50 to perform reliably (Google's published guidance).

`TARGET_ROAS` and `MAXIMIZE_CONVERSION_VALUE` need ≥ 50 conv with
values / 30d, ideally ≥ 100.

🔴 **critical** if a campaign's 30-day primary conversion count is
below the floor for its current strategy — the strategy is operating
in noise. Recommend either:
1. Switch to `MANUAL_CPC` + `ENHANCED_CPC` until volume builds, OR
2. Loosen targeting (broader match, expand keywords) to grow volume,
   accepting temporary CPA/ROAS variance.

🟡 **warning** if 30-day volume is between floor and 2× floor — the
strategy works but with high variance. Be careful interpreting weekly
CPA/ROAS noise as signal.

### 4. Target vs realized hit rate

For `TARGET_CPA`:
```
realized_cpa = SUM(metrics.cost_micros) / SUM(metrics.conversions) / 1_000_000
target_cpa   = campaign.target_cpa.target_cpa_micros / 1_000_000  (or maximize_conversions.target_cpa_micros)
hit_ratio    = realized_cpa / target_cpa
```

For `TARGET_ROAS`:
```
realized_roas = SUM(metrics.conversions_value) / SUM(metrics.cost_micros) * 1_000_000
target_roas   = campaign.target_roas.target_roas  (raw ratio, e.g. 4.0 = 400%)
hit_ratio     = realized_roas / target_roas
```

🟡 **warning** if `hit_ratio` is consistently > 1.20 over 4+ weeks
(realized CPA 20% above target / realized ROAS 20% below target) — the
target is too tight and Google is throttling delivery to hit it. Either
loosen the target by ~15% or switch to `MAXIMIZE_CONVERSIONS` /
`MAXIMIZE_CONVERSION_VALUE` (no explicit target, just maximize within
budget).

🟡 **warning** if `hit_ratio` is consistently < 0.80 (CPA well below
target / ROAS well above target) — operator is leaving volume on the
table. Tighten the target by ~10% to capture more conversions at
acceptable CPA.

### 5. Recent target changes

Track the last 30 days of target_cpa / target_roas changes via the
change-log (`workspace/change-log/*.jsonl`). If the operator changes
the target more than once per month:

🟡 **warning** — frequent target nudging keeps the strategy in
`LEARNING_SETTING_CHANGE` and prevents convergence. Recommend "set the
target, leave it alone for 14 days, then re-evaluate."

## Decisions to draft as proposals

The plugin can draft these via the existing `change-execution` kinds
(no new kinds needed — bidding strategy targets are campaign updates):

- **Adjust `target_cpa_micros` / `target_roas`** when hit-rate analysis
  warrants and the operator has stated tolerance in `kpi-tree.md`.
  Single-step cap: ±15% per change. Larger swings need operator
  judgment in chat.

- **Switch to `MANUAL_CPC` + `ENHANCED_CPC`** when volume falls below
  floor and a Smart Bidding strategy is misconfigured-zero-eligibility.
  This is a campaign update; treat as a `campaign-toggle`-style
  proposal but with explicit operator review (it's a strategic shift,
  not just status flip).

NOT drafted automatically:
- **Switching from MAXIMIZE_CLICKS → TARGET_CPA** — strategy-class
  change. Surface in audit with the data, but require operator
  acknowledgment in chat before drafting. Encoded as
  `bidding-strategy-shift` (NEW kind, see change-execution kinds
  table).

## Cap

Max ONE bidding-strategy-related proposal per `/weekly` or `/monthly`
run. Bidding changes have outsized account impact; pace them.

## Severity rubric

- 🔴 critical: strategy actively misaligned with goals or operating in
  zero-eligibility state
- 🟡 warning: strategy plausible but volume/target hit-rate not where
  it should be
- 🟢 healthy: strategy matches intent, system status ENABLED, volume
  above floor, hit-rate within ±20%

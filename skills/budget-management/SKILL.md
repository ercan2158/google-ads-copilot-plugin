---
name: budget-management
description: Use when checking budget pacing, deciding whether to raise or lower a daily budget, or proposing budget shifts between campaigns. Provides the pacing formula (actual vs expected against days-elapsed), decision thresholds tied to context/budget-policy.md and the operator's CPA target from context/kpi-tree.md, and the JSON shape for campaignBudgets:mutate (wrapped via change-execution).
---

# budget-management

## Pacing formula

Two formulas. Use the day-of-week-weighted one when the campaign has
≥ 60 days of history; fall back to flat for new campaigns.

### Flat (fallback for new campaigns)

```
days_elapsed   = today's day-of-month
expected_spend = (campaign_budget.amount_micros / 1_000_000) * days_elapsed
actual_spend   = SUM(metrics.cost_micros) DURING THIS_MONTH / 1_000_000
pacing_ratio   = actual_spend / expected_spend
```

This is naive — most accounts spend disproportionately on weekdays vs
weekends. On a Monday-Tuesday-Wednesday window early in a month, flat
pacing systematically over-predicts expected and the alarm fires
spuriously.

### Day-of-week-weighted (preferred, ≥ 60 days history)

Pull "Day-of-week historical baseline" from `gaql`. Compute per-campaign
weight vector `w_dow ∈ {Mon, Tue, …, Sun}` summing to 1.0. Then:

```
elapsed_weighted = Σ (w_dow[d] × days_count_of_dow_d_so_far_this_month)
                   for d in {Mon, Tue, …, Sun}, capped to days_elapsed total
target_full      = (campaign_budget.amount_micros / 1_000_000) ×
                   days_in_month
expected_spend   = target_full × elapsed_weighted
actual_spend     = SUM(metrics.cost_micros) DURING THIS_MONTH / 1_000_000
pacing_ratio     = actual_spend / expected_spend
```

Worked example: campaign with weights `[0.18, 0.18, 0.17, 0.17, 0.17,
0.07, 0.06]` (Mon-Sun) on day 8 of a 30-day month = 1×Mon + 1×Tue +
1×Wed + 1×Thu + 1×Fri + 2×Sat + 1×Sun = 0.18+0.18+0.17+0.17+0.17+0.14+
0.06 = 1.07 / 30 normalized = 35.7% of monthly target expected. Flat
formula would say 8/30 = 26.7% — alarming if actual is at 30%, when
it's actually under-pacing on a weekend-heavy slice.

`pacing_ratio == 1.0` is on-target. Read `context/budget-policy.md` for the
operator's tolerance band — assume ±20% if not specified.

### Conversion-lag adjustment

Conversion counts in pacing comparisons (CPA-driven decisions below)
should subtract the trailing `lag_days` from the read window —
conversions for the last N days are still firing in. Read
`context/kpi-tree.md` for `lag_days` (default 3 if absent). Surface in
TL;DR: "actual reflects through `<today minus lag_days>`; trailing
conversions still firing."

## When to propose a budget shift

| Condition | Proposal |
|---|---|
| `pacing_ratio > 1.20` AND CPA < target_cpa from kpi-tree | Increase daily budget — performance is good and we're hitting limits |
| `pacing_ratio > 1.20` AND CPA > target_cpa | DON'T increase. Flag in TL;DR — we're spending too fast at bad efficiency |
| `pacing_ratio < 0.80` | Investigate first (impression share lost-rank? lost-budget? low search volume?) before proposing a decrease |
| Two campaigns: one starving (rank-lost > 30%) and one underperforming | Propose shifting budget from underperformer → starving |

## Proposal shape

`kind: "budget"`, `method: "POST"`,
`endpoint: "/v23/customers/<id>/campaignBudgets:mutate"`.

Each op:
```json
{
  "update": {
    "resourceName": "customers/<id>/campaignBudgets/<budget-id>",
    "amountMicros": <new amount * 1_000_000>
  },
  "updateMask": "amountMicros"
}
```

Wrap this op in a `change-execution` proposal envelope. The agent never
calls `:mutate` directly; the proposal goes through
`/google-ads-copilot:apply` with the five safety gates (account-ID pin,
`validate_only` dry-run, append-only change-log, single-mutation gate,
always-propose).

## Cap

Never propose a single-step change > 50% of current budget. If the math
says +200%, propose +50% with a note "next week consider another step."

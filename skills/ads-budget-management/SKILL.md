---
name: ads-budget-management
description: Budget pacing math + thresholds for proposing budget shifts. Reads context/budget-policy.md to know what counts as "wildly off."
---

# ads-budget-management

## Pacing formula

For each campaign with `status = ENABLED`:

```
days_in_month  = days in current calendar month
days_elapsed   = today's day-of-month
expected_spend = (campaign_budget.amount_micros / 1_000_000) * days_elapsed
actual_spend   = SUM(metrics.cost_micros) DURING THIS_MONTH / 1_000_000
pacing_ratio   = actual_spend / expected_spend
```

`pacing_ratio == 1.0` is on-target. Read `context/budget-policy.md` for the
operator's tolerance band — assume ±20% if not specified.

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

## Cap

Never propose a single-step change > 50% of current budget. If the math
says +200%, propose +50% with a note "next week consider another step."

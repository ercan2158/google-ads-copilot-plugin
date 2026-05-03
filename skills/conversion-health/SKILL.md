---
name: conversion-health
description: Use when auditing whether the operator's Google Ads conversion tracking is correctly configured — wrong setup is the #1 cause of wasted spend. Checks conversion-action category alignment with kpi-tree, primary_for_goal mismatches, attribution model, counting_type, lookback windows vs typical conversion latency, value_settings, and inclusion flags. Outputs a severity-classified report and (where safe) drafts conversion-action-mod proposals via change-execution. Loaded by /bootstrap, /monthly, /weekly when KPIs look off.
---

# conversion-health

Goal: catch the silent killers before they distort every other metric. A
mis-categorized conversion action, a `counting_type` mismatch, or a
secondary action marked primary will mean Smart Bidding optimizes for
the wrong thing — and your search-term mining, budget pacing, and
quality-score audits all stand on a broken foundation.

## Pull data

Run the **gaql** query "Conversion-action diagnostic". One row per
active conversion action, with all configuration fields.

## The eight checks

For each conversion action returned (filter `status = 'ENABLED'`):

### 1. Category alignment with kpi-tree.md

Read `context/kpi-tree.md` and `context/product-positioning.md`. Map the
declared north-star to expected `category` values:

| North-star described as | Expected category |
|---|---|
| Trial signup, demo request, account creation | `SIGNUP` |
| Paid subscription start, purchase, checkout complete | `PURCHASE`, `SUBSCRIBE_PAID` |
| Lead form, contact form, "talk to sales" | `LEAD`, `SUBMIT_LEAD_FORM`, `QUALIFIED_LEAD` |
| Phone call to sales | `PHONE_CALL_LEAD` |
| Add to cart, begin checkout (mid-funnel) | `ADD_TO_CART`, `BEGIN_CHECKOUT` (should NOT be primary) |
| App install / mobile signup | `DOWNLOAD` |

🔴 **critical** if `category = DEFAULT` for any action that's
`primary_for_goal = true` — Smart Bidding can't use generic categories
effectively and Performance Max requires explicit goals.

🔴 **critical** if `primary_for_goal = true` AND the category is a
mid-funnel category (`ADD_TO_CART`, `BEGIN_CHECKOUT`, `PAGE_VIEW`,
`ENGAGEMENT`) AND `kpi-tree.md` describes a bottom-of-funnel north-star.
This causes Smart Bidding to optimize toward cheap upper-funnel actions
instead of revenue.

🟡 **warning** if multiple categories are marked primary and they're
for substantively different actions (`PURCHASE` + `LEAD`) — fine for
e-commerce + lead-gen hybrid SaaS, but flag for operator review.

### 2. Counting type vs conversion semantics

`counting_type` ∈ `ONE_PER_CLICK`, `MANY_PER_CLICK`. Default is
`MANY_PER_CLICK` but the right choice is action-dependent:

| Action type | Right counting_type | Why |
|---|---|---|
| Purchase, paid signup, lead form | `ONE_PER_CLICK` | One user → one paying customer; counting many inflates conv |
| Trial signup (single per user) | `ONE_PER_CLICK` | Same |
| Phone call, contact (could legitimately repeat) | `MANY_PER_CLICK` | A user calling twice = two leads |
| Page view, engagement (rare) | `MANY_PER_CLICK` | Activity counter |

🔴 **critical** if a `PURCHASE` or `SIGNUP` action is
`MANY_PER_CLICK` — likely double-counting. Confirms by checking
`metrics.conversions` per click ratio in the gaql query: if average
conv-per-click for that action exceeds 1.0, the counting_type is
inflating numbers and any tCPA/tROAS bidding is optimizing toward a
ghost.

### 3. Attribution model

`attribution_model_settings.attribution_model` enum. The
recommended default since 2023:

| Value | Meaning | When right |
|---|---|---|
| `GOOGLE_SEARCH_ATTRIBUTION_DATA_DRIVEN` | Data-driven (DDA) | Default for accounts with ≥300 conv/30d on the action; uses ML to credit touches |
| `GOOGLE_ADS_LAST_CLICK` | Last click within Google Ads | Fallback when conv volume too low for DDA |
| `EXTERNAL` | Imported (e.g. GA4 last-click, custom model) | Conv imported from GA4/CRM with that source's model |

🟡 **warning** if `attribution_model = EXTERNAL` AND
`include_in_conversions_metric = true` AND the operator imports
conversions from GA4 — usually the GA4 model is last-click cross-channel,
which credits Google Ads less than DDA would. Surface as: "your imported
conversions use GA4's model; tCPA bidding may underbid Google Ads in
multi-touch journeys."

🔴 **critical** if `attribution_model_settings.data_driven_model_status`
returns anything other than `AVAILABLE` for an action set to
`GOOGLE_SEARCH_ATTRIBUTION_DATA_DRIVEN` — DDA isn't actually firing,
falling back to last-click silently. Switch to `GOOGLE_ADS_LAST_CLICK`
explicitly until volume returns.

### 4. Lookback windows vs conversion latency

`click_through_lookback_window_days` (1–90, default 30).
`view_through_lookback_window_days` (1–30, default 1).

Read `context/kpi-tree.md` for declared time-to-convert. If absent,
infer from product type:

| Product type | Typical click-through lookback | Why |
|---|---|---|
| Self-serve B2C SaaS, e-commerce | 7–14 days | Decisions are fast |
| B2B SaaS with trial → paid | 30 days | Trial period |
| B2B with sales cycle | 60–90 days | Multi-stakeholder eval |
| Enterprise / RFP-driven | 90 days (max) | Long procurement |

🟡 **warning** if `click_through_lookback_window_days` is set to the
default 30 but the operator's product is enterprise B2B — they're
under-counting conversions that fire 31-90 days post-click. Smart
Bidding learns "this click didn't convert" when it actually did.

🟡 **warning** if window is > typical conversion latency by 2x or more
— overly broad windows give credit to clicks for conversions that
weren't influenced, distorting CPA reads.

### 5. Primary_for_goal correctness

`primary_for_goal: true` means the action contributes to `conversions`
(the metric Smart Bidding optimizes against). `false` means it shows
in the `all_conversions` metric only.

🔴 **critical** if `primary_for_goal = false` AND the conversion action
NAME or category clearly matches the kpi-tree's north-star — Smart
Bidding is ignoring the metric the operator cares about.

🔴 **critical** if `primary_for_goal = true` for upper-funnel actions
(category in `PAGE_VIEW`, `ENGAGEMENT`, `ADD_TO_CART`) — these inflate
the conversion count Smart Bidding sees, training it to chase cheap
top-of-funnel.

🟡 **warning** if all conversion actions are `primary_for_goal = true`
("counting everything") — typical of accounts that haven't been audited
since launch. Recommend selecting only the bottom-of-funnel action(s)
as primary.

### 6. include_in_conversions_metric

Closely related to `primary_for_goal` but the conversion-goal-system
override. If a campaign uses an account-default goal, `primary_for_goal`
controls inclusion. If a campaign overrides the goal at campaign level,
`include_in_conversions_metric` controls.

🔴 **critical** if `include_in_conversions_metric = false` AND
`primary_for_goal = true` — contradictory state, action effectively
excluded from bidding. Usually a leftover from a manual override; reset.

### 7. Value settings

For revenue-tracking actions (`PURCHASE`, `SUBSCRIBE_PAID`):

`value_settings.default_value` — used when the conversion fires without
a transaction value.
`value_settings.always_use_default_value` — boolean; if true, ignores
the per-conversion value passed in the tag.

🔴 **critical** if a `PURCHASE` action has
`always_use_default_value = true` AND `default_value = 0` (or unset)
— every purchase is recorded as €0 of revenue, breaking all tROAS
and conversion-value bidding. Surface as "your purchases are tracked
with €0 value; tROAS will not work."

🟡 **warning** if `always_use_default_value = true` AND
`default_value > 0` — average transaction value used instead of actual.
Acceptable if revenue varies little per transaction; harmful if it
varies (e.g. SaaS plans at €19/€99/€499).

🟡 **warning** if a `SIGNUP` or `LEAD` action has `default_value = 0`
AND the operator declared a customer LTV in `kpi-tree.md` — operator is
leaving Smart Bidding blind to value differences across leads. Suggest
setting `default_value` to expected first-year LTV per lead.

### 8. Conversion volume per action (statistical health)

For each `primary_for_goal = true` action, check 30-day volume:

🔴 **critical** if a primary action has < 15 conversions in the last
30 days — too low for any meaningful bid optimization, especially
tCPA/tROAS. Either increase budget, switch to broader-match strategy,
or merge with a related action.

🟡 **warning** if 15–30 conversions/30d — Smart Bidding is operating
at the lower volume edge; expect higher CPA variance.

🟢 **healthy** if ≥ 50 conversions/30d (Google's recommended floor for
tCPA stability) per primary action.

## Enhanced conversions check

Enhanced conversions is an account-level + tag-level setup. The API
doesn't expose a single "is enhanced conversions on" flag on
`conversion_action`. The diagnostic is indirect:

Run the `customer.conversion_tracking_setting.enhanced_conversions_for_leads_enabled`
query (note: the boolean is on `customer`, not on `conversion_action`).
Pair with `customer.conversion_tracking_setting.accepted_customer_data_terms`.

🔴 **critical** if `accepted_customer_data_terms = false` AND any
primary `LEAD`/`SUBMIT_LEAD_FORM` action exists — enhanced conversions
not legally enabled, accuracy ~15-30% lower than possible.

🟡 **warning** if `enhanced_conversions_for_leads_enabled = false`
AND lead-form conversions exist — operator hasn't turned on the lift.
Recommend enabling in the dashboard.

The plugin doesn't draft enhanced-conversions activation as a proposal —
it requires UI agreement to data terms, which is intentionally
out-of-band. Surface in the audit; instruct the operator to enable
manually.

## Output

Conversion-health is read-only at the diagnostic layer. **Surface
findings in the audit; for fixable issues, draft a
`conversion-action-mod` proposal per `change-execution` (kinds table).**

Drafted mutations are limited to:
- Flipping `primary_for_goal`
- Adjusting `click_through_lookback_window_days`
- Switching `attribution_model` between `GOOGLE_ADS_LAST_CLICK` and
  `GOOGLE_SEARCH_ATTRIBUTION_DATA_DRIVEN` (Google only allows these two
  via the API on create; updates are similarly constrained)
- Setting `value_settings.default_value`

NOT drafted (operator-decision territory):
- `category` changes — these are foundational; risk of breaking
  historical conversion attribution. Recommend in audit, not auto-draft.
- `status` changes (REMOVE / HIDDEN) — same reason.
- `counting_type` changes — affects historical reporting baseline.

## Cap

Maximum of 2 conversion-action-mod proposals drafted per session. More
than 2 issues found means the operator should sit with the audit before
mutating; conversion config is the last thing you want to change in a
hurry.

## Severity rubric (mirrors account-audit)

- 🔴 critical: bidding is optimizing on wrong/distorted signal
- 🟡 warning: signal partially distorted but not breaking
- 🟢 healthy: actions configured per modern best practice

# Example: Bid adjustments (kind = bid-adjust)

Bid adjustments tell Google to spend a percentage more or less per
impression based on a criterion (device, location, schedule, audience).
They're applied at the campaign level via `campaignCriteria:mutate`
operations on existing or new criteria.

## When to draft a bid-adjust proposal

Run the relevant query from `gaql`:
- **Device** — "Device performance (last 30d)"
- **Geographic** — "Geographic performance (last 30d)"
- **Time-of-day** — "Time-of-day & day-of-week performance (last 30d)"

For each segment, compute `cost_per_conv = cost_micros / conversions / 1_000_000`.
Compare to the campaign's `target_cpa` from `context/kpi-tree.md`.

Decision rule:

| Segment performance vs target CPA | Bid modifier proposal |
|---|---|
| ≥ 30% better (lower CPA) AND ≥ 50 conv in 30d | +10% to +30% bid up |
| ≥ 30% worse (higher CPA) AND ≥ 30 conv in 30d | -10% to -30% bid down |
| Within ±30% OR insufficient volume | no proposal — too noisy |

Cap any single adjustment at ±30%. Larger swings need operator review.

## Compute cumulative effect before drafting

Bid modifiers stack **multiplicatively**. Three modifiers on the same
campaign (device -25% + geo +20% + schedule -50%) yield a final bid of
`base × 0.75 × 1.20 × 0.50 = 0.45 × base` — 45% of base, not "the
average" or "the biggest one wins."

Before drafting any new `bid-adjust`, query existing modifiers via the
"Existing bid modifiers" query in `gaql`. Compute the cumulative for
the (campaign, intent slice) the new modifier targets:

```
existing_modifiers_on_intent = filter campaign_criterion rows where:
  campaign.id == target_campaign AND
  ( the criterion type intersects the new modifier's slice
    — e.g. for a new device:MOBILE modifier, include any current
    device:MOBILE row, plus any audience or schedule modifier that
    co-applies during the same impressions )

cumulative_after = product(existing.bid_modifier) × new_modifier
```

Cap proposals at cumulative ±50%. If `cumulative_after` would exceed
1.50 or fall below 0.50, reject the new modifier as proposed; either
update an existing modifier instead (`update` op against the existing
criterion's resourceName), or surface in TL;DR that the targeted slice
is already heavily modified and a structural fix (separate campaign /
ad group) is the right answer.

Surface the cumulative in the proposal's TL;DR:

> *"Mobile modifier: -25% (this proposal). Existing geo Germany +20%
> already applied. Combined effect on Mobile-in-Germany impressions:
> 0.75 × 1.20 = 0.90 → 10% bid down vs base. Within ±50% cumulative
> cap."*

Without this surfacing, an operator who applied three "small" -15%
modifiers over three weeks would silently end up at 0.85³ = 61%
of base — and wonder why volume crashed.

## Proposal: device bid modifier

`workspace/proposals/2026-05-03-bid-adjust-01.md`

````markdown
# Mobile bid -25% on flagship campaign — 2026-05-03

## TL;DR

Mobile clicks on "Search-Brand" cost €4.20/click vs desktop €1.80, with
65% lower conversion rate over 30 days. Reducing mobile bid 25%
reallocates budget toward desktop where the audience converts.

## Per-item rationale

- Mobile CPA last 30d: €82, well above target €40 from kpi-tree.md
- Desktop CPA last 30d: €31, below target
- Mobile clicks are 40% of total but only 18% of conversions
- Risk: low — modifier is reversible, not a permanent change

## Expected impact

- Reallocate ~€90/mo from mobile to desktop
- Expected conv lift +8% based on desktop's better CPA
- Honest uncertainty: assumes desktop has headroom (impression share
  lost-rank should not be near 0 on desktop — verify before applying)

## Executable

```json
{
  "proposal_id": "2026-05-03-bid-adjust-01",
  "kind": "bid-adjust",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/campaignCriteria:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/<campaign_id>",
        "device": { "type": "MOBILE" },
        "bidModifier": 0.75
      }
    }
  ],
  "metadata": {
    "modifier_type": "device",
    "device": "MOBILE",
    "previous_modifier": null,
    "new_modifier_pct": -25
  }
}
```
````

## Proposal: geographic bid modifier

````markdown
## Executable

```json
{
  "proposal_id": "2026-05-03-bid-adjust-02",
  "kind": "bid-adjust",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/campaignCriteria:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/<campaign_id>",
        "location": { "geoTargetConstant": "geoTargetConstants/2276" },
        "bidModifier": 1.20
      }
    }
  ],
  "metadata": {
    "modifier_type": "geo",
    "location": "Germany (geoTargetConstants/2276)",
    "new_modifier_pct": 20
  }
}
```
````

`geoTargetConstants/<id>` IDs come from Google's geo target reference
(e.g. `2276` = Germany, `2840` = US, `2826` = UK). The `bidModifier`
1.20 = +20% bid up; 0.75 = -25% bid down.

## Proposal: ad schedule (day-parting)

````markdown
## Executable

```json
{
  "proposal_id": "2026-05-03-bid-adjust-03",
  "kind": "bid-adjust",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/campaignCriteria:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "campaign": "customers/8191097521/campaigns/<campaign_id>",
        "adSchedule": {
          "dayOfWeek": "SATURDAY",
          "startHour": 0,
          "endHour": 24,
          "startMinute": "ZERO",
          "endMinute": "ZERO"
        },
        "bidModifier": 0.50
      }
    }
  ],
  "metadata": {
    "modifier_type": "schedule",
    "schedule": "Saturdays full day",
    "new_modifier_pct": -50,
    "rationale": "0 conversions on 12 of last 13 Saturdays"
  }
}
```
````

`startMinute`/`endMinute` ∈ `ZERO`, `FIFTEEN`, `THIRTY`, `FORTY_FIVE`.
`dayOfWeek` ∈ `MONDAY..SUNDAY`.

## Updating an existing bid modifier

If a modifier already exists on the criterion (you've adjusted device
before), use `update` with the resource name and `updateMask: bidModifier`:

```json
{
  "update": {
    "resourceName": "customers/8191097521/campaignCriteria/<criterion_id>",
    "bidModifier": 0.85
  },
  "updateMask": "bidModifier"
}
```

## Inverse for /undo

Read the `metadata.previous_modifier` from the change-log entry. If
`null` (modifier didn't exist before), the inverse is a `remove` of the
created criterion. If a previous modifier existed, the inverse is an
`update` setting the modifier back.

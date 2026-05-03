---
name: creative-management
description: Use when reviewing responsive search ad (RSA) creative — identifying LOW-performing headlines or descriptions, drafting replacements aligned to the operator's ICP and positioning, or proposing creative-pause + creative-add op pairs. Reads context/icp.md and context/product-positioning.md for tone, persona pain, and value props. See examples/rsa-headlines.md for a worked before/after.
---

# creative-management

## Read

Run the "Responsive search ad asset performance" query from
**gaql**. Filter to `performance_label IN ('LOW')`.

## Decide

For each ad with one or more LOW assets:

- If LOW headline count ≥ 2 → propose pause for those headlines AND draft
  replacement headlines.
- If LOW description count ≥ 1 → propose pause AND draft replacement
  descriptions.
- If the ad has < 8 active headlines after pausing the LOW ones → must
  draft replacements (Google requires at least 3, recommends ≥ 8).

## Draft replacements

Read `context/icp.md` and `context/product-positioning.md`. Headlines:

- 30 chars max each
- 8–15 candidates per RSA
- Cover: value prop, persona pain, social proof, CTA, feature highlight, differentiation
- No duplicate first words across the set (Google penalizes)
- Match the existing ad's tone and persona (don't introduce new positioning silently)

Descriptions: 90 chars max, **target 4, hard limit 4** (Google's
maximum for active descriptions on an RSA). Each one expands a value
prop or pain → outcome pairing.

## Proposal kinds

- `kind: "creative-pause"` — pause specific assets. `method: "POST"`,
  `endpoint: /v23/customers/<id>/adGroupAdAssets:mutate`.
- `kind: "creative-add"` — add new assets to an existing RSA. Same endpoint,
  `create` operations.

Both kinds are wrapped in `change-execution` proposal envelopes; the
operator approves each via `/google-ads-copilot:apply` before they ship.
The two proposals are paired (same date + sequence letter, e.g.
`2026-05-03-creative-01a-pause` and `2026-05-03-creative-01b-add`); both
must apply for the change to be complete. See
[`examples/rsa-headlines.md`](examples/rsa-headlines.md) for a worked
before/after that shows a full LOW-asset audit and the resulting pair.

## Scope

Per-RSA, max one proposal per session. If multiple ads need work, draft
the highest-spend one first; note the others in the rationale.

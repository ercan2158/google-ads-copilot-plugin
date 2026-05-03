---
name: creative-management
description: Read RSA asset performance, identify weak assets, draft replacements. Inputs: context/icp.md, context/product-positioning.md.
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

Descriptions: 90 chars max, 4 candidates per RSA, expanded value prop.

## Proposal kinds

- `kind: "creative-pause"` — pause specific assets. `method: "POST"`,
  `endpoint: /v23/customers/<id>/adGroupAdAssets:mutate`.
- `kind: "creative-add"` — add new assets to an existing RSA. Same endpoint,
  `create` operations.

## Scope

Per-RSA, max one proposal per session. If multiple ads need work, draft
the highest-spend one first; note the others in the rationale.

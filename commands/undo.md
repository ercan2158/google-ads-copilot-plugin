---
description: Roll back an applied proposal by drafting a new proposal containing the inverse operation. Reads the original from workspace/proposals/applied/, reads its change-log entry, generates the inverse per the kind's rules in change-execution. Refuses for non-invertible kinds.
argument-hint: <proposal-id>  e.g. /google-ads-copilot:undo 2026-05-03-budget-01
---

# /google-ads-copilot:undo

Run as **manager**. Load **change-execution** (incl.
`references/apply-contract.md` for inverse-op rules).

## Required argument

`$1` = proposal ID of an already-applied proposal. The original lives
at `workspace/proposals/applied/$1.md`. Its change-log entries live in
`workspace/change-log/<date>.jsonl` filtered by `proposal_id = $1`.

If `$1` is missing or doesn't exist in `applied/`: print

```
Usage: /google-ads-copilot:undo <proposal-id>

Recently applied proposals (last 7 days):
  <list workspace/proposals/applied/*.md basenames here>
```

## Steps

1. **Locate the original.** Read `workspace/proposals/applied/$1.md`.
2. **Locate the change-log entries** for `proposal_id = $1` across
   `workspace/change-log/*.jsonl`. Each entry has the response from
   Google (resource names, etc.).
3. **Determine invertibility.** Look up the kind in
   `references/apply-contract.md`'s "Per-kind inverse rules" table:

   | kind                    | invertible? | how                                                                |
   |---|---|---|
   | `negatives`             | yes         | `remove` on the criterion resource names from the response         |
   | `budget`                | yes         | `update` `amountMicros` back to old value (read from original `metadata.previous_amount` if present, else from change-log diff context) |
   | `creative-pause`        | yes (best-effort) | re-create the asset link with same `adGroupAd`+`asset`+`fieldType` |
   | `creative-add`          | yes         | `remove` the link resource names from the response                 |
   | `assets-add`            | yes (cascade-aware) | `remove` op on `assets:mutate`. WARN if asset is also linked elsewhere; suggest `assets-unlink` instead. |
   | `assets-link`           | yes         | `remove` on the customerAsset/campaignAsset link resource names    |
   | `assets-unlink`         | yes         | re-create the link with same `asset`+`fieldType`                   |
   | `keyword-add`           | yes         | `remove` on the criterion resource names                           |
   | `keyword-pause`         | yes         | `update` `status: ENABLED` + `updateMask: status` on the resource  |
   | `campaign-toggle`       | yes         | `update` flipping `status` back                                    |
   | `ad-toggle`             | yes         | `update` flipping `status` back                                    |
   | `bid-adjust`            | yes         | If `metadata.previous_modifier` was null: `remove` the criterion. Else `update` `bidModifier` back to old value. |
   | `conversion-action-mod` | yes (best-effort) | `update` fields back to their pre-change values from the original proposal's `metadata.previous_*` |
   | `customer-match-upload` | **NO**       | Refuse — Google's offline matching can't be cleanly reversed. Print the manual scrub recipe from `examples/customer-match.md`. |
   | `recommendation-apply`  | **NO**       | Refuse — Google's apply may have spawned downstream entities (assets, links, criteria). Print the spawned resource names from the change-log; the operator drafts kind-specific undos against each. |
   | `recommendation-dismiss`| n/a          | Recs naturally resurface; no inverse needed.                       |

4. **For invertible kinds**: draft a new proposal at
   `workspace/proposals/<today>-undo-of-<original-id>.md`. The new
   proposal's `metadata` includes `inverse_of: <original-id>`. The
   operations list contains the inverse ops per the table above.

5. **For non-invertible kinds**: print the refusal reason, the manual
   recipe (if applicable), and stop. Don't write a proposal file.

6. **Print TL;DR**:
   ```
   TL;DR: Drafted inverse of 2026-05-03-budget-01 (set "Search-Brand"
   daily budget back from €40 to €30).

   Apply: /google-ads-copilot:apply 2026-05-03-undo-of-2026-05-03-budget-01
   ```

7. Stop. The undo proposal goes through the normal apply flow
   (account-ID pin, validate_only dry-run, change-log entry). The
   original applied proposal stays in `applied/` for traceability — the
   audit trail records both the change and its reversal.

## Important

- `/undo` does NOT auto-apply the inverse. It drafts. The operator
  reviews and applies.
- The change-log entry for the undo references the original proposal ID
  in `metadata.inverse_of`. This makes the audit trail clear: change X
  was applied, then reversed.
- For paired proposals (`assets-add` + `assets-link`), the operator
  typically wants to undo BOTH. `/undo` only handles one at a time;
  drafting both inverses requires running it twice, in reverse order
  (undo the link first — the unlink — then the create).

## Out of scope

- Bulk undo ("undo everything from this week"). Each undo is per-proposal
  for safety. The operator can chain `/undo` calls.
- Time-travel ("revert to last Tuesday's account state"). Out of v1
  scope; the change-log gives enough info to reconstruct manually.

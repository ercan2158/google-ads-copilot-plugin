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
3. **Determine invertibility.** Look up the kind in the canonical
   per-kind inverse rules table at
   [`skills/change-execution/references/apply-contract.md`](../skills/change-execution/references/apply-contract.md#per-kind-inverse-rules-canonical).
   Two kinds are non-invertible (`customer-match-upload`,
   `recommendation-apply`); for those, follow the table's refusal
   recipe and stop. For all others, the table specifies the inverse op
   shape (typically a `remove` against the original response's resource
   names, or an `update` flipping status / restoring previous values).

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

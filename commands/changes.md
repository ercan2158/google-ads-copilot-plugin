---
description: Show what's been applied recently. Reads workspace/change-log/<date>.jsonl, groups by proposal, summarises in plain English. Read-only — pure visibility on the audit trail.
argument-hint: [days]  e.g. /google-ads-copilot:changes 7
---

# /google-ads-copilot:changes

Run as **manager**. Load **explain-to-beginner**.

## Argument

`$1` = number of days to look back. Accepted forms:
- `7` (last 7 days)
- `30` (last 30 days)
- `month` (current calendar month)
- `all` (everything in the change-log)
- *(no arg)* = `7`

## Steps

1. Bind to workspace.
2. Determine the date range from `$1`.
3. List `workspace/change-log/*.jsonl` files within the range. Each line = one applied operation.
4. Parse each line: `proposal_id`, `op`, `kind`, `request`, `response`, `applied`, `ts`.
5. Group lines by `proposal_id`. Each proposal = one logical change unit; one or more ops per proposal.
6. List `workspace/proposals/*.md` (still pending, not yet applied) within the range.
7. List `workspace/proposals/applied/*.md` and verify each has at least one change-log entry.

## Output shape

```
TL;DR: 4 proposals applied in the last 7 days — 2 budget shifts, 1 creative refresh, 1 negatives batch. €120/mo expected savings from the negatives.

Applied (4):
| Date    | Proposal ID                     | Kind            | Summary                                |
|---|---|---|---|
| Apr 30  | 2026-04-30-budget-01            | budget          | +€10/day on "Search-Brand"             |
| May 1   | 2026-05-01-creative-01a-pause   | creative-pause  | Paused 4 LOW headlines on flagship ad  |
| May 1   | 2026-05-01-creative-01b-add     | creative-add    | Added 6 new headlines + 1 description  |
| May 3   | 2026-05-03-negatives-02         | negatives       | 14 negatives across 2 campaigns        |

Pending review (1):
- workspace/proposals/2026-05-03-budget-02.md (drafted by /google-ads-copilot:weekly)

Failed/skipped (0):
  (none)
```

## Plain-English rule

Translate every kind into a one-line action summary. Don't dump raw JSON in chat unless the operator asks. The change-log is the source of truth for technical detail.

## Filtering

If the operator asks for a slice ("show me only budget changes this month", "what extension links did we add this week"), filter from the parsed dataset and re-render the table. Don't extend the command's argument surface — keep it conversational.

## Out of scope

- Mutations. Pure visibility command.
- Reconstructing what would have happened ("what if we hadn't applied X?") — that's a separate analysis the operator can ask in chat.

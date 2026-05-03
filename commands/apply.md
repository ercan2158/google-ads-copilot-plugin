---
description: Apply a previously drafted proposal. The ONLY command that mutates the Google Ads account. Refuses if account-ID doesn't match. Runs validate_only dry-run first, then asks y/n, then logs every op to change-log.
argument-hint: <proposal-id>  e.g. /google-ads-copilot:apply 2026-04-30-negatives-01
---

# /google-ads-copilot:apply

Run as the **manager** agent. Load the **change-execution** skill.

## Required argument

`$1` = proposal ID. The file is at
`workspace/proposals/$1.md`.

If `$1` is missing or empty: print
```
Usage: /google-ads-copilot:apply <proposal-id>

Available pending proposals:
  <list workspace/proposals/*.md basenames here>
```

## Steps

Follow the `/google-ads-copilot:apply` contract in the **change-execution** skill
verbatim. Specifically:

1. Read `workspace/proposals/$1.md`. Extract the last fenced ```json block.
2. Account-ID pin: refuse on mismatch with `workspace.json`.
3. Run validate_only dry-run via the ga helper. On error: print error, stop.
4. Print diff in chat (operation summary). Ask "Proceed? (y/n)".
5. On 'y':
   - Live run via the ga helper.
   - For each op, append a JSON line to `workspace/change-log/$(date +%Y-%m-%d).jsonl`.
   - `mv` proposal to `workspace/proposals/applied/`.
   - Print "Applied. N operations live."
6. On 'n':
   - Leave proposal in place. Print "Skipped."

## Plain-English chat output rule

Every step that surfaces something to the operator follows
**explain-to-beginner**: TL;DR first, jargon translated on first use,
units on numbers.

---
description: Apply a previously drafted proposal. The ONLY command that mutates the Google Ads account. Refuses if account-ID doesn't match. Runs validate_only dry-run first, then asks y/n, then logs every op to change-log.
argument-hint: <proposal-id>  e.g. /google-ads-copilot:apply 2026-04-30-negatives-01
---

# /google-ads-copilot:apply

Run as the **manager** agent. Load the **change-execution** skill.

The mutation gates run inside **`bin/apply`**, not inside this prompt.
The agent's job here is: surface the plan to the operator in plain
English, capture their y/n in chat, and call the script. The script
enforces the five gates mechanically.

## Required argument

`$1` = proposal ID. The file is at `workspace/proposals/$1.md`.

If `$1` is missing or empty: print
```
Usage: /google-ads-copilot:apply <proposal-id>

Available pending proposals:
  <list workspace/proposals/*.md basenames here>
```

## Steps

1. **Plan** — run the deterministic plan command (does the dry-run, no
   mutation):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/apply" "$1" --plan
   ```

   On non-zero exit: the script has printed Google's structured error
   to stderr. Translate to plain English per **explain-to-beginner**,
   surface to the operator, stop. The proposal is untouched.

2. **Diff in chat** — read the proposal's TL;DR + per-item rationale,
   summarize for the operator. Ask in chat: "Proceed? (y/n)".

3. **On 'y'** — call apply with `--confirm` to skip the script's own
   prompt (the operator already said yes in chat):

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/bin/apply" "$1" --confirm
   ```

   The script runs the dry-run again, then the live mutation, then
   logs to change-log, then moves the proposal to applied/. All
   atomic — the agent doesn't touch any files.

4. **On 'n'** — do not call --confirm. Print "Skipped."

## What the script enforces (so the agent doesn't have to)

- Account-ID pin (gate 3): refuses on mismatch with `workspace.json`.
- Proposal schema validation (calls `bin/validate-proposal`): catches
  malformed JSON, missing fields, invalid endpoints before any API call.
- `validate_only` dry-run (gate 4): for endpoints that accept it.
- Resource-name auto-substitution: `<resourceName from proposal X op N>`
  placeholders are resolved from the change-log automatically — no
  manual editing of paired proposals.
- Append-only change-log (gate 5): every op gets a JSONL line; failures
  are logged with `applied:false`.
- `mv` proposal to `applied/`: only on full success.

## Plain-English chat output rule

Every step that surfaces something to the operator follows
**explain-to-beginner**: TL;DR first, jargon translated on first use,
units on numbers. The script's own output is terse and operational —
your job in chat is to explain it.

---
name: change-execution
description: Proposal protocol. Loaded any time the agent considers a mutation. Defines the proposal-file format, the five safety gates between intent and account, and the kinds of proposals that exist. The full /google-ads-copilot:apply pseudo-code and change-log line shape live at references/apply-contract.md (loaded only by the apply command itself).
---

# change-execution

Mutations never go straight to the account. The agent drafts a proposal
file; the operator runs `/google-ads-copilot:apply <id>`; and only `/google-ads-copilot:apply` calls
the ga helper against the account.

## The five gates

1. **Single mutating command.** Only `/google-ads-copilot:apply` mutates.
2. **Always-propose.** Every mutation = a `.md` file the operator can read.
3. **Account-ID pin.** `/google-ads-copilot:apply` refuses if the proposal's `account_id`
   does not match `workspace.json`'s `account.customer_id`.
4. **`validate_only` dry-run.** `/google-ads-copilot:apply` runs the change with
   `validateOnly:true` first; only proceeds on success.
5. **Append-only change-log.** Every applied operation = one JSON line in
   `workspace/change-log/$(date +%Y-%m-%d).jsonl`.

## Proposal file format

Path: `workspace/proposals/<YYYY-MM-DD>-<kind>-<seq>.md` where:
- `<kind>` ∈ `negatives`, `budget`, `creative-pause`, `creative-add`, …
- `<seq>` is `01`, `02`, … if multiple proposals on the same day

Structure:

````markdown
# <Title> — <YYYY-MM-DD>

## TL;DR

<2–4 lines, plain English. What you want to do, why, what could go wrong.>

## Per-item rationale

- **<thing>** — <why, with numbers>. Risk: <low/medium/high>, because <reason>.
- ...

## Expected impact

<1–2 lines. €X savings, Y% lift, etc. Be honest about uncertainty.>

## Executable

```json
{
  "proposal_id": "<YYYY-MM-DD>-<kind>-<seq>",
  "kind": "<kind>",
  "account_id": "<customer_id from workspace.json>",
  "method": "POST",
  "endpoint": "/v23/customers/<id>/<resource>:mutate",
  "validate_first": true,
  "operations": [
    { ...op-specific fields... }
  ]
}
```
````

The fenced ```json block at the bottom is the **executable** part.
`/google-ads-copilot:apply` extracts it with `awk` / `jq` and runs it.

## /google-ads-copilot:apply contract

The apply command's full pseudo-code, change-log line shape, and
failure-mode reference live at
[`references/apply-contract.md`](references/apply-contract.md). That
file is loaded only by `/google-ads-copilot:apply` itself; drafters
working with this skill don't need it.

## What "kinds" of proposals exist (v1)

| kind | drafted by | ops |
|---|---|---|
| `negatives` | `/google-ads-copilot:search-terms`, `/google-ads-copilot:weekly` | add negative keywords (campaign-level) |
| `budget` | `/google-ads-copilot:budgets`, `/google-ads-copilot:weekly`, `/google-ads-copilot:monthly` | update `campaign_budget.amount_micros` |
| `creative-pause` | `/google-ads-copilot:creative`, `/google-ads-copilot:monthly` | pause `ad_group_ad` |
| `creative-add` | `/google-ads-copilot:creative` | add headlines/descriptions to RSA |

Out of scope for v1: `campaign-create`, `ad-group-create`, anything structural.

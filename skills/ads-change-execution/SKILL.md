---
name: ads-change-execution
description: Proposal protocol. Loaded any time the agent considers a mutation. Defines the proposal-file format, the /ads-apply contract, the change-log line shape, and the five safety gates between intent and account.
---

# ads-change-execution

Mutations never go straight to the account. The agent drafts a proposal
file; the operator runs `/ads-apply <id>`; and only `/ads-apply` calls
`ads-ga proxy` against the account.

## The five gates

1. **Single mutating command.** Only `/ads-apply` mutates.
2. **Always-propose.** Every mutation = a `.md` file the operator can read.
3. **Account-ID pin.** `/ads-apply` refuses if the proposal's `account_id`
   does not match `workspace.json`'s `account.customer_id`.
4. **`validate_only` dry-run.** `/ads-apply` runs the change with
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
`/ads-apply` extracts it with `awk` / `jq` and runs it.

## /ads-apply contract

Pseudo-code for `/ads-apply <id>`:

```
1. Read workspace/proposals/<id>.md, extract last fenced ```json block.
2. Parse JSON. Verify .account_id == workspace.json .account.customer_id.
   On mismatch: print "REFUSED: proposal account_id mismatch" and stop.
3. Build a copy of the request body with validateOnly:true. Most Google Ads
   :mutate endpoints accept it; if the specific endpoint doesn't, skip the
   dry-run and note in chat.
   Call: ads-ga proxy <method> <endpoint> '<body-with-validateOnly-true>'
4. If dry-run errors: print error, leave proposal in place, stop.
5. Print chat diff: "About to apply <kind>: <summary of operations>. Proceed? (y/n)"
6. On 'y':
   - Run live (validate_only:false).
   - For each op, append to workspace/change-log/$(date +%Y-%m-%d).jsonl:
     {"ts":"<iso>","proposal_id":"<id>","op":"<kind>","request":<op>,"response":<resp>,"applied":true}
   - mv workspace/proposals/<id>.md workspace/proposals/applied/<id>.md
   - Print "Applied. N operations live. Logged to change-log/."
7. On 'n':
   - Leave proposal in place. Print "Skipped. Re-run /ads-apply <id> later."
```

## Change-log line shape

One JSON line per applied operation. Newline-terminated. Append-only.

```json
{
  "ts": "2026-04-30T14:22:01Z",
  "proposal_id": "2026-04-30-negatives-01",
  "op": "add_negative_keyword",
  "account_id": "8191097521",
  "request": { "campaign_id": "...", "text": "...", "match_type": "PHRASE" },
  "response": { "resourceName": "..." },
  "applied": true
}
```

## What "kinds" of proposals exist (v1)

| kind | drafted by | ops |
|---|---|---|
| `negatives` | `/ads-search-terms`, `/ads-weekly` | add negative keywords (campaign-level) |
| `budget` | `/ads-budgets`, `/ads-weekly`, `/ads-monthly` | update `campaign_budget.amount_micros` |
| `creative-pause` | `/ads-creative`, `/ads-monthly` | pause `ad_group_ad` |
| `creative-add` | `/ads-creative` | add headlines/descriptions to RSA |

Out of scope for v1: `campaign-create`, `ad-group-create`, anything structural.

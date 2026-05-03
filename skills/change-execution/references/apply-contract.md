# /google-ads-copilot:apply contract

Implementation contract for the `/google-ads-copilot:apply` command —
the only command in this plugin that mutates the Google Ads account.
Drafters of proposals don't need to read this; the parent
[`change-execution`](../SKILL.md) skill has everything a drafter cares
about (proposal-file format, the five gates summary, the kinds table).

## Pseudo-code

```
1. Read workspace/proposals/<id>.md, extract last fenced ```json block.
2. Parse JSON. Verify .account_id == workspace.json .account.customer_id.
   On mismatch: print "REFUSED: proposal account_id mismatch" and stop.
3. Build a copy of the request body with validateOnly:true. Most Google
   Ads :mutate endpoints accept it; if the specific endpoint doesn't,
   skip the dry-run and note in chat.
   Call: "${CLAUDE_PLUGIN_ROOT}/bin/ga" proxy <method> <endpoint> '<body-with-validateOnly-true>'
4. If dry-run errors: print error, leave proposal in place, stop.
5. Print chat diff: "About to apply <kind>: <summary of operations>. Proceed? (y/n)"
6. On 'y':
   - Run live (validate_only:false).
   - For each op, append to workspace/change-log/$(date +%Y-%m-%d).jsonl:
     {"ts":"<iso>","proposal_id":"<id>","op":"<kind>","request":<op>,"response":<resp>,"applied":true}
   - mv workspace/proposals/<id>.md workspace/proposals/applied/<id>.md
   - Print "Applied. N operations live. Logged to change-log/."
7. On 'n':
   - Leave proposal in place. Print "Skipped. Re-run /google-ads-copilot:apply <id> later."
```

## Change-log line shape

One JSON line per applied operation. Newline-terminated. Append-only.
Never edit; the file's an audit trail.

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

## Failure-mode reference

| Failure | Behavior |
|---|---|
| Account-ID mismatch (gate 3) | Refuse, leave proposal in place, exit non-zero |
| `validate_only` returns error (gate 4) | Print Google's structured error, leave proposal, exit non-zero |
| Operator answers 'n' at the diff prompt | Leave proposal in place, exit zero, no change-log entry |
| Live mutate returns error after dry-run passed | Append `applied:false` line to change-log with the error response, leave proposal in place |
| `mv` of proposal to `applied/` fails | Log to change-log but warn — the mutation already shipped, the operator should manually move the file |

The first three are expected paths. The last two are unexpected and the
operator should be loud about them in chat ("⚠️ The mutation shipped
but I couldn't move the proposal — manually mv workspace/proposals/X to
workspace/proposals/applied/").

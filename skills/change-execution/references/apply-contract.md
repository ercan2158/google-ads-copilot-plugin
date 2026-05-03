# /google-ads-copilot:apply contract

Implementation contract for the `/google-ads-copilot:apply` command —
the only command in this plugin that mutates the Google Ads account.
Drafters of proposals don't need to read this; the parent
[`change-execution`](../SKILL.md) skill has everything a drafter cares
about (proposal-file format, the five gates summary, the kinds table).

This file also hosts the canonical per-kind inverse rules (loaded by
`/google-ads-copilot:undo`).

## Request-body construction

The proposal envelope supports **two shapes** depending on whether the
target endpoint is a batch `:mutate` endpoint or a single-object endpoint
(`:create`, `:apply`, `:run`, `:dismiss`, `:addOperations`). The apply
contract picks based on which field is present:

| Proposal has        | Apply constructs request body as                              | Use for                                                                  |
|---|---|---|
| `operations: [...]` | `{ "operations": [...], "validateOnly": <validate_first> }`   | Batch `:mutate` endpoints (campaignCriteria, adGroupCriteria, assets…)   |
| `body: {...}`       | The `body` object passed through, with `"validateOnly": true` injected at the root if `validate_first: true` | Non-batch endpoints (`offlineUserDataJobs:create`, `:run`, single-object creates) |
| Neither             | `{}`                                                          | Parameterless endpoints (`:run`, `:dismiss` with just resourceName in path) |

`validateOnly` is injected only when `validate_first: true` AND the
endpoint accepts it. Endpoints that don't accept `validateOnly`
(`recommendations:apply`, `recommendations:dismiss`,
`offlineUserDataJobs:run`) are documented per-kind in the change-execution
kinds table and skip the dry-run.

After the dry-run passes, the live request body is identical with
`validateOnly` flipped to `false` (or removed entirely on endpoints that
treat its absence as "live").

## Pseudo-code

```
1. Read workspace/proposals/<id>.md, extract last fenced ```json block.
2. Parse JSON. Verify .account_id == workspace.json .account.customer_id.
   On mismatch: print "REFUSED: proposal account_id mismatch" and stop.
3. Determine the request body shape per the table above (operations[] | body | empty).
4. If validate_first is true AND the endpoint accepts validateOnly:
   - Build dry-run body with validateOnly:true
   - Call: "${CLAUDE_PLUGIN_ROOT}/bin/ga" proxy <method> <endpoint> '<dry-run-body>'
   - If error: print Google's structured error, leave proposal in place, stop
5. Print chat diff: "About to apply <kind>: <summary of operations>. Proceed? (y/n)"
6. On 'y':
   - Build live body (no validateOnly, or validateOnly:false)
   - Call bin/ga proxy with the live body
   - For each op (or for the single non-batch call), append to
     workspace/change-log/$(date +%Y-%m-%d).jsonl:
     {"ts":"<iso>","proposal_id":"<id>","op":"<kind>","request":<op-or-body>,"response":<resp>,"applied":true}
   - mv workspace/proposals/<id>.md workspace/proposals/applied/<id>.md
   - Print "Applied. N operations live. Logged to change-log/."
7. On 'n':
   - Leave proposal in place. Print "Skipped. Re-run /google-ads-copilot:apply <id> later."
```

## Change-log line shape

One JSON line per applied operation (or per non-batch call). Newline-
terminated. Append-only. Never edit; the file's an audit trail.

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
| Endpoint doesn't accept validateOnly | Skip dry-run, proceed to confirm prompt; surface "no dry-run available for <endpoint>" in chat |
| Operator answers 'n' at the diff prompt | Leave proposal in place, exit zero, no change-log entry |
| Live mutate returns error after dry-run passed | Append `applied:false` line to change-log with the error response, leave proposal in place |
| `mv` of proposal to `applied/` fails | Log to change-log but warn — the mutation already shipped, the operator should manually move the file |

The first three are expected paths. The last two are unexpected and the
operator should be loud about them in chat ("⚠️ The mutation shipped
but I couldn't move the proposal — manually mv workspace/proposals/X to
workspace/proposals/applied/").

## Per-kind inverse rules (canonical)

Used by `/google-ads-copilot:undo` to draft the inverse of an applied
proposal. Read the original proposal from `workspace/proposals/applied/`
+ its change-log entry, then construct the inverse op per this table.
The inverse is a new proposal that goes through the normal apply flow.

| kind                    | invertible? | inverse construction                                                                                          |
|---|---|---|
| `negatives`             | yes         | `remove` op against each criterion `resourceName` from the original response.                                |
| `budget`                | yes         | `update` `amountMicros` back to the original value (read from the original proposal's `metadata.previous_amount`, or compute from change-log if absent). `updateMask: amountMicros`. |
| `creative-pause`        | yes (best-effort) | Re-`create` link with the same `adGroupAd` + `asset` + `fieldType` from the change-log's request. The asset itself wasn't deleted, so the link can be restored.                |
| `creative-add`          | yes         | `remove` op against each link `resourceName` from the original response.                                      |
| `assets-add`            | yes (cascade-aware) | `remove` op on `assets:mutate` for each asset `resourceName`. **Warn if the asset is also linked elsewhere** (query `customerAssets`/`campaignAssets` for the asset before removing). Prefer `assets-unlink` against orphaning links first. |
| `assets-link`           | yes         | `remove` op against each customerAsset/campaignAsset link `resourceName` from the original response.          |
| `assets-unlink`         | yes         | Re-`create` link with the same `asset` + `fieldType` from the original request.                               |
| `keyword-add`           | yes         | `remove` op against each criterion `resourceName` from the original response.                                |
| `keyword-pause`         | yes         | `update` `status: ENABLED` + `updateMask: status` against each criterion resource name.                       |
| `campaign-toggle`       | yes         | `update` flipping `status` back (PAUSED → ENABLED or vice-versa) + `updateMask: status`.                      |
| `ad-toggle`             | yes         | `update` flipping `status` back + `updateMask: status`.                                                        |
| `bid-adjust`            | yes         | If the original proposal's `metadata.previous_modifier` was null: `remove` the criterion (created by the original). Else `update` `bidModifier` back to the previous value + `updateMask: bidModifier`. |
| `conversion-action-mod` | yes (best-effort) | `update` fields back to their pre-change values from the original proposal's `metadata.previous_*`. If those weren't recorded, refuse with explanation; the operator must restore manually. |
| `customer-match-upload` | **NO**       | Refuse with: "customer-match-upload is non-invertible. Google's offline matching can't be cleanly reversed mid-run. Manually scrub via a new proposal — see `examples/customer-match.md` 'Inverse for /undo' section." |
| `recommendation-apply`  | **NO**       | Refuse with: "recommendation-apply is non-invertible. Google's apply may have spawned downstream entities (assets, links, criteria). Print the spawned resource names from the change-log; draft kind-specific undos against each (e.g. `assets-unlink` for spawned extension links)." |
| `recommendation-dismiss`| n/a          | No inverse needed — recs naturally resurface when conditions warrant. The operator can wait or `/recommendations` again to see if it's back. |

The undo proposal's `metadata.inverse_of: <original-id>` links the audit
trail. The original applied proposal stays in `applied/` — both the
forward and reverse changes are preserved in the change-log.

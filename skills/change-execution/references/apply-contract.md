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

## Dashboard-drift detection (cross-kind)

`/google-ads-copilot:undo` MUST query the current live value of every
field it's about to invert before drafting the inverse op. If the live
value differs from BOTH the original proposal's pre-value AND its
post-value, the operator changed it manually in the dashboard between
apply and undo — the inverse would silently overwrite that manual
change.

The pattern (per kind, in pseudo-code):

```
1. Read original applied proposal + change-log entry.
2. For each updated field, read metadata.previous_<field> (pre) and
   the change-log response (post).
3. Query the current live value via gaql / bin/ga for the same resource.
4. If current != pre AND current != post:
   refuse with: "⚠️ dashboard-drift detected on <field>:
                  live=<current>, apply pre=<pre>, apply post=<post>.
                  Re-run /undo with --force to overwrite, or draft a
                  fresh <kind> proposal targeting the value you want."
5. Else proceed with normal inverse construction below.
```

Applies to every `update`-flavored kind — fields the operator might
also touch in the dashboard:

- `budget` (`amount_micros`)
- `bidding-target-tune` (`target_cpa.target_cpa_micros` /
  `target_roas.target_roas`)
- `bidding-strategy-shift` (`bidding_strategy_type` — any non-equal
  current value is drift)
- `conversion-action-mod` (every updated field: `primary_for_goal`,
  `click_through_lookback_window_days`, `attribution_model_settings.attribution_model`,
  `value_settings.default_value`)
- `campaign-setting-update` (every updated field — `geo_target_type_setting.positive_geo_target_type`,
  `network_settings.*`, etc.)
- `bid-adjust` (`bid_modifier` on the target criterion)
- `keyword-pause` / `ad-toggle` / `campaign-toggle` (`status` —
  flip-only inverse, drift = operator already toggled)

Does NOT apply to additive `create` kinds. The inverse is `remove` by
resource-name; if the operator already removed the resource externally,
the live mutate returns `RESOURCE_NOT_FOUND` and the change-log records
`applied:false` — no silent overwrite is possible:

- `negatives`, `keyword-add`, `creative-add`, `creative-pause` (re-link),
  `assets-add`, `assets-link`, `assets-unlink` (re-link), `audience-attach`,
  `audience-detach` (re-link), `customer-negative-criterion-add`

Per-kind rows below mark drift-checked kinds with **drift-checked**.
The original `budget` rule already documents the full check verbatim
as the canonical example; other rows reference back to this section.

## Per-kind inverse rules (canonical)

Used by `/google-ads-copilot:undo` to draft the inverse of an applied
proposal. Read the original proposal from `workspace/proposals/applied/`
+ its change-log entry, then construct the inverse op per this table.
The inverse is a new proposal that goes through the normal apply flow.

| kind                    | invertible? | inverse construction                                                                                          |
|---|---|---|
| `negatives`             | yes         | `remove` op against each criterion `resourceName` from the original response.                                |
| `budget`                | yes (with drift check) | `update` `amountMicros` back to `metadata.previous_amount` + `updateMask: amountMicros`. **Before drafting, query the campaign budget's current `amount_micros`.** If it differs from BOTH the original proposal's pre-value AND post-value, the operator changed the budget in the dashboard between apply and undo — refuse the undo, print: "current amount €X differs from the apply's pre €Y and post €Z; dashboard-edit detected. Re-run /undo with --force or draft a fresh `budget` proposal targeting the value you want." This prevents silently overwriting an intentional manual change. |
| `creative-pause`        | yes (best-effort) | Re-`create` link with the same `adGroupAd` + `asset` + `fieldType` from the change-log's request. The asset itself wasn't deleted, so the link can be restored.                |
| `creative-add`          | yes         | `remove` op against each link `resourceName` from the original response.                                      |
| `assets-add`            | yes (cascade-aware) | `remove` op on `assets:mutate` for each asset `resourceName`. **Warn if the asset is also linked elsewhere** (query `customerAssets`/`campaignAssets` for the asset before removing). Prefer `assets-unlink` against orphaning links first. |
| `assets-link`           | yes         | `remove` op against each customerAsset/campaignAsset link `resourceName` from the original response.          |
| `assets-unlink`         | yes         | Re-`create` link with the same `asset` + `fieldType` from the original request.                               |
| `keyword-add`           | yes         | `remove` op against each criterion `resourceName` from the original response.                                |
| `keyword-pause`         | yes — **drift-checked** | `update` `status: ENABLED` + `updateMask: status` against each criterion resource name. Drift check (see above): refuse if the criterion's live status doesn't match the apply's pre or post. |
| `campaign-toggle`       | yes — **drift-checked** | `update` flipping `status` back (PAUSED → ENABLED or vice-versa) + `updateMask: status`. Drift check: refuse if the campaign's live status differs from both the apply's pre and post. |
| `ad-toggle`             | yes — **drift-checked** | `update` flipping `status` back + `updateMask: status`. Drift check: refuse if the ad's live status differs from both pre and post. |
| `bid-adjust`            | yes — **drift-checked** | If the original proposal's `metadata.previous_modifier` was null: `remove` the criterion (created by the original). Else `update` `bidModifier` back to the previous value + `updateMask: bidModifier`. Drift check on the live `bid_modifier`: refuse if it differs from both the apply's pre and post (operator manually re-tuned the modifier in the dashboard). |
| `conversion-action-mod` | yes (best-effort) — **drift-checked** | `update` fields back to their pre-change values from the original proposal's `metadata.previous_*`. If those weren't recorded, refuse with explanation; the operator must restore manually. Drift check **per field**: query the conversion action's current values; refuse the field's inverse if it differs from both pre and post (operator manually edited the action in the dashboard). |
| `bidding-strategy-shift` | yes (best-effort) — **drift-checked** | `update` `bidding_strategy_type` + matching target back to `metadata.previous_strategy` + `metadata.previous_target_*`. Drift check: query the campaign's current `bidding_strategy_type`; refuse if it differs from both pre and post (operator switched strategy manually). **Warn loudly**: a strategy switch invalidates the strategy's learning, so even a perfect inverse means the campaign re-enters `LEARNING_NEW` for ~14 days. Surface this before applying the undo. |
| `bidding-target-tune` | yes — **drift-checked** | `update` `target_cpa.target_cpa_micros` / `target_roas.target_roas` back to `metadata.previous_target_micros` / `metadata.previous_target_roas` + matching `updateMask`. Single-step ±15% cap doesn't apply to undo (restoring is exact). Drift check: query the campaign's current target; refuse if it differs from both pre and post (operator manually tuned the target in the dashboard). |
| `campaign-setting-update` | yes — **drift-checked** | `update` the changed field(s) back to `metadata.previous_*` values + identical `updateMask`. For `geo_target_type_setting.positive_geo_target_type`: PRESENCE → PRESENCE_OR_INTEREST flip is exact-reversible. Drift check **per field** in the original updateMask: refuse the field's inverse if its live value differs from both pre and post. |
| `customer-match-upload` | **NO**       | Refuse with: "customer-match-upload is non-invertible. Google's offline matching can't be cleanly reversed mid-run. Manually scrub via a new proposal — see `examples/customer-match.md` 'Inverse for /undo' section." |
| `recommendation-apply`  | **NO**       | Refuse with: "recommendation-apply is non-invertible. Google's apply may have spawned downstream entities (assets, links, criteria). Print the spawned resource names from the change-log; draft kind-specific undos against each (e.g. `assets-unlink` for spawned extension links)." |
| `recommendation-dismiss`| n/a          | No inverse needed — recs naturally resurface when conditions warrant. The operator can wait or `/recommendations` again to see if it's back. |
| `audience-attach`       | yes         | `audience-detach` (`remove` op) against the assetGroupSignal / adGroupCriterion `resourceName` returned by the original create. |
| `audience-detach`       | yes         | `audience-attach` (`create` op) re-creating the link with the same audience + asset_group / ad_group from the original request. |
| `customer-negative-criterion-add` | yes | `remove` op against each `customerNegativeCriterion` `resourceName` from the original response. Note: removing a customer-level negative re-enables the query across **all** campaigns, including any non-PMax campaigns that benefited from the block — surface in undo's TL;DR. |

The undo proposal's `metadata.inverse_of: <original-id>` links the audit
trail. The original applied proposal stays in `applied/` — both the
forward and reverse changes are preserved in the change-log.

# Example: Customer Match upload (kind = customer-match-upload)

Customer Match lets you target (or exclude) people by uploading a
hashed list of email addresses and/or phone numbers. The Google Ads API
flow is multi-step:

1. Create a `userList` of type `CRM_BASED_USER_LIST` (the container)
2. Create an `offlineUserDataJob` referencing that list
3. Add operations to the job (one per user record, with hashed PII)
4. Run the job (Google processes asynchronously, ~hours to days for matching)

Because this spans 4 endpoints, the plugin treats it as a sequence of
proposals. Step 4 is async — the operator polls status separately.

## Threshold check before drafting

Customer Match doesn't activate (audience usable for targeting/exclusion)
until Google matches **≥ 1,000 users** per segment. Below threshold the
list exists but doesn't drive impressions. Verify the operator has
≥ 1k matchable records before drafting any proposal.

## Hashing requirement

Email and phone fields must be **SHA-256 lowercase normalized hex**
strings, not raw values. Compute client-side; the API rejects raw PII.

```
email: "alice@example.com" → "f04b0ad0e2..."
phone: "+15551234567" → "1f6fa9e27d..."
```

The plugin's apply contract does NOT hash — the operator must pre-hash
the CSV. Document this in the proposal's TL;DR.

## Proposal A: create the user list

`workspace/proposals/2026-05-03-cm-list-create-01.md`

```json
{
  "proposal_id": "2026-05-03-cm-list-create-01",
  "kind": "customer-match-upload",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/userLists:mutate",
  "validate_first": true,
  "operations": [
    {
      "create": {
        "name": "Trial signups — re-engage",
        "description": "Users who signed up for trial but did not convert to paid; for re-engagement campaigns",
        "membershipLifeSpan": 540,
        "crmBasedUserList": {
          "uploadKeyType": "CONTACT_INFO",
          "dataSourceType": "FIRST_PARTY"
        }
      }
    }
  ],
  "metadata": {
    "step": "1-of-4",
    "next_proposal": "2026-05-03-cm-job-create-01"
  }
}
```

`membershipLifeSpan: 540` = max (540 days). Lower for shorter retention.

## Proposal B: create the offline job

`offlineUserDataJobs:create` is a **non-batch** endpoint — it takes a
single `job` object at request-body root, not an `operations` array. Use
the envelope's `body` field instead of `operations[]`. (See
[`references/apply-contract.md`](../references/apply-contract.md#request-body-construction)
for the operations-vs-body rule.)

`workspace/proposals/2026-05-03-cm-job-create-01.md`

```json
{
  "proposal_id": "2026-05-03-cm-job-create-01",
  "kind": "customer-match-upload",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/offlineUserDataJobs:create",
  "validate_first": true,
  "body": {
    "job": {
      "type": "CUSTOMER_MATCH_USER_LIST",
      "customerMatchUserListMetadata": {
        "userList": "<resourceName from proposal A>"
      }
    }
  },
  "metadata": {
    "step": "2-of-4",
    "depends_on": "2026-05-03-cm-list-create-01",
    "next_proposal": "2026-05-03-cm-job-add-01"
  }
}
```

## Proposal C: add user operations to the job

`workspace/proposals/2026-05-03-cm-job-add-01.md`

```json
{
  "proposal_id": "2026-05-03-cm-job-add-01",
  "kind": "customer-match-upload",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/offlineUserDataJobs/<job_id>:addOperations",
  "validate_first": false,
  "operations": [
    {
      "create": {
        "userIdentifiers": [
          { "hashedEmail": "<sha256-hex of normalized email>" },
          { "hashedPhoneNumber": "<sha256-hex of E.164 phone>" }
        ]
      }
    },
    { "create": { "userIdentifiers": [ { "hashedEmail": "<sha256-hex>" } ] } }
    // ... up to 100,000 ops per request, paginate larger lists
  ],
  "metadata": {
    "step": "3-of-4",
    "depends_on": "2026-05-03-cm-job-create-01",
    "user_count": 1247,
    "next_proposal": "2026-05-03-cm-job-run-01"
  }
}
```

For lists > 100k, split into multiple `:addOperations` proposals
(C1, C2, …) before running the job.

## Proposal D: run the job

`offlineUserDataJobs/<id>:run` takes no body — the apply contract sends
an empty request when neither `operations` nor `body` is set in the
envelope. `validate_first: false` because `:run` doesn't accept
`validateOnly`.

`workspace/proposals/2026-05-03-cm-job-run-01.md`

```json
{
  "proposal_id": "2026-05-03-cm-job-run-01",
  "kind": "customer-match-upload",
  "account_id": "8191097521",
  "method": "POST",
  "endpoint": "/v23/customers/8191097521/offlineUserDataJobs/<job_id>:run",
  "validate_first": false,
  "metadata": {
    "step": "4-of-4",
    "depends_on": "2026-05-03-cm-job-add-01",
    "post_apply_note": "Job runs async — Google's matching takes hours to days. Poll status via `offlineUserDataJobs/<job_id>` until status = SUCCESS."
  }
}
```

After this lands, the user list slowly populates with matches.
The audience becomes usable for targeting once ≥ 1k users match.

## Apply order

```bash
/google-ads-copilot:apply 2026-05-03-cm-list-create-01    # → list resource name
# substitute resource name into proposals B/C/D, then:
/google-ads-copilot:apply 2026-05-03-cm-job-create-01     # → job ID
# substitute job_id into proposals C/D, then:
/google-ads-copilot:apply 2026-05-03-cm-job-add-01
/google-ads-copilot:apply 2026-05-03-cm-job-run-01
```

## Inverse for /undo

`customer-match-upload` is **non-invertible by /undo**. Reasons:
- Once a list is populated, removing it doesn't un-match users in
  Google's index immediately
- Google's offline jobs can't be cancelled mid-run
- If the operator wants to remove the audience: draft a new proposal
  with the inverse semantic (e.g. `userLists:mutate` with `remove` on
  the list resource name, optionally `addOperations` with `remove` user
  ops first to scrub the list)

The /undo command refuses with: "customer-match-upload is non-invertible.
Manually scrub via a new proposal — see `examples/customer-match.md`."

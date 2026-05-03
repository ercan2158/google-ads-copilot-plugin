---
description: First-run for a SaaS project. If no workspace.json exists, scaffolds it interactively (customer-id picker, currency/timezone, MCC, context/ stubs). Then runs a one-time deep audit + phased refactor plan. Read-only against the account.
argument-hint: (no arguments)
---

# /ads-bootstrap

Run as **ads-manager**. Load every skill the audit needs (gaql, account-audit
full, search-term-mining, budget-management, creative-management,
explain-to-beginner). Do NOT load change-execution — bootstrap doesn't draft
proposals; it produces a plan for the operator to consider.

## Stage A — Workspace scaffold (only if `workspace.json` is missing)

Walk up from cwd up to 5 levels looking for `workspace.json` (matches what
`bin/ga`'s `find_workspace` does). If found, skip to Stage B.

If missing, run the interactive scaffold:

1. **List accessible accounts.** Call:
   ```
   "${CLAUDE_PLUGIN_ROOT}/bin/ga" proxy GET /v23/customers:listAccessibleCustomers
   ```
   Parse `resourceNames` → list of `customers/<id>` strings. Strip the prefix
   to get raw customer IDs.

2. **Enrich with names + currency + timezone.** For each accessible ID,
   set `GA_CUSTOMER_ID=<id>` so `bin/ga` uses it instead of trying to
   resolve `workspace.json` (which doesn't exist yet during bootstrap):
   ```
   GA_CUSTOMER_ID=<id> "${CLAUDE_PLUGIN_ROOT}/bin/ga" query "SELECT customer.id, customer.descriptive_name, customer.currency_code, customer.time_zone, customer.manager FROM customer LIMIT 1"
   ```
   If a specific ID returns a `PERMISSION_DENIED` error, the operator
   doesn't have direct read access to that account — skip it but still
   list it as a raw ID in step 3 with a "(no read access)" note.

3. **Ask the operator to pick a customer.** Present a numbered list:
   ```
   Which Google Ads account do you want to bind to this project?

     1) 819-109-7521  Acme Yamazumi (EUR, Europe/Berlin) [child]
     2) 555-000-1234  Acme MCC (USD, America/Los_Angeles) [manager]
   ```
   The operator picks one. Refuse if they pick a `manager` account — they
   need to pick a child.

4. **Determine `manager_customer_id`.** If the chosen child account has a
   manager, ask: "Is this account managed by an MCC? If yes, what's the MCC
   customer ID? (default: none)". Capture the answer.

5. **Confirm currency + timezone.** Show the autodetected values, ask
   "Confirm? (Y/n) — or type override values."

6. **Pick a project root.** Ask "Where should `workspace.json` live? (default:
   the current directory `$(pwd)`)". Use the answer as `<PROJECT_ROOT>`.

7. **Write `workspace.json`** at `<PROJECT_ROOT>/workspace.json`:
   ```json
   {
     "account": {
       "customer_id": "<chosen>",
       "manager_customer_id": "<from step 4 or null>",
       "currency": "<EUR|USD|...>",
       "timezone": "<IANA tz>"
     }
   }
   ```

8. **Scaffold `context/` stubs** at `<PROJECT_ROOT>/context/`:
   - `icp.md` — "Describe your ideal customer profile in 3–5 bullets. Who
     are they, what pain do they have, what makes them choose you?"
   - `product-positioning.md` — "What's your one-line positioning? Top 3
     value props? Direct competitors you DO/DON'T bid on?"
   - `budget-policy.md` — "Monthly budget? Per-campaign caps? CPA target?
     ROAS floor?"
   - `kpi-tree.md` — "North-star KPI → leading indicators → ad-level
     metrics. What does success look like in 30/90 days?"
   - `persona-overrides.md` — "Who is NOT your customer? Free-tier seekers,
     hobbyists, students — anyone who shouldn't trigger your ads."

   Each stub gets a one-line frontmatter comment + the prompt above as
   placeholder content. Tell the operator: "Fill these in before running
   `/ads-weekly` or `/ads-monthly` — the agent reads them every run."

9. **Confirm scaffold.** Print:
   ```
   Scaffolded:
     <PROJECT_ROOT>/workspace.json
     <PROJECT_ROOT>/context/icp.md           (template — please fill in)
     <PROJECT_ROOT>/context/product-positioning.md
     <PROJECT_ROOT>/context/budget-policy.md
     <PROJECT_ROOT>/context/kpi-tree.md
     <PROJECT_ROOT>/context/persona-overrides.md

   Now running the deep audit. You can fill in the context files in
   parallel — they're read on every command, not just bootstrap.
   ```

Then proceed to Stage B with the just-created workspace.

## Stage B — Deep audit

1. Bind to workspace.
2. Run the full 8-section audit per ads-account-audit.
3. Write `workspace/audit/$(date +%Y-%m-%d)-bootstrap.md` with all 8 sections.
4. Write `workspace/refactors/$(date +%Y-%m-%d)-phased-plan.md` containing:
   - Phase 0 (now): things the operator should do manually outside this plugin
     (e.g. fix conversion tracking, link GA4, set up enhanced conversions)
   - Phase 1 (next 1–2 weeks): things `/ads-weekly` and `/ads-monthly` will
     handle once they start running (mining, budget-tuning, creative refresh)
   - Phase 2 (next 1–3 months): structural recommendations the operator
     should review (campaign restructure, new themes) — NOT v1 scope
5. Print TL;DR + section severity emojis + paths to both files.
6. Stop.

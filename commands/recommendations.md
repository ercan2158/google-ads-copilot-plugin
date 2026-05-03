---
description: Pull Google Ads' pending recommendations, score each against the operator's ICP/positioning/budget policy/KPI tree, and draft proposals for the ones worth applying. Read-only against the account; writes proposal files for accepted ones.
argument-hint: (no arguments)
---

# /google-ads-copilot:recommendations

Run as **manager**. Load **gaql**, **change-execution**,
**creative-management**, **search-term-mining**, **budget-management**,
**explain-to-beginner**.

## Steps

1. Bind to workspace.
2. Pull live recommendations via `gaql`'s "Pending Google recommendations"
   query.
3. For each rec, classify by `recommendation.type` → plugin kind:

   | Recommendation type            | Plugin kind                                         |
   |---|---|
   | `SITELINK_ASSET`               | `assets-add` + `assets-link` (paired)               |
   | `CALLOUT_ASSET`                | `assets-add` + `assets-link` (paired)               |
   | `CALL_ASSET`                   | `assets-add` + `assets-link` (paired)               |
   | `STRUCTURED_SNIPPET_ASSET`     | `assets-add` + `assets-link` (paired)               |
   | `KEYWORD`                      | `keyword-add`                                        |
   | `KEYWORD_MATCH_TYPE`           | `keyword-pause` + `keyword-add`                      |
   | `RESPONSIVE_SEARCH_AD`         | `creative-add`                                       |
   | `OPTIMIZE_TEXT_AD_AND_RSAS`    | `creative-add`                                       |
   | `CAMPAIGN_BUDGET`              | `budget`                                             |
   | `TARGET_CPA_OPT_IN`            | manual review (bidding strategy change)              |
   | `TARGET_ROAS_OPT_IN`           | manual review (bidding strategy change)              |
   | `MAXIMIZE_CONVERSIONS_OPT_IN`  | manual review (bidding strategy change)              |
   | `OPTIMIZE_AD_ROTATION`         | manual review (rare, low impact)                     |
   | `CUSTOMER_MATCH`               | `customer-match-upload` (only if ≥1k matched users)  |
   | `SEARCH_PARTNERS_OPT_IN`       | typically SKIP (low-quality traffic at small budgets)|
   | `PERFORMANCE_MAX_OPT_IN`       | typically SKIP unless conv ≥ 30/mo + tracking solid  |
   | (anything else)                | `recommendation-apply` if Google's auto-content fits |

4. **Score each rec** against the operator's context:
   - Read `context/icp.md`, `product-positioning.md`, `budget-policy.md`, `kpi-tree.md`
   - **✅ ACCEPT** — fits, expected lift > risk
   - **⚠️ CONDITIONAL** — accept only if a precondition holds (state it)
   - **❌ SKIP** — doesn't fit, or risk > expected lift, or anti-pattern per positioning

5. **For ACCEPTED recs:**
   - **`assets-add` + `assets-link`** (sitelinks/callouts/snippets/calls) — draft operator-aligned copy per `creative-management` rules (≤25 chars, persona-aligned, no duplicate openers). Two paired proposals — see `change-execution/examples/assets-flow.md`.
   - **`recommendation-apply`** — draft a single proposal accepting Google's auto-generated content. Use only when the operator's positioning doesn't constrain the copy. See `change-execution/examples/recommendation-apply.md`.
   - **`creative-add` / `budget` / `keyword-add`** — draft per the relevant skill's rules.

6. **For CONDITIONAL recs:** print the condition; don't draft. The operator clarifies, then re-run.

7. **For Customer Match recs:** check the operator's CRM list size first (in chat — "how many customer email records do you have?"). Threshold is ~1,000 hashed-and-matched users per segment for Google to activate the audience. Below threshold → CONDITIONAL with "wait until you cross 1k records".

8. **Print TL;DR + per-rec verdict + drafted proposals:**

   ```
   TL;DR: 4 recs reviewed. 3 ACCEPTED (sitelinks, callouts, structured snippets) — drafted 6 paired proposals. 1 CONDITIONAL (Customer Match — only after CRM ≥1k). 0 SKIPPED.

   | Type                       | Verdict        | Drafted                                                    |
   |---|---|---|
   | SITELINK_ASSET             | ✅ ACCEPT      | 2026-05-03-assets-add-01a-create + -01b-link               |
   | CALLOUT_ASSET              | ✅ ACCEPT      | 2026-05-03-assets-add-02a-create + -02b-link               |
   | STRUCTURED_SNIPPET_ASSET   | ✅ ACCEPT      | 2026-05-03-assets-add-03a-create + -03b-link               |
   | CUSTOMER_MATCH             | ⚠️ CONDITIONAL | (not drafted — see condition)                              |

   Apply order: run the create proposals first, capture asset resource names, then run the link proposals. /google-ads-copilot:apply <id>
   ```

9. **Stop.** Account untouched until operator runs `/google-ads-copilot:apply`.

## Plain-English rule

The operator doesn't know `RESPONSIVE_SEARCH_AD` vs `EXPANDED_TEXT_AD`. Translate every rec type to one line ("Google wants you to add a new ad with rotating headlines") in the chat output. The change-log keeps the technical type for traceability. See `explain-to-beginner` skill.

## Out of scope for this command

- Auto-applying anything. Even ACCEPTED recs require operator approval via `/google-ads-copilot:apply <id>`.
- Recs Google has already dismissed (filtered by `dismissed = FALSE` in the gaql query).
- Bidding-strategy changes (`TARGET_CPA_OPT_IN` etc.) — these are surfaced as "manual review" in the table; the operator decides in chat. The plugin doesn't auto-flip bidding strategies.

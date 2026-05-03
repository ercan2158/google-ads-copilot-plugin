---
name: account-audit
description: Use when running a Google Ads account audit — daily anomaly checks, weekly tactical reviews, full monthly audits, or first-time bootstrap. Provides the 10-section audit structure (spend, conversion-tracking health, smart-bidding health, search terms, creative, disapprovals + URL liveness, structure + quality + geo footgun, KPI alignment, brand defense, recommendations), a severity rubric (🔴 critical / 🟡 warning / 🟢 healthy), and which gaql queries + skills to invoke for each section.
---

# account-audit

Audit sections, in priority order. Sections 2 and 3 (conversion-tracking
+ smart-bidding) are *foundational* — every other read assumes they're
healthy. Run them first; if they're 🔴, cap section 4-10 findings as
"may be distorted by the upstream issue."

1. **Spend & pacing** — actual vs. expected at this point in the month, by campaign. Use the day-of-week-weighted pacing formula in `budget-management` (≥ 60d history) or fall back to flat. For deeper diagnosis when pacing is off, dimension the spend by **device**, **geo**, and **time-of-day** (queries in `gaql`) — drives `bid-adjust` proposals via `examples/bid-adjust.md`. Apply the conversion-lag adjustment per `kpi-tree.md`'s `lag_days`.

2. **Conversion-tracking health** — apply `conversion-health` skill. Pull the "Conversion-action diagnostic" + "Customer-level conversion tracking settings" queries from `gaql`. Score each ENABLED action across the 8 checks (category alignment, counting_type, attribution model, lookback windows, primary_for_goal, include_in_conversions_metric, value settings, volume floor). Flag enhanced-conversions opt-in status. **If this section is 🔴, every downstream audit metric stands on a broken foundation — surface that explicitly in the TL;DR.**

3. **Smart-bidding health** — apply `smart-bidding` skill. For each ENABLED campaign: bidding_strategy_type vs kpi-tree, bidding_strategy_system_status (LEARNING / LIMITED / MISCONFIGURED / NOT_ACTIVE), conversion-volume floor (≥30 for tCPA, ≥50 for tROAS), realized vs target hit-rate. Misalignments here move the dial more than mining ever will. May draft one bidding-strategy proposal per audit run.

4. **Search terms** — full mining via `search-term-mining` skill, including the close-variants advisory and lag-aware conversion thresholds. Cross-reference with branded-vs-non-branded performance (Section 9).

5. **Creative** — RSA asset performance via gaql skill; flag LOW assets. Pair with `ad_group_ad.ad_strength` (gaql "Ad-strength" query) — high-spend ads with `POOR` or `AVERAGE` ad_strength go to the top of the action list even before per-asset LOW analysis.

6. **Disapprovals + final-URL liveness** — any disapproved ads (gaql query). Then for each ENABLED ad's `final_urls`, run a HEAD request via `bin/ga`'s caller (or shell out via the agent's Bash tool):

   ```bash
   for url in $(echo "$ads_response" | jq -r '.results[].adGroupAd.ad.finalUrls[]?'); do
     status=$(curl -sS -o /dev/null -w "%{http_code}" -I --max-time 10 "$url" || echo "ERR")
     [[ "$status" =~ ^2 ]] || echo "🔴 $status $url"
   done
   ```

   Any non-2xx response is 🔴 — the operator just shipped a deploy that broke a paid landing page. Surface the campaign + ad. Disapprovals from Section 6 alone cover Google's *policy* checks; this catches *infrastructure* breakage that Google won't flag for ~24h.

7. **Structure sanity, quality score & geo footgun** —
   - Campaign count, ad-group count, keyword count per campaign. Flag campaigns with > 50 keywords (Google's recommended max for Search) or < 3 ads (no A/B coverage).
   - Pull "Quality score history" from `gaql`; flag any keyword spending > €5 with `quality_score ≤ 4` (drives `creative-management` review or `keyword-pause`). Note: `quality_info` is current state, not 30-day history; spend in the same row is 30d aggregate. Read the comparison as "this keyword right now has low QS and has spent significant money in the last 30 days."
   - Pull "Auction insights" (gaql); flag campaigns with `search_rank_lost_impression_share > 30%` (creative or bid issue) and `search_budget_lost_impression_share > 30%` (budget issue → `budget` proposal).
   - Pull "Geo-targeting setting" (gaql). Flag any ENABLED campaign where `positive_geo_target_type = 'PRESENCE_OR_INTEREST'` AND `context/icp.md` or `product-positioning.md` describes a strictly local product, region-locked SaaS, or single-country focus. PRESENCE_OR_INTEREST is Google's broadest default and silently shows ads to people *interested* in your country who live elsewhere — a steady source of unconverting clicks for B2B SaaS. Flag 🟡; recommend switching to `PRESENCE` via a `campaign-setting-update` proposal (see `change-execution`).

8. **KPI alignment** — read `context/kpi-tree.md`, compare current 30-day metrics (lag-adjusted), surface KPI gaps. Cross-reference against Section 2 — if a `primary_for_goal` action doesn't match the kpi-tree north-star, that's the issue, not the metrics.

9. **Brand defense** — pull "Branded vs non-branded search terms" (gaql), using brand terms from `context/product-positioning.md`. Surface:
   - Branded impression share (target ≥ 90%; 🔴 if < 70% — competitors stealing cheap brand-search conv)
   - Branded vs non-branded CPA ratio (branded should be < 30% of non-branded)
   - Whether a dedicated brand campaign exists (typically lower CPA, shouldn't share budget with generic). If absent and brand impressions exist → 🟡 recommend creating one (out of v1 mutation scope; flag in audit).

10. **Recommendations** — bullet list, ranked by expected € impact, separated into "I'll handle" (proposable) and "you decide" (out of v1 scope, structural). Cross-reference with `/google-ads-copilot:recommendations` output if Google's dashboard recommendations have surfaced relevant items. Audience-level findings from "Audience performance" gaql query land here as `bid-adjust` candidates.

## Severity rubric

- **🔴 critical** — money is being wasted right now, OR required tracking is broken (conv-action removed but still primary; counting_type inflating; final-URL 4xx/5xx; misconfigured-zero-eligibility on Smart Bidding).
- **🟡 warning** — drift from policy or best practice, but not actively losing money.
- **🟢 healthy** — performing per `context/budget-policy.md` and `context/kpi-tree.md`.

Apply per section. The TL;DR uses the *worst* severity across all
sections; an account with one 🔴 in Section 2 and 🟢 elsewhere should
not be reported as "healthy."

## Output target

- `/google-ads-copilot:monthly` writes `workspace/audit/<YYYY-MM>-monthly.md` with all 10 sections.
- `/google-ads-copilot:weekly` covers sections 1, 2 (light), 3 (light), 4, 5, 6 — quick weekly cycle. Conversion-tracking + smart-bidding light = "did anything change since last week?" not the full 8-check / 5-check audit.
- `/google-ads-copilot:bootstrap` writes `workspace/audit/<YYYY-MM-DD>-bootstrap.md` (full 10 sections) AND `workspace/refactors/<YYYY-MM-DD>-phased-plan.md` with the prioritized fix list as phases. Sections 2 + 3 land in Phase 0 (operator-must-fix-before-anything-else) when 🔴.
- `/google-ads-copilot:daily` does NOT call this skill; it has its own narrower checks.

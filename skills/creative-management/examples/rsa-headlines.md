# Example: RSA before/after for a B2B SaaS

A worked example showing how `creative-management`'s heuristics produce a
real proposal pair. Based on a hypothetical industrial-engineering SaaS
("Linelabs"); the agent should adapt voice and value props to the
operator's actual `context/icp.md` + `context/product-positioning.md`.

## What the gaql query returned

The "Responsive search ad asset performance" query in the `gaql` skill
returned this slice of the flagship campaign's RSA over the last 30 days:

| field_type   | text                                                       | performance_label |
|---|---|---|
| HEADLINE     | Improve Your Operations                                    | LOW               |
| HEADLINE     | Software for Manufacturing                                 | LOW               |
| HEADLINE     | Try It Free                                                | LOW               |
| HEADLINE     | Balance Lines in Minutes                                   | BEST              |
| HEADLINE     | Trusted by 500+ Plants                                     | GOOD              |
| HEADLINE     | Linelabs for Industrial Engineers                          | GOOD              |
| DESCRIPTION  | Our app helps you optimise efficiency.                     | LOW               |
| DESCRIPTION  | Cycle-time math, takt sync, line balancing — in one tool.  | GOOD              |

## Diagnose the LOW pattern

The four LOW assets share a vagueness pattern:

- **"Improve Your Operations"** — generic verb, no specific outcome
- **"Software for Manufacturing"** — category name, no differentiation
- **"Try It Free"** — generic CTA, no persona hook
- **"Our app helps you optimise efficiency."** — corporate hedge, no number

The GOOD/BEST assets share the opposite:
specific outcome (*"Balance Lines in Minutes"*),
social proof with a real number (*"500+ Plants"*),
persona-aligned (*"Industrial Engineers"*),
concrete mechanism (*"Cycle-time math, takt sync"*).

## Draft replacements

Read `context/icp.md` (industrial engineers at $50M+ plants, technically
deep) and `context/product-positioning.md` (line-balancing math, replaces
spreadsheets, on-prem option for plants that won't cloud-store production
data). Then draft six new assets:

| Asset type   | Text                                                                                  | Coverage                                |
|---|---|---|
| HEADLINE     | Cut Cycle Time 18% in 90 Days                                                         | Outcome + timeline                      |
| HEADLINE     | Stop Balancing Lines in Excel                                                         | Persona pain — spreadsheet drudgery     |
| HEADLINE     | Used by Toyota Suppliers                                                              | Social proof, credible name             |
| HEADLINE     | See Your Bottleneck Today                                                             | CTA with concrete promise               |
| HEADLINE     | Math, Not Guesswork                                                                   | Differentiation against intuition tools |
| DESCRIPTION  | Industrial engineers cut takt-time variance in days. Free 14-day pilot, no setup fee. | Pain → outcome → CTA, ≤90 chars         |

**Constraints validated before proposing:**

- Headlines ≤ 30 chars, descriptions ≤ 90 chars (Google's hard limits)
- No two headlines start with the same word ("Cut", "Stop", "Used", "See", "Math" — all distinct)
- Coverage spans value-prop, pain, social proof, CTA, differentiation —
  minimum diversity per `creative-management`'s heuristics
- Tone matches the existing GOOD/BEST assets (concrete + numeric)

## The paired proposals

This becomes two `change-execution` proposals filed on the same day:

| Proposal ID                       | Kind             | Operations                                  |
|---|---|---|
| `2026-05-03-creative-01a-pause`   | `creative-pause` | `remove` the 4 LOW asset resourceNames      |
| `2026-05-03-creative-01b-add`     | `creative-add`   | `create` the 6 new headlines + descriptions |

The operator runs both via `/google-ads-copilot:apply <id>`. Both must
succeed for the change to land cleanly. After the pair applies, the RSA
has 8 active headlines (3 GOOD/BEST kept + 5 new) and 4 active
descriptions (1 GOOD kept + 3 new) — comfortably above Google's
3-headline floor and back at the recommended 8-headline target, with
the LOW-noise gone.

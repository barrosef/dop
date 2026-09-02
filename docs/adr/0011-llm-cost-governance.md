# ADR-0011 — LLM cost governance: firm measurement, routing in draft

- **Status:** **Draft** (measurement and budget: firm; routing: to evolve)
- **Date:** 2026-08-29
- **Resolves:** F-6 — see `docs/analysis/2026-08-29-platform-critical-review.md`

## Context

N autonomous agents × long sessions × multi-tenant = the product's largest variable cost
line — and no document had a line about it. With no per-account measurement there is no
business model; with no per-demand budget, a pathological demand burns money in a loop; with
no routing, everything runs on the most expensive model.

## Decision

Two firm parts and one in draft:

1. **Measurement from day one (firm).** Every model use emits a cost event (tokens, model,
   demand, thread, account) in the demand's log (ADR-0006). Measurement is a projection — no
   parallel system.
2. **A per-demand budget with a soft cut (firm).** On an overrun: the demand **pauses and
   asks** (the attention box), never dies mid-way and never keeps burning. The mechanism: the
   API's **task budgets** — the agent sees the ceiling and paces itself, finishing gracefully
   instead of being cut off; the card's budget (ADR-0010) is the per-thread slice.
3. **`ModelRouter` (draft — to evolve).** A port that chooses **model + effort** per type of
   work. The initial table (to be calibrated with telemetry — P-7):

   | Work | Model | Effort |
   |---|---|---|
   | Mechanical: a commit, a log summary, the dossier, i18n | cheap (the Haiku class) | low |
   | A subagent's investigation (logs, forensics) | medium (the Sonnet class) | medium |
   | Planning and implementation | strong | high/xhigh |
   | **The critic** (ADR-0007) | strong | **max** |

   A fixed rule: **there is no saving on the critic** — it is the brake. The price spread
   between classes is ~5×; the effort reduces tool calls and preamble within the class.
4. **Cache telemetry (firm).** The cost event carries `cache_read` and `cache_creation`; a
   recurring cache miss on a stable prefix is an alert (ADR-0012).

## Alternatives considered

**A single strong model for everything.** Simple and expensive; it becomes a ceiling on the
margin.

**Routing by a prompt-size heuristic.** Rejected: what matters is the task's nature, not its
length.

## Consequences

- ➕ Cost visible per demand/account before there is any billing.
- ➕ The port follows ADR-0001: model providers change leader every six months.
- ➖ The routing policy needs calibrating with real data — hence a draft: the task→model
  table will be revised with F-7's telemetry.

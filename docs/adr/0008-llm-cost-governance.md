# ADR-0008 — The LLM's cost: measuring it, capping it, routing it, and spending less

- **Status:** Accepted; the routing table (§3) is a draft to be calibrated with telemetry
- **Date:** 2026-08-29
- **Relations:** relies on ADR-0004 (cost events), ADR-0006 (the package), ADR-0007 (per-thread quarantine); refined by ADR-0016 (policy vs catalogue per vendor)

## Context

Model usage is the product's largest variable cost. An agent loop resends
the conversation on every turn; the APIs offer prefix caching (up to ~90%
discount on cached input) and batching (~50%), both requiring the prompt to
be designed for them.

## Decision

1. **Measurement.** Every model use emits a cost event (tokens in/out, cache
   read, cache creation, model, demand, thread, account) into the demand's
   log. Measurement is a projection. A recurring cache miss on a stable
   prefix is an alert.
2. **Budget.** A per-demand budget with a soft cut: on overrun the demand
   pauses and opens an attention item. The agent is told its ceiling (the
   API's task budget). A card's budget (ADR-0007) is the per-thread slice.
3. **`ModelRouter`** chooses a class and an effort per kind of work; the
   `ModelCatalog` resolves the class to a concrete model of the active
   provider (ADR-0016).

   | work | class | effort |
   |---|---|---|
   | mechanical (commit message, log summary, dossier, i18n) | cheap | low |
   | a subagent's investigation | medium | medium |
   | planning and implementation | strong | high / xhigh |
   | the critic (ADR-0005) | strong | max — **never reduced** |

4. **Cache-first prompt layout:** `[system → deterministic tools → context
   package] → cache breakpoint → conversation`. The context package is
   serialized deterministically (stable order, no timestamps, no volatile
   ids). An operator's intervention is a `system` message inside the
   conversation, never an edit of the prefix.
5. **Dirty context does not enter the main agent:** voluminous tool output
   stays in the specialist's thread; filters run as code in the sandbox
   where possible; findings and verdicts use structured outputs; raw tool
   results are removed from an investigation thread once its finding is
   published.
6. **Resume is by reconstruction:** a resumed demand rebuilds its context
   from the package, the findings and a trace summary; the transcript is not
   resent.
7. **Projections are computed in code**, never by a model.
8. **Non-interactive work uses the Batch API:** index regeneration after a
   merge, memory pruning, dossier summaries, nightly metrics.
9. **Tools are loaded on demand** (tool search with deferred loading) in
   workspaces with many tools; schemas are appended, not swapped.

## Alternatives considered

- **One strong model for everything** — rejected: cost ceiling.
- **Routing by prompt size** — rejected: the task's nature decides.
- **A router alone** — rejected: it does not address transcript resending.
- **Compaction as the resume mechanism** — rejected: reconstruction from
  events is cheaper.

## Consequences

- Cost is visible per demand and account before any billing exists.
- The package's deterministic serialization is a permanent constraint on
  ADR-0006.
- The routing table and the resume summary are calibrated with telemetry
  (`ROADMAP.md` P-7).

## Revisions

- 2026-09-04 — consolidated two records (measurement and budget; token
  economy) into one.

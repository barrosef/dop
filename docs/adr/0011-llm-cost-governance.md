# ADR-0011 — The LLM's cost: measuring it, capping it, routing it, and spending less

- **Status:** Accepted, with one part in **draft** (measurement, budget and token economy:
  firm; the routing table: to be calibrated)
- **Date:** 2026-08-29 · **consolidated 2026-09-04**
- **Absorbs:** ADR-0012 (token economy as an engineering discipline) — it was already declared
  a complement to this one: this measures and caps, that one spends less. That number is
  **retired and never reused**.
- **Resolves:** F-6 — see `docs/analysis/2026-08-29-platform-critical-review.md`

## Context

N autonomous agents × long sessions × multi-tenant = the product's largest variable cost line
— and no document had a line about it. With no per-account measurement there is no business
model; with no per-demand budget, a pathological demand burns money in a loop; with no routing,
everything runs on the most expensive model.

And underneath all three: in an agent loop **the whole conversation is resent on every turn** —
a 40-turn agent pays for the transcript 40 times. The API offers mechanisms with a discount of
up to 90% (cache) and 50% (batch), but none of them is a flag; they all require engineering
discipline. Half the saving does not even come from the API: it comes from architecture
decisions DOP had already taken for other reasons (per-subagent quarantine, findings,
projections in code).

## Decision

### 1. Measurement from day one

Every model use emits a cost event (tokens, model, demand, thread, account) in the demand's log
(ADR-0006). Measurement is a projection — no parallel system. The event carries `cache_read`
and `cache_creation`: a recurring cache miss on a stable prefix is an **alert**, not a mystery.

### 2. A per-demand budget with a soft cut

On an overrun the demand **pauses and asks** (the attention box) — it never dies mid-way and
never keeps burning. The mechanism: the API's **task budgets**, so the agent sees the ceiling
and paces itself, finishing gracefully instead of being cut off. The card's budget (ADR-0010)
is the per-thread slice.

### 3. `ModelRouter` — the table is a draft

A port that chooses **model + effort** per type of work. The initial table (to be calibrated
with telemetry — P-7):

| Work | Model | Effort |
|---|---|---|
| Mechanical: a commit, a log summary, the dossier, i18n | cheap (the Haiku class) | low |
| A subagent's investigation (logs, forensics) | medium (the Sonnet class) | medium |
| Planning and implementation | strong | high/xhigh |
| **The critic** (ADR-0007) | strong | **max** |

The price spread between classes is ~5×; the effort reduces tool calls and preamble within the
class.

### 4. Cache-first: the prompt is designed for a stable prefix

- A fixed layout: `[system → deterministic tools → context package] → breakpoint →
  conversation`. A cache read costs ~0.1× of the input; a write 1.25× (5 min TTL) — the stable
  part comes out at ~10% of the price.
- **The context package is serialized deterministically**: a stable order, no timestamps, no
  volatile IDs. A changed byte in the prefix invalidates everything from there on.
- An operator's intervention comes in as a **`system` message in the middle of the
  conversation** (a native mechanism, it preserves the prefix) — never by editing the top of
  the prompt.

### 5. Dirty context does not enter the main agent

- Per-subagent quarantine (ADR-0010): logs, dumps and voluminous reads live in the specialist's
  thread; the main agent receives the **finding**. Where it fits, **programmatic tool calling**:
  the filter runs as code in the sandbox and only the final result passes through the model.
- **Context editing** in the investigation threads: once the finding is published, the raw tool
  results leave the transcript.
- Findings and opinions use **structured outputs**: terse, validated, with no re-parse.

### 6. Resuming by reconstruction, not by replay

A suspended demand that resumes days later does **not** resend the transcript (expensive, and
the cache has expired anyway): the context is rebuilt from scratch — package + findings + a
summary of the trace. Events and findings are the material for the reconstruction; compaction
is a safety net within a continuous session, not a resume mechanism.

### 7. Do not use an LLM where code does the job

The dossier, the metrics, the auditing and the attention box are projections of the event log
(ADR-0006), computed in code. Token cost: zero.

### 8. Asynchronous work goes to the Batch API (a 50% discount)

Regenerating the index after a merge, pruning the memory, dossier summaries, nightly metrics —
none of it is interactive; all of it runs in batch.

### 9. Tools on demand

Workspaces with many MCPs use **tool search with deferred loading**: the agent does not load the
schema catalogue — it searches for and loads what the task asks for, preserving the cache
(schemas are appended, not swapped).

### The rule that limits all the others

**There is no saving on the critic** (ADR-0007): a strong model, maximum effort. Saving on the
brake returns the cost as a rejected PR — the most expensive rework in the flow.

## Alternatives considered

**A single strong model for everything.** Simple and expensive; it becomes a ceiling on the
margin.

**Routing by a prompt-size heuristic.** Rejected: what matters is the task's nature, not its
length.

**Handling cost with a model router alone.** Not enough: the biggest waste in an agent loop is
resending the transcript, and the router does not touch it.

**Compaction as a resume mechanism.** Rejected: reconstruction from events is cheaper, cleaner
and we already have the material (ADR-0006/0009/0010).

## Consequences

- ➕ Cost visible per demand/account before there is any billing, and waste becomes visible: a
  cache miss is an alert.
- ➕ The saving comes mostly from decisions already taken — this ADR turns them into a rule.
- ➕ The port follows ADR-0001: model providers change leader every six months.
- ➖ The routing policy needs calibrating with real data — hence the draft status of §3: the
  task→model table will be revised with F-7's telemetry.
- ➖ The package's deterministic serialization is a permanent constraint on ADR-0009.
- ➖ Reconstruction on resume has to be demonstrably sufficient — if the agent "forgets" what
  mattered, it is the trace's summary that is weak; calibrate with F-7.

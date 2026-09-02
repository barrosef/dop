# ADR-0009 — Context is a subsystem: a knowledge base and a package per demand

- **Status:** Accepted
- **Date:** 2026-08-29
- **Resolves:** F-2 — see `docs/analysis/2026-08-29-platform-critical-review.md`

## Context

What separates a useful agent from a useless one in 2026 is context: the project's rules,
the code's map, the memory of what has already been tried. In the requirements this showed
up as "context created by Claude" and "the workspace's rules" — with no entity, no port, no
mechanism. The product's directive is explicit: documentation in secure, available and
permissioned storage, reachable from the microVMs, "so that the agents work in a genuinely
intelligent way".

The storage is the easy half. The half that generates intelligence is **what** is in there
and **how** it is assembled per demand.

## Decision

1. **A knowledge base per project**, versioned, with three layers:
   - **Rules** — the conventions the agent obeys ("never merge `develop` into the feature");
   - **The index** — the code's map: what lives where, how to build, how to test. Without
     it, every demand spends its first 30 minutes rediscovering the repository;
   - **Memory** — findings and lessons from past demands, ADRs, forensic readings (the
     artifacts the dossier already promised).
2. **Access through a port** (`KnowledgeStore`, over `ObjectStore` — ADR-0001), in storage
   permissioned per account/project, exposed to the sandbox **read-only** during execution.
3. **A context package per demand**, assembled when the sandbox is provisioned: the demand's
   spec + the rules + the index of the repositories involved + the relevant memories. It is
   the agent's carry-on luggage — curated, not dumped.
4. **A write-back at closing**: the demand's findings (ADR-0010) and lessons go into the
   memory layer. Context is a cycle, not a file.
5. **The index updates on a merge event** (ADR-0006/0008), not on a cron: the map follows
   the real `main`.

## Alternatives considered

**A raw document folder in the sandbox.** Rejected: with no curation and no assembly, the
agent digs — and digging is what the package exists to eliminate.

**Everything embedded in the prompt.** Rejected: it blows the context window and grows with
the project, not with the demand.

**An external RAG service per customer.** Deferred: the port allows plugging one in later;
starting there is buying infrastructure before having content.

## Consequences

- ➕ The agent is born knowing what this working session knows — rules, map, memory.
- ➕ Today's forensic reading is tomorrow's demand's context.
- ➖ Curation has a cost: assembling the package and judging a memory's relevance is real
  work for the orchestrator.
- ➖ Per-account storage with fine-grained permission — one more surface for the
  `SecretStore`/`ObjectStore` contract tests to cover.

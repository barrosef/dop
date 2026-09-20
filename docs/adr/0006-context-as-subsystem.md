# ADR-0006 — Context is a subsystem: a knowledge base and a package per demand

- **Status:** Accepted
- **Date:** 2026-08-29
- **Relations:** storage defined by ADR-0021 (the project root repository); relied on by ADR-0007, ADR-0008

## Context

An agent's usefulness depends on the project's rules, the code's map and the
memory of previous demands. Storage is permissioned per account and project
and reachable from the sandbox; what matters is what is stored and how it is
assembled per demand.

## Decision

1. **A knowledge base per project**, versioned, in three layers:
   - **rules** — the conventions the agent obeys;
   - **index** — one map per repository: what lives where, how to build, how
     to test;
   - **memory** — findings and lessons from past demands.

   Text lives in the project's root repository (`rules/`, `index/`,
   `memory/`, `demand/<id>/` — ADR-0021). Binary artifacts live in the
   `ObjectStore`, referenced from the repository.
2. **A context package per demand** is assembled when the sandbox is
   provisioned: the demand's spec + rules + the index of the repositories
   involved + the relevant memories. It is serialized deterministically
   (ADR-0008 §4) and is what enters the prompt.
3. **The package is curated; the repository is the shelf.** The complete
   root repository is cloned into the sandbox with a generated `README.md`
   manifest; the package is paid for per turn, the shelf only when a file is
   opened.
4. **Write-back at closing:** a demand's findings and lessons are committed
   into `memory/`.
5. **The index is regenerated on a merge event**, not on a schedule.

## Alternatives considered

- **A raw document folder as the only mechanism** — rejected: no curation.
- **Everything in the prompt** — rejected: grows with the project.
- **An external RAG service per customer** — deferred; the port allows it.

## Consequences

- Assembling the package and judging a memory's relevance is the
  orchestrator's work.
- Per-account, per-project permissions on the storage are covered by the
  `ProjectRepository` and `ObjectStore` contract suites.

## Revisions

- 2026-09-03 — text moved from the `ObjectStore` to the project root
  repository (ADR-0021); the shelf added alongside the package.

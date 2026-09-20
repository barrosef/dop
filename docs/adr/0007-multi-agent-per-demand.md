# ADR-0007 — Multi-agent per demand: addressable threads and published findings

- **Status:** Accepted
- **Date:** 2026-08-29
- **Relations:** relies on ADR-0004 (findings are events), ADR-0006 (findings feed memory), ADR-0008 (the card's model and budget), ADR-0017 (one sandbox per demand)

## Context

A demand may need several agents at once (implementation, a forensic read
of a database, a log investigation). Between demands the boundary is the
sandbox (ADR-0017); inside a demand, N agents cooperate in the same sandbox.

## Decision

1. **A demand's conversation is a set of threads:** `#main` plus one thread
   per subagent, each with its own history. The developer addresses one
   thread at a time.
2. **Every subagent has a card:** purpose, tools granted, model (chosen by
   the router, ADR-0008), and a slice of the demand's budget.
3. **Cross-thread knowledge is by query, not by dump:** threads are readable
   by siblings through tools (`read_thread`, `ask`). No thread's timeline is
   copied into another's context.
4. **A conclusion is a published finding:** a structured result on the
   demand's board. Findings enter the siblings' context, are events
   (ADR-0004) and are written to the project's memory (ADR-0006).
5. **Subagents are launched by the human (chat) or by the main agent** on
   its own initiative; the thread is visible to the developer immediately.
   *Assumption:* the main agent's initiative may be restricted by the
   product.
6. **The security boundary is the demand.** Subagents share the sandbox, the
   workspace, the credential and the quota.

## Alternatives considered

- **A single sequential agent** — rejected: no specialization, no
  parallelism.
- **One sandbox per subagent** — rejected: breaks the shared workspace;
  buys no isolation between cooperating agents.
- **One shared timeline** — rejected: the requirement is separate timelines.

## Consequences

- The agent runtime supports N sessions per sandbox.
- The attention box is a prerequisite for scale, not an option.
- Raw tool output stays in the specialist's thread; the main agent receives
  findings (ADR-0008 §5).

# ADR-0010 — Multi-agent per demand: addressable threads and published findings

- **Status:** Accepted (definitive, by product decision)
- **Date:** 2026-08-29

## Context

A real demand may require specialists at the same time. A concrete case from the product:
SUOPT-1315 — the main agent implements; one subagent does a forensic reading of the database
through the MySQL MCP; another combs the server's logs. The dev needs to talk to all three
**without mixing the timelines**, and all three need to use each other's conversations as
knowledge.

Two axes that are not to be confused: **between demands** (1 demand = 1 microVM, a hard
boundary) and **inside the demand** (N agents in the same sandbox, collaborating). This ADR
is about the second. In the market, a subagent is a black box: you dispatch it and you wait.
An addressable subagent, with a thread of its own and interrogable in flight, does not exist
in today's tools.

## Decision

1. **The demand's conversation is a set of threads**, not a timeline: `#main` plus one
   thread per subagent. Each with its own history; the dev enters and talks to that agent,
   in isolation.
2. **Every subagent is born with a card**: purpose, tools granted (e.g. the workspace's
   MySQL MCP — R1.14 gains its real use), model (the router's decision, ADR-0011) and a
   slice of the demand's budget.
3. **Cross-knowledge by query, not by dump.** Threads are readable by their siblings as a
   tool (`read_thread`, `ask`); dumping whole timelines into every agent's context does not
   scale and widens the injection surface.
4. **A conclusion becomes a published finding**: a structured result on the demand's common
   board ("a deadlock on table X, 14:02–14:07, caused by migration Y"). Findings go
   automatically into the siblings' context, are events (ADR-0006) and feed the project's
   memory (ADR-0009).
5. **Who launches subagents: the human and the main agent.** The human, through the chat;
   the main agent, on its own initiative when it judges it necessary — the thread shows up
   immediately for the dev to follow or step into.
   > **A recorded assumption:** the main agent's own initiative was adopted for coherence
   > with the philosophy of autonomy; the product may restrict it on review.
6. **The security boundary is still the demand.** Subagents share the microVM, the
   workspace, the credential and the quota — they are collaborators, not strangers.

## Alternatives considered

**A single sequential agent.** Rejected: it loses specialization and parallelizes nothing.

**One sandbox per subagent.** Rejected: it breaks the shared workspace (the forensic agent
needs the same database the main agent brings up), multiplies cost and buys no isolation
that matters — the agents cooperate.

**A single shared timeline.** Rejected: it is the problem the requirement came to solve.

## Consequences

- ➕ A genuinely new UX in the market — the dev-as-manager talks to each member of the team.
- ➕ Threads, findings and cards are events and entities the dossier and the memory were
  already expecting.
- ➖ The `AgentRuntime` port has to support N sessions per sandbox.
- ➖ More threads = more points of attention; the attention box stops being optional (F-5)
  and becomes a prerequisite for scale.

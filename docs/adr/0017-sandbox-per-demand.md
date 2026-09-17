# ADR-0017 — A microVM per demand, with a single shared worktree

- **Status:** Accepted, **superseded in part** — the third decision this ADR carried, *"an
  ephemeral pod per verification run"*, was withdrawn (P-27) and then replaced by
  [ADR-0023](0023-verification-runs-from-source.md). What still holds is the sandbox: one
  microVM per demand, one worktree shared by its threads. See §"Superseded in part" below.
- **Date:** 2026-08-31 · retitled 2026-09-04
- **Resolves:** P-24 (sandbox provisioning) and the question of isolation between threads

## Context

A demand has 1 main agent and N subagents (ADR-0007) — one investigating a log, another the
database, another the code, with the main one orchestrating. We had to decide where each of
those agents runs, and where the application under test runs.

Three problems showed up together:

1. **Isolation between threads.** One microVM per thread would give strong isolation, at the
   cost of 20 microVMs in a project with 5 parallel demands of 4 threads each — every one with
   its own kernel and hundreds of MB of overhead.
2. **Ports.** Bringing the same application up more than once in the same environment requires
   arbitrating a port, and still exposing a route for the human to evaluate. Inside a shared
   sandbox that becomes manual coordination.
3. **Which code the test speaks about.** This is the one that decided it.

## Decision

**One microVM per DEMAND**, with **one worktree**, and **one ephemeral pod per verification
run**.

### A microVM per demand

The boundary that has to be hard is between **accounts** and between **demands** — and that
is the one the per-demand sandbox guarantees. (For the WORKSPACE. For KNOWLEDGE the boundary
is the project, by design: every sandbox of a project shares its root repository —
[ADR-0021](0021-project-knowledge-as-a-git-repository.md). The workspace stays per demand.) A demand's threads are agents of the same
account working on the same problem: mutually trusted. Spending a microVM between them would
be using a security tool to solve a coordination problem.

It is already what the database's constraint imposes:
`UNIQUE (demand_id) WHERE state <> 'destroyed'`.

### One worktree, shared

The threads share `/workspace`. The alternative — one git worktree per thread — would solve
file collision, but it adds real complexity: `ExecRequest` would start carrying the concept of
a thread, and every command would have to know which tree it runs in.

**The risk accepted, explicitly:** two threads that EDIT the same file trample each other.
That is tolerable because, in the multi-agent design, most threads READ — investigating a log,
querying a database and analysing source do not write to the repository — and whoever edits is
typically the main agent. If practice shows two threads editing frequently, the way out is
already mapped: a worktree per thread, and the cost will be documented here.

### An ephemeral pod per verification run

**The argument that decided it, and it comes from our own code.** `VerificationRun.Commit` is
mandatory, and the refusal says: *"evidence that does not say which code it ran on is not
evidence"*.

A test running inside the agent's sandbox runs against the **dirty working tree**, which is no
commit at all. It cannot produce honest evidence under ADR-0005's rule. A pod built **from a
commit** does — and it tests exactly what is going to be merged.

The pod lives only during the run and is discarded. Port and route stop being the sandbox's
problem: each pod has its own network, and a Service and an Ingress give the human a live URL
while the test runs.

## Consequences

- ➕ Five microVMs in a project of five demands, instead of twenty.
- ➕ The evidence of green becomes honest by construction: it speaks about a commit because it
  ran in an environment built from that commit.
- ➕ Ports and routes become the cluster's responsibility, which is what it does well.
- ➖ **Threads that edit the same file trample each other.** Accepted above, with the way out
  mapped.
- ➖ There are now TWO kinds of compute: the agent's long sandbox and verification's short pod.
  They are different life cycles on purpose, but it is one more thing to operate.
- ➖ A test now requires a **published commit** before it runs. That changes the agent's flow:
  edit, commit, and only then verify — which is closer to what a human does, and what the
  merge queue already presupposes.
- ➖ `VerificationRun.SandboxID` today points at "where it ran". With verification in an
  ephemeral pod, it starts pointing at an environment that no longer exists — the field still
  holds as a trail, but the name became imprecise.
- ➖ `EndpointURL` is `<service>--<demand>.<domain>`, designed for the sandbox. The
  verification environment needs its own address, per RUN, or two verifications of the same
  demand collide.

## Left open

**When to provision.** The option discussed — provisioning when the demand enters a stage
whose type requires execution, instead of at start — was not decided. Today provisioning is by
an explicit call, and it stays that way.

**Where to validate the microVM.** The local cluster does not offer it: `SupportedTiers`
returns only `namespace`, because k3d has no Kata RuntimeClass. The contract suite proves the
`namespace` tier in both adapters; the `hardware` tier will only be exercised where there is
Kata. Meanwhile, the refusal is honest — asking for `hardware` where there is none returns an
error, not a lesser isolation in silence.

## Superseded in part — 2026-09-03

**"An ephemeral pod per verification run", with its own Service and Ingress, is withdrawn.**
The owner's decision (P-27): the address stays **per demand** — `<service>--<demand>.<domain>`
— and when a demand needs parallel verification runs, **they queue**. It trades latency inside
one demand for simplicity, and it removes the per-run address `EndpointURL` would have needed.
The argument for honest evidence stands: a verification still runs from a COMMIT
(`VerificationRun.Commit`).

**Corrected on 2026-09-04 — see [ADR-0023](0023-verification-runs-from-source.md).**
The sentence that used to end this paragraph said the verification "just runs in
the demand's sandbox". That was an error in the write-up, not the owner's
decision: what was decided was the ADDRESS (one per demand, runs queue), and
putting the run inside the sandbox contradicted this ADR's own argument by
returning it to the dirty tree. ADR-0023 keeps the argument and changes the
mechanism: an ephemeral RUNNER that pulls the commit and builds from source —
no image of the project is built, pushed or deployed.

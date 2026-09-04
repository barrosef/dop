# ADR-0030 — Verification builds from source in a runner, not from an image

- **Status:** Accepted
- **Date:** 2026-09-04
- **Supersedes:** [ADR-0024](0024-sandbox-per-demand-and-ephemeral-verification.md)'s "an ephemeral pod per verification run" — the argument stands, the mechanism changes
- **Depends on:** [ADR-0007](0007-no-green-no-pr-native-verification-before-the-human.md) (evidence names the commit it ran on), [ADR-0001](0001-infrastructure-behind-ports.md) (two adapters and a contract suite), [ADR-0003](0003-organization-credential-human-authorship.md) (the credential that pulls the code)
- **Refines:** P-27 (one address per demand; runs queue)

## Context

Three documents disagreed about where a demand's application runs, and the
disagreement was ours to fix:

- the substrate spec says an **internal Docker** brings up the demand's stack
  inside the sandbox, with `docker compose -p <demand>`;
- ADR-0024 says a verification runs in an **ephemeral pod** in the cluster,
  because *"a test running inside the agent's sandbox runs against the dirty
  working tree, which is no commit at all"*;
- and P-27's write-up, on 2026-09-03, withdrew the ephemeral pod and said the
  verification *"just runs in the demand's sandbox"* — which put the run back on
  the dirty tree the ADR had refused. **That sentence was an error in the
  write-up**: the owner decided about the ADDRESS (one per demand, runs queue)
  and said nothing about the location.

Resolving it exposed the real cost of "a pod in the cluster". A pod runs an
IMAGE, so verification would need: reading the project's compose, translating it
into manifests, building the application's image from the commit, pushing it to a
registry, and pulling it back on a node — a builder and a registry that do not
exist, on the critical path of every run.

## Decision

**The verification environment is a RUNNER: an ephemeral environment that pulls
the commit, builds from source and starts the application. No image of the
project is ever built, pushed or deployed.**

### 1. Why building from source is the cheap path

The slow sequence is not the build — it is `build → push → pull → start`, three
network hops around a registry that only exists to move bytes between two places
in the same cluster. Cutting it leaves `pull the code → build → start`, which is
what every CI runner in the world does, and what a developer does on their own
machine.

It also removes the compose question entirely: there is no stack to translate,
because there is no stack description to read. There is a repository, a
commit, and a command that starts the application.

### 2. The runner's IMAGE is ours, and it is built once

The toolchains — Node, Go, Python, the JVM — live in an image WE publish and the
node caches. It is a fat image, and that is the deliberate trade: one big image
cached everywhere beats a small image built per demand.

This is the cost of the decision, stated plainly: that image has to carry the
versions our customers use, and version drift is a maintenance burden we take on
rather than push onto the client. It is the same burden every CI provider
carries, and it is smaller than a builder plus a registry.

### 3. It is SEPARATE from the sandbox, and that is the point

The sandbox holds the agent, the dirty tree and everything installed along the
way. The runner starts from nothing, on a commit, so:

- **the evidence is honest about the environment**, not only about the code —
  which is what ADR-0024 bought with the ephemeral pod, and what a `git worktree`
  inside the sandbox would NOT have bought;
- **the test does not compete with the agent** for memory or CPU;
- and a runner that dies takes nothing of the demand's work with it.

It is created when the verification stage starts and destroyed when the run ends.
It is not kept waiting: an environment idling for a push that may not come today
is money burning quietly.

### 4. Third-party dependencies are pulled, never built

A database, a cache, a broker: those are published images (`postgres:16`), and
pulling one costs a cached layer. **Nothing of a third party is ever built.** What
the project declares is small — which dependencies, which versions — and it is a
few lines, not a translation of its compose file.

The application itself is the only thing built, and it is built from source.

### 5. The cache is what makes the second run fast

The account's cache volume — already in the substrate spec, per account and never
global, because a shared cache is a side channel — is mounted into the runner.
`node_modules`, the Go build cache, the Maven repository: the first run of a
project pays, the rest do not.

Without this the decision does not hold: building from source on a cold cache
every time would be slower than the registry sequence it replaces.

### 6. The address, and the queue

The runner takes the demand's address (`<service>--<demand>.<domain>`) while it
runs — the P-27 decision, unchanged: **one address per demand, and parallel runs
queue**. Since they queue, there is one holder at a time.

A run that dies leaves the address pointing at nothing, and something has to
notice: reconciling the address is part of the runner's lifecycle, not an
afterthought.

### 7. It is a PORT, with two adapters

"Run this commit and give me a URL" is a port, and each substrate answers it
natively: pods on Kubernetes, containers on the host daemon under Docker. That is
what keeps the two substrates from diverging on the very thing that produces
evidence — the mistake this ADR nearly made by thinking of verification as
hand-written Kubernetes manifests.

## Alternatives considered

**Compose inside the sandbox** (the substrate spec's original). Cheapest to
build and it keeps the project's own file. Rejected as the VERIFICATION path: the
environment is the agent's, with whatever the agent installed in it, and evidence
from there speaks about that environment and not about a clean one. It remains
the candidate for the developer's own bench — a separate question, still open.

**An ephemeral pod from a built image** (ADR-0024's mechanism). Honest
environment, and it costs a builder, a registry and three network hops per run.
Rejected for the cost, not for the argument — the argument is what this ADR
keeps.

**Translating the project's compose into manifests.** It works for the simple
case and lies for the rest: `build:`, `healthcheck`, `depends_on`, volumes and
profiles have no clean equivalent, and the developer ends up debugging a manifest
they never wrote.

**A runner kept warm, waiting for a push.** Faster to start and it burns money
while nothing happens. Revisit with a measured start latency, not before.

## Consequences

- **A new port and two adapters**, with a contract suite: pull, build, start,
  expose, tear down.
- **A runner image is a product artifact of ours** — versions, size, and a
  release cadence. It is the maintenance we accepted in §2.
- **The project declares its dependencies**, in a few lines. It is a tax, and it
  is the smallest of the ones available.
- **The developer's bench is now an open question of its own**: does a demand
  keep a running application while the agent works, or does the application only
  exist during a verification? The first costs a second environment per demand;
  the second is cheaper and poorer.
- **P-38's verification runner stops being undefined** — it now has a shape. It
  is still not built.
- **The substrate spec's "internal Docker" line no longer describes the
  verification path**, and has to say so.

# ADR-0023 — Verification builds from source in a runner, not from an image

- **Status:** Accepted
- **Date:** 2026-09-04
- **Relations:** supersedes ADR-0017's verification clause; relies on ADR-0005 (evidence names a commit), ADR-0001, ADR-0003 (the credential that pulls the code)

## Context

Evidence of a green verification must name the commit it ran on and the
environment it ran in. Building an image per run requires a builder and a
registry on every run's critical path.

## Decision

1. **The verification environment is a runner:** ephemeral, it pulls the
   commit, builds the application from source and starts it. No image of
   the project is built, pushed or deployed.
2. **The runner's image is the platform's**, published once with the
   toolchains (Node, Go, Python, JVM, …) and cached on the nodes.
3. **Third-party dependencies are pulled as published images** (a
   database, a cache, a broker), declared by the project in
   `.dop/verification.yml`; nothing of a third party is built.
4. **The account's cache volume is mounted into the runner** (`node_modules`,
   the Go build cache, Maven, …); the cache is per account, never shared.
5. **The runner is separate from the sandbox**, created when a run starts
   and destroyed when it ends; it is never kept idle.
6. **Address:** the runner holds the demand's address
   `<service>--<demand>.<domain>` while it runs; parallel runs of one demand
   queue; the address is reconciled when a run dies.
7. **Port:** `VerificationRunner` — pull, build, start, expose, tear down —
   with Kubernetes and Docker adapters and one contract suite.
8. **Triggers:** (a) the end of development, automatically, once the
   reaction-as-data process exists to decide it (`ROADMAP.md` P-29);
   (b) the developer asking (*test*), in which case the run holds the
   environment after the checks for the developer to use. A run holds when
   asked to, not because it has no checks.
9. **The demand keeps no running application** outside a verification or a
   held run.

## Alternatives considered

- **Compose inside the sandbox** — rejected for verification: the agent's
  environment is not a clean one; remains a candidate for a developer bench.
- **An ephemeral pod from a built image** — rejected: builder, registry,
  three network hops per run.
- **Translating the project's compose into manifests** — rejected: no
  faithful mapping.
- **A warm runner** — rejected until start latency is measured.

## Consequences

- The runner image is a product artifact with a release cadence.
- Projects declare their dependencies in a few lines.
- The port's guarantees and the change list are in
  `superpowers/specs/verification-runner.md`; the runner is not built yet.

## Revisions

- 2026-09-04 — decision 9.
- 2026-09-05 — decision 8 (the two triggers).

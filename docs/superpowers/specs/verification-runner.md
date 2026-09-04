# The verification runner

> **Status:** Approved for review · **Date:** 2026-09-04 · **Project:** the DOP platform
>
> **Answers:** where a verification runs, how the application gets there, and what the
> project has to declare for it.
>
> **Also answers, since 2026-09-04:** WHEN the application exists at all — only during a
> verification, or while a developer asked for it.
>
> **Does not answer:** what is verified — the criteria, the critic and the merge queue are
> [`verification-and-delivery.md`](verification-and-delivery.md); where the AGENT works, which
> is the bench ([`execution-substrate.md`](execution-substrate.md)).

The base decision: [ADR-0030](../../adr/0030-verification-runs-from-source.md), which
supersedes ADR-0024's ephemeral pod and corrects the sentence P-27's write-up put in it.

## 1. The idea in one paragraph

A verification does not run where the agent works. It runs in a **runner**: an ephemeral
environment that pulls a COMMIT, builds the application **from source** and starts it. No
image of the customer's application is ever built, pushed or deployed — the slow sequence was
never the build, it was `build → push → pull` around a registry that exists only to move bytes
between two places in the same cluster.

## 2. The vocabulary this spec assumes

| | |
|---|---|
| **Bench** | the sandbox, where the agent works. Dirty tree, everything installed along the way |
| **Runner** | this document. Ephemeral, from a commit, starts from nothing |
| **The application** | the customer's software, built from source. Never an image of ours |
| **Dependency** | a third party the application needs — a database, a cache. Always a published image, pulled and never built |

## 3. The sequence

```
a commit  →  [ runner ]  →  dependencies up      (published images, pulled)
                        →  code pulled           (the account's derived token, ADR-0003)
                        →  cache mounted         (per account — never global)
                        →  build                 (declared command)
                        →  start                 (declared command; takes the demand's address)
                        →  checks                (aaa · e2e · integration, one step each)
                        →  destroyed
```

A **dev session** is the same sequence with no checks: it stops at `start` and holds.

Each step produces an exit code, output and a duration, and each becomes an event (ADR-0006).
A step that fails **stops the sequence**: a build that did not compile is not a test failure,
and reporting it as one sends whoever reads the evidence to the wrong place.

## 4. The application exists in two windows, and in no other

Decided 2026-09-04, closing the question ADR-0030 left open: **a demand does not keep a running
application.** The application exists only

- **during a verification** — it comes up, the checks run, it is destroyed; or
- **while a developer asked for it** — a *dev session*, when someone wants to click through it.

The bench does not run it. That removes a second environment per demand — one that would sit
idle most of the day, since an agent writing code is not exercising a frontend — and it removes
the "resume brings the stack back up" latency the substrate spec listed as a risk.

**A dev session builds from a pushed commit**, like any run. If the agent has not pushed, there
is nothing to bring up: the push is the event (ADR-0028), and running the un-pushed tree is the
same lie as verifying on the bench.

**The lifetime is a deadline, not idleness.** A session comes up with a visible clock, extends
when the developer asks, and dies on the deadline, on an explicit stop, or when the demand
closes. Idle detection was rejected: it needs traffic knowledge from the ingress and it lies —
a developer reading the code for ten minutes has not stopped using the environment.

**The address belongs to the dev session.** A verification runs closed: its checks reach the
application at `localhost` inside the run, so it never needs a public address, and the
contention over the demand's single address (P-27) disappears. When a red needs eyes, the
developer opens a session **on the same commit** — cheap, because the cache is warm.

## 5. What the project declares

`.dop/verification.yml`, in the repository, at the commit being verified:

```yaml
dependencies:
  - name: db
    image: postgres:16
    env: { POSTGRES_PASSWORD: test }
    ready: "pg_isready -U postgres"
build: "go build ./..."
start: { command: "./bin/api", port: 8080 }
checks:
  - { kind: aaa,         command: "go test ./..." }
  - { kind: integration, command: "go test -tags=integration ./..." }
cache: ["/root/.cache/go-build", "/go/pkg/mod"]
```

**With no file, the run REFUSES and names the file.** Guessing how to build somebody's
application is the class of silent lie this design exists to avoid — a wrong guess produces a
green that means nothing, or a red nobody can explain. Twelve lines from the project is the
smaller price.

**Dependencies are pulled, never built.** A `build:` on a dependency is refused: what is built
from source is the application, and only it.

## 6. Where the dependencies live, and why it costs nothing

On Kubernetes the dependencies are **containers in the SAME pod** as the runner; on Docker they
are containers on one network. Both give the application the same thing: its dependencies at
`localhost:<port>`.

That is what removes the translation problem. A compose file's networking exists so that
`backend` resolves; a single pod gives the application `localhost`, which is simpler and needs
no name resolution to invent.

## 7. The runner's image is OURS, and built once

The toolchains — Node, Go, Python, the JVM — live in an image the platform publishes and every
node caches. It is fat on purpose: **one big image cached everywhere beats a small image built
per demand.**

The cost, stated so it is not discovered later: that image has to carry the versions customers
use, and version drift is maintenance we take on rather than push onto the client. It is the
same burden every CI provider carries, and it is smaller than a builder plus a registry.

## 8. The cache is what makes the second run fast

The account's cache volume (already in the substrate spec: per account, never global, because
a shared cache is a side channel) is mounted at the paths the project declared.

**Without it the decision does not hold**: building from source on a cold cache every time
would be slower than the registry sequence it replaces. The first run of a project pays; the
rest do not.

## 9. The address

`<service>--<demand>.<domain>` — ONE per demand (P-27). It is published for a **dev session**
and for nothing else (§4): a verification's checks talk to `localhost` inside the run, so two
runs never fight over it and nothing has to queue for it.

A session that dies leaves the address pointing at nothing. Reconciling it is part of the
runner's lifecycle and not an afterthought: the symptom of getting this wrong is a URL that
answers nothing, hours later, with no error anywhere.

## 10. The port

```
SupportedKinds()                → which check kinds this substrate can run
Start(spec)      → handle      // dependencies, pull, cache, build, start
Status(handle)   → run          // the steps, their codes, the endpoints
Logs(handle, emit)              // streams; dies with the caller
Destroy(handle)                 // irreversible and idempotent
```

`Start` is asynchronous: a verification takes minutes, and a call that blocks for minutes is a
call that times out somewhere else. The shape mirrors `SandboxLauncher` on purpose — the same
lifecycle vocabulary in both places is one less thing to learn.

**Guarantees the contract suite proves, in EVERY adapter:**

1. it builds the COMMIT, not the branch's tip — the same commit twice produces the same tree;
2. the runner starts from **nothing**: a file a previous run wrote is not there;
3. the **cache** is there: a second run of the same account finds what the first one cached;
4. a failing step **stops** the sequence, and the result says which step failed;
5. dependencies are ready **before** the start step, and one that never becomes ready fails the
   run with a message naming it — never a mysterious connection refused in the app's log;
6. `Logs` streams and dies with the caller, leaving no goroutine behind;
7. `Destroy` is irreversible and idempotent; after it `Status` answers not-found and the
   address answers nothing;
8. a run of account X cannot read account Y's cache;
9. a project with no `.dop/verification.yml` is refused by name, before anything is created;
10. a run with **no checks** starts and **stays** — that is a dev session (§4) — and it is the
    deadline, an explicit stop or the demand closing that ends it, never the absence of work.

## 11. What changes in the code

| Where | What |
|---|---|
| `internal/domain/ports/ports.go` | the `VerificationRunner` port, `RunSpec`, `RunStep`, `RunStatus`, and the guarantees above as its documentation |
| `internal/adapter/verification/k8s.go` | a pod: the runner container plus one container per dependency; the cache PVC; the address |
| `internal/adapter/verification/docker.go` | containers on one network, the cache volume, the published port |
| `test/contract/verification.go` + two adapter tests | the nine guarantees, run against both |
| `internal/domain/delivery/` | drives the sequence and records each step as a `VerificationRun` (the entity already exists, with its mandatory `Commit`) |
| `internal/domain/delivery/` | parses and validates `.dop/verification.yml` — a dependency with `build:` is refused here, in the domain, not in an adapter |
| `internal/app/{register,wire}.go`, config | the runner image, the cache storage class, the ingress domain |
| `dop-infra` | the runner image and its Makefile target; the cache PVC per account; the egress policy for the runner's namespace |

## 12. Documents this correction touches

- **`execution-substrate.md`** — "an internal Docker that brings up that demand's stack for
  testing and QA" describes the bench, not the verification. The line, §4's table and R-1/R-2
  say so now.
- **`verification-and-delivery.md`** §2 — acceptance ran "in the sandbox … over the internal
  compose stack". It runs in the runner, from a commit.
- **ADR-0024** — corrected in place: the argument stands, the mechanism is ADR-0030's.

## 13. Risks

| # | |
|---|---|
| R-1 | The runner image grows with every toolchain and version a customer needs — the maintenance §6 accepts. Mitigation: a version manager inside one image before splitting into many |
| R-2 | A cold cache makes the first run of a project slow enough to look broken — it needs to say what it is doing, not just take minutes |
| R-3 | `.dop/verification.yml` is one more file to keep in step with how the project really builds. It drifts, and the symptom is a red that is not the code's fault |
| R-4 | A run that dies holding the address leaves a URL answering nothing (§8) |
| R-5 | A dev session is the most expensive thing a demand can hold, and it is held by a human who walks away. The deadline is the only thing standing between that and a bill: it has to be short by default and visible, not a setting nobody sees |
| R-6 | Dependencies as containers in one pod share its memory limit: a hungry database starves the application, and the failure looks like the application's |

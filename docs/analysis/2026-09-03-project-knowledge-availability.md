# Project knowledge: where it stands against the expectation

**Date:** 2026-09-03 · **Requested by:** the owner · **Scope:** memories, context, specs, plans — everything a project knows — and how it reaches the agents.

## The expectation, as stated

> The project's knowledge base must be available to ANY demand of the project when the microVM and the agents come up. No sends, no requests, no ConfigMaps. Anything that takes effort for the agent to know the project — file transfer, transport, a ConfigMap as a volume — is strange and must be flagged as a serious warning. The knowledge is SHARED and COLLABORATED between agents: transparent, practical, accessible, available and secure. PVCs or a storage like Firebase Storage are fine, as long as it is very practical, simple and secure.

Two words in that carry the whole design: **shared** (one volume for the project, not one per demand) and **collaborated** (agents WRITE to it, not only read).

## Inventory: what exists today

| Piece | Where it lives | Who writes | How it reaches the agent | Verdict |
|---|---|---|---|---|
| **Rules** (`rule`) | `knowledge_artifacts` row (+ ObjectStore for large bodies) | humans, through the cockpit (`PutArtifact`) | only inside the **context package** — selected, budgeted, cut per turn | reaches the prompt, never the filesystem |
| **Repository index** (`index`) | same | humans | same, filtered to the demand's repos | same |
| **Memory** (`memory`) | same, with an embedding | humans | same, by relevance search against the demand's statement | **never fed back from demands** — there is no lessons loop |
| **Findings** | `demand_findings` | the agent, per thread | the package, on resume | the only thing an agent writes today |
| **Spec / plan / context / test plan / diagram / report** | **nowhere** | nobody | — | they exist as stage TYPES and artifact KINDS in the flow vocabulary (`demand.ArtifactKind`), `ValidateFlow` checks a stage declares one — and **no table stores their content**. `DemandContext.Spec` is the demand's statement string, not a spec document |
| **Context package** | assembled per turn (`BuildContextPackage`), measured, with `dropped` | the platform | in the prompt | correct for what it is: the paid path. It is NOT a shelf, and was never meant to be |

**Summary of the inventory:** three of the six kinds of knowledge the owner named do not exist as stored things. The three that exist reach the agent only through the prompt, cut against a budget. Nothing is written by agents except findings. Nothing is shared between demands except through the database and the prompt.

## ⚠ Serious warnings — what violates the expectation

### W1. What was built on 2026-09-02/03 is a TRANSPORT, and it is per demand

The mechanism delivered yesterday (`SandboxSpec.Documents`, guarantees 18–21) does this on Kubernetes: create a **per-demand** PVC → raise a loader pod → **push a tar over WebSocket stdin** → delete the loader → mount read-only. On Docker: extract an archive into the container's layer.

Against the expectation, every step is wrong in kind:

- it is a **send** — bytes travel from the core into the sandbox at every provisioning;
- it is **per demand** — two demands of the same project have two copies that never meet;
- it is **read-only** — agents cannot collaborate on it;
- it is **rewritten at every resume** — nothing an agent could contribute would survive;
- the day before, it was a **ConfigMap** (capped at 1 MiB, in etcd), which the owner rightly rejected.

The port constant (`SandboxDocumentsPath = /project`) and the four contract guarantees are salvageable; the guarantees' TEXT is not — 19 (read-only) and 20 (rebuilt from the spec on resume) assert the opposite of "shared and collaborated". **The mechanism has to be replaced, not tuned.**

### W2. The agent does not know the shelf exists

`internal/domain/agent/prompt.go` and `tools.go` never mention `/project`. The mount was built and the brief never told the agent to look there. A shelf the reader does not know about is an empty shelf.

### W3. Specs, plans and context have no storage at all

The flow vocabulary promises them (`spec`, `plan`, `context` are stage types with a CHECK constraint in `demand_stages`), the validator requires a human gate to "put an artifact on the table" — and there is nothing to put. This is the original P-16, and it has not moved. Any story of epics 08/09 that reads or writes a spec has nowhere to read from or write to.

### W4. Memory is a one-way street

Memories are written only by humans through the cockpit. There is no path by which a demand's lessons become the project's memory. "Knowledge collaborated between agents" is exactly this loop, and it does not exist.

### W5. The sandbox is still empty of code (P-38)

A project volume solves knowledge. It does not clone the repository: no `git` in the devbox image, no fetch anywhere. An agent with a full library and no code is still idle.

### W6. The local cluster refuses ReadWriteMany

Verified on 2026-09-03: `local-path` answers *"NodePath only supports ReadWriteOnce and ReadWriteOncePod"*. A project volume mounted by several demand sandboxes at once IS ReadWriteMany. The local environment (k3d) cannot host the expectation as it stands today; it needs an RWX provisioner (NFS) or a storage-backed CSI driver.

## What the expectation actually requires

1. **One volume per project**, mounted by EVERY sandbox of that project at the same path, **read-write**. From the agent's side: it was always there, and what it writes is there for the next agent.
2. **The platform writes to the same place** (rules from the cockpit, generated indexes), so there is one truth, not a database copy plus a volume copy.
3. **An index that stays true while agents write** — the manifest cannot be a snapshot generated at provisioning any more. Either agents maintain it by convention, or the platform regenerates it (the `sched` process exists for exactly this kind of job).
4. **Security in two directions:** a project never sees another project's volume (namespace + claim per project); and a demand's WORKSPACE stays per demand (ADR-0024's boundary holds for code; for knowledge the boundary moves up to the project, deliberately).
5. **Attribution.** ADR-0006's premise is telling apart what the agent did from what the human did. A plain shared filesystem loses it: a file changed, by whom? This is the one property a volume does not give for free and the design has to add — a git-backed knowledge directory (a commit per write, author = the thread) is the cheapest known answer and it also gives history and rollback.

## Two ways to build it — both are "storage as a volume"

| | A. RWX PersistentVolume per project | B. Object storage mounted (GCS FUSE / Firebase Storage) |
|---|---|---|
| Nature | a POSIX filesystem shared by pods | a bucket presented as a filesystem |
| GKE | Filestore CSI (RWX) | **GCS FUSE CSI driver, native** — the cockpit and the core already write to GCS through the `ObjectStore` port; the sandbox would mount the same bucket prefix |
| OKD / on-prem | CephFS or NFS (RWX) | needs a FUSE sidecar; no native CSI |
| k3d (local) | an NFS provisioner in the cluster (local-path refuses RWX) | no CSI on k3d; a gcsfuse sidecar against the emulator, or fall back to A |
| Concurrent writes | real POSIX semantics | last-writer-wins per object, no locking — acceptable for documents, not for anything append-heavy |
| Attribution | none built in → git-backed dir | none built in → object versioning gives history, not authorship |
| Copies | one | one — this is the only option with genuinely ZERO transport, because the storage IS the volume |
| Simplicity for the owner | one PVC, one mount | one bucket, one mount — and it is the storage the platform already uses |

**Recommendation:** B where the platform runs on GCP (it removes the copy entirely, and the ObjectStore port already points at the same bucket), A everywhere else — **behind the same port constant**. The adapter chooses; the domain and the agent see `/project` either way. That is what the port is for, and it is the two-adapters discipline of ADR-0001 applied to storage.

Regardless of A or B, the four contract guarantees get rewritten: 18 stays (readable at the path), 19 flips (**writable**, and a write is visible to the next sandbox of the same project), 20 flips (**persists** across resume and across demands), 21 stays (paths that escape are refused). And a new one: **a sandbox of project X cannot reach project Y's volume.**

## What this changes in the plan

- **P-16** is not "the mechanism is done, the filling is open". The mechanism built is the wrong kind and is flagged (W1). P-16 reopens with the definition above.
- **P-38** stands: the code side of the empty sandbox is untouched.
- **New: the local environment needs RWX** (W6) — an infra task before any of this runs on k3d.
- **New: knowledge attribution** — decide git-backed vs. platform-written events, before agents start writing (round 2 or 3; it touches ADR-0006).
- **New: the lessons loop** (W4) — how a demand's findings become the project's memory. It is a story of epic 09, but it is also what "collaborated" means.
- **Immediate and cheap:** W2 — the brief tells the agent the shelf exists — is one paragraph in `prompt.go`, and it is worth doing the moment the mount is real.

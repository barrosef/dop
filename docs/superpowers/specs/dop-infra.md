# `dop-infra` — the DOP platform's infrastructure

> **Status:** Approved for review · **Date:** 2026-08-29 · **Project:** the DOP platform
>
> **Answers:** where the infrastructure lives, how QA/stage/prod are born without duplicating a
> declaration, and how a developer brings the dependencies up locally.
>
> **Does not answer:** what the compute target is (P-4), what the database is (SP-3), what the
> component topology is (SP-1). See [`ROADMAP.md`](../../ROADMAP.md).

The base decision: [ADR-0001](../../adr/0001-infrastructure-behind-ports.md) — it is what
defines what needs an emulator and what does not.

## 1. This delivery's state

`dop-infra` is born with **two deliberately different speeds**:

| Part | State in this delivery |
|---|---|
| **Terraform** | **Structure, with no resources.** There is no fleshed-out project to publish a version of yet; provisioning now would be building to throw away |
| **The local environment (k3s)** | **Working.** The emulators come up, and a developer can work against them |

The asymmetry is intentional: Terraform's structure is a known problem and worth fixing early,
but its content depends on decisions that have not been taken yet. The local environment
depends on none of them — the infrastructure dependencies are already known.

## 2. The repository's structure

```
dop-infra/
├── README.md
├── Makefile                    minimal: the context guard + shortcuts; ENV mandatory in Terraform
├── terraform/
│   ├── bootstrap/              projects, the state bucket, the CI's SAs — applied once
│   ├── modules/                reusable blocks; no environment value inside
│   │   ├── project-baseline/   APIs, base IAM, logging, budget
│   │   ├── identity/           Firebase Auth + OAuth providers
│   │   ├── secrets/            Secret Manager + Workload Identity
│   │   ├── network/
│   │   ├── runtime-service/    awaiting SP-5 / P-4
│   │   └── data/               awaiting SP-3
│   └── stacks/
│       └── platform/           the ONLY root module
│           ├── main.tf  variables.tf  outputs.tf  versions.tf  backend.tf
│           └── envs/
│               ├── qa.tfvars      qa.backend.hcl
│               ├── stage.tfvars   stage.backend.hcl
│               └── prod.tfvars    prod.backend.hcl
├── k3s/
│   ├── emulators/              ONLY what has no native adapter
│   │   └── firebase-auth/
│   ├── services/               real services supporting development
│   │   ├── minio/
│   │   └── mongodb/
│   └── overlays/local/         the local environment's composition
└── docs/
```

## 3. Terraform — the organization

**One GCP project per environment:** `dop-qa`, `dop-stage`, `dop-prod`. IAM, quotas, billing
and API limits genuinely isolated; a mistake in QA does not reach production by accident.

**A single root module.** The `qa.tfvars`, `stage.tfvars` and `prod.tfvars` files change
**values**, never declarations. A new resource appears once, inside a module, and all three
environments gain it together. It is the "no duplication of resources" requirement.

**State per environment through `-backend-config`**, in a `.backend.hcl` file per environment.
`terraform workspace` is not used: workspaces share the backend's configuration and
credentials, and "I forgot to switch workspace" is a failure mode that applies QA in
production. With a project per environment, the target has to be **explicit in the command**.

**Protections from the start**, even with no resources: `prevent_destroy` foreseen in the data
modules, `deletion_protection` turned on in `prod.tfvars`, a CI service account per environment
with permission only on its own project, and a `Makefile` that refuses to run without `ENV`.

**What "empty" means exactly:** the directories, `versions.tf`, `backend.tf` and the variable
declarations exist; there is **no `resource` block**. The skeleton has to pass
`terraform fmt -check` and `terraform validate` — a valid structure that provisions nothing.
`bootstrap/` is documented and **not applied**.

**Two modules are born with an interface only.** `runtime-service/` and `data/` get variables
and outputs, with no implementation, until SP-5 decides where the execution runs and SP-3
decides the database. A module with a defined boundary and a pending core is honest; a guessed
module is debt.

## 4. The local environment — what comes up

### 4.1 The cluster

**There is no local cluster on the machine today** — no k3s, k3d, kind or minikube. There is
`kubectl` (with Kustomize built in, making the standalone binary unnecessary) and `docker`.

The cluster is provisioned with **k3d**: it is k3s itself packaged to run in Docker. It is
installed with one binary, it is created and destroyed in seconds, and it keeps the fidelity to
k3s that ADR-0001's portability presupposes. Installing native k3s would require systemd and
root privilege, taking over the host's network — a disproportionate cost for a disposable
development environment.

The `dop-local` cluster, which produces the `k3d-dop-local` context.

### 4.2 The context guard — a hard requirement

This machine's `kubectl` today points at **`sar-sicar-prod`, the production namespace of a
customer project unrelated to DOP**, in a remote OKD cluster. A careless `apply` would deploy
the emulators into somebody else's production.

**The only automation that exists is the context guard**, in a minimal `Makefile`: every target
that talks to a cluster first checks that `kubectl config current-context` is exactly
`k3d-dop-local` and **refuses to run** if it is not — before the command, never as a warning.
It is not a convenience: it is the difference between a development environment and an
incident. Beyond that guard, no scripts; a composed command is only born when the repetition
really hurts.

### 4.3 The components

The `dop-local` namespace, composed with Kustomize. **Built and tested on 2026-08-31.**

| Component | Role | Port |
|---|---|---|
| **PostgreSQL 17 + pgvector** | State, the event log and semantic search (ADR-0014) | 5432 |
| **NATS JetStream** | The event broker (ADR-0014) | 4222 · monitor 8222 |
| **The Firebase emulators** | Auth and Storage — the same SDK as production (ADR-0015) | 9099 · 9199 · hub 4400 |

**Kustomize, not Helm** — a small, internal set; no template language to learn, and the `local`
overlay literally expresses "the base plus the emulators".

**Everything is declarative — there is no orchestration script.** What in a `docker compose`
environment would require a `dev.sh` (creating the data directory, a conditional import,
waiting for readiness, giving the shutdown time, resetting a root-owned volume) Kubernetes
solves in a manifest:

| Need | Resource |
|---|---|
| persistence across restarts | a PVC |
| a conditional `--import` | an `if` in the container's `command` — the logic lives in the pod |
| time for `--export-on-exit` to finish | `terminationGracePeriodSeconds: 30` |
| configuration shared with the deploy | a ConfigMap from the versioned files |
| resetting the data | `kubectl delete pvc` — no permission juggling |
| waiting for readiness | a `readinessProbe` |

Day-to-day operation: `kubectl apply -k`, `k3d cluster start/stop` and **k9s** for logs, exec
and inspection.

**The emulator's image is built here, not pulled from the community.** Firebase publishes no
official container of the Auth emulator alone; the alternative would be trusting a third
party's image. A thin image is built on Node with `firebase-tools` at a **pinned version** —
coherent with the supply chain posture `dop-app` already adopts, where `pnpm-workspace.yaml`
imposes a minimum release age against a supply chain attack.

**Measured consumption:** ~958 MB in total (the cluster 935 + the LB 10 + the registry 13). The
emulator is the heaviest because it is Java; `k3d cluster stop` gives everything back while
preserving the data.

### 4.4 The emulator's data across restarts

*(the operational half of [ADR-0015](../../adr/0015-firebase-emulators-and-single-owner.md),
moved here on 2026-09-04: the decision is the ADR's, the recipe is this spec's)*

The combination that works — each part is there because its absence broke something:

- `--export-on-exit <dir>` **plus** a **conditional** `--import <dir>`: pass the import flag
  only if the directory exists, otherwise the very first start fails;
- **`stop_grace_period: 30s`** on the container — without it SIGKILL arrives before the export
  finishes, and the data is lost exactly when stopping;
- `reset` removes the directory **through the container**: it is born root-owned and the user
  cannot delete it from outside.

**The environment-variable bridge.** The Cloud Storage SDK reads `STORAGE_EMULATOR_HOST`; the
Firebase CLI exposes `FIREBASE_STORAGE_EMULATOR_HOST`. **The application bridges them at
boot** — without that, a local upload goes to the real bucket.

## 5. An emulator is not an adapter

The distinction that governs what goes into `k3s/emulators/`, and that is easy to get wrong:

| Service | Cloud | Local | Why |
|---|---|---|---|
| Identity | Firebase Auth | **An emulator** | Issuing and verifying a token is not reimplemented |
| Secrets | Secret Manager | **A k8s Secret** | It is already an ADR-0001 adapter. Emulating would duplicate work |
| Objects | GCS / Firebase Storage | **The Firebase Storage emulator** | The same SDK and semantics as production; MinIO only if a customer without GCP appears |
| Database | Cloud SQL Postgres | a real container | A database runs the same locally; it is not emulation |
| Services | to be decided | a container in k3s | Cloud Run has no emulator; a container is the common denominator |

**The rule: only what has no native adapter goes into `emulators/`.** Today the list has **one
item** — Firebase's Emulator Suite, which covers Auth and Storage in the same process.

**Traps solved during the construction** (detailed in `dop-infra/docs/local-environment.md`): a
writable `HOME` for an arbitrary user; JARs downloaded at build time; JDK 21; the probe checks
the **hub (4400)**, not the UI (which only comes up if some emulator has a UI); and a versioned
image tag, because rebuilding with the same tag does not guarantee the pod pulls the new layer.

## 6. Absorbing the root's `infra/`

The meta-repository has an `infra/` with a skeleton `docker-compose.yml` and two Dockerfiles,
created at the project's bootstrap and never filled in.

**`dop-infra` takes over the local environment and the root's `infra/` is removed.** Keeping
both guarantees one goes stale in silence, and there is no investment to preserve. The local
k3s is also closer to the production target than compose, shortening the distance between "it
works on my machine" and "it works on the cluster".

## 7. The repository

`Digital-Business-One/dop-infra`, private, a **submodule** at `repos/dop-infra` — consistent
with `dop-api`, `dop-app` and `dop-cli`, all of them components of the platform.

## 8. Verification

The criterion is asymmetric, like the delivery:

**Terraform** — `terraform fmt -check` and `terraform init -backend=false && terraform validate`
pass on the `platform` stack. Nothing is applied.

**Local** — the overlay comes up on a real k3s and the three components answer:

0. The context guard **refuses** to run when the active context is not `k3d-dop-local` — tested
   deliberately before anything else.
1. `make up` (the context guard + `kubectl apply -k`) leaves the pods `Running`.
2. The Firebase Auth emulator answers on 9099.
3. MinIO accepts creating a bucket.
4. MongoDB accepts a connection and a `ping`.
5. `make down` removes the namespace leaving no residue; `make reset` deletes the PVCs.

## 9. Risks and open items

| # | |
|---|---|
| R-1 | **The Auth emulator is not Firebase.** Behaviour differences show up under federated authentication and account linking — exactly what the identity spec requires from day one. The emulator validates the flow, not equivalence |
| R-2 | **Our own emulator image requires maintenance** — a pinned `firebase-tools` ages and needs a deliberate update |
| R-3 | **`kubectl`'s context pointing at somebody else's production.** The machine's current state is exactly that. Mitigated by §4.2's guard, which is mandatory in every target |
| R-4 | **k3d is not identical to a native k3s** in networking and storage. Enough for this spec's dependencies; it stops being so when the execution plane (P-4) comes in |
| R-5 | **Terraform empty for too long rots.** An unused structure is not exercised; when the resources arrive, the organization may not serve. The mitigation: `validate` in CI from now on |
| P-4 | The compute target — Cloud Run × a cluster. It blocks `modules/runtime-service/` |
| SP-3 | The choice of database. It blocks `modules/data/` and confirms or replaces the local MongoDB |

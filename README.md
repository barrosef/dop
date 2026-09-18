# dop — the product's meta-repository

**DOP** is an *AI-first* tool that assists software development, where a **Dev** and the
**Claude** agent collaborate to run demands end to end. This **root** repository orchestrates the
product (documentation + the local environment's pointer) and aggregates the components as
independent repositories under `repos/`.

The product's public site — what it is, how it is built, where it stands — is **[dop-t.com](https://dop-t.com)**.

## Structure

```
dop/
├── docs/                 # the 1.0 PRODUCT's docs (the PRD, ADRs, specs, the API collections)
├── infra/                # a leftover skeleton compose — superseded by dop-infra
└── repos/                # the components as git SUBMODULES (independent repos, pinned by commit)
    ├── dop-core/         # the core in Go — domain, state, transactions, events
    ├── dop-api/          # the BFF in Python — REST+SSE for the app, gRPC for the CLI and the sandbox
    ├── dop-app/          # the frontend (React/Vite) — the cockpit
    ├── dop-infra/        # infrastructure: Terraform + the local k3s environment
    ├── dop-cli/          # reserved for the platform's CLI
    └── dop-cmd/          # the operational tool in use (v0.7.1) — NOT a submodule
```

## Cloning

The components are **git submodules** (each pinned at a specific commit). Clone with
`--recursive`:

```bash
git clone --recursive git@github.com:barrosef/dop.git
# or, after a plain clone:
git submodule update --init --recursive
```

To update a component to its `main`'s latest commit and pin the new pointer:

```bash
git -C repos/<component> pull origin main
git add repos/<component> && git commit -m "chore: bump <component>"
```

**`dop-cmd` is not a submodule** and therefore does not come in the recursive clone. Get it
separately:

```bash
git clone git@github.com:barrosef/dop-cmd.git repos/dop-cmd
```

## Components

- **dop-core** (`repos/dop-core`) — the core in Go: the domain, the state, the transactions and
  the event log. One binary, four modes (`serve`, `worker`, `sched`, `launcher`). It owns the
  schema and the vault; it is the only source of truth (ADR-0012, ADR-0016).
- **dop-api** (`repos/dop-api`) — the BFF in Python: REST+SSE for the cockpit, gRPC for the CLI
  and the sandbox. It has no database and no secret — every write goes through the core.
- **dop-app** (`repos/dop-app`) — the cockpit where the Dev works (the attention box, the tree of
  workspaces and projects, the demand's cockpit).
- **dop-infra** (`repos/dop-infra`) — the platform's infrastructure: Terraform for GCP and the
  local k3s (k3d) environment with Postgres, NATS and the Firebase emulators.
- **dop-cli** (`repos/dop-cli`) — reserved for the platform's CLI. No implementation yet.
- **dop-cmd** (`repos/dop-cmd`) — the **operational tool in use** (v0.7.1). It reaches the
  workspace directly and answers for the environment: multi-platform git/PR, a docker-compose
  runtime, e2e/AAA and Allure. **A project of its own**, independent of the platform.
  Installation: `pip install 'git+ssh://git@github.com/barrosef/dop-cmd.git'`.

## Documentation

- **The index of everything:** [`docs/ROADMAP.md`](docs/ROADMAP.md) — the subprojects, the
  phasing and the cross-cutting open items.
- **Architecture decisions:** [`docs/adr/`](docs/adr/) — 23 ADRs in the MADR format, numbered contiguously.
- **Subsystem specs:** [`docs/superpowers/specs/`](docs/superpowers/specs/).
- **Vocabulary:** [`docs/GLOSSARY.md`](docs/GLOSSARY.md).
- **API collections:** [`docs/api/`](docs/api/) — Bruno, the core's gRPC and the BFF's REST/gRPC.
- **The 1.0 base PRD:** [`docs/prd/dop-1.0-mvp/README.md`](docs/prd/dop-1.0-mvp/README.md).
- The operational tool's internal docs (ADRs, references, architecture) live in
  `repos/dop-cmd/docs/`.

## The local environment

The local environment is **dop-infra**'s: a k3d cluster with Postgres + pgvector, NATS JetStream
and the Firebase emulators, composed with Kustomize. See
[`repos/dop-infra/docs/local-environment.md`](repos/dop-infra/docs/local-environment.md).

The `infra/` directory at the root is the skeleton `docker compose` from the project's bootstrap
and was superseded by dop-infra (the dop-infra spec §6); it is kept only until it is removed.

## State

- ✅ The foundation: contracts, ports, the event spine, the schema and the local environment up
  (the backend architecture spec §9).
- 🚧 `dop-core`, `dop-api`, `dop-app` and `dop-infra` — the platform's components, under
  construction.
- ✅ `dop-cmd` v0.7.1 — the operational tool in use, installable and maintained.

# AGENTS.md

Shared briefing for the coding agents that work in this repository — Claude Code
reads it through `CLAUDE.md`, Codex reads it natively. **One source, two readers:**
change it here and both agents change together.

`README.md` describes what the product is and how the repository is laid out.
This file carries only what an agent cannot derive by reading the tree.

## The one mistake that costs a morning

`repos/*` are **git submodules pinned by commit**. Code changes belong in the
component's own repository; the root repository only moves the pointer.

```bash
# inside the component
git -C repos/<component> checkout -b feat/x && ... && git -C repos/<component> push
# then, at the root, in a separate commit
git add repos/<component> && git commit -m "chore: avança o ponteiro do <component> (...)"
```

Committing component code from the root, or bumping a pointer to an unpushed
commit, breaks the clone for everyone else.

**`dop-cmd` is not a submodule.** It does not arrive with a recursive clone and
is a project of its own.

## Components and their commands

| Component | Stack | Commands |
|---|---|---|
| `dop-core` | Go | `make build` · `make test` (unit + contract + architecture, no environment) · `make test-integration` · `make test-contract-integration` · `make lint` · `make proto` · `make proto-breaking` · `make migrate` |
| `dop-api` | Python | `make test` · `make lint` · `make proto-all` · `make run` |
| `dop-app` | React/Vite, pnpm | `pnpm typecheck` · `pnpm build` |
| `dop-infra` | Terraform + k3d | `make up` · `make down` · `make status` · `make reset` · `make logs` |
| `dop-cmd` | Python | operational tool, entry point `dop` |
| `dop-cli` | — | reserved, no implementation yet |

`dop-core`'s `make test` needs no environment and is the cheapest real signal in
the repository. Prefer it over reasoning about whether something works.

## Invariants — what must stay true after any change

These are the architecture's load-bearing walls. A change that breaks one is
wrong even when it compiles and the tests pass.

1. **The core is the only source of truth.** It owns the schema and the vault
   (ADR-0012, ADR-0016). Every write goes through it.
2. **The BFF has no database and no secret.** `dop-api` translates and forwards;
   it never persists and never holds a credential.
3. **The `.proto` files are the contract** (ADR-0013). Generated code is
   regenerated, never hand-edited. `make proto-breaking` refuses an incompatible
   change on purpose.
4. **The cockpit consumes a committed contract.** `lib/api-spec/openapi.json` is
   downloaded and committed; Orval generates the react-query hooks and the Zod
   schemas from it. See `repos/dop-app/RAILS.md`, which states the cockpit's own
   invariants in full — read it before changing that repository.
5. **The core verifies its callers** (ADR-0022), and **verification runs from
   source** (ADR-0023).

When a change appears to require breaking one of these, that is a decision for a
human and probably an ADR — not something to work around.

## Conventions

- **Commit subjects are in Portuguese** and describe the *finding*, not the
  edit: `fix(identity): a regra D-5 estava morta contra o adaptador padrão`.
  Conventional-commit prefixes (`feat`, `fix`, `docs`, `chore`) with an optional
  scope.
- **Documentation, code and comments are in English.** Only commit subjects and
  the specs written for humans are in Portuguese.
- ADRs follow MADR and live in `docs/adr/`. Twenty-four of them exist, numbered 0001–0024; they are the
  reason behind most of what looks arbitrary.

## Where to look before asking

| Question | Answer lives in |
|---|---|
| What is the plan, what is done | `docs/ROADMAP.md` |
| Why is it like this | `docs/adr/` |
| What does this word mean here | `docs/GLOSSARY.md` |
| What does the API accept | `docs/api/` (Bruno collections) |
| What must stay true in the cockpit | `repos/dop-app/RAILS.md` |
| How do I run the local environment | `repos/dop-infra/docs/local-environment.md` |

## For a reviewing agent

When reviewing a change here rather than writing one, weight the findings in
this order:

1. **A broken invariant** from the list above — the highest severity, regardless
   of how small the diff is.
2. **A decision taken in the wrong repository** — the cockpit deciding something
   that belongs to the core or the BFF is the failure mode `RAILS.md` was
   written to prevent.
3. **Hand-edited generated code**, or a contract changed without regenerating.
4. **A submodule pointer moved to a commit that was never pushed.**
5. Ordinary correctness: error paths, boundary conditions, concurrency.

Report style preferences separately from correctness, and only when asked. A
review that returns twenty findings of mixed severity gets read as noise, and
the one finding that mattered is lost with the rest.

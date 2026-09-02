# The `dop-cmd` × `dop-cli` separation

> **Status:** Approved for implementation
> **Date:** 2026-08-26
> **Scope:** the `dop` meta-repository, the `dop-cli` repository, the new `dop-cmd` repository
> **Out of scope:** any decision about the DOP platform, which is another project

## 1. Context and motivation

The `dop-cli` repository today contains **two overlapping things**:

1. The **operational tool in use** (v0.7.1) — a Python CLI that reaches the workspace directly
   and answers for the environment: git operations, multi-platform PRs, a docker-compose
   runtime, e2e/AAA tests, Allure reports and a state machine per demand. It is used daily in
   real workspaces.
2. The **`dop-cli` name**, which belongs to the DOP platform's project and needs to be free for
   it.

Keeping both identities in the same repository prevents the platform's CLI from being built
without putting the tool in production at risk, and it makes any conversation about "the
dop-cli" ambiguous.

The separation solves that by giving each name back to its project:

- **`dop-cmd`** — the tool that answers for the environment. **A project of its own**, with an
  independent life cycle.
- **`dop-cli`** — the name becomes available again for the DOP platform.

> **The two projects are distinct.** `dop-cmd` originated the platform's idea, but it is neither
> its technical ancestor nor a design reference. Nothing in this spec decides anything about the
> platform, and the platform inherits nothing from here.

The name `dop-cmd` is more appropriate for the first role: an environment *command*, not a
*client's command-line interface*.

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| D-1 | `dop-cmd` is born **clean**, with the code copied from `dop-cli`'s `main` in a single initial commit | The decision history stays reachable in `dop-cli`; a clean start avoids dragging along tags and branches that no longer describe the new role |
| D-2 | `dop-cli` is **emptied**, left with only a marker | It gives the name back to the other project without losing the history, which stays in the repository itself |
| D-3 | The `dop-cmd` distribution; **the `dop` package and the `dop` executable unchanged** | Zero disruption for the workspaces in use and zero import refactoring. See risk R-1 |
| D-4 | The version stays **0.7.1** | It is the same code; only the distribution was renamed. Restarting the numbering would create an apparent regression |
| D-5 | **All the documentation** (ADRs, the CLI-era PRDs, references, architecture, specs and plans) goes with the code to `dop-cmd` | They are that implementation's decision record; separating them from the code makes both less useful |
| D-6 | `dop-cmd` lives at `repos/dop-cmd`, but it is **not a submodule** of the meta-repo | It is part of the project and coexists with the other components in the same tree, without being tracked by the meta-repo, which aggregates only the 1.0 product's components |

## 3. The final topology

```
/opt/wks/dbo/dop/            the product's meta-repo
├── .gitmodules              3 entries: dop-cli, dop-api, dop-app  (unchanged)
├── .gitignore               + repos/dop-cmd/
├── docs/                    the 1.0 product's docs
├── infra/                   the local stack
└── repos/
    ├── dop-cmd/             NEW — an independent git repo, with its own remote.
    │                        NOT a submodule. The operational engine (v0.7.1).
    ├── dop-cli/             a submodule — emptied; the name given back to the platform
    ├── dop-api/             a submodule — unchanged
    └── dop-app/             a submodule — unchanged
```

The new component's remote: `git@github.com:Digital-Business-One/dop-cmd.git` (private).

## 4. Component A — `dop-cmd`

### 4.1 The content

A copy of the 99 files versioned in `dop-cli`'s `main` (`src/`, `tests/`, `docs/`,
`pyproject.toml`, `README.md`, `.gitignore`), in a **single initial commit**.

`.claude/settings.local.json` is not versioned in `dop-cli`; it is copied locally to preserve
the session's preferences, without entering the commit.

### 4.2 Changes over the copy

| File | Change |
|---|---|
| `pyproject.toml` | `name = "dop"` → `name = "dop-cmd"`. `version`, `[tool.setuptools.packages.find]` and `[project.scripts] dop = "dop.cli:main"` stay intact |
| `README.md` | The title and the installation URL point at `dop-cmd.git`; a new paragraph explaining that `dop-cmd` is a project of its own and that the name `dop-cli` belongs to another project |
| `docs/adr/0015-separacao-dop-cmd-e-dop-cli.md` | A new ADR recording this decision |
| `docs/adr/README.md` | An index line for ADR 0015 + a footnote clarifying that the "ADR-16" cited in `docs/workspace-migration-adr16.md` and in the superpowers specs is a document **on the workspace's side**, outside this index |

Everything else is copied unchanged.

### 4.3 The ADR's numbering

The ADR index goes up to 0014. There is an informal "ADR-16", about the test layer setup of the
Optum workspace, that never entered the index. The new ADR gets **0015** (the next free number
in the index) and the footnote undoes the ambiguity.

## 5. Component B — `dop-cli`

One commit removing `src/`, `tests/`, `docs/` and `pyproject.toml`, and rewriting the
`README.md` into a short marker: the repository is reserved for the DOP platform's CLI, it has
no implementation yet, and the tool that used to live here moved to the `dop-cmd` project.

The repository is left with **`README.md` and `.gitignore`**, nothing else. No `pyproject.toml`:
`dop-cli`'s content is the platform project's business, not this spec's.

**No work is lost:** the two local branches (`feat/runtime-orchestrator-abstraction`,
`fix/allure-aggregation-headed-x11`) are already fully merged into `main`, and the complete
history stays in the repository.

## 6. Component C — the root meta-repository

| Target | Change |
|---|---|
| `.gitmodules` | **No change.** It stays with three entries |
| `.gitignore` | It adds `repos/dop-cmd/`, so the new repository does not show up as untracked and is not mistaken for a submodule |
| `README.md` | The structure tree and the **Components** section now list `dop-cmd`, making explicit that it is obtained through its own clone and not through `git submodule update`. The installation instruction, today pointing at `dop-cli.git@v0.5.0`, now points at `dop-cmd`. The **State** section is updated |
| the `repos/dop-cli` pointer | Pinned at the emptying commit (today it is already behind the local checkout) |

The root's README documents obtaining the non-submodule component:

```bash
git clone git@github.com:Digital-Business-One/dop-cmd.git repos/dop-cmd
```

The DOP platform's documentation (`docs/prd/`, `docs/superpowers/`) is **not touched**: it
belongs to another project.

## 7. Verification

1. **Suite parity:** `pytest -p no:playwright` inside `dop-cmd`, compared with `dop-cli`'s
   baseline. An identical result is expected, including the known and unrelated failure in
   PR-publish.
2. **Installability:** `pip install -e .` in `dop-cmd` generates the `dop` executable;
   `dop --version` returns `0.7.1`.
3. **The meta-repo's cleanliness:** `git status` at the root does not report `repos/dop-cmd` as
   untracked, and `git submodule status` still lists exactly three submodules.
4. **`dop-cli`'s integrity:** `git log` preserves the complete history and the `v0.1.0` and
   `v0.5.0` tags still resolve.

## 8. Consequences and accepted risks

- **R-1 — A collision on the `dop` command.** `dop-cmd` and the platform's future CLI compete
  for the same executable and **will not be able to coexist in the same Python environment**. It
  is a conscious choice, made so as not to break the workspaces in use. When the 1.0 CLI takes
  the name, it will be in a separate environment or with `dop-cmd` already retired.
- **R-2 — A change of installation origin.** Whoever installs from `dop-cli.git` has to change
  the URL to `dop-cmd.git`. The installed code is identical.
- **R-3 — A recursive clone does not bring `dop-cmd`.** As it is not a submodule, it requires an
  explicit clone. Mitigated by the documentation in the root's README.
- **C-1 — The session's memory.** The memory that references "dop-cli test running" now points
  at `dop-cmd`.

## 9. Out of scope

- **Everything concerning the DOP platform** — architecture, components, the contract, identity,
  the work model. It is another project, with specs of its own.
- The `dop-cli` repository's future content.
- Any functional change to `dop-cmd`'s code.

## 10. The execution order

1. Create `Digital-Business-One/dop-cmd` (private) and prepare the local `repos/dop-cmd` with
   the copy, the changes of §4.2 and the initial commit.
2. Verification §7.1 and §7.2.
3. Publish `dop-cmd`.
4. Empty `dop-cli` as per §5 and publish.
5. Update the meta-repo as per §6, pin the pointers and publish.
6. Verification §7.3 and §7.4; update the session's memory (C-1).

Each publication is confirmed before it happens.

# The `dop-cmd` × `dop-cli` separation — the implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the operational tool in use from the `dop-cli` repository into a new `dop-cmd` repository, giving the name `dop-cli` back to the DOP platform's project.

**Architecture:** Three repositories are touched. `dop-cmd` is born clean with a copy of the versioned files of `dop-cli`'s `main`, changing only the distribution's identity. `dop-cli` is reduced to `README.md` + `.gitignore`. The meta-repository starts documenting `dop-cmd` as a non-submodule component, ignored by git.

**Tech Stack:** Python 3.11+ (setuptools), git, the `gh` CLI, pytest.

**Spec:** [`2026-08-26-separation-design.md`](2026-08-26-separation-design.md)

## A note on method

**This plan is not TDD.** No production code is written: `src/` and `tests/` are copied byte for
byte, with no functional change. The red-green cycle is replaced by a **parity check** — the
existing suite has to produce, at the destination, exactly the same result it produced at the
origin. Every task ends in a concrete check.

## Global Constraints

- The distribution: `dop-cmd`. The Python package: `dop`. The executable: `dop`. The version: `0.7.1`.
- No functional change in `src/` or `tests/`. Only `pyproject.toml`, `README.md` and `docs/adr/` change.
- The new repository's remote: `git@github.com:Digital-Business-One/dop-cmd.git`, **private**.
- The new repository's local path: `/opt/wks/dbo/dop/repos/dop-cmd`.
- `dop-cmd` is **not a submodule**. The root's `.gitmodules` stays with **exactly three** entries.
- The test command: `python3 -m pytest tests/ -p no:playwright` (the `-p no:playwright` is mandatory; without it the collection aborts with `ModuleNotFoundError: No module named 'playwright'`).
- The expected baseline: **143 tests collected**, with **one known and unrelated failure** — `tests/test_handlers.py::TestPrPublish::test_commits_pushes_and_creates_prs` (`TypeError: Object of type MagicMock is not JSON serializable`).
- The temporary working directory: `/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad`.
- **Every publication (`gh repo create`, `git push`) is confirmed with the user before it happens.**

---

### Task 1: A verification baseline for `dop-cli`

It captures the reference state **before** any file moves. Without it, Task 3's parity
comparison is impossible and Task 4's emptying is irreversible without consulting the history.

**Files:**
- Create: `<scratchpad>/baseline-files.txt`
- Create: `<scratchpad>/baseline-pytest.txt`

**Interfaces:**
- Produces: `<scratchpad>/baseline-files.txt` (an ordered list of the versioned files) and `<scratchpad>/baseline-pytest.txt` (the suite's complete output), consumed by Tasks 2 and 3.

- [ ] **Step 1: Record the exact list of versioned files**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
git -C /opt/wks/dbo/dop/repos/dop-cli ls-files | sort > "$SP/baseline-files.txt"
wc -l < "$SP/baseline-files.txt"
```

Expected: `99`.

- [ ] **Step 2: Run the suite and save the output**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
cd /opt/wks/dbo/dop/repos/dop-cli
python3 -m pytest tests/ -p no:playwright 2>&1 | tee "$SP/baseline-pytest.txt" | tail -5
```

- [ ] **Step 3: Check that the baseline matches what is expected**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
grep -E "^(FAILED|ERROR)" "$SP/baseline-pytest.txt"
tail -1 "$SP/baseline-pytest.txt"
```

Expected: exactly one `FAILED tests/test_handlers.py::TestPrPublish::test_commits_pushes_and_creates_prs`
line, and a summary of the kind `1 failed, 142 passed`.

If **more than one** failure shows up, **stop** and report to the user before going on — the
baseline has to be known for parity to mean anything.

- [ ] **Step 4: Confirm git's starting point**

```bash
git -C /opt/wks/dbo/dop/repos/dop-cli log --oneline -1
git -C /opt/wks/dbo/dop/repos/dop-cli status --short
```

Expected: `19fa56a chore: bump version to 0.7.1` and a clean tree. If there are uncommitted
modifications, **stop** and report — they would be lost in the emptying.

No commit in this task: nothing in the repository changed.

---

### Task 2: Materialize `repos/dop-cmd`

It creates the complete local repository — the copy, the new identity and the ADR that records
the decision — in a **single initial commit**, as per the spec's §4.1.

**Files:**
- Create: `repos/dop-cmd/**` (99 files, a copy of `dop-cli`'s `main`)
- Modify: `repos/dop-cmd/pyproject.toml`
- Modify: `repos/dop-cmd/README.md`
- Create: `repos/dop-cmd/docs/adr/0015-separacao-dop-cmd-e-dop-cli.md`
- Modify: `repos/dop-cmd/docs/adr/README.md`

**Interfaces:**
- Consumes: `<scratchpad>/baseline-files.txt` (Task 1), to check file parity.
- Produces: a git repository at `/opt/wks/dbo/dop/repos/dop-cmd` with one commit, the `main` branch, no remote.

- [ ] **Step 1: Extract the versioned files**

`git archive` delivers exactly the files tracked on `main`, with no `.git`, no
`.pytest_cache`, no `.venv`.

```bash
mkdir -p /opt/wks/dbo/dop/repos/dop-cmd
git -C /opt/wks/dbo/dop/repos/dop-cli archive main | tar -x -C /opt/wks/dbo/dop/repos/dop-cmd
```

- [ ] **Step 2: Copy the local preferences and keep them out of versioning**

The `.gitignore` inherited from `dop-cli` covers `__pycache__/`, `*.pyc`, `.venv/`, `dist/`,
`*.egg-info/` and `.env` — it does **not cover `.claude/`**. Since the spec (§4.1) determines
that `settings.local.json` be copied *without entering the commit*, the exclusion rule has to be
created here; without it the `git add -A` of Step 9 would version the file.

```bash
mkdir -p /opt/wks/dbo/dop/repos/dop-cmd/.claude
cp /opt/wks/dbo/dop/repos/dop-cli/.claude/settings.local.json \
   /opt/wks/dbo/dop/repos/dop-cmd/.claude/settings.local.json
printf '.claude/\n' >> /opt/wks/dbo/dop/repos/dop-cmd/.gitignore
tail -2 /opt/wks/dbo/dop/repos/dop-cmd/.gitignore
```

Expected: the `.gitignore`'s last line is `.claude/`.

- [ ] **Step 3: Check file parity against the baseline**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
cd /opt/wks/dbo/dop/repos/dop-cmd
find . -type f -not -path './.claude/*' | sed 's|^\./||' | sort > "$SP/copied-files.txt"
diff "$SP/baseline-files.txt" "$SP/copied-files.txt" && echo "PARITY OK"
```

Expected: `PARITY OK`, with no difference line.

- [ ] **Step 4: Initialize the repository**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git init -q -b main
```

- [ ] **Step 5: Adjust the distribution's name in `pyproject.toml`**

Change the `name = "dop"` line to `name = "dop-cmd"`. Nothing else in the file changes —
`version`, `[tool.setuptools.packages.find]` and `[project.scripts]` stay intact.

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
sed -i 's/^name = "dop"$/name = "dop-cmd"/' pyproject.toml
grep -n 'name = \|^version\|^dop = ' pyproject.toml
```

Expected:
```
name = "dop-cmd"
version = "0.7.1"
dop = "dop.cli:main"
```

- [ ] **Step 6: Rewrite the `README.md`'s header**

Replace the file's **first nine lines** — from `# dop` (line 1) to the triple backtick that
closes the `pip install` block (line 9), inclusive — with:

```markdown
# dop-cmd

DevOps Pipeline CLI - IA-First development workflow, multi-workspace, multi-platform.

DOP's operational tool: it **answers for the environment**. It reaches the workspace
directly and runs git operations, multi-platform PRs, a docker-compose runtime, e2e/AAA
tests and Allure reports.

> **A project of its own.** This tool lived until August 2026 in the `dop-cli`
> repository. The name was given back to another project, and it now has an independent
> repository and life cycle.
>
> The distribution is called `dop-cmd`, but the Python package and the executable are
> still `dop`. That is why it **cannot coexist** with any other package that installs
> the `dop` command in the same Python environment.

## Install

```bash
pip install git+ssh://git@github.com/Digital-Business-One/dop-cmd.git
```
```

Check that the rest of the README (`## Configuration` onwards) stayed intact:

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
grep -c '' README.md && grep -n '^## ' README.md
```

Expected: the sections `## Install`, `## Configuration`, `## CLI Commands`, `## Plan branch
table requirement`, `## Multi-platform support` and `## Auth methods` are still present, in that
order.

- [ ] **Step 7: Write ADR 0015**

Create `docs/adr/0015-separacao-dop-cmd-e-dop-cli.md` with the content below. The format follows
the existing ADRs (MADR: Context / Decision / Consequences).

```markdown
# ADR-0015 — Separating `dop-cmd` (the environment tool) and `dop-cli` (the platform's name)

- **Status:** Accepted
- **Date:** 2026-08-26
- **Spec:** `docs/dop-cmd/2026-08-26-separation-design.md` (the `dop` meta-repository)

## Context

The `dop-cli` repository accumulated **two overlapping roles**:

1. The **operational tool in use** (v0.7.1) — this code base, which reaches the
   workspace directly and answers for the environment.
2. The **`dop-cli` name**, which belongs to the DOP platform's project.

With both roles in the same repository, building the platform's CLI meant touching the
repository of a tool in production, and any conversation about "the dop-cli" was
ambiguous.

This code base and the DOP platform are **distinct projects**. This tool originated the
idea of that one, but it is not its technical ancestor: the platform inherits no code,
no model and no decision from here. Keeping both in the same repository suggested the
opposite.

## Decision

1. **Move** this implementation into a repository of its own, `dop-cmd`. The name suits
   the role better: an *environment command*, not a client's interface.
2. **Empty** `dop-cli`, giving the name back to the platform's project.
3. **Be born clean:** `dop-cmd` receives the files of `dop-cli`'s `main` in a single
   initial commit. The decision history stays reachable in `dop-cli` (the `v0.1.0` and
   `v0.5.0` tags and commit `19fa56a`).
4. **Preserve the execution identity:** the distribution is now called `dop-cmd`, but
   the **Python package and the executable are still `dop`**, and the version is still
   `0.7.1`. No workspace in use has to change command.
5. **Not be a submodule** of the meta-repository: `dop-cmd` lives at `repos/dop-cmd` and
   coexists with the other components, but the meta-repo aggregates only the 1.0
   product's components.

## Consequences

- ➕ The platform's CLI can be built from scratch without putting the tool in production
  at risk.
- ➕ Each name now designates a single role; the ambiguity of "the dop-cli" disappears.
- ➕ Zero operational disruption: `dop <subcommand>` keeps working as before.
- ➖ `dop-cmd` and the future `dop-cli` compete for the `dop` executable and **cannot
  coexist in the same Python environment**. When the 1.0 CLI takes the name, it will be
  in a separate environment or with `dop-cmd` already retired.
- ➖ Whoever installed from `dop-cli.git` has to change the origin to `dop-cmd.git`.
- ➖ As it is not a submodule, `dop-cmd` does not come in the meta-repository's recursive
  clone; it requires an explicit clone, documented in the root's README.
```

- [ ] **Step 8: Add the ADR to the index**

In `docs/adr/README.md`, add the 0015 line at the end of the table, right after the 0014 line:

```markdown
| [0015](0015-separacao-dop-cmd-e-dop-cli.md) | Separating `dop-cmd` (the environment tool) and `dop-cli` (the platform's name) | Accepted |
```

And add, to the "Provenance note" quote block that already exists at the top of the file, a
final line clarifying the numbering:

```markdown
> The "ADR-16" cited in `docs/workspace-migration-adr16.md` and in the
> `docs/superpowers/` specs is a document **on the workspace's side**, outside this index.
```

Check:

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
tail -3 docs/adr/README.md
ls docs/adr/0015-*.md
```

- [ ] **Step 9: A single initial commit**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git add -A
git status --short | wc -l
git commit -q -F - <<'MSG'
chore: imports the operational CLI from dop-cli as dop-cmd (v0.7.1)

A copy of dop-cli's main in a single initial commit. Only the
distribution's identity changes: name = "dop-cmd" in pyproject; the
package and the executable are still `dop`, version 0.7.1. It records
the decision in ADR-0015.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
git log --oneline
git ls-files | wc -l
```

Expected: a single commit and **100 versioned files** — the baseline's 99 plus ADR-0015.
`.claude/settings.local.json` stays out through the rule added in Step 2, and `.gitignore` still
counts as one of the 99 (it was modified, not created).

- [ ] **Step 10: Check that no unwanted file got in**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git ls-files | grep -E '\.venv/|__pycache__|\.pytest_cache|settings\.local\.json' && echo "PROBLEM: an unwanted file is versioned" || echo "CLEAN"
```

Expected: `CLEAN`.

If `settings.local.json` shows up versioned, Step 2 did not add `.claude/` to the `.gitignore`.
Fix it: `git rm --cached .claude/settings.local.json`, add the line to the `.gitignore` and amend
the commit with `git commit -q --amend --no-edit`.

---

### Task 3: Verify and publish `dop-cmd`

Proof that the copy is functionally identical, and only then the publication.

**Files:**
- Create: `repos/dop-cmd/.venv/` (a disposable environment, covered by the `.gitignore`)

**Interfaces:**
- Consumes: `<scratchpad>/baseline-pytest.txt` (Task 1); Task 2's repository.
- Produces: the repository published at `git@github.com:Digital-Business-One/dop-cmd.git`, the `main` branch.

- [ ] **Step 1: Run the suite in `dop-cmd`**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
cd /opt/wks/dbo/dop/repos/dop-cmd
python3 -m pytest tests/ -p no:playwright 2>&1 | tee "$SP/dopcmd-pytest.txt" | tail -5
```

- [ ] **Step 2: Compare with the baseline**

```bash
SP=/tmp/claude-1000/-opt-wks-dbo-dop/18641555-f07e-4cd9-a851-9d9427340b49/scratchpad
diff <(grep -E "^(FAILED|ERROR)" "$SP/baseline-pytest.txt") \
     <(grep -E "^(FAILED|ERROR)" "$SP/dopcmd-pytest.txt") && echo "IDENTICAL FAILURES"
diff <(tail -1 "$SP/baseline-pytest.txt" | sed 's/in [0-9.]*s//') \
     <(tail -1 "$SP/dopcmd-pytest.txt"   | sed 's/in [0-9.]*s//') && echo "IDENTICAL SUMMARY"
```

Expected: `IDENTICAL FAILURES` and `IDENTICAL SUMMARY`. Any divergence **stops** the plan — it
means the copy is not faithful.

- [ ] **Step 3: Check installability and the executable**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
python3 -m venv .venv
./.venv/bin/pip install -q -e . 2>&1 | tail -3
./.venv/bin/dop --version
./.venv/bin/pip show dop-cmd | grep -E '^(Name|Version)'
```

Expected: `dop --version` prints `0.7.1`; `pip show` reports `Name: dop-cmd`,
`Version: 0.7.1`. That proves decision D-3: a renamed distribution, an intact executable.

- [ ] **Step 4: Confirm the publication with the user**

Present to the user: the repository's name, its visibility and what is going to be pushed (1
commit, 100 files). **Wait for the go-ahead before the next step.**

- [ ] **Step 5: Create the repository on GitHub**

```bash
gh repo create Digital-Business-One/dop-cmd --private \
  --description "DOP — the operational environment tool (a Python CLI, v0.7.1)"
```

- [ ] **Step 6: Push**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
git remote add origin git@github.com:Digital-Business-One/dop-cmd.git
git push -u origin main
```

- [ ] **Step 7: Check the publication**

```bash
gh repo view Digital-Business-One/dop-cmd --json name,visibility,defaultBranchRef \
  | python3 -m json.tool
git -C /opt/wks/dbo/dop/repos/dop-cmd status -sb | head -1
```

Expected: `"visibility": "PRIVATE"`, the default branch `main`, and the local status showing
`## main...origin/main` with no divergence.

---

### Task 4: Empty and publish `dop-cli`

**Files:**
- Delete: `repos/dop-cli/src/`, `repos/dop-cli/tests/`, `repos/dop-cli/docs/`, `repos/dop-cli/pyproject.toml`
- Modify: `repos/dop-cli/README.md`

**Interfaces:**
- Consumes: `dop-cmd`'s publication (Task 3) — the emptying is only safe once the copy is published.
- Produces: `dop-cli` with two versioned files, the history and the tags preserved.

- [ ] **Step 1: Confirm `dop-cmd` is already published**

```bash
git -C /opt/wks/dbo/dop/repos/dop-cmd ls-remote --exit-code origin main >/dev/null \
  && echo "dop-cmd published, safe to empty" \
  || echo "STOP: dop-cmd not published yet"
```

If it prints `STOP`, go back to Task 3.

- [ ] **Step 2: Remove the migrated content**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git rm -r -q src tests docs pyproject.toml
git status --short | head
```

- [ ] **Step 3: Rewrite the `README.md`**

Replace the whole file with:

```markdown
# dop-cli

A repository reserved for the **DOP platform's CLI**. No implementation for now.

## The earlier implementation

Until August 2026 this repository contained a command-line tool that reaches the
workspace directly (v0.7.1). It is **a project of its own** and moved to
**[`dop-cmd`](https://github.com/Digital-Business-One/dop-cmd)**, where it stays
installable and maintained:

```bash
pip install git+ssh://git@github.com/Digital-Business-One/dop-cmd.git
```

The earlier code stays reachable in **this** repository's history: the `v0.1.0` and
`v0.5.0` tags, and commit `19fa56a` (the last state before the emptying). That tool's
ADRs and documentation travelled with the code.
```

- [ ] **Step 4: Check that only two files are left**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git add -A
git ls-files
```

Expected, exactly:
```
.gitignore
README.md
```

- [ ] **Step 5: Commit**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git commit -q -F - <<'MSG'
chore!: empties dop-cli; the implementation migrates to dop-cmd

The operational tool (v0.7.1) was moved to the dop-cmd repository.
This repository is reserved for the DOP platform's CLI. The history and the
v0.1.0/v0.5.0 tags stay here; the last state of the earlier implementation
is commit 19fa56a.

See ADR-0015 in dop-cmd/docs/adr/.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
git log --oneline -2
```

- [ ] **Step 6: Confirm the publication with the user**

This push is the plan's highest-impact step — it removes 97 files from a published
repository's `main`. **Wait for an explicit confirmation.**

- [ ] **Step 7: Push**

```bash
git -C /opt/wks/dbo/dop/repos/dop-cli push origin main
```

- [ ] **Step 8: Check that the history and the tags survived**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git log --oneline | wc -l
git tag -l
git cat-file -t 19fa56a
git show --stat 19fa56a | head -3
```

Expected: a commit count greater than 30 (nothing was rewritten); the `v0.1.0` and `v0.5.0` tags
present; `19fa56a` resolving as a `commit`.

---

### Task 5: Update and publish the meta-repository

**Files:**
- Modify: `/opt/wks/dbo/dop/.gitignore`
- Modify: `/opt/wks/dbo/dop/README.md`

**Interfaces:**
- Consumes: `dop-cmd` published (Task 3) and `dop-cli` emptied and published (Task 4).
- Produces: the meta-repository with an updated submodule pointer and `repos/dop-cmd` ignored.

- [ ] **Step 1: Ignore `repos/dop-cmd`**

Add to the end of the root's `.gitignore`:

```
# dop-cmd is a component of the project, but it is NOT a submodule of this meta-repository.
# Get it with: git clone git@github.com:Digital-Business-One/dop-cmd.git repos/dop-cmd
repos/dop-cmd/
```

Check that it disappears from the status:

```bash
cd /opt/wks/dbo/dop
git status --short | grep dop-cmd && echo "PROBLEM: it still shows up" || echo "IGNORED OK"
```

Expected: `IGNORED OK`.

- [ ] **Step 2: Update the structure tree in the `README.md`**

Replace the block of lines 14–17 with:

```
└── repos/                # the product's components
    ├── dop-cmd/          # the operational tool in use (v0.7.1) — NOT a submodule
    ├── dop-cli/          # reserved for the DOP platform's CLI (a submodule)
    ├── dop-api/          # the product's API (a submodule) — under construction
    └── dop-app/          # the frontend (React/Vite) (a submodule) — built by Replit + Claude
```

- [ ] **Step 3: Document getting `dop-cmd` in the `## Cloning` section**

Add to the end of the section (right before `## Components`):

```markdown
**`dop-cmd` is not a submodule** and therefore **does not come in the recursive clone**.
Get it separately:

```bash
git clone git@github.com:Digital-Business-One/dop-cmd.git repos/dop-cmd
```
```

- [ ] **Step 4: Rewrite the `## Components` entries**

Replace the three lines of the `dop-cli` entry (lines 40–42) with these two entries, keeping
`dop-api` and `dop-app` unchanged:

```markdown
- **dop-cmd** (`repos/dop-cmd`) — the **operational tool in use** (v0.7.1). It reaches
  the workspace directly and answers for the environment: multi-platform git/PR, a
  docker-compose runtime, e2e/AAA and Allure. It stays installable and maintained.
  **It is not a submodule** — see [Cloning](#cloning).
  **A project of its own**, independent of the platform.
  Installation: `pip install 'git+ssh://git@github.com/Digital-Business-One/dop-cmd.git'`.
- **dop-cli** (`repos/dop-cli`) — reserved for the DOP platform's CLI. Under construction.
```

> A note for whoever executes this: the descriptions of `dop-api` and `dop-app` belong to the
> DOP platform's project. **Do not change them here** — they are outside this spec's scope.

- [ ] **Step 5: Fix the internal docs pointer**

In the `## Documentation` section, change the line:

```markdown
- The CLI 0.5.x's internal docs live in `repos/dop-cli/docs/` (ADRs, references).
```

to:

```markdown
- The operational tool's internal docs (ADRs, references, architecture) live in
  `repos/dop-cmd/docs/`.
```

- [ ] **Step 6: Update the `## State` section**

Replace the two lines with:

```markdown
- ✅ `dop-cmd` v0.7.1 — the operational tool in use, installable and maintained.
- 🚧 `dop-cli`, `dop-api` and `dop-app` — the DOP platform's components, under construction.
```

- [ ] **Step 7: Pin the submodule pointer and check**

```bash
cd /opt/wks/dbo/dop
git add .gitignore README.md repos/dop-cli
git status --short
git diff --cached --stat
```

Expected: three paths in the index — `.gitignore`, `README.md` and `repos/dop-cli`.
`repos/dop-cmd` must **not** show up.

- [ ] **Step 8: Check that the submodules are still three**

```bash
cd /opt/wks/dbo/dop
git config -f .gitmodules --get-regexp path
git submodule status
```

Expected: exactly three entries — `dop-cli`, `dop-api`, `dop-app`. If `dop-cmd` shows up, some
step added it by mistake: undo it with `git rm --cached repos/dop-cmd` and check the
`.gitignore`.

- [ ] **Step 9: Commit**

```bash
cd /opt/wks/dbo/dop
git commit -q -F - <<'MSG'
chore: records dop-cmd as a non-submodule component

It adds repos/dop-cmd to the .gitignore, documents getting it through its
own clone and updates the structure, the components and the state in the
README. It pins the dop-cli submodule pointer at the emptying commit.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
git log --oneline -3
```

- [ ] **Step 10: Confirm and push**

Confirm with the user and then:

```bash
git -C /opt/wks/dbo/dop push origin main
```

---

### Task 6: The final verification and updating the memory

**Files:**
- Modify: `/home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/dop-cli-test-running.md` → renamed to `dop-cmd-test-running.md`
- Modify: `/home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/MEMORY.md`

**Interfaces:**
- Consumes: the final state of Tasks 3, 4 and 5.

- [ ] **Step 1: Verification §7.3 — the meta-repository's cleanliness**

```bash
cd /opt/wks/dbo/dop
git status --short
git submodule status | wc -l
```

Expected: no line mentioning `repos/dop-cmd`; a submodule count equal to `3`. (The untracked
`docs/dop-screenshot.png` and `docs/prompts/` may stay — they are outside this spec's scope.)

- [ ] **Step 2: Verification §7.4 — `dop-cli`'s integrity**

```bash
cd /opt/wks/dbo/dop/repos/dop-cli
git ls-files
git tag -l
git log --oneline -1
```

Expected: only `.gitignore` and `README.md`; the `v0.1.0` and `v0.5.0` tags present; HEAD at the
emptying commit.

- [ ] **Step 3: A cross check — `dop-cmd` is still working**

```bash
cd /opt/wks/dbo/dop/repos/dop-cmd
./.venv/bin/dop --version
python3 -m pytest tests/ -p no:playwright 2>&1 | tail -1
```

Expected: `0.7.1` and the same summary as the baseline (`1 failed, 142 passed`).

- [ ] **Step 4: Rewrite the project's memory**

Create `/home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/dop-cmd-test-running.md`:

```markdown
---
name: dop-cmd-test-running
description: How to run the dop-cmd (repos/dop-cmd) Python test suite without the pytest-playwright collection error
metadata:
  type: project
---

In `/opt/wks/dbo/dop/repos/dop-cmd`, run tests with `python3 -m pytest tests/ -p no:playwright`.

**Why:** the `pytest-playwright` plugin auto-loads and fails at COLLECTION with
`ModuleNotFoundError: No module named 'playwright'` (playwright isn't installed in the
host venv), which aborts the whole run before any test executes. `-p no:playwright`
disables that plugin so the pure-Python unit tests run.

**How to apply:** always append `-p no:playwright` when running pytest here. Green
baseline is 143 collected, "all pass except one": the PRE-EXISTING unrelated failure
`tests/test_handlers.py::TestPrPublish::test_commits_pushes_and_creates_prs`
(`TypeError: Object of type MagicMock is not JSON serializable`). The relevant unit
files are `test_config_schema_v05.py`, `test_runtime_handlers.py`, `test_cli_parsing.py`.

This suite lived in `repos/dop-cli` until 2026-08-26; that repository is now the empty
skeleton of the 1.0 thin client and has no tests.
```

Remove the old file:

```bash
rm /home/edbarros/.claude/projects/-opt-wks-dbo-dop/memory/dop-cli-test-running.md
```

- [ ] **Step 5: Update the memory index**

In `MEMORY.md`, replace the existing line with:

```markdown
- [dop-cmd test running](dop-cmd-test-running.md) — run pytest with `-p no:playwright`; 143 tests, one known unrelated PR-publish failure
```

- [ ] **Step 6: The final report to the user**

Report: `dop-cmd`'s URL, the test parity result, the file count in each repository and the three
commits created. Mention explicitly risk R-1 (a future collision on the `dop` command) and R-2
(the change of installation origin for whoever already uses the tool).

---

## The spec's coverage

| The spec's section | Task |
|---|---|
| §4.1 `dop-cmd`'s content | Task 2, steps 1–3 |
| §4.2 Changes over the copy | Task 2, steps 5–8 |
| §4.3 The ADR's numbering | Task 2, steps 7–8 |
| §5 `dop-cli`'s skeleton | Task 4, steps 2–5 |
| §6 The root meta-repository | Task 5, steps 1–9 |
| §7.1 Suite parity | Task 1 steps 2–3; Task 3 steps 1–2 |
| §7.2 Installability | Task 3, step 3 |
| §7.3 The meta-repo's cleanliness | Task 5 step 8; Task 6 step 1 |
| §7.4 `dop-cli`'s integrity | Task 4 step 8; Task 6 step 2 |
| §8 C-1 The session's memory | Task 6, steps 4–5 |
| §10 The execution order | The order of tasks 1 → 6 |

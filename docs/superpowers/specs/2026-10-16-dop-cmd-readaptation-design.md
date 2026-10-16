# dop-cmd readaptation — design spec

**Demand:** readapt `repos/dop-cmd` as this project's operating-environment tooling
(`foreman/records/environment.md` §1). **Brief:** `docs/prompts/2026-10-16-dop-cmd-readaptation.md`.
**Card:** ClickUp `wdu0h6hdvw` (https://app.clickup.com/t/wdu0h6hdvw), folder `13 ⚙️ Espinha, Ambiente e Operação`, list `Backlog`. Branch: `feat/wdu0h6hdvw-dop-cmd-readaptation`.
**Written:** 2026-10-16, by the architect session. **Status:** v2, after the reviewer's pass (§10).

---

## 0. Read and doubt — where the brief is wrong

The brief describes `repos/dop-cmd` as "version 0.7.1, built for another client".
That is true of `origin/main` (one commit, the import of 2026-09-01). It is not
the state of the working copy, and it is not the whole story:

1. **Eighteen local worktrees and branches** of the former client's later work
   sit under `repos/dop-cmd/.worktrees/` (`feat/ambiente-geral*`, `k3s`,
   `feat/e2e-no-cluster`, `feat/command-model`, `feat/dop-runtime-only`). Only
   `k3s` is on the remote (16 commits ahead of it). The most advanced line,
   `feat/ambiente-geral` (5,585 lines of source, 473 tests), carries a README
   saying the tool was **frozen on 2026-10-05 and folded into the other client's
   `optumdev`** ("Nada mais é editado aqui"). Those branches are history of
   another project, not a base for this one. Not deleted by this demand (not
   ours to decide); finding §8.1.
2. **The checked-out branch is `feat/dop-runtime-only`**, four unpushed commits
   that prune the git/PR/Jira side (122 tests green) and add design specs
   ("command model by immersion" v3.1, k3s local environment). The pruning is
   redone on a clean base rather than inherited: the base of record is `main`,
   and `dev` must be born from it (`delivery.md` §1).
3. **`environment.md` §2 is wrong about `dop-app`.** It says "no test command
   found"; `artifacts/dop/package.json` has `test` (`vitest run`, 8 files). The
   same error is in `quality.md` §2. This spec fixes `environment.md` in the
   same pull request (allowed); `quality.md` is reported (§8.2).
4. **`dop-infra`'s `make down` deletes the namespace including the PVCs** (data
   gone); `make reset` deletes PVCs while pods keep running; `make cluster-stop`
   exists but no `cluster-start` target does. The record's two verbs — `down`
   (tear down) and `reset` ("data included") — are mapped in §3 onto what the
   Makefile and `k3d` really do, without changing the Makefile.
5. **Nothing in `dop-infra` brings up a subset.** `make up` applies the whole
   overlay. "`dop up app` brings up only the app and what it needs" is refined in
   §3.1: the app's own process is started and the wait covers only the declared
   dependency closure; the cluster stays the unit `dop-infra` offers (§8.3).
6. **`dop-cli` is not "reserved".** It is the same v0.7.1 code as `dop-cmd`'s
   `main`: package `dop`, console script `dop = dop.cli:main`, about twenty test
   files about Jira, compose and Azure, and one test known red
   (`tests/test_handlers.py::TestPrPublish::test_commits_pushes_and_creates_prs`).
   Two consequences: `dop test cli` is red on day one, and that red is a
   `dop-cli` defect that stays red (row 2); and a `dop-cli` installed on the
   same machine **replaces this tool's `dop` on the path** (the v0.7.1 README
   says so itself). The entry-point collision is the owner's decision (§8.7).
7. **A fresh machine cannot `make up` after `cluster-up`.** `local-environment.md`'s
   life cycle is `cluster-up → images → up`; the registry starts empty, and the
   `firebase-emulators` image has no make target at all. The brief's acceptance
   row 7 ("runs from a fresh clone") needs §3.1's prepare step and §8.3's
   finding.

What holds: the verbs in `environment.md` §1 (none renamed or merged), the
governance boundary (`delivery.md` §5), the delivery order app → bff → core →
cli, and "wrap `dop-infra`, do not change it".

## 1. The decision in one paragraph

`dop-cmd` becomes a small, dependency-free Python CLI (`dop`, stdlib only,
Python ≥ 3.11, Linux and macOS) that **knows how to operate an environment and
never which components exist**. Everything project-specific — the components,
their repositories, how each is brought up, observed and tested, and how the
shared environment is driven — lives in a **`dop.toml` at the root of the `dop`
meta-repository**, committed there. The code keeps the two things of v0.7.1
that are general as they are (`core/security.py`: `redact`, `guard_text`;
`core/logging_utils.py`), rewrites `core/process.py` for the modes the verbs
need, and drops every docker-compose, Maven, Allure, Playwright and Jira verb,
module, document and test. Six verbs, as the record names them. Exit codes `0`
done, `1` failed, `2` usage or configuration error (including a missing tool),
`3` partial (several units asked, some failed or skipped) — the one general idea
of the command-model spec worth keeping.

## 2. The configuration — `dop.toml`

Location: `<root>/dop.toml`, found by walking up from the current directory;
`DOP_CONFIG=<path>` overrides. One file, one project. All paths relative to the
file. **Unknown keys anywhere are a configuration error (exit 2)**; so are
unknown `kind`, unknown `needs`, cycles, a `process` without `run`, a `cluster`
without `workloads`, a `test` layer not in `unit | integration | contract`.

```toml
[project]
name = "dop"
state_dir = ".dop"                    # lock, pid files and process logs; gitignored at the root
default_environment = "local"         # the only one today; the table is plural so a later GCP verb adds a row, not a migration

[environments.local]
kubeconfig = "k3d kubeconfig write dop-local"      # stdout = path; every make/kubectl runs with KUBECONFIG=<path>
namespace = "dop-local"
cluster_exists = "k3d cluster list dop-local"      # exit 0 = exists
cluster_running = "k3d cluster list dop-local -o json"   # dop reads serversRunning > 0
cluster_up = "make -C repos/dop-infra cluster-up"
cluster_start = "k3d cluster start dop-local"
cluster_stop = "make -C repos/dop-infra cluster-stop"
prepare = ["make -C repos/dop-infra images", "make -C repos/dop-infra image-runner"]   # after cluster_up only
up = "make -C repos/dop-infra up"
down = "make -C repos/dop-infra down"              # used by reset only (deletes the namespace and its data)
status = "make -C repos/dop-infra status"          # appended verbatim under -v
workloads = ["sts/postgres", "sts/nats", "sts/firebase", "deploy/secretmanager"]   # the environment's own readiness
wait_timeout = "240s"
addresses = ["http://api.localtest.me:8080", "http://auth.localtest.me:8080", "http://traces.localtest.me:8080"]

[components.app]
repo = "repos/dop-app"
kind = "process"
needs = ["bff"]
setup = "pnpm install --frozen-lockfile"
run = "pnpm -C artifacts/dop dev"
env = { PORT = "5173", BASE_PATH = "/", VITE_API_BASE_URL = "http://api.localtest.me:8080", VITE_FIREBASE_AUTH_EMULATOR_URL = "http://auth.localtest.me:8080", VITE_FIREBASE_PROJECT_ID = "dop-local", VITE_FIREBASE_API_KEY = "fake-api-key" }
ready = "http://localhost:5173"
address = "http://localhost:5173"
[components.app.test]
unit = ["pnpm typecheck", "pnpm -C artifacts/dop test"]

[components.bff]
repo = "repos/dop-api"
kind = "cluster"
needs = ["core"]
workloads = ["deploy/dop-api"]
logs = "make -C repos/dop-infra logs C=dop-api"
ready = "http://api.localtest.me:8080/healthz"
address = "http://api.localtest.me:8080"
setup = "uv sync"
[components.bff.test]
unit = ["make test"]

[components.core]
repo = "repos/dop-core"
kind = "cluster"
workloads = ["deploy/dop-core-serve", "deploy/dop-core-worker", "deploy/dop-core-sched"]
logs = "make -C repos/dop-infra logs C=dop-core"
[components.core.test]
unit = ["make test"]
[components.core.test.integration]
forwards = ["svc/postgres 5432:5432", "svc/nats 4222:4222"]
commands = ["make test-integration"]
[components.core.test.contract]
forwards = ["svc/nats 4222:4222", "svc/firebase 9199:9199", "svc/secretmanager 8085:9090"]
commands = ["make test-contract-integration", "make proto-breaking"]

[components.cli]
repo = "repos/dop-cli"
kind = "none"
[components.cli.test]
unit = ["uv run --with pytest --with-editable . python -m pytest tests -p no:playwright -q"]
```

Rules of the model:

- `kind` ∈ `cluster | process | none`. A `cluster` component is brought up by the
  environment's `up`; `dop` waits for its `workloads` and probes `ready`. What
  runs is the image the manifests name (`API_TAG`, `CORE_TAG`), **not the working
  copy**; taking a source change to the cluster (build, tag, rollout) has no
  `dop` verb in this delivery (§8.4). A `process` component is started by `dop`
  from `repo` with `run` and `env`, detached, with pid and log under `state_dir`.
  A `none` component has no runtime.
- `needs` is a list of component names; the closure is computed; a `cluster`
  component implicitly needs the environment.
- `setup` (optional, any kind) is an idempotent install command run in `repo`
  before `run` and before any test layer (`pnpm install`, `uv sync`).
- `test.<layer>` is either a list of commands or a table `{ forwards?, commands }`.
  Commands run in order inside `repo`; the first failure stops the layer and
  fails the verb. `forwards` are `kubectl port-forward -n <ns> <svc> <ports>`
  entries that `dop` opens for the run and closes after, through `kubeconfig`.
- Every command runs through the rewritten `core/process.py`: shell string,
  cwd, env, one of three modes — **stream** (foreground, inherits the terminal:
  `logs`, `test`, `up`'s make calls), **capture** (stdout returned, redacted on
  failure: `cluster_*`, `kubeconfig`, `kubectl get`), **detach** (new session,
  stdout+stderr to a file, pid returned: `run`, `forwards`) — and returns the
  return code. `--dry-run` prints `WOULD RUN <cmd>` for commands and `WOULD WAIT
  <what>` for probes and polls, parses nothing, and exits 0.
- The tool never resolves pods, images, ports or hosts from code. If it is not in
  `dop.toml`, `dop` does not know it.

The root repository gets `dop.toml` and the `.gitignore` line `.dop/`.
Configuration is neither component code nor a pointer, so `repositories.md` §2's
rule holds; its sentence "the root holds documentation and the pointers" becomes
incomplete the day the file lands — finding §8.6 for the owner's edit.

## 3. The verbs

All verbs take `--dry-run`, `-v`, `--config <path>`. `dop --help` lists exactly:
`up`, `down`, `status`, `logs`, `test`, `reset`. A missing tool (`k3d`,
`kubectl`, `make`, `pnpm`, `uv`) is reported by name with exit 2, never a
traceback. A lock file under `state_dir` serialises `up`, `down` and `reset`:
a second one says "another dop is running (pid N)" and exits 1.

### 3.1 `dop up [component…]`

No argument: the environment and every component. With arguments: the named
components, their `needs` closure, and the environment if any of them is
`cluster`.

1. **Cluster.** `cluster_exists` fails → `cluster_up`, then every `prepare`
   command. Exists but `cluster_running` says stopped → `cluster_start`.
2. **Environment.** `up`, then wait for `[environments.local].workloads`
   (`kubectl -n <ns> rollout status <w> --timeout=<wait_timeout>`, `KUBECONFIG`
   set). Nothing else in the namespace is waited for: jaeger, headlamp and any
   workload no row declares are tools, not dependencies.
3. **Components, in dependency order.** `cluster`: wait for its `workloads`,
   then probe `ready` if declared. `process`: if `ready` already answers before
   anything was started and no pid of ours is alive → "port held by a process
   dop does not own" (failed, exit 1); if our pid is alive → "already running"
   (done); otherwise `setup` if declared, then detach `run` (new session), then
   probe `ready` until `wait_timeout` while checking the pid is still alive — a
   dead pid is **failed**, never ready. `none`: "nothing to bring up" (done).
4. **Print** one line per unit with outcome and `address`, then the
   environment's `addresses`.

So `dop up app` = cluster running + `make up` + wait postgres/nats/firebase/
secretmanager → wait `deploy/dop-core-*` → wait `deploy/dop-api` + `/healthz` →
`pnpm install` → start Vite → probe `:5173`. **Refinement of acceptance row 1**
(recorded in `environment.md`): "what it needs" is the declared closure plus the
environment's own workloads; the cluster is the unit `dop-infra` provides.

`KUBECONFIG` from `kubeconfig` is set on every `make` and `kubectl` the tool
runs, so the Makefile's guard (`kubectl config current-context` must be
`k3d-dop-local`) passes **without touching the machine's current context**,
which holds other clients' clusters. `dop` never runs `kubectl config
use-context`.

### 3.2 `dop down`

Stops every `process` component `dop` owns (SIGTERM to the process group, SIGKILL
after 10 s, pid file removed), then `cluster_stop`. Data survives: the next
`dop up` runs `cluster_start` and the same `make up`. Help text: *"stops the
app processes and the local cluster; data is kept"*. This is `environment.md`
§1's "tears it down" as distinct from `reset`'s "data included".

### 3.3 `dop status`

Never changes state. Prints the environment (cluster absent / stopped /
running, namespace, every declared workload ready/desired from `kubectl get -o
json`, the `addresses`) and one line per component: `kind`, state (`ready | not
ready | down | n/a`), `address`; for `process` the pid and log path; for
`cluster` each workload and the `ready` probe. Exit `0` all ready, `3` some not,
`1` cluster absent or kubectl failing, `2` missing tool. `-v` appends the
environment's `status` command output verbatim.

### 3.4 `dop logs <component>`

`cluster`: the component's `logs` command in stream mode (the Makefile's `-f`);
Ctrl-C ends it with exit 0. `process`: `tail -f` of the component's log; never
started → "never started" (exit 3). `none`: "cli has no runtime; nothing to
follow" (exit 3). **Refinement of acceptance row 3.**

### 3.5 `dop test <component> [--layer unit|integration|contract]`

Default `unit`. `setup` first if declared; then open `forwards` (detached,
waited until the local port answers, closed in `finally`); then the commands in
order, streaming. Exit `1` on the first failing command, `2` if the layer is not
declared. Nothing is retried, skipped or masked: a red `dop-cli` suite is a
`dop-cli` defect and stays red.

### 3.6 `dop reset`

Stop owned processes, then the environment's `down` (namespace and PVCs gone),
then §3.1 for everything. The core worker re-migrates and re-seeds at boot.
Help text: *"starts the local environment over; all local data is lost"*.

## 4. What is removed from `dop-cmd`

Verbs `start stop restart rebuild status ps log e2e aaa it codegen report clean`;
`src/dop/runtime/` entirely; `src/dop/config/{schema,loader,discovery}.py` in
their workspace/repos/runtime/apps form (replaced by `dop/config.py`);
`core/state.py`, `core/hashing.py`, `core/fs.py` unless used after the rewrite;
`docs/adr/0003, 0004, 0005, 0008, 0009, 0010, 0011, 0012, 0013, 0014, 0015`;
`docs/prd/`, `docs/examples/`, `docs/reference/`, `docs/superpowers/`,
`docs/architecture/`, `docs/workspace-migration-adr16.md`, `docs/prompts/`;
every test of the removed code. ADRs 0001 (single CLI, handler dispatch), 0002
(TOML configuration, now one file per project), 0006 (redaction), 0007 (dry-run
everywhere) stay, amended; new ADR 0016 records the readaptation and the
`dop.toml` model. Acceptance row 4 is the grep

```
grep -riE "optum|odev|csptech|lifesupport|jira|SUOPT|maven|mvn|allure|testcontainers|Digital-Business-One" \
  repos/dop-cmd --exclude-dir=.git --exclude-dir=.worktrees --exclude-dir=.venv
```

returning nothing.

## 5. Package, install, version, platform

`pyproject.toml`: name `dop-cmd`, version `1.0.0` (a new tool under an old name),
`requires-python >= 3.11`, no dependencies, script `dop = dop.cli:main`. Linux
and macOS; Windows is out of scope (process groups, `tail -f`). Install, the one
documented command from the `dop` root after the clone of `environment.md` §3:

```bash
uv tool install --editable repos/dop-cmd      # `dop` on ~/.local/bin
```

`uv` becomes a named prerequisite in `environment.md` §3 (S5). The README also
gives the form from the repository URL for a machine without the clone, and
warns that `dop-cli`'s own `dop` script must not be on the same path (§8.7).

## 6. Documentation

- `repos/dop-cmd/README.md`: what the tool is, the six verbs with one line each,
  the `dop.toml` model, install, exit codes, what it is not (no git, pull
  requests, cards, deploy, source-to-cluster).
- `repos/dop-cmd/docs/adr/0016-readaptation-dop-toml.md` (MADR).
- Root `foreman/records/environment.md`: §1 verb table confirmed (no rename) with
  the two refinements (`up <component>` = closure + environment workloads; `logs
  cli` = nothing to follow) and the `down`/`reset` sentences of §3.2/§3.6; §2
  rows for the four components name the `dop` verb in every column (fallback
  column empty), the `dop-app` test row corrected, and the bff/core "Up" rows
  stating that `dop up` runs the published image, not the working copy; §3 adds
  `uv`, `k3d`, `kubectl` and `repos/dop-cmd` installed with the §5 command.
- Root `README.md`/`AGENTS.md` are not changed (§8.8).

## 7. The split, in dispatch order

Shared vocabulary for the builders (module layout and dataclasses, so no
separate plan is needed), all under `repos/dop-cmd/src/dop/`:

- `config.py` — `Project(name, state_dir, default_environment)`,
  `Environment(dir, kubeconfig, namespace, cluster_exists, cluster_running,
  cluster_up, cluster_start, cluster_stop, prepare, up, down, status, workloads,
  wait_timeout, addresses)`, `Component(name, repo, kind, needs, setup, run,
  env, ready, address, workloads, logs, tests)`, `TestLayer(forwards,
  commands)`, `Config(root, project, environments, components)`;
  `load(path) -> Config` (tomllib, strict keys, validation, exit-2 errors as
  `ConfigError`), `find_config(cwd) -> Path`, `closure(config, names) ->
  list[Component]` in dependency order.
- `core/process.py` — `run(cmd, *, cwd, env, mode: "stream"|"capture"|"detach",
  log_file=None, dry_run) -> Result(rc, stdout, pid)`; `kill_group(pid)`;
  redaction via `core/security.py` on captured failure output.
- `kube.py` — `Kube(kubeconfig_path, namespace)`: `rollout_wait(workload,
  timeout)`, `get_workloads() -> list[WorkloadState]`, `port_forward(spec) ->
  pid`; all through `run`.
- `cluster.py` — `ClusterDriver(env)`: `state() -> absent|stopped|running`,
  `ensure_running()` (up+prepare / start), `stop()`, `env_up()`, `env_down()`,
  `wait_environment()`.
- `processes.py` — `ProcessManager(state_dir)`: `start(component) -> pid`,
  `alive(component)`, `stop(component)`, `log_path(component)`, `lock()`.
- `probe.py` — `http_ready(url) -> bool`, `wait_until(fn, timeout, alive=None)`.
- `verbs/{up,down,status,logs,test,reset}.py` — one `run(config, args) -> int`
  each; `cli.py` — argparse with the six subparsers, global flags, exit codes,
  `ToolMissing`/`ConfigError` → exit 2.

| # | Slice | Tree | Depends on | Who |
|---|---|---|---|---|
| S0a | **Skeleton.** Prune §4 (the full list), `pyproject.toml` (§5), `config.py` with validation and closure, `core/process.py` rewrite, `cli.py` with the six subparsers, `--help`, `--dry-run`, exit codes, and the `test` verb complete (setup, forwards via a `Kube` stub interface, commands). Unit tests with fakes for every path. README skeleton + ADR 0016. | `repos/dop-cmd` worktree on `feat/wdu0h6hdvw-dop-cmd-readaptation` | — | builder, **senior** (defines the contracts the others consume) |
| S0b | **Cluster side.** `kube.py`, `cluster.py`, `verbs/up.py` (cluster + environment + `cluster` components), `verbs/down.py` (cluster_stop part), `verbs/reset.py`, `verbs/status.py`, `verbs/logs.py` (cluster part). Fakes for `k3d`/`kubectl`/`make`. | same worktree, after S0a's commit | S0a | builder, senior |
| S0c | **Process side.** `processes.py`, `probe.py`, the `process` branch of `up`/`down`/`status`/`logs`, lock, port-held and dead-pid cases. Fakes for processes. | a second worktree of the same branch is **not** allowed (one tree, one agent): S0c runs after S0b, same tree | S0b | builder, mid |
| S1 | **Live validation.** Root `dop.toml` (§2 in full), root `.gitignore`; against the real cluster, in this order because of the closure: `core` (up, logs, the three test layers), `bff` (up, logs, test), `app` (up, status, logs, test, down), `cli` (up, logs, test — expected red stays red), then `dop up`, `dop status`, `dop down`, `dop up` again (data kept), `dop reset`, `dop --help`, the §4 grep, the §5 install in a fresh `uv tool` environment. Fixes go to `dop-cmd` or to the config row, never to `dop-app`/`dop-api`/`dop-core`/`dop-infra`. | same worktree + root | S0c | builder, senior (reads failures of four stacks) |
| S5 | **Records.** `environment.md` §1–§3 as §6 says. | root | S1 | builder, junior (text only) |

The brief's app → bff → core → cli order is the **delivery priority**; S1's
validation order is dictated by the dependency closure. Each slice ends with a
commit on the branch (Portuguese subject describing the finding); pushes, pull
request and the pointer move are the architect's. One worktree, one agent at a
time: S0a → S0b → S0c → S1 → S5 are sequential by construction.

Estimated worth: the project's daily entry point for every agent and the owner,
and the base of two later verbs. Three senior slices and two cheaper ones is
proportionate; a fork of the architect is not.

## 8. Findings for the card (not built here)

1. `repos/dop-cmd` holds 17 local branches/worktrees of the former client's
   work, 16 unpushed; the frozen code lives in `optumdev`. Owner: delete, or
   archive under `archive/*` on the remote.
2. `quality.md` §2: `dop-app` has unit tests (`pnpm test`, vitest). Owner's edit.
3. `dop-infra` gaps, each its own demand: no `cluster-start` target (the tool
   calls `k3d cluster start` directly from config); `make reset` leaves pods
   running on deleted PVCs; no subset kustomization; image tags duplicated
   between Makefile and manifests; the `firebase-emulators` image has no make
   target (a fresh machine cannot come up by any route until it is built by
   hand); the VITE_* values and the three `localtest.me` hosts now live in
   `dop.toml` and in the Makefile's `deploy-app` — drift risk.
4. Missing `dop` verbs the records will owe: source → cluster for bff/core
   (build, tag, rollout — `make image-*` + manifest edit today), cockpit publish
   (`make deploy-app`), moving the ClickUp card (`demands.md` §1), deploying
   `dev` to GCP (`delivery.md` §4). `dop up bff|core` runs the published image,
   not the working copy; `make run` on the host is not wired (needs env and
   forwards nobody defined).
5. `dop-core`'s `test-integration` / `test-contract-integration` only echo the
   port-forwards they need; `dop` opens them (§2 `forwards`). A `dop-core`
   Makefile that opened its own would make the config rows shorter.
6. `repositories.md` §2 should name `dop.toml` beside "documentation and the
   pointers". Owner's edit.
7. `dop-cli` installs a console script `dop` from the same v0.7.1 code; on a
   machine with both, whichever `~/.local/bin/dop` was written last wins. Owner
   decides `dop-cli`'s future name or entry point.
8. `AGENTS.md`'s command table could point at `dop` once this lands.
9. `dop-cmd` has no integration layer of its own: its tests run on fakes; the
   live behaviour is proved only by S1 and the QA run. Building a fake-cluster
   layer is its own demand (`quality.md` §1).

Found by S1's live run (2026-10-16):

10. **`dop-core` cannot migrate an empty database** (image 0.1.0-22): `$$`
    functions in migrations 0001, 0005, 0009, 0010 lack goose's
    `StatementBegin/End`; the local database had been hand-migrated and
    baselined at 27, so the path was never exercised. `dop reset` exposed it and
    left serve/worker in CrashLoopBackOff. Card **wdu0h6hdxk** (urgent), branches
    `fix/wdu0h6hdxk-*` in `dop-core` and `dop-infra` (tag 0.1.0-23). §3.6's
    premise ("the worker re-migrates at boot") holds only after that fix.
11. `dop-core`'s contract suite is red against the shared environment's NATS
    (the running worker consumes the test events; sandbox docker cases time out
    or hit `/etc/dop/git-token: Permission denied`). Row 2's contract half runs
    the forwards and the first command, then stops on that red — a `dop-core`
    test-design demand, recorded on card wdu0h6hdxk.
12. `k3s/services/dop-core/configmap.yaml` pins `COLLECTOR_IMAGE` to
    `dop-core:0.1.0-13` while the deployments run 0.1.0-22. Owner's call.
13. The cli test row needs `uv run --no-project …`; without it `uv` writes a
    `uv.lock` and a `.venv` into `repos/dop-cli` (fixed in `dop.toml`).

## 9. Acceptance rows (refined from the brief §4)

1. `dop up`, `dop down`, `dop status`, `dop reset` work against the environment
   `dop-infra` provides; `dop down` keeps data and `dop up` after it comes back
   with the same data; `dop up app` starts the app's process and waits only for
   the environment's workloads and the app's declared closure.
2. `dop test app|bff|core|cli` run the `unit` commands `dop.toml` declares;
   `dop test core --layer contract` opens the forwards, runs `make
   test-contract-integration` then `make proto-breaking`; `--layer integration`
   runs `make test-integration`; `dop test cli` is red with `dop-cli`'s known
   failure and `dop` reports exit 1 (row proved by the red, not masked).
3. `dop logs app|bff|core` follow the component's logs; `dop logs cli` answers
   "nothing to follow" with exit 3.
4. The §4 grep over `repos/dop-cmd` returns nothing.
5. `dop --help` lists exactly `up down status logs test reset`.
6. `environment.md` §2's fallback column is empty for the four components.
7. `uv tool install --editable repos/dop-cmd` on a clone that followed
   `environment.md` §3 puts a working `dop` on the path; `dop status` runs; on a
   machine without `k3d` it exits 2 naming the tool.
8. Exit codes `0` done, `1` failed, `2` usage/config/missing tool, `3` partial;
   a failing component command is never masked; `dop up app` with Vite dying
   after start reports failed, not ready; a second `dop up` while one runs
   exits 1 "another dop is running".

**QA ceiling for this demand: 60 minutes and 30 cases** (default 30/20 raised:
rows 1, 2 and 8 need real cluster time — a `reset` alone costs minutes). Rows
4, 5 and the config/exit-code cases run on fakes; rows 1, 2, 3, 7 run live.

## 10. Review record

Codex (`codex-review`, the culture's reviewer of record) could not run on
2026-10-16: "Your access token could not be refreshed" — re-login is the
owner's manual step. The `reviewer` archetype (`.claude/agents/reviewer.md`)
was run instead at the architect's seniority, read-only, with the same attack
list. It raised 16 objections; all changed the spec:

| # | objection | decision |
|---|---|---|
| 1 | fresh machine: no images, no `pnpm install`/`uv sync`, `uv` unlisted, missing tool → traceback | `prepare` after `cluster_up`; per-component `setup`; `uv`/`k3d`/`kubectl` in §3 via S5; missing tool = exit 2 (§2, §3, §6) |
| 2 | cluster has three states, spec modelled two | `cluster_running` + `cluster_start` (§2, §3.1) |
| 3 | `down` destroyed data; `k3d cluster start` is prescribed by dop-infra's own docs, no Makefile change needed | `down` = stop processes + `cluster_stop`; `reset` = `make down` + up (§3.2, §3.6) |
| 4 | Makefile guard vs the machine's current context | `KUBECONFIG=$(k3d kubeconfig write …)` on every make/kubectl; `--context` dropped (§2, §3.1) |
| 5 | §3.1 waited for the whole namespace and promised not to | `[environments.local].workloads` is the environment's readiness; components wait theirs (§2, §3.1) |
| 6 | pnpm forks vite; orphan on :5173 answers the probe | new session + process-group kill; port-held check; dead pid = failed (§3.1, §3.2) |
| 7 | core's integration/contract targets only echo their forwards | `forwards` per layer, opened and closed by `dop` (§2, §3.5) |
| 8 | S0 too big for one builder; ADRs 0003–0005, 0008–0010 forgotten | S0a/S0b/S0c with named modules and dataclasses; full ADR list (§4, §7) |
| 9 | S1–S4 order contradicts the closure; four cold builders on one file | one S1, validation order core → bff → app → cli; app-first stays the delivery priority (§7) |
| 10 | `dop-cli` is the v0.7.1 copy with a `dop` script and a known red | §0.6; row 2 expects the red; collision is §8.7 |
| 11 | "keep process.py" was false (argv, capture, raise) | rewritten with three modes (§2, §7) |
| 12 | `kind=cluster` silently changed `up bff|core`'s meaning; no source→cluster or publish verb; Hosting address never populated | stated in §2 and §6's record rows; §8.4; Hosting address dropped from `addresses` |
| 13 | unknown keys, dry-run on conditionals/polls, no lock, platform undeclared | strict keys exit 2; `WOULD RUN`/`WOULD WAIT`, no parsing; lock; Linux/macOS (§2, §3, §5) |
| 14 | QA would run out of minutes; dop-cmd has no integration layer | ceiling 60 min / 30 cases with the reason; live vs fakes stated; §8.9 (§9) |
| 15 | singular environment; VITE_*/hosts duplicated with the Makefile | `[environments.<name>]` + `default_environment`, **no `--env` flag yet** (a flag with one value is surface nobody asked for — partial acceptance); duplication in §8.3 |
| 16 | spec asked the reviewer to bless the root `dop.toml` instead of recording the record's gap | §2 states the reading; §8.6 for the owner |

Overruled: none in substance; #15's `--env` flag deferred, reason above.

### 10.1 After the QA run (2026-10-16, report `foreman/qa/reports/2026-10-16-wdu0h6hdvw/`)

The QA lead read **FAIL on five defects**, all in `dop-cmd`'s edge paths, none in
live behaviour; all eight rows proved. Architect's decision: fix before the pull
request, in one slice (S6), and re-attack with the same lead. What S6 fixes, and
the contract changes it brings into §2–§3:

| # | finding | decision |
|---|---|---|
| D1 | config path that is a directory / unreadable / not UTF-8 → traceback, exit 1 | every load error is `ConfigError`, exit 2, one sentence |
| D2 | `wait_timeout = nan|inf` accepted → waits forever | durations must be finite and > 0 |
| D3 | `--dry-run up|reset` creates `state_dir` | dry-run writes nothing, creates no directory |
| D4 | relative executable tool-checked against dop's cwd | tool check resolves relative paths against the command's cwd (`repo`) |
| D5 | `repo` that does not exist passes the loader → traceback at run time | `repo` must exist and be a directory at load (exit 2) |
| W1 | a `process` that never became ready is left running; the next `up` says "already running" and never probes | **§3.1**: on not-ready or process-exited, `dop` stops the group and removes the pid file, so the retry starts again; "already running" re-probes `ready` and reports `not ready` (failed) when it does not answer |
| W3 | a pid is trusted on its number alone (reuse after reboot → a stranger's group killed) | the pid file records the command line's first word and the start time; `alive()` also checks `ps -o args=` matches, else the file is stale |
| W4 | `logs app` after `down` follows a dead log forever | **§3.4**: `process` not alive → prints the last 20 lines, says "not running", exit 3 |
| W5 | dry-run `up` of a running process prints `WOULD RUN` setup/run | dry-run consults `alive()` and prints "already running" |
| W6 | keys contradicting the `kind` are accepted; `[environments].dir` unused; `up`/`down` not required | **§2**: kind-specific keys are validated (`none` admits only `repo`, `kind`, `needs`, `setup`, `test`; `process` forbids `workloads`/`logs`; `cluster` forbids `run`/`env`); `workloads` entries must be `kind/name`; duplicate `needs` rejected; `dir` dropped from the model; `kubeconfig`, `namespace`, `up`, `down`, `cluster_exists`, `cluster_running`, `cluster_up`, `cluster_start`, `cluster_stop` required |
| — | `dop … \| head` → BrokenPipeError traceback | handled, exit 0 |
| — | a command containing `os.environ` refused as "Security violation", exit 1 | the guard stays for captured *output*; a configured *command* is not guarded (a project's own command is not a secret dump) |
| — | `--config ""` / `DOP_CONFIG=""` treated as unset | empty path is a usage error, exit 2 |

**Second pass** (same report, section "Second pass"): FAIL on R1, a regression of
the W3 fix — identity inferred from the text of `run` (`./start.sh`, `exec …`)
never matches `ps -o args=` after the exec, so the process is judged a stranger
the instant it starts and is orphaned — and R2, `workloads` regex with `$`
accepting a trailing newline. Decision (S7): **identity is `pid` + start time
only** (`ps -o lstart=`, stable through `exec`; a reused pid has a different
start time), the executable name is recorded for display and never checked;
`fullmatch` on the regex; the tool check skips every shell builtin and keyword
(`trap`, `set`, `eval`, `exec`, `exit`, `if`, `for`, `while`, `case`, `{`, `(`,
`!`, `true`, `false`, `test`, `[`, `echo`, `printf`, `read`, `wait`, `kill`,
`type`, `command`, `source`, `.`, `cd`, `export`, `unset`, `umask`, `ulimit`),
checking the first non-builtin word of the first segment when there is one;
the "already running, not ready" message names `dop down` as the way out.

Recorded, not fixed (W2, W7, W8, W9 and the beyond-plan notes; plus from the
second pass: no upper bound on `wait_timeout`; a `ps` failure trusts the pid;
`make up` reports secrets and statefulsets `configured` on every apply): `status` could
say "port answers but not ours"; only the first word of a command is tool-checked
and commands are echoed verbatim (never put a credential in `dop.toml`);
port-forward logs have no rotation and forwards would leak if `dop` itself were
SIGKILLed mid-`test`; `app.log` ends with pnpm's exit-143 noise after `down`;
`make up` reports `secret/dop-core configured` on every apply (dop-infra); root
`README.md` still describes `dop-cmd` v0.7.1 and a `pip install` (owner's edit,
§8.8).

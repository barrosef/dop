# ADR-0028 consistency map — what contradicts it, and what changes

**Date:** 2026-09-03 · **Rule:** everything that defines knowledge, artefacts, the sandbox's shelf or the sandbox's credential differently from ADR-0028 (and from today's P-27 decision) is to be eliminated and replaced. This map lists every such place, doc by doc and file by file, with the change.

Legend — **C** conflicts (must change) · **D** drift (doc and code already disagree with each other) · **G** gap (promised, never built) · **A** align (same intent, different words).

## 1. ADRs

| Where | What it says today | Verdict | Change |
|---|---|---|---|
| **ADR-0009** §Decision 2 | "Access through a port (`KnowledgeStore`, over `ObjectStore`)" | **C** | Text lives in the root repository (git); the ObjectStore keeps BYTES (diagrams, exports). Amend with a "Revised by ADR-0028" note; the three layers stay |
| **ADR-0009** §Alternatives | "**A raw document folder in the sandbox. Rejected**: with no curation and no assembly, the agent digs" | **C** — the sharpest one | The rejection was of a folder AS A REPLACEMENT for the package. ADR-0028 keeps the package (the paid, curated path into the prompt) and ADDS the shelf (complete, on disk, with a manifest so the agent does not dig). Amend the alternative to say exactly that, or a reader finds two ADRs contradicting each other |
| **ADR-0024** §"A microVM per demand" | "The boundary that has to be hard is between accounts and between demands" | **A** | Still true for the WORKSPACE. For KNOWLEDGE the boundary is the project — by design, it is what "shared and collaborated" means. Add the pointer |
| **ADR-0024** §"An ephemeral pod per verification run" | a pod per run, "a Service and an Ingress give the human a live URL" | **C** — by P-27, not by 0028 | The owner cut it on 2026-09-03: one address per demand, parallel runs inside a demand QUEUE. Today the decision lives only in the ROADMAP; the ADR still says the opposite. Amend 0024 with a "Superseded in part (2026-09-03)" section |
| **ADR-0003** §To attribute | "each commit carries an `author` with the name and e-mail of the dev who ran the card" | **C** with ADR-0028 §2 ("the commit's author is the THREAD") | Both are right and git has two fields. **Reconcile: `author` = the dev who ran the card (ADR-0003 stands, for code AND knowledge); `committer` = the thread.** The customer's history keeps the person; the platform's attribution keeps the agent. Change 0028 §2; add one line to 0003 |
| **ADR-0028** §3 | the token "travels in the sandbox's `Env`" | **A** with the substrate spec §5 ("as a projected volume") | The spec is right: a projected FILE, not environ — environ is inherited by every child process. Fix 0028 |
| **ADR-0014** §Decision | `artifacts: [document\|spec\|plan\|test_plan\|…]` as stage vocabulary | **G** | Where an artefact LIVES was never said, and nothing stores one. Now: a file at `demand/<id>/<kind>.md` in the root repository. Amend 0014 with "where it lives"; P-8 (the syntax of the criteria) stays open |
| **ADR-0007** | executable criteria "inside the `spec` artifact" | **A** | The spec now has an address. No conflict; add the pointer |
| **ADR-0010** §3 | "Threads are readable by their siblings as a tool (`read_thread`, `ask`)" | **D** with the single-tool design (tools.go, ADR-0023) | Not 0028's, same family: named tools that do not exist. Note it; the fix is the same as the knowledge spec's below |
| **ADR-0010** §4 | "Findings … feed the project's memory (ADR-0009)" | **G** | Promised, never built — this is P-41. With 0028 the mechanism is a commit into `memory/` |

## 2. Specs

| Where | What it says today | Verdict | Change |
|---|---|---|---|
| `context-and-knowledge.md` §storage | "Behind the `KnowledgeStore` port (over `ObjectStore`)" | **C** | git for text, bucket for bytes |
| `context-and-knowledge.md` "Who writes" table | memory: "written back at the end of each demand"; rules: "a human (and the agent, with approval)" | **G** | Keep the intent; say HOW: a commit into `memory/` by the thread; a rule change by an agent is a commit that needs a human gate |
| `context-and-knowledge.md` §size | "the agent may ask for more (`search_memory`, `read_index(repo)`)" | **D** | Those tools do not exist and must not: `run_command` composes them — `cat /project/index/<repo>.md`, `grep -r … /project/memory`. Rewrite; and add the package-vs-shelf distinction, which this spec does not have |
| `execution-substrate.md` §4 table | "**The context package** — assembled at provisioning, read-only" | **C** | The package is per TURN and lives in the prompt. What is at provisioning is "**the project's root repository** — cloned at `/project`, read-write, the agent commits" |
| `execution-substrate.md` §5 | "a short-lived derived token (a 1h installation token for selected repositories — ADR-0003), as a projected volume" | **A** | Already the right shape. Add the platform git token beside it: same shape, opens one repository |
| `execution-substrate.md` §6.1 | egress allowlist: "only the demand's provider's git, the BFF and the model endpoints" | **C** | Add the platform's git server |
| `backend-architecture.md` schema | `demand_stages(…, artifact_ref)` | **D** | The column does not exist in migration 0006. Either it never did or it was dropped; with 0028 it becomes a PATH in the root repository. Fix the spec to match the code, then the code to match 0028 |
| `backend-architecture.md` schema | `knowledge_artifacts(project_id, kind, version, object_ref, meta)` | **C** | The row becomes an INDEX over the repository — `path`, `commit`, the embedding — not the storage of the body |
| `backend-architecture.md` components | no git server | **G** | Add it to the component list and the k3s services |
| `GLOSSARY.md` | has "Context package"; no "root repository", no "shelf/library", "artifact" undefined | **G** | Add the three; define artifact as "a file in `demand/<id>/` of the root repository" |
| `user-stories.md` US-7.4 | "consult the accumulated knowledge … in the configuration (ADR-0009)" | **A** | "in the project's root repository (ADR-0028)" — it is a repo the cockpit shows, not a configuration screen |
| `user-stories.md` US-8.5.x | diagrams/opinions "kept as artifacts of the demand" | **A** | Text in `demand/<id>/`, the rendered bytes in the ObjectStore with a reference |
| ClickUp US-7.4 | "the domain `knowledge` exists in the core. The configuration screen is missing" | **A** | Reframe when the card is next touched: what is missing is the repository's view in the cockpit |

## 3. Code — dop-core

| Where | What it says / does today | Verdict | Change |
|---|---|---|---|
| `ports.go` ExecRequest header | "**the port has no field through which a credential could arrive**. It is not a promise of discipline, it is the absence of a field" | **C** with the substrate spec §5 AND 0028 §3 | Rewrite: the port carries exactly ONE credential shape — the demand's token to the platform's git, as a projected file — and it is the agent's own workbench key, never a third party's. The absence-of-a-field argument stays for `ExecRequest` (no env, no stdin) |
| `ports.go` `SandboxSpec.Documents []SandboxFile` | files pushed into the sandbox | **C** | Replace with `Repository{CloneURL, TokenFile}`; the adapter mounts the token and the image's entrypoint clones |
| `ports.go` guarantees 18–21 | 19 read-only, 20 rebuilt from the spec on resume | **C** | 18 stays (readable at `/project`); 19 → **writable, and a push is visible to the next sandbox of the project**; 20 → **persists across resume and across demands**; 21 stays; **new 22**: a sandbox of project X cannot open Y's repository; **new 23**: the mirror's credential is never in a sandbox |
| `adapter/sandbox/k8s.go` | `ensureLibrary`, `ensureLibraryClaim`, `runLibraryLoader`, `waitLoaderRunning`, `pushArchive`, `execFailure`, the v5 stdin protocol, the `library` PVC + read-only mount | **C** — the transport | Remove all of it. What replaces it: mount the token file; no PVC for documents (the clone lives in the workspace PVC or beside it) |
| `adapter/sandbox/docker.go` | `putDocuments`; Resume **recreates the container** (existed only for guarantee 20) | **C** | Remove `putDocuments`; revert Resume to reusing the container |
| `adapter/sandbox/documents.go` | `validateDocuments`, `documentsTar` | **C** | Remove (path validation moves to the repository layout, server-side) |
| `adapter/sandbox/websocket.go` `WriteMessage` | added for the loader | **C** | Remove — exec has no stdin, and now nothing else needs it |
| `test/contract/sandbox.go` subtests 18–21 | prove the transport | **C** | Rewrite to prove the clone, the push visibility, the persistence, the project isolation |
| `knowledge/library.go` | tree + manifest + `FileName` | **keep** | It IS the repository's layout and `README.md` generator. `Library()` stops returning `SandboxFile`s and returns files to COMMIT |
| `knowledge/service.go` `LibraryFor` | assembles `[]SandboxFile` for the spec | **C** | Becomes the README regeneration on push (`ProjectRepository.Commit`), fired by the push event |
| `knowledge/service.go` `PutArtifact` (`s.objects.Put`) | body to the ObjectStore | **C** | Text → `ProjectRepository.Commit`; bytes → ObjectStore, unchanged; the row keeps `path` + `commit` |
| `execution/service.go` `Library` port, `WithLibrary`, `documentsFor` | fills `spec.Documents` | **C** | Replace with `ProjectRepository.Ensure` + `IssueToken` in `specFor` |
| `agent/prompt.go` | never mentions `/project` | **G** (W2) | One paragraph in the brief: the shelf exists, read `README.md` first, commit what you learn into `memory/` |
| `agent/tools.go` | single tool `run_command` | **keep** | Correct; it is the docs that name tools that do not exist |
| `workflow/entity.go` artifact validation | "declares an unknown artifact", "puts no artifact on the table" | **A** | Keep; the artefact now has an address, so "on the table" means "at `demand/<id>/<kind>.md`" |
| `demand/entity.go` `ArtifactKind` | six kinds, no storage | **G** | The kind becomes the file name; `demand_stages` gains the path (the `artifact_ref` the spec already claims) |
| migrations | `knowledge_kind` enum; no `project_repositories` | **G** | New: `project_repositories(project_id, clone_url, mirror_url, mirror_credential_ref)`; `knowledge_artifacts` gains `path`, `commit`, drops `object_ref` for text |
| `app/register.go` | `executionSvc.WithLibrary(knowledgeSvc)` | **C** | Goes with the rest |

## 4. Code — dop-infra

| Where | Today | Verdict | Change |
|---|---|---|---|
| `images/devbox/Dockerfile` | no `git`, TODO recorded | **G** (P-38) | `git` + an entrypoint that clones the root repository from the token file before the long-running process |
| k3s services | no git server | **G** | A git server (bare repositories on a PVC behind smart-HTTP), its NetworkPolicy, the sandbox egress rule |
| NetworkPolicy of the sandbox namespace | not present in this repo's sandbox setup | **G** | The egress allowlist the substrate spec §6.1 promises, with the git server in it |

## 5. Order of the work

1. **Docs first, one commit:** the ADR amendments (0009, 0024, 0003, 0014, 0007, 0028 §2/§3), the two specs, the glossary, the stories. After this commit no document contradicts another.
2. **Code removal WITH its replacement, one change:** the port (`Repository`, guarantees 18–23), both adapters, the contract suite, `execution`, `knowledge`. Removing the loader before the clone exists would leave the guarantees pointing at nothing — the suite has to flip in one move.
3. **The git server in dop-infra**, the devbox entrypoint, the token issuance — the build proper.
4. **P-41**, the lessons loop: the agent commits into `memory/`; the push event regenerates `README.md`.

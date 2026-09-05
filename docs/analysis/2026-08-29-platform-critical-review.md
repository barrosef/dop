# A critical review — the DOP platform × the state of the art (August 2026)

> **Date:** 2026-08-29
> **Method:** a rereading of every requirement and decision (ADRs 0001–0005, the SP-0 specs,
> the dop-infra spec, the executor's design, PRD 1.0, 20 adjustment prompts, the
> dop-app analysis), compared with the state of the art of autonomous development with agents.
> `dop-cmd` was used **only as a source of knowledge** — it is a separate utility and is not
> part of the platform.
> **Purpose:** to find as many weak points as possible and point at solutions, before SP-4.

## 1. The project's intent, as I understand it

A multi-tenant digital platform where **the dev is a manager of agents, not an executor**:
demands arrive from the task manager, agents develop them end to end in isolated sandboxes (a
microVM with an internal Docker), with a full-stack test environment per demand, specs as a
durable artifact, a PR as the delivery, and the human deciding, approving and giving context. A
gRPC core + a multi-protocol BFF, hexagonal infrastructure portable GCP ↔ k3s/OKD, a front end
with the soul of an IDE.

**The real differentiator, confirmed by research:** no agent on the market (Codex, Jules,
Devin, Copilot agent) brings up the demand's *application stack* — they all deliver a code
sandbox. The full-stack environment per demand + the multi-account management layer is what DOP
has that the others do not.

## 2. Weak points and solutions

Ordered by severity. ⬛ critical · 🟧 high · 🟨 medium.

### A. The product's core

**⬛ F-1. The executor is running ahead of the work model.**
SP-4 — what the platform *does* — is still undefined, while the sandbox, the infrastructure and
identity already have a design. It is a product dependency inversion: the executor may be born
in the wrong shape (e.g. a suspend/resume cycle sized for gates that may not even exist).
*The solution:* lock SP-4 as the mandatory next step before any executor plan; validate the
executor against the demand's real life cycle.

**⬛ F-2. There is no management of the project's context/knowledge.**
What separates a good agent from a useless one in 2026 is context: the code's index, the
conventions, the customer's ADRs, the memory of previous demands, the workspace's rules. In the
requirements that shows up as "context created by Claude" (stage 2) and "the workspace's rules"
— but there is no entity, no port, no retrieval design.
*The solution:* raise the **knowledge base per project** to a first-class subsystem in SP-4: a
versioned entity (rules, conventions, the repo's map, demand memories), a `KnowledgeStore`
port, and a "context package" assembled per demand before the agent starts.

**⬛ F-3. The verification loop is not designed — and without it autonomy becomes a review queue.**
The 2026 research is explicit: agents already close the loop up to the PR; the bottleneck has
become human review capacity. If DOP does not give the agent machine-verifiable acceptance
criteria (derived from the spec) + iteration to green + an automatic critic before review,
every parallelism gain dies on the reviewer's desk.
*The solution:* in SP-4, acceptance is born **in the spec** in executable form; the agent
iterates against it in the sandbox; a critic agent reviews before the human; the evidence
(tests, diffs, runs) arrives attached to the PR. The human reviews the exception, not the rule.

**⬛ F-4. Parallelism in the same repo with no merge orchestration.**
The requirement says: SUOPTS-1501/1502/1503 at the same time, "regardless of the repos
overlapping". Three agents, three PRs, overlapping files — the merge order decides what
survives, and CI does not catch a behavioural regression between parallel PRs. The consolidated
practice is a **serialized merge queue with verification between merges**. None of that is
designed. (`dop-cmd` has mineable knowledge here: `integrate-desenv`,
`prepare/finish-merge-conflicts`, `solve-conflict` — real conflict flows tested in production.)
*The solution:* a merge queue per repository as a domain concept; an automatic rebase of the
queue; conflict resolution as an *agent's task* with escalation to a human; the orchestrator
sees file overlap between active demands and flags the risk before the PR.

**🟧 F-5. Human attention is the sizing bottleneck — and it is marked as "proposed".**
With 6–8 parallel demands, the scarce resource is the dev's attention (the PRD itself said so).
The cross-workspace "where am I needed" view (R2.9) is still marked as a *proposal*. Worse: the
same human approves the spec and reviews the PR — a rubber-stamping risk.
*The solution:* the **attention box** as a central UX primitive (not an optional screen): a
single prioritized queue of "decisions only a human can take", with batching and context. Gates
with a risk level: a low-risk change with a green critic may have a reduced review.

### B. Economics and operation

**⬛ F-6. LLM cost with no measurement, budget or routing.**
N autonomous agents × long sessions × multi-tenant = the product's largest variable cost line,
and there is not a line about it in any document. With no metering per account, the business
model is undefinable; with no per-demand budget, a pathological demand burns money in a loop.
*The solution:* measuring tokens/cost per demand and per account from day one (an event in the
dossier); a budget with a soft cut (it pauses and asks) per demand; a `ModelRouter` port to
route mechanical stages to cheap models.

**🟧 F-7. No telemetry of the agent's quality.**
There is no planned metric of: human interventions per demand, rework, rejected PRs, time to
green. Without it there is no way to know whether autonomy improves or worsens — and the
conversation has already produced the right seed ("every interruption is a sign of an
incomplete spec").
*The solution:* demand metrics as part of the dossier; a quality panel per project; using
interruptions as a spec quality metric, closing the spec-driven cycle.

**🟧 F-8. Auditing treated as an open item (P-1) when here it is the product.**
A platform that runs autonomous agents with a customer's credentials needs a complete and
reproducible trace of every action — for trust, debugging and compliance. The SOTA already
delivers session replay.
*The solution:* the demand's timeline as an **append-only event log** (it aligns with the
incremental dossier already asked for in prompt 17); every agent action becomes an event with
the actor, the credential used and the result. That also resolves P-1 for free.

**🟨 F-9. Demand scheduling is undefined.**
The executor is CPU-bound (measured in the reference document); the orchestrator "decides",
but does not exist. Who queues, who prioritizes, what happens when the 9th demand arrives?
*The solution:* an admission queue per account/project with limits; an explicit priority;
preemptive suspension of idle demands (already designed) as the valve.

### C. Security

**⬛ F-10. Prompt injection is not handled — and DOP has the complete lethal triad.**
The agent reads untrusted content (a Jira card, a repo's README, third-party code), it has
credentials (an installation token) and it has an exit to the outside (a git push, a PR). The
2026 research (OWASP, Microsoft) shows injection as the number 1 cause of agentic security
failure in production; a malicious card can instruct the agent to exfiltrate code.
*A layered solution:* (1) an **egress allowlist per sandbox** — only the provider's git, the
BFF and the model endpoints; (2) card and repo content marked as untrusted in the agent's
context; (3) the already existing minimal credential (a 1h installation token — keep it); (4)
secret redaction in every output (`dop-cmd`'s knowledge, its ADR-0006, to be mined and
reimplemented); (5) runtime detection of anomalous commands + F-8's trail.

**🟧 F-11. A degradable isolation has to be an account policy, not a silent fallback.**
The declared `isolationTier` has already been designed — what is missing is the other side: the
account requiring a minimum tier ("never run my demand below kernel-emulated") and the platform
refusing instead of degrading.
*The solution:* `minIsolationTier` as an account policy; a violation = a refusal with a message,
not a downgrade.

### D. Technical consistency

**🟧 F-12. The contract is already tripled before it exists.**
A hand-written `types.ts` in the frontend (rich, evolved), an empty `openapi.yaml` with codegen
running over nothing, and a future `.proto` for the core. Three sources, none authoritative —
the drift has already started on the `dev` branch.
*The solution:* SP-2 decides on **one** source (probably: the core's proto as the truth; the
BFF's OpenAPI and the front's types generated). Until then, freeze the invention of new
contract in the frontend.

**🟧 F-13. Repository governance is broken in dop-app.**
The submodule points at a scaffold; all the work lives on a `dev` branch with no common
ancestor with `main`; 3,523 orphan lines awaiting a decision.
*The solution:* promote `dev` (or re-anchor main), pin the pointer, and decide the orphan code's
fate **in SP-4** — neither restoring it out of inertia, nor deleting it before the stage model's
decision.

**🟧 F-14. The agent engine is not behind a port.**
ADR-0001 was applied to the infrastructure, but the agent itself (the Claude Agent SDK) is being
assumed directly. It is exactly the kind of dependency the rule says to isolate — models and
SDKs are changing leader every six months.
*The solution:* an `AgentRuntime` port (start a session, continue, cancel, an event stream,
cost); the Claude Agent SDK as the first adapter.

**🟨 F-15. The mock-first frontend encoded semantics the domain never ratified.**
`Stage.execData`, `parallelGroup`, shapes of progress — invented for the screen, they may not
match SP-4. The exception is the commit attribution rule, which is genuine domain.
*The solution:* treat `types.ts` as an *inventory of requirements* for SP-4/SP-3, not as a
contract; explicitly ratify what stays.

**🟨 F-16. Persistence with contradictory signals.**
"Mongo, for example" coexists with an event-oriented incremental dossier (F-8) and versioned
specs — workloads of different natures (a document, an append-only log, a blob).
*The solution:* SP-3 decides with the event log as a first-class citizen; the document store
serves projections, it does not replace the log.

## 3. What is strong (not to be touched)

- The full-stack environment per demand — a real differentiator, keep it at the centre.
- ADR-0001 (ports) with two families and the two-adapter discipline — above the market's
  standard; it only remains to apply it to the agent (F-14).
- The account as the unit of ownership (ADR-0002) — the GitHub/GCP model, it dissolves the
  requirement conflicts by construction.
- An organization credential + human authorship (ADR-0003) — exactly the practice of serious CI
  bots.
- Verification by domain (ADR-0002) — validated against what GitHub/GCP actually do.
- Spec-driven as the method — aligned with the market's direction (Kiro, Spec Kit), and DOP was
  already converging on it before naming it.
- The commit attribution rule (dop-app) — genuine domain discovered through the UI.

## 4. The recommended order of attack

1. **SP-4** resolves F-1, F-3, F-15 and decides the orphan's fate (F-13) — it is the unblocker.
2. **The sandbox's security** (F-10, F-11) goes into the execution spec before the plan.
3. **The merge queue and conflicts** (F-4) — designed together with SP-4, mining dop-cmd.
4. **Cost and telemetry** (F-6, F-7, F-8) — they go into SP-3 as dossier events.
5. **The contract** (F-12) — SP-2 right after SP-4; freeze invention in the front until then.
6. **The missing ports** (F-14) — the AgentRuntime in the execution spec.

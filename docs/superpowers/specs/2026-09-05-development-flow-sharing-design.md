# Sharing a development flow between accounts

> **Status:** Approved for review · **Date:** 2026-09-05 · **Project:** the DOP platform
>
> **Answers:** how a development flow is built through conversation, drawn, shared between
> accounts, adopted, pinned, and revoked.
>
> **Does not answer:** the flow's own structure — `Flow`, typed stages, the inheritance chain
> and versioning are [ADR-0014](../../adr/0014-dynamic-workflow.md) and are already built. Nor
> the account TREE, which this design depends on for one question and which is decided
> elsewhere (P-44).

The base decisions: [ADR-0014](../../adr/0014-dynamic-workflow.md) (the flow itself),
[ADR-0013](../../adr/0013-resource-as-unit-of-sharing.md) (a flow is a content resource),
[ADR-0002](../../adr/0002-account-as-unit-of-ownership.md) (the account owns; handles are one
namespace), [ADR-0006](../../adr/0006-demand-as-event-log.md) (every act is an event).

**It partially reopens P-9**, which ADR-0014 §7 deferred as strategic: sharing to a NAMED
account is in; the public community catalogue stays out (§6).

## 1. What does NOT change

The whole of `Flow` — `{ id, name, version, stages: [{key, name, type, artifacts, gate,
substages}] }` — the stage type vocabulary, the chain `platform ◁ account ◁ workspace ◁ project
◁ demand`, `Resolve`, `Promote`, versioning, and the access default that treats a flow as
content (open within the account) rather than as a credential.

Stating it first because it is the design's main finding: **the seven requirements asked for
nothing inside the flow.** They asked for things around it.

## 2. Publication, grant, derivation

Three concepts, and the vocabulary is borrowed rather than invented: `GRANT`/`REVOKE` from SQL,
and `wasDerivedFrom` from W3C PROV-O.

### 2.1 Publication — a version becomes addressable

```
FlowPublication { id, flow_id, version, slug, account_id,
                  notes, published_at, published_by }
```

The reference is `@acme/backend-go` — resolving to the latest published version — or
`@acme/backend-go@v3`, which pins one. It is the requirement's *"easily identified"*, and it
costs nothing: `accounts.handle` is already `UNIQUE`, and ADR-0002 already puts personal
accounts and organizations in ONE handle namespace. A person publishes exactly like a company.

A publication freezes a VERSION. Publishing again publishes a newer one; it never mutates what
somebody already adopted.

### 2.2 Grant — who may derive

```
FlowShare { publication_id, to_account_id, revocation_policy,
            granted_by, granted_at, revoked_at }
```

### 2.3 Derivation — adoption is a COPY, with provenance

Adopting creates a NEW `Flow` in the adopting account, at whatever scope it chooses — account,
workspace, project or demand. The copy carries where it came from:

```
Flow.origin { reference: "@acme/backend-go", version: 3, adopted_at }
```

**A live reference was rejected.** It would let one company's edit change how another company's
development runs, and revoking it would break demands already moving. A copy is the adopter's,
and that is the property everything else here depends on.

### 2.4 The same fact is recorded on BOTH sides, deliberately

Provenance lives on the copy, inside the adopting account. For the publisher to answer *"where
did my flow go?"* from that alone, it would have to scan every account for copies pointing at
it — the cross-tenant scan the isolation rule exists to forbid.

So the publisher keeps its own index, written at derivation time:

```
FlowAdoption { publication_id, version, by_account_id, flow_id,
               derived_at, revoked_at }
```

Two rows for one `wasDerivedFrom`, so that neither side has to cross the boundary. It is
duplication on purpose, and it is what makes §3 implementable.

### 2.5 Inheritance across an ownership boundary is PINNED

Adoption is a copy (§2.3). Inheritance down the chain is a reference. Between the two there is
a third case, and it is the platform's default flow: inherited — no copy — but **pinned to a
version**.

The rule that decides which levels need a pin is about OWNERSHIP, not about depth:

- **inside one account** (account → workspace → project → demand), inheritance stays LIVE. The
  person who changes the flow is the same owner who lives with the change; that is governance
  working, and a pin there would only add ceremony;
- **across an ownership boundary** (a platform account's flow inherited by another account), it
  is **pinned**. Whoever changes it is not whoever suffers it, and an automatic change to how
  somebody else's development runs is the same objection that killed the live reference in §2.3.

```
AccountFlowPin { account_id, flow_id, version, pinned_at, pinned_by }
```

An account is born pinned to the version current at its creation. When the platform publishes a
newer one, the cockpit says so — *"`@dop` published v4; you are on v3"* — and moving is an
explicit act by owner or admin. Nothing about it is automatic.

The vocabulary is dependency management's on purpose: this IS a dependency — an artefact owned
by somebody else, pinned, upgraded deliberately. The same relationship `.dop/verification.yml`
has with `postgres:16`.

**What this buys over both alternatives.** A live reference would let the platform fix a defect
and have it reach everyone with nobody deciding. A copy per account would mean the fix reaches
nobody, ever, and a thousand accounts keep the defect with no way to repair it without touching
data that is not ours. A pin makes the fix **offered** to everyone: it exists, it is visible,
and it is taken deliberately.

ADR-0014 §4 still freezes the flow's VERSION when a demand starts. The pin sits one level above
it: it decides which version new demands freeze onto.

## 3. Revocation

### 3.1 When a revocation REACHES a copy, it is a state change — never a deletion

Under `prospective` no copy is touched at all: what is revoked is the grant, so nobody new can
derive, and every existing derivation goes on working untouched. The rest of this section
describes `drain` and `terminate`, which are the two that reach a copy.

The copy moves to `revoked`, and three things stay true:

- **it remains visible** in the adopting account, marked *revoked by the origin on `<date>`*.
  Vanishing silently turns "my process stopped working" into a question with no answer;
- **the adopter's own edits and history stay.** They built on top; deleting destroys work that
  is theirs;
- **a demand that already ran stays auditable.** ADR-0014 §4 freezes the flow's version when a
  demand starts, and the dossier has to be able to read the definition that run happened under.
  It is ADR-0007's argument again: evidence pointing at something deleted is evidence nobody can
  check.

### 3.2 The policy has three values, and it is STAMPED on the grant

| Value | What it does | Where the name comes from |
|---|---|---|
| **`prospective`** *(default)* | Existing derivations keep working; only new ones are blocked | Legal/API-deprecation usage: applies going forward. It is `cargo yank` |
| **`drain`** | Derivations are revoked, but demands already running finish under their frozen version | Load balancers and `kubectl drain`: stop taking new work, let current work end |
| **`terminate`** | Derivations are revoked at once; running demands stop at the current gate and raise an attention item | k8s/systemd: end now |

`accounts.default_revocation_policy` holds the account's default, editable by **owner or admin**
— the same `CanManageMembers()` pair that already gates every account-level change, rather than
a new permission. A personal account has exactly one member, `owner` (ADR-0002), so the rule
answers it with no special case.

**The value is copied onto the `FlowShare` when the grant is made.** Reading it at revocation
time would let the publisher change the terms after somebody accepted them — you adopt under
`prospective` and get terminated under `terminate`, with a demand stopping mid-flight. Changing
the account default therefore affects future grants only.

### 3.3 Granularity, events, and the one limit

Revoking a `FlowShare` reaches the derivations made under it — one account at a time.
Withdrawing a publication reaches all of them. **Both sides emit an event** (ADR-0006): the
origin revoked, the target was revoked. Neither finds out by accident.

**The limit, named now rather than discovered later:** if B derives from A, republishes as
`@b/other-name`, and C derives from B, then A revoking from B does **not** reach C. Cascading a
revocation down an unbounded chain of accounts is a distributed-transaction problem this version
does not take on. Provenance chains and stays auditable; revocation reaches one level. The
alternative — forbidding republication of a derived flow — is available and was not chosen.

## 4. The agent builds it; the human commits it

### 4.1 The agent proposes and cannot persist

```
agent  → flow.propose(draft)  → Report (valid?) + Diff (against what is in force)
                                 nothing persisted
human  → confirms             → Create/Update in the core, with its event
```

If the agent could write, the diff would be a report of what already happened instead of a
gate. `Validate` already exists in `workflow.Service` and returns a `Report`; the tool wraps
what is built rather than reimplementing it.

**Why a whole new version rather than named operations.** The agent reads the current flow and
produces the complete next one. A closed vocabulary of operations (`move_stage`, `add_stage`)
would be safer against silent drift, and was rejected: ADR-0014 exists so that a new composition
does NOT require the platform to evolve, and a closed operation set fights exactly that. The
diff is what covers the risk the rewrite creates — a model that rewrites a structure can quietly
drop a stage nobody asked it to touch, and without a diff that surfaces on the day a demand runs
wrong.

**The first flow has no "current" to compare against.** Diff it against the flow INHERITED from
the chain (`flow.effective`), not against nothing: what matters is what you are changing
relative to what already applied there.

### 4.2 What the agent reads

- `flow.vocabulary()` — stage types, artifact kinds, gates, self-describing. It is what stops
  the agent inventing a type that ADR-0014 §1 defines as a contract error, not user data;
- `flow.effective(scope, id)` — the flow in force there, and where in the chain it came from;
- `project.summary()` — repositories, connected integrations, flows that already exist;
- `demand.history()` — how earlier demands ran: where they stalled, which gates waited.

The last two are what separate a generic proposal from one made for THIS project.

### 4.3 Confirmation is human; its surface is not fixed

Chat is the only surface for EDITING (requirement 3). Confirming is not editing, so a button
beside the diff and a "go ahead" in the chat are equally valid. The invariant is that a human
confirmation step exists.

## 5. One drawing, three states

The cockpit draws the flow from the `Flow` structure itself, in React — no diagram library.

- **definition** — the stage's type decides its icon and colour (ADR-0014 §1 already says the
  type decides the renderer); a human gate is a visible badge; substages nest;
- **progress** — the same chain with state on top, from the event log's projection (ADR-0006):
  what passed, where it is, which gate is waiting. This is requirement 7;
- **diff** — the same chain marking what enters, leaves and changes, before confirmation.

**It is a chain, not a graph.** ADR-0014 §2 fixes v1 with no conditionals, no stage parallelism
and no rules DSL, so there is nothing to branch and **no layout algorithm is needed** — which is
why a renderer of our own is cheap and a BPMN library would be dead weight. The word "BPM" in
the requirement should be read as *a picture of the process*, not as BPMN 2.0 conformance: the
standard's semantics (gateways, pools, lanes, boundary events) are far richer than what v1
stores, and claiming the standard without them would be a lie in the file format.

## 6. Out of this version, on purpose

| Out | Why |
|---|---|
| The public community catalogue | Discovery, curation, trust and abuse are a different product. The mechanism is shaped to receive it later; P-9 stays open for that half |
| Conditionals and branching | ADR-0014 §2. If a real process needs "if A then B", that is a deliberate extension of the flow structure, not an adjustment here |
| Three-way merge on an update | We show that a newer version exists and the agent helps produce the next one; the diff decides |
| Cascading revocation past one level | §3.3 |
| A parent account administering its children | The breadcrumb records the relationship; the rule is P-44's |
| A visual flow editor | Requirement 3: chat is the only editing surface |

## 7. What changes in the code

| Where | What |
|---|---|
| `migrations/` | `flow_publications`, `flow_shares`, `flow_adoptions`, `account_flow_pins`; `flows.origin_*`; `accounts.default_revocation_policy` |
| `internal/domain/workflow/` | `Publish`, `Grant`, `Revoke`, `Withdraw`, `Derive`, `Pin`/`BumpPin`; provenance on the entity; the revocation policy as a domain type with its three values |
| `internal/domain/workflow/` | `Resolve` learns the pin: crossing an ownership boundary returns the PINNED version, never the newest |
| `internal/domain/workflow/` | reference resolution `@handle/slug[@vN]` — parsing and lookup, refusing a reference the caller was not granted |
| `internal/domain/identity/` | `default_revocation_policy` on the account, gated by `CanManageMembers()` |
| `internal/domain/agent/tools.go` | the four read tools and `flow.propose`, which validates and diffs without persisting |
| `api/proto/dop/v1/workflow.proto` | the publication, grant and derivation RPCs; the diff as a message |
| `dop-app` | the renderer with its three states, and the confirmation surface |

## 8. Risks

| # | |
|---|---|
| R-1 | The agent rewrites the whole flow on every edit, so it can silently drop a stage. The diff is the only thing between that and a demand running wrong — it has to be genuinely readable, not a JSON dump |
| R-2 | `terminate` stops another company's running demand. It is the correct behaviour when chosen, and it is the most destructive act in this design: it needs a confirmation that names how many demands will stop |
| R-3 | Provenance is duplicated on both sides (§2.4). Two rows can drift — a derivation recorded on one side and not the other — and the reconciliation is nobody's job yet |
| R-4 | A flow adopted and then edited diverges from its origin, and "there is a v4" becomes noise the adopter cannot act on without redoing their edits |
| R-5 | A pin nobody ever bumps is the npm problem: every account stuck on v1 forever, and the platform unable to fix anything in practice. The notice has to be visible where flows are read, not buried in a settings screen |
| R-6 | The chain-not-a-graph limit will meet the first customer whose real process branches. The answer is an extension of ADR-0014, and until then the honest response is that the platform does not model it |

## 9. What this design waits on

**P-44 — the account tree.** `Account` gains a kind for a platform account, a `parent_id`, and
a materialized path (`ltree`) so ancestry is read with an index instead of recursion. This
design needs exactly ONE thing from it: with several platform-level accounts, *which* level 0
applies to an account is answered as **the nearest ancestor whose kind is `platform`** — one
indexed query, no recursion. Everything else here is independent of the tree, and the isolation
invariant does not move: every query still filters `account_id`.

**The platform's default flow stays INHERITED — and pinned (§2.5).** Nobody chose it; it came
with the account. Copying it into every account at signup would mean a defect found in it
reaches nobody, ever. Leaving it live would mean a change reaches everybody with nobody
deciding. Pinned, the fix is offered and taken deliberately. A flow somebody CHOSE to adopt
earns a copy; a default earns a pin.

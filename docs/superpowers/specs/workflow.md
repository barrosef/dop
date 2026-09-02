# The dynamic workflow

> **Status:** Approved for review · **Date:** 2026-08-30 · **Project:** the DOP platform
>
> **Answers:** the `workflow` resource's format, the inheritance chain, the cycle on the
> demand and how the agent and the screen consume it. It is SP-4's core.
> **Does not answer:** the syntax of the executable criteria inside the `spec` artifact (P-8);
> external sharing (P-9).

The base decisions: [ADR-0014](../../adr/0014-dynamic-workflow.md),
[ADR-0013](../../adr/0013-resource-as-unit-of-sharing.md),
[ADR-0006](../../adr/0006-demand-as-event-log.md),
[ADR-0007](../../adr/0007-no-green-no-pr.md).

## 1. The structure

```
Flow {
  name, description, version,
  stages: [ {
    key,                 // unique within the flow
    name,                // free, the author's
    type,                // the platform's vocabulary — it decides renderer and behaviour
    artifacts: [...],    // what the stage produces: document | spec | plan | test_plan | diagram | report
    gate: human | none,
    substages?: [...]    // e.g. test → [aaa, e2e, integration]
  } ]
}
```

**The v1 types:** `context`, `spec`, `plan`, `implementation`, `test` (subtypes `aaa`, `e2e`,
`integration`), `human_validation`, `finalization`, `generic`. A new type is an evolution of
the platform (it requires a decision); a new composition is the user's freedom.

**Absent in v1, on purpose:** conditionals, stage parallelism, a rules DSL. They evolve over
the same structure.

## 2. Contracts per type

The type is a three-ended contract — the **screen** (the renderer), the **agent** (what to
produce and where to stop) and the **platform** (which events to emit):

| Type | The agent produces | The screen renders | Note |
|---|---|---|---|
| `context` | a survey of the terrain (repos, points of impact) | an MD document | it absorbs the old "init": it reads the provider's card |
| `spec` | the spec with executable criteria | a document + an approval gate | ADR-0007; the criteria's syntax = P-8 |
| `plan` | an implementation plan and a test plan | a document + tabs | |
| `implementation` | code in the attached git flow's branches | progress per repo/task | |
| `test` | running the suites per subtype | aaa/e2e/integration tabs, results | green is required before the PR (ADR-0007) |
| `human_validation` | a validation plan with links | a **checklist tickable item by item**, expandable | the dev validates outside and ticks; they can talk to the agent midway |
| `finalization` | PRs, entering the merge queue, closing | steps with idle/running/done/warn/error states | ADR-0008; a consolidated dossier |
| `generic` | whatever the stage's description asks for | a document | an escape valve |

## 3. The resolution chain

`platform ◁ account ◁ workspace ◁ project ◁ demand` — the nearest wins; it is inherited by
omission, overridden by declaration. The interface always shows the effective flow's origin
("inherited from the project ◂ the workspace ◂ the account"). The dev may choose a flow for a
single demand; **promotion** takes a flow to levels above (by whoever has `manage`).

**Access (ADR-0014 §6):** in an organization, flows are open within the account by default,
restrictable by a grant. The v1 scopes: private → account. External = P-9.

## 4. The cycle on the demand

1. The demand starts → it resolves the effective flow → it **freezes the version**.
2. Every stage transition, artifact produced and gate decided is an **event** (ADR-0006); the
   ruler at the centre of the Chat is a projection.
3. A pending `human` gate becomes an item in the **attention box**.
4. Stages generate the artifacts in the knowledge storage (ADR-0009); the subagents' findings
   attach to the current stage.

## 5. The platform's default

A global resource from the catalogue (adoptable as a versioned copy — ADR-0013 §3):

```
context → spec (a human gate) → plan → implementation
        → test [aaa, e2e, integration] → human_validation (a human gate) → finalization
```

## 6. Risks

| # | |
|---|---|
| R-1 | A flow with no `spec` stage breaks the spec-driven method — the structural validation warns (it does not block: accounts rule their own process, the platform makes the cost explicit) |
| R-2 | A long demand with a frozen flow diverging from the account's new flow — the visible origin and the explicit freeze are the answer; migrating a demand in flight stays out of v1 |
| R-3 | The type vocabulary growing without control — a new type requires a platform decision (ADR-0014 §1) |

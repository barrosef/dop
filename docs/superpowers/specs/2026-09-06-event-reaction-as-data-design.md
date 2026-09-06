# Reacting to an event is data, not code

> **Status:** Approved for review · **Date:** 2026-09-06 · **Project:** the DOP platform
>
> **Answers:** what decides that an event should cause something, where that decision is
> stored, what the something can be, and what happens when it fails.
>
> **Does not answer:** which reactions the product actually wants — that is epic 10's content.
> Nor the cockpit screen for editing rules: the model allows one, the screen comes later.

The base decisions: [ADR-0006](../../adr/0006-demand-as-event-log.md) (the event log is the
truth), [ADR-0019 — now part of ADR-0018](../../adr/0018-postgres-persistence.md) (the outbox,
at-least-once delivery, idempotent consumers, the DLQ),
[ADR-0025](../../adr/0025-communication-trigger-and-channel.md) (the trigger and the channel are
separate), [ADR-0014](../../adr/0014-dynamic-workflow.md) (the flow, whose `StageSpec` this
extends).

This is **P-29**, and four things wait on it: epic 10, P-26's automatic provisioning trigger,
P-46 (making `terminate` differ from `drain`), and every reaction the user stories will want.

## The decisions, and who made them

Six, taken by the owner on 2026-09-06. One went against the recommendation on the table and is
recorded as such, because its cost lands later rather than now:

| | Decision | |
|---|---|---|
| 1 | **The demand's flow is the process engine** for what happens inside a demand | owner's |
| 2 | **Two deciders, one executor** — the flow inside a demand, a rules table outside it | owner's, over "onboarding becomes a demand" |
| 3 | **One dispatcher replaces all three consumers at once** | owner's, **over the recommendation** to migrate incrementally |
| 4 | **Rules live in Postgres**, resolved by the flow's own chain | owner's |
| 5 | **A stage's action fires on entry or exit**, declared per action | owner's |
| 6 | **A failed action goes to ONE dead-letter queue, then to ONE errors table** | owner's |

## 1. The dispatcher

Today there are three subscriptions in `RegisterProjections`, each with its own subject filter:
`timeline` on `dop.>`, `attention` on `attention.Subjects()`, `notification` on
`notification.Subjects()`. The attention one carries a comment explaining the bind: subscribing
to `dop.>` and discarding wastes deliveries, subscribing to too few makes the item **never
arrive, in silence** — and a domain test exists to guarantee the subject list covers every
handled event.

One dispatcher replaces the three, and the subject list stops being written by hand: **it is
derived from the rules**. Whoever writes a rule for a new event no longer has to remember a list
in another file, which is the class of mistake that test exists to catch.

```
event → projections   (always, no decision)
      → the rules table, resolved by the chain of the event's account
      → if it is a demand stage event: the actions on the FROZEN flow version
```

### Projection is not reaction

The timeline materialises every event and decides nothing. Putting it behind rules would need a
rule saying "record everything" — a rule that decides nothing, and a table that starts holding
rows which exist only to satisfy the mechanism. Projections run under the same dispatcher, in
the same consumer, and **outside the decision path**.

### What this does to ADR-0025

ADR-0025 said the trigger and the channel are born together, and created the `Notifier` as the
trigger so that no use case would call the `Mailer` directly and become a diffuse trigger. With
this design the **table** is the trigger and the `Notifier` becomes a channel.

That does not contradict ADR-0025 — it is what ADR-0025 anticipated, and `register.go` already
says so in a comment: *"when the reaction becomes data (P-29), you swap the loader, not the
caller."* The rule ADR-0025 actually protects — that nothing calls the `Mailer` directly —
survives intact.

`projection.Attention` and the notifier stop deciding and become executors of one action each.

## 2. The rules table

```
Rule { id, account_id, owner_scope, owner_id,   -- the chain, as in flows
       event_type,                              -- "dop.identity.invite.created"
       when     map[field]value,                -- optional; all must match
       actions  []Action,
       disables []rule_id,
       enabled, created_by, created_at }

Action { name, params map[string]string }
```

### Rules ACCUMULATE; flows do not

In the flow chain the nearest level wins and there is one effective flow. Rules cannot work that
way: an account creating **one** rule would silence the platform's welcome e-mail without
meaning to. So every rule in the chain applies.

Which is why `disables` exists: a lower level switches off an inherited rule **by id**,
explicitly. Turning something off has to be an act, never a side effect of creating something
else.

### `when` is data, and stays data

P-29 requires that no row hold a function, a closure or a `switch`; ADR-0014 §2 already refused a
rules DSL inside flows for the same reason. So `when` is a map of field to value and every entry
must match. That covers *"the stage advanced **and** `to` is implementation"*, which is P-26's
case. It does not cover comparison, ranges or composite booleans — and when somebody needs one,
that is a new decision, not an `if` slipped in.

### Parameters are copied by NAME

`send_email` takes `to_source: payload|account` and `to_field: email`, exactly the shape
`notification/rules.go` already uses for `recipientSource`. That is what keeps the migration a
loader rather than a rewrite.

### Scope

Platform ◁ account ◁ workspace ◁ project. **Not demand** — a demand's reactions come from its
frozen flow (§3). Edited by owner or admin, like every other account-level setting.

## 3. The actions on a stage

```go
type StageSpec struct {
    Key, Name  string
    Type       StageType
    Artifacts  []ArtifactKind
    Gate       GateKind
    Subtypes   []string
    Actions    []StageAction   // new
}

type StageAction struct {
    On     StageMoment   // "enter" | "exit"
    Name   string        // the same closed vocabulary the rules use
    Params map[string]string
}
```

Both moments are derived from the `from`/`to` the `dop.demand.stage.advanced` event already
carries (`demand/service.go:257`) — nothing changes in the emitter.

This is a change to ADR-0014's structure, merged the day before. Two consequences travel with it:
`Validate` refuses an action whose name is outside the vocabulary (ADR-0014 §1 already treats an
unknown type as a contract error rather than user data), and **a demand in flight keeps its
frozen version** — a v3 with no actions goes on having none until somebody moves the pin.

## 4. The executor

An action is code, so the vocabulary is **closed**: a registry of `name → handler` wired in the
composition root, and an unknown name is a contract error. The initial vocabulary is what today's
cases require and nothing more:

| Name | Executed by | Where it comes from |
|---|---|---|
| `open_attention` | `projection.Attention` | what `attention.Apply` does today |
| `close_attention` | idem | the box closes items too |
| `send_email` | the notifier and the `Mailer` port | what the notification consumer does today |
| `provision_bench` | the launcher | P-26's automatic trigger |

### Idempotency, in the agreed shape

```sql
applied_actions ( event_id, rule_ref, action_name, applied_at,
                  PRIMARY KEY (event_id, rule_ref, action_name) )
```

`rule_ref` is the rule's id, or `<flow_id>/<version>/<stage_key>/<enter|exit>` when the decider
was a stage. **The row is written only on success.**

### Actions are independent, and a failure does not stop the others

If a rule carries three actions and the second fails, the third still runs, the delivery is
nacked, and on redelivery the two that succeeded are skipped by the key — only the failed one is
retried. An e-mail that does not go out never stops an attention item from opening.

### Failure has three stages, and one queue

```
happy path        the dispatcher runs the action; JetStream redelivers on nack
   ↓ attempts exhausted
the DLQ           ONE queue for the whole platform. Its consumer re-executes,
                  through the same registry, N more times
   ↓ attempts exhausted
the errors table  ONE table. Terminal. Carries the WHOLE attempt history, and
                  a panel is where a person or an agent decides what to do —
                  which may be no more than telling the user it failed
```

**A DLQ record carries the frozen PLAN, not the raw event.** This is the part that makes
re-execution possible at all: `{event, rule_ref, action_name, params, attempts[]}` — everything
`Decide` produced, as it was produced.

Replaying the event and deciding again would be wrong, and quietly so. Rules are data now, and
data changes: a rule edited between the failure and the retry would make the DLQ consumer
execute something **different from what failed**. Freezing the plan is what keeps a retry a
retry.

The same reasoning gives the DLQ consumer no logic of its own: it calls the same `name → handler`
registry the dispatcher calls, with the parameters already decided. One executor, three callers
— the dispatcher, the DLQ consumer, and whatever the panel triggers.

**One queue and one table, not one per consumer.** A queue per consumer means a retry mechanism
per consumer, each with its own idea of how many attempts are enough, and an operator who has to
know which queue to look in. The record is self-contained precisely so that one queue can serve
every action.

`applied_actions` still gates the whole path: a success anywhere — first attempt, DLQ retry, or a
panel-triggered re-run — writes the row, and every later attempt is skipped.

## 5. Out of this version, on purpose

| Out | Why |
|---|---|
| Conditions beyond equality | It is a DSL, and ADR-0014 §2 already refused one |
| User-supplied action code | An action is code; the vocabulary is the platform's |
| Rules at demand scope | The frozen flow covers it (§3) |
| A cockpit editor for rules | The model allows it; the screen is later work |
| The SRE around the errors table | The panel, the containment actions, who is paged and when — deliberately deferred by the owner. This design owes that work a table with the full attempt history, and delivers it |
| Putting the timeline behind rules | §1 — "record everything" is not a decision |

## 6. What changes in the code

| Where | What |
|---|---|
| `migrations/` | `rules`, `rule_actions` (or actions as JSONB on the rule), `applied_actions`; `flow_versions.stages` gains `actions` inside its existing JSONB |
| `internal/domain/reaction/` (new) | the `Rule`/`Action` entities, `Validate`, the chain resolution, and `Decide(event) []PlannedAction` — the decider, with no infrastructure |
| `internal/domain/workflow/` | `StageAction` on `StageSpec`, and `Validate` refusing an unknown action name |
| `internal/domain/ports/` | `ActionHandler`, and the registry's shape |
| `internal/adapter/postgres/reaction.go` | the rules repository, `applied_actions`, and the errors table with its attempt history |
| `internal/app/register.go` | the DLQ consumer, wired to the same action registry |
| `internal/app/register.go` | one subscription instead of three; the registry wired with the four handlers |
| `internal/domain/attention/rules.go` | `Apply`'s `switch` deleted; its rows become seeded rules |
| `internal/domain/notification/rules.go` | the table becomes the seed of the rules it already describes |

## 7. Risks

| # | |
|---|---|
| R-1 | **Two retry layers can hide a permanent failure for a long time.** JetStream's attempts plus the DLQ consumer's attempts mean a genuinely broken action — a wrong template id, a revoked credential — takes both budgets to reach the errors table where somebody would see it. The budgets should be small enough that a real failure surfaces in minutes, not hours |
| R-2 | **The plan frozen in a DLQ record can outlive the world it was decided in.** A `provision_bench` retried an hour later may target a demand that has since been destroyed, and a `send_email` may name a user who has left the account. The handler, not the queue, has to tolerate that — every action needs to be safe to run late, or to refuse cleanly when its subject is gone |
| R-3 | **Rules accumulate.** A four-level chain can fire more actions than anyone intended, and nobody can see the effective set without a "what fires for this event" view. The flow chain has the same shape and solved it by showing where the effective flow came from — rules will want the same |
| R-4 | The equality-only `when` will meet the case it cannot express, and the pressure will be to add a DSL — the thing ADR-0014 refused for flows |
| R-5 | A flow authored before this change has no actions, and that is **silent**: correct, and indistinguishable from a broken mechanism |
| R-6 | A rule written for an event nobody emits does nothing and says nothing — the opposite of the test that today guarantees subject coverage. The derived subject list should refuse, or at least report, an event type no aggregate emits |
| R-7 | Replacing three consumers at once (decision 3) means the attention box, communication and the timeline all change behaviour in one deployment. Migrating incrementally was the recommendation; the mitigation available is that the seeded rules reproduce today's rows exactly, so the first deployment should be behaviour-identical |

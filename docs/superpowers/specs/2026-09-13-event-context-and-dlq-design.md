# Events that carry their context, and failures that survive — design

**Status:** approved by the owner on 2026-09-13.
**Scope:** `dop-core` only. The BFF has no broker and no database (invariant 2);
nothing here touches it until a panel exists to read the errors table.

Base decisions: [ADR-0018](../../adr/0018-postgres-persistence.md) (the outbox,
at-least-once delivery, idempotent consumers, the DLQ),
[ADR-0006](../../adr/0006-demand-as-event-log.md) (the event log is the truth),
[ADR-0025](../../adr/0025-communication-trigger-and-channel.md) (the trigger and
the channel are separate), and decisions 6 and 7 of
[P-29](2026-09-06-event-reaction-as-data-design.md), taken by the owner on
2026-09-06 and still unbuilt.

## Why now

The owner asked what happens to a failed event: how many attempts, which DLQ.
Measuring the answer produced three findings, and the third is the reason this
document exists.

**There are retries, and they are real.** `MaxDeliver = 5`, with a backoff ladder
of 1s → 5s → 15s → 1min and a 30s ack wait, configured on the JetStream consumer.

**There is no DLQ.** On exhaustion the adapter calls `msg.Term()`, which tells
JetStream to stop redelivering — it **discards**. There is no dead-letter stream,
no advisory consumer on `$JS.EVENT.ADVISORY.CONSUMER.MAX_DELIVERIES`, and no
republish. All three were searched for.

**And the log says otherwise:**

```go
log.Error("event exhausted its attempts, going to the DLQ", ...)
_ = msg.Term()
```

That line names a destination that was never built. It is worse than silence:
whoever reads it goes looking for a queue that does not exist and concludes the
message is safe somewhere.

One mitigation is real and worth stating: the stream keeps `MaxAge: 30 days`, so
the event is still *in* the stream and recoverable by replay. Recoverable by
archaeology, not by operation — nothing routes it, nothing alerts, nobody learns.

## What this design is NOT

**It is not the transversal emission of events.** Today the 40 `Emit` calls live
inside 13 Postgres repository files, in the same transaction as the write. The
owner decided on 2026-09-13 that emission must become infrastructure, transparent
to use cases — *"é transversal, faz parte do core da arquitetura e não do core de
negócio"*. That is a second project with its own spec, deliberately sequenced
**after** this one so that it refactors a target standing still.

**It is not P-29's dispatcher.** See "The frozen plan, and why this version
freezes less" below.

## The decisions

| # | decision | whose |
|---|---|---|
| 1 | **N aggregates affected ⇒ N events**, one per aggregate | delegated, taken 2026-09-13 |
| 2 | **The event carries `aggregate_key`**, a readable snapshot of the aggregate's name | delegated, taken 2026-09-13 |
| 3 | **The envelope carries the call's context** — actor, request, session, caller | delegated, taken 2026-09-13 |
| 4 | **ONE dead-letter queue for the whole platform**, and then ONE terminal errors table | owner's, 2026-09-06 (P-29 §6) |
| 5 | **Failures are classified** recoverable / irrecoverable / unknown, seeded from `errs.Kind`, learned from repetition, demoted by a success | owner's, 2026-09-06 (P-29 §7) |
| 6 | **This version's frozen plan is `{event, consumer}`**, not `{rule_ref, action_name, params}` | delegated, taken 2026-09-13 |

### On decision 1

The owner's model, stated on 2026-09-13: *"o dono do evento é o processo buscado
pelo usuário, assinado por ele como source"*. An event is the name of what the
request meant to do — not a side effect of a write.

That model raised a question the code had already answered differently. Revoking
one person's access emits **one event per grant removed**
(`resource.go:322`): five resources, five `dop.resource.grant_revoked`. The same
shape appears in `RevokeShare`, which also emits for every copy the policy
reaches in other accounts.

One event carrying five resources would have no `aggregate_id` to attach to, and
every consumer would have to open the payload and fan out on its own — the same
logic repeated in each of them. The index that makes an aggregate's history cheap
(`events_aggregate_idx ON events (aggregate, aggregate_id, occurred_at DESC)`)
would stop serving those five resources.

So a process may produce more than one fact. The owner's model survives intact:
the owner is still the process, the signature is still the actor.

### On decision 2

The `type` field is already the readable key for a *process*
(`dop.identity.account.created`), and it is the currency of every conversation
about events — it will be P-29's `event_type` as well.

The gap is the *aggregate*. Talking about `account.created` works; talking about
"`account.created` for the **acme** account" degrades into `9a2c-4f1b-…`. It
costs a lookup in the DLQ panel, in the log, and in a conversation like the one
that produced this document.

**Narrow on purpose.** `aggregate_key` is filled only where a natural, stable
handle exists — an account, a workspace, a project. Where none exists (a grant, a
notification), it stays empty: an honest blank beats a uuid wearing a nickname.

**It is a snapshot, not the truth of now.** Renaming a workspace does not rewrite
the events that already happened; the old event keeps saying the old name, which
is what a log of facts is for. This rule is written here because the opposite
assumption is the natural one, and acting on it would make the event log lie.

## 1. The envelope carries the context

The context is already captured. `postgres.Emit` reads `ctxutil.Call` and writes
`actor_kind`, `actor_id`, `request_id` into the `events` table, inside the same
transaction (`migrations/0001_foundation.sql:175`).

The envelope published to NATS drops it:

```go
env, _ := json.Marshal(map[string]any{
    "id": id, "account_id": ..., "aggregate": ..., "aggregate_id": ...,
    "type": ..., "payload": ..., "occurred_at": ...,
})
```

So a consumer — the exact place where failures happen — runs with no idea who
caused the work it is doing. The information is one join away in Postgres, which
is archaeology at the moment of an error, not a payload.

**Change:** `Envelope` and `ports.Event` gain `ActorKind`, `ActorID`,
`RequestID`, `SessionID`, `Caller` and `AggregateKey`. `Emit` fills them from the
`Call` it already reads. The relay carries them through untouched.

**Why on the event and not only in the DLQ record:** a projection that wants to
show "who did this" has the same need, and so does any log line a consumer
writes. Putting it on the envelope serves every consumer; putting it only in the
DLQ would serve the failure path and leave the success path blind.

## 2. One dead-letter queue

### Where it hooks in

`eventbus.Subscribe` wraps every handler — it is the single place every consumer
of every kind passes through:

```go
if err := h(ctx, e); err != nil {
    md, _ := msg.Metadata()
    if md != nil && md.NumDelivered >= MaxDeliver { ... }
```

That seam already has, at once: the event, the error, the attempt number, the
consumer's durable name and the clock. That is the whole DLQ record. **No domain
service and no repository learns that a DLQ exists** — which is the requirement
the owner stated: *"em nível de infraestrutura e não nos componentes de negócio"*.

### The record

```
DeadLetter {
  event        the full envelope, context included
  consumer     the durable that failed ("timeline", "attention", "notification")
  attempts     [ { at, error_kind, error_code, error_message } ]
  first_failed_at, last_failed_at
  classification   recoverable | irrecoverable | unknown, at the time of routing
}
```

Everything a retry needs travels **in one payload**, which is the owner's
requirement verbatim: *"que o consumidor da dlq identifique e saiba o que
retentar com base no próprio evento e contexto tudo num único payload"*.

### The frozen plan, and why this version freezes less

P-29 §6 describes the DLQ record as carrying `{event, rule_ref, action_name,
params, attempts[]}` — the plan `Decide` produced, frozen. The reasoning is
exact and stands: rules are data, data changes, and a rule edited between the
failure and the retry would make the DLQ consumer execute **something different
from what failed**. Freezing is what keeps a retry a retry.

`rule_ref` and `action_name` do not exist yet: there is no dispatcher, and the
three consumers are wired by hand in `register.go`. So this version freezes what
this version has — `{event, consumer}` — and retrying means re-invoking that
consumer's handler with that event.

**The two fields are additive.** When P-29's dispatcher lands, the record gains
`rule_ref` and `action_name`; the queue, the table and the classification do not
change. The unit of retry is the same in both designs — one event, one handler.
The dispatcher changes *who decides which handler*, not *what is retried*.

Waiting for the dispatcher would have been the tidier sequence and was rejected
for one reason: today an exhausted event **disappears**, under a log line that
says it was saved.

### The subject

`dop.dlq` — inside `dop.>`, so the existing stream retains it for the same 30
days with no new stream and no new retention policy to forget about.

### Both adapters

`eventbus` has two implementations, `nats.go` and `memory.go`, and a contract
suite that runs against both with no infrastructure. The DLQ is part of the
port's contract, so the suite grows the cases: an exhausted handler produces
exactly one dead-letter record; the record carries the context that came in; a
handler that succeeds on attempt three produces none.

## 3. Classification, so the queue is not a mill

Retrying a permanently broken action across two budgets is waste with a delay
attached, and it pushes a real failure hours away from the table where a person
would see it. So a failure is classified **before** it is retried.

**The seed is derived, not hand-kept.** `errs.Kind` already encodes it:

| kind | classification | why |
|---|---|---|
| `unavailable` | recoverable | the world was busy; the same call may work later |
| `internal` | unknown | it may be a bug or a blip; repetition decides |
| `not_found`, `invalid_argument`, `permission_denied`, `unauthenticated`, `failed_precondition`, `conflict`, `already_exists` | irrecoverable | the input is wrong; the same call gives the same answer |

A template id that does not exist arrives as `not_found` and is born
irrecoverable with nobody registering anything.

**The signature is `(consumer, code)`.** `errs.Error` already carries a stable
`Code` separate from the developer-facing message, precisely because the message
is free text that changes. Comparing messages would make the learning brittle;
comparing codes makes it exact. (P-29 says `(action_name, code)`; until the
dispatcher exists, the consumer is what stands in that slot — the same additive
upgrade as the record.)

```
error_signatures ( consumer, code,
                   classification,    -- recoverable | irrecoverable | unknown
                   exhausted_count,   -- times it burned EVERY retry
                   last_success_at,   -- the evidence that contradicts the mark
                   classified_by,     -- seed | learned | human
                   first_seen, last_seen )
```

**It learns.** A signature that has burned every retry more than once and has
never succeeded is promoted to `irrecoverable`, marked `learned`. From then on
the DLQ consumer skips it and spends its budget on what is `recoverable` or still
`unknown`.

**And it takes evidence back.** A success on that signature demotes it to
`recoverable` — but only when the mark was `seed` or `learned`. A mark a human
placed stays until another human moves it: somebody marked it for a reason the
system cannot see, and one accidental success must not throw that judgement away.

**Irrecoverable does not loop.** Those records go straight to the errors table.

## 4. The terminal errors table

```
event_errors ( id, event_id, consumer, account_id,
               event_type, aggregate, aggregate_id, aggregate_key,
               actor_kind, actor_id, request_id,
               attempts jsonb,        -- the WHOLE history, DLQ rounds included
               classification, last_code, last_message,
               state,                 -- open | retrying | resolved | given_up
               created_at, updated_at )
```

Terminal, and read by a person or an agent. The panel that reads it is a later
slice and belongs to the BFF and the cockpit; this spec stops at the table,
because a table nobody reads is still better than an event nobody kept.

**Retention:** written into the migration, as `email_verification_requests`
learned to do. A rows-forever table fed by failures is a table that grows fastest
exactly when things are worst.

## 5. Out of this version, on purpose

- **The panel.** REST route, cockpit screen, manual "retry this" button.
- **Alerting.** The errors table gets an owner before it gets a pager.
- **P-29's dispatcher.** Its own plan; this design is built to be extended by it,
  not to anticipate it.
- **Transversal emission.** Its own spec, next.

## 6. Risks

**The wrapper swallows an error it should not.** The DLQ path runs inside the
consumer's goroutine, and a failure to publish the dead letter cannot itself be
retried forever. Decision: if publishing the dead letter fails, the message is
**nacked**, not terminated — JetStream keeps it and tries again. Losing a
redelivery is cheaper than losing the record of a loss.

**Classification learns something wrong.** Mitigated by the demotion rule and by
`classified_by`: a human mark is never overwritten by the machine.

**The envelope grows and old messages lack the new fields.** Consumers must treat
the context fields as optional. Messages published before the change are still in
the stream for 30 days, and they have no actor — the record shows it as empty
rather than inventing one.

**`aggregate_key` drifts from the current name.** By design. Written into the
field's comment so nobody "fixes" it later.

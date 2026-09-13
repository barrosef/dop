# Event context and the dead-letter queue — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An event that fails every retry stops disappearing: it lands in one dead-letter queue carrying everything needed to retry it, and ends in one terminal table a person can read.

**Architecture:** The context an event already records in Postgres (`actor_kind`, `actor_id`, `request_id`) starts travelling in the envelope. A wrapper inside `eventbus.Subscribe` — the single seam every consumer passes through — publishes a dead-letter record on exhaustion, so no domain service learns a DLQ exists. A pure classifier seeded from `errs.Kind` decides what deserves a retry; a signatures table learns from repetition; a terminal errors table holds what nobody could fix.

**Tech Stack:** Go, pgx, NATS JetStream (`jetstream` package), goose migrations.

**Spec:** [`docs/superpowers/specs/2026-09-13-event-context-and-dlq-design.md`](../specs/2026-09-13-event-context-and-dlq-design.md)

## Global Constraints

- **Everything is in `dop-core`.** The BFF has no broker and no database (invariant 2) and is not touched by this plan.
- **Code, comments and documentation in English.** Commit subjects in Portuguese, describing the *finding*, with a conventional prefix (`feat`, `fix`, `docs`, `chore`) — e.g. `fix(eventbus): o log prometia uma DLQ que nunca foi construída`.
- **Two adapters, one contract.** `internal/adapter/eventbus/` has `nats.go` and `memory.go`. Anything added to the port's behaviour is asserted by `test/contract/eventbus.go`, which runs with **no infrastructure**. A behaviour implemented in only one adapter is a plan failure.
- **`make test` must stay green** — it runs unit + contract + architecture tests and needs no environment. Run it before every commit.
- **Migrations are numbered sequentially.** The last is `0024_email_verification_requests.sql`; this plan adds `0025` and `0026`.
- **A table fed by failures gets a retention statement in its own migration**, written now rather than discovered when it is large.
- **The classification seed is derived from `errs.Kind`, never a hand-kept list.**

---

### Task 1: The envelope carries the call's context

**Files:**
- Modify: `internal/domain/ports/ports.go` (the `Event` struct, around line 215)
- Modify: `internal/adapter/eventbus/nats.go` (the `Envelope` struct and the handler's construction of `ports.Event`)
- Modify: `internal/adapter/postgres/outbox.go` (`Emit`, around line 32)
- Modify: `internal/adapter/eventbus/memory.go` (its envelope decoding, around line 174)
- Test: `test/contract/eventbus.go` (new case), `internal/adapter/postgres/outbox_test.go`

**Interfaces:**
- Consumes: `ctxutil.Call` (fields `ActorKind`, `ActorID`, `RequestID`, `SessionID`, `Caller`), read by `ctxutil.From(ctx)`.
- Produces: `ports.Event` with six new fields — `ActorKind string`, `ActorID string`, `RequestID string`, `SessionID string`, `Caller string`, `AggregateKey string`. Every later task reads them off the event.

- [ ] **Step 1: Write the failing contract case**

In `test/contract/eventbus.go`, inside `EventBusSuite`, add a case after case 1:

```go
t.Run("1c_the_call_context_survives_the_round_trip", func(t *testing.T) {
    // The consumer is where failures happen, and a failure that cannot say
    // who caused it costs a join into Postgres at exactly the wrong moment.
    bus := newBus(t)
    subject := uniqueSubject("contexto")
    c := newCollector()
    subscribe(t, bus, subject, c.handler)

    id := uniqueEventID()
    data := []byte(`{"id":"` + id + `","account_id":"acct-1","aggregate":"account",` +
        `"aggregate_id":"9a2c","aggregate_key":"acme","type":"dop.identity.account.created",` +
        `"payload":{},"occurred_at":"2026-09-13T12:00:00Z",` +
        `"actor_kind":"user","actor_id":"u-1","request_id":"req-1",` +
        `"session_id":"s-1","caller":"bff"}`)
    publish(t, bus, subject, data)

    got := c.await(t, 1)[0]
    if got.ActorID != "u-1" || got.ActorKind != "user" {
        t.Fatalf("the actor did not survive: kind=%q id=%q", got.ActorKind, got.ActorID)
    }
    if got.RequestID != "req-1" || got.SessionID != "s-1" || got.Caller != "bff" {
        t.Fatalf("the call's identity did not survive: %+v", got)
    }
    if got.AggregateKey != "acme" {
        t.Fatalf("the readable key did not survive: %q", got.AggregateKey)
    }
})
```

- [ ] **Step 2: Run it and watch both adapters fail**

Run: `go test ./test/contract/ -run EventBus -v`
Expected: FAIL for `memory` and `nats` — the fields do not exist yet (compile error on `got.ActorID`).

- [ ] **Step 3: Add the fields to the port**

In `internal/domain/ports/ports.go`, replace the `Event` struct:

```go
type Event struct {
	ID          string
	AccountID   string
	Aggregate   string
	AggregateID string
	// AggregateKey is the aggregate's readable handle — "acme" for an account,
	// the workspace's slug. It exists so a human or an agent can talk about a
	// fact without a uuid, in a log, in a panel or in a conversation.
	//
	// It is a SNAPSHOT, not the truth of now: renaming the workspace does not
	// rewrite the events that already happened, and the old event keeps saying
	// the old name. That is what a log of facts is for.
	//
	// Empty where the aggregate has no natural stable handle — a grant, a
	// notification. An honest blank beats a uuid wearing a nickname.
	AggregateKey string
	Type         string
	Payload      []byte
	OccurredAt   time.Time

	// ── Who caused this ────────────────────────────────────────────────────
	// Recorded by the outbox from the call's context, and carried all the way
	// to the consumer. Before this existed the envelope dropped them, so a
	// consumer failed without being able to say who caused the work — the
	// answer was one join away in Postgres, which is archaeology at the moment
	// of an error rather than a payload.
	//
	// All optional: a message published before this change has none, and an
	// event raised by the scheduler has no person behind it.
	ActorKind string
	ActorID   string
	RequestID string
	SessionID string
	// Caller is the COMPONENT that signed the call — "bff", "collector"
	// (ADR-0029). Empty when the call was proven only by a person's token.
	Caller string
}
```

- [ ] **Step 4: Add the fields to the NATS envelope**

In `internal/adapter/eventbus/nats.go`, replace the `Envelope` struct and the construction of `ports.Event` inside `Consume`:

```go
type Envelope struct {
	ID           string          `json:"id"`
	AccountID    string          `json:"account_id"`
	Aggregate    string          `json:"aggregate"`
	AggregateID  string          `json:"aggregate_id"`
	AggregateKey string          `json:"aggregate_key,omitempty"`
	Type         string          `json:"type"`
	Payload      json.RawMessage `json:"payload"`
	OccurredAt   time.Time       `json:"occurred_at"`
	ActorKind    string          `json:"actor_kind,omitempty"`
	ActorID      string          `json:"actor_id,omitempty"`
	RequestID    string          `json:"request_id,omitempty"`
	SessionID    string          `json:"session_id,omitempty"`
	Caller       string          `json:"caller,omitempty"`
}

// eventFrom builds the port's Event from the wire envelope. One function, used
// by the consumer and by the dead-letter path, so the two can never disagree
// about which fields cross.
func eventFrom(env Envelope, raw []byte) ports.Event {
	return ports.Event{
		ID:           env.ID,
		AccountID:    env.AccountID,
		Aggregate:    env.Aggregate,
		AggregateID:  env.AggregateID,
		AggregateKey: env.AggregateKey,
		Type:         env.Type,
		Payload:      raw,
		OccurredAt:   env.OccurredAt,
		ActorKind:    env.ActorKind,
		ActorID:      env.ActorID,
		RequestID:    env.RequestID,
		SessionID:    env.SessionID,
		Caller:       env.Caller,
	}
}
```

Then, inside `Consume`, replace the hand-built `e := ports.Event{...}` with `e := eventFrom(env, msg.Data())`.

- [ ] **Step 5: Do the same in the memory adapter**

In `internal/adapter/eventbus/memory.go`, find where it unmarshals into its envelope (around line 174) and build the `ports.Event` through the same `eventFrom` helper. The two adapters live in the same package, so the helper is shared, not duplicated.

- [ ] **Step 6: Run the contract suite**

Run: `go test ./test/contract/ -run EventBus -v`
Expected: PASS for both `memory` and `nats`.

- [ ] **Step 7: Write the failing test for the outbox**

In `internal/adapter/postgres/outbox_test.go` (create it if absent), assert that `Emit` puts the context into the published envelope. If the file does not exist, model it on any existing `internal/adapter/postgres/*_test.go` for how a test gets a pool; if the suite has no pool available without infrastructure, assert instead on the JSON that `Emit` builds by extracting envelope construction into a testable function:

```go
func TestTheEnvelopeCarriesWhoCausedTheEvent(t *testing.T) {
	// The information already reaches the events table. What this pins is that
	// it also reaches the CONSUMER, which is where it is needed and where it
	// used to be dropped.
	call := ctxutil.Call{
		ActorKind: ctxutil.ActorUser, ActorID: "u-1",
		RequestID: "req-1", SessionID: "s-1", Caller: "bff",
	}
	e := ports.Event{
		AccountID: "acct-1", Aggregate: "account", AggregateID: "9a2c",
		AggregateKey: "acme", Type: "dop.identity.account.created",
		Payload: []byte(`{}`), OccurredAt: time.Date(2026, 9, 13, 12, 0, 0, 0, time.UTC),
	}

	raw := envelopeOf("ev-1", e, call)

	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("unreadable envelope: %v", err)
	}
	for field, want := range map[string]string{
		"actor_kind": "user", "actor_id": "u-1", "request_id": "req-1",
		"session_id": "s-1", "caller": "bff", "aggregate_key": "acme",
	} {
		if got[field] != want {
			t.Errorf("%s: got %v, want %q", field, got[field], want)
		}
	}
}
```

- [ ] **Step 8: Run it and watch it fail**

Run: `go test ./internal/adapter/postgres/ -run TheEnvelopeCarries -v`
Expected: FAIL — `envelopeOf` is undefined.

- [ ] **Step 9: Extract and fill the envelope in `Emit`**

In `internal/adapter/postgres/outbox.go`, replace the inline `json.Marshal(map[string]any{...})` with a named function, and fill the new fields:

```go
// envelopeOf builds the wire envelope the relay publishes. Extracted from Emit
// so the fields that cross can be asserted without a database: this is the
// boundary where the context used to be silently dropped.
func envelopeOf(id string, e ports.Event, call ctxutil.Call) []byte {
	env, _ := json.Marshal(map[string]any{
		"id": id, "account_id": e.AccountID, "aggregate": e.Aggregate,
		"aggregate_id": e.AggregateID, "aggregate_key": e.AggregateKey,
		"type": e.Type, "payload": json.RawMessage(e.Payload),
		"occurred_at": e.OccurredAt,
		"actor_kind":  string(call.ActorKind), "actor_id": call.ActorID,
		"request_id": call.RequestID, "session_id": call.SessionID,
		"caller": call.Caller,
	})
	return env
}
```

And in `Emit`, after the `INSERT INTO events ... RETURNING id`, replace the marshalling with `env := envelopeOf(id, e, call)`.

- [ ] **Step 10: Run the test and the whole suite**

Run: `go test ./internal/adapter/postgres/ -run TheEnvelopeCarries -v && make test`
Expected: PASS, and `make test` green.

- [ ] **Step 11: Commit**

```bash
git add internal/domain/ports/ports.go internal/adapter/eventbus/ internal/adapter/postgres/ test/contract/eventbus.go
git commit -m "feat(events): o contexto da chamada passa a viajar com o evento

O Emit já gravava ator e request_id na tabela events, na mesma transação. O
ENVELOPE descartava tudo — então o consumidor, que é exatamente onde as
falhas acontecem, rodava sem saber quem causou aquilo. A informação estava a
um JOIN de distância, que é arqueologia na hora do erro e não payload.

Entra junto o aggregate_key: o apelido legível do agregado, para uma pessoa
ou um agente falarem de um fato sem uuid. É retrato do momento e não a
verdade de agora — renomear o workspace não reescreve o que já aconteceu."
```

---

### Task 2: Classifying a failure, before retrying it

**Files:**
- Create: `internal/domain/event/classify.go`
- Create: `internal/domain/event/classify_test.go`

**Interfaces:**
- Consumes: `errs.KindOf(err) errs.Kind`, `errs.CodeOf(err) (string, map[string]any)`.
- Produces: `event.Classification` (a string type with constants `Recoverable`, `Irrecoverable`, `Unknown`) and `event.Classify(err error) Classification`.

- [ ] **Step 1: Write the failing test**

Create `internal/domain/event/classify_test.go`:

```go
package event_test

import (
	"errors"
	"testing"

	"github.com/Digital-Business-One/dop-core/internal/domain/event"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

func TestTheSeedComesFromTheKindAndNotFromAList(t *testing.T) {
	// A hand-kept list is a list somebody forgets to extend. errs.Kind already
	// answers the question — "does repeating this call change the answer?" —
	// so the seed is derived from it.
	cases := map[errs.Kind]event.Classification{
		errs.KindUnavailable:   event.Recoverable,
		errs.KindInternal:      event.Unknown,
		errs.KindNotFound:      event.Irrecoverable,
		errs.KindInvalid:       event.Irrecoverable,
		errs.KindPermission:    event.Irrecoverable,
		errs.KindUnauthorized:  event.Irrecoverable,
		errs.KindPrecondition:  event.Irrecoverable,
		errs.KindConflict:      event.Irrecoverable,
		errs.KindAlreadyExists: event.Irrecoverable,
	}
	for kind, want := range cases {
		if got := event.Classify(errs.New(kind, "whatever")); got != want {
			t.Errorf("%s classified as %s, expected %s", kind, got, want)
		}
	}
}

func TestAnErrorThatIsNotOursIsUnknownAndNotIrrecoverable(t *testing.T) {
	// A plain error carries no kind. Calling it irrecoverable would stop
	// retrying something that might just have been a blip, and silently.
	if got := event.Classify(errors.New("a bare error")); got != event.Unknown {
		t.Fatalf("a bare error classified as %s, expected unknown", got)
	}
}

func TestNoErrorIsNotAFailure(t *testing.T) {
	if got := event.Classify(nil); got != event.Recoverable {
		t.Fatalf("nil classified as %s", got)
	}
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `go test ./internal/domain/event/ -run Classif -v`
Expected: FAIL — package `event` has no `Classify`.

- [ ] **Step 3: Write the classifier**

Create `internal/domain/event/classify.go`:

```go
package event

import "github.com/Digital-Business-One/dop-core/internal/platform/errs"

// Classification says whether repeating a failed call is worth anything.
//
// Retrying a permanently broken action across two budgets is waste with a delay
// attached, and it pushes a real failure hours away from the table where
// somebody would see it. So a failure is classified BEFORE it is retried.
type Classification string

const (
	// Recoverable — the world was busy; the same call may work later.
	Recoverable Classification = "recoverable"
	// Irrecoverable — the input is wrong; the same call gives the same answer.
	Irrecoverable Classification = "irrecoverable"
	// Unknown — it may be a bug or a blip. Repetition decides, and until it
	// does, the budget is spent on it.
	Unknown Classification = "unknown"
)

// Classify derives the seed from errs.Kind.
//
// DERIVED, not a hand-kept list: a list is a list somebody forgets to extend,
// and the kind already encodes the only question that matters here — does
// repeating this call change the answer? A template id that does not exist
// arrives as NotFound and is born irrecoverable with nobody registering
// anything.
//
// This is only the SEED. The signatures table learns from repetition and a
// human can overrule both.
func Classify(err error) Classification {
	if err == nil {
		return Recoverable
	}
	switch errs.KindOf(err) {
	case errs.KindUnavailable:
		return Recoverable
	case errs.KindNotFound, errs.KindInvalid, errs.KindPermission,
		errs.KindUnauthorized, errs.KindPrecondition, errs.KindConflict,
		errs.KindAlreadyExists:
		return Irrecoverable
	default:
		// KindInternal and anything errs cannot classify. Calling it
		// irrecoverable would stop retrying a blip, and silently.
		return Unknown
	}
}
```

- [ ] **Step 4: Run the test**

Run: `go test ./internal/domain/event/ -run Classif -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add internal/domain/event/classify.go internal/domain/event/classify_test.go
git commit -m "feat(event): a classificação da falha, semeada do errs.Kind

Retentar ação permanentemente quebrada por dois orçamentos é desperdício com
atraso junto, e empurra a falha real para horas longe da tabela onde alguém
a veria. Então a falha é classificada ANTES de ser retentada.

A semente é DERIVADA e não uma lista escrita à mão: lista é o que alguém
esquece de estender, e o Kind já responde a única pergunta que importa aqui
— repetir esta chamada muda a resposta? Um template id inexistente chega
como NotFound e nasce irrecuperável sem ninguém cadastrar nada.

Erro que não é nosso vira unknown, nunca irrecuperável: chamá-lo de
irrecuperável pararia de retentar algo que podia ser só uma instabilidade."
```

---

### Task 3: The dead letter, published instead of discarded

**Files:**
- Create: `internal/domain/event/deadletter.go`
- Modify: `internal/adapter/eventbus/nats.go` (the exhaustion branch inside `Consume`)
- Modify: `internal/adapter/eventbus/memory.go` (its exhaustion branch, around line 192)
- Modify: `test/contract/eventbus.go` (new cases)

**Interfaces:**
- Consumes: `ports.Event` with the context fields (Task 1); `event.Classify` (Task 2).
- Produces: `event.DeadLetter` and the constant `eventbus.DLQSubject = "dop.dlq"`. Task 6's consumer subscribes to that subject and decodes that type.

- [ ] **Step 1: Write the failing contract cases**

In `test/contract/eventbus.go`, add:

```go
t.Run("7_an_exhausted_event_lands_in_the_dead_letter_queue", func(t *testing.T) {
    // Before this, exhaustion called Term() — which DISCARDS — under a log
    // line saying the event had gone to a DLQ that was never built.
    bus := newBus(t)
    subject := uniqueSubject("exausto")

    dead := newCollector()
    subscribe(t, bus, eventbus.DLQSubject, dead.handler)
    subscribe(t, bus, subject, func(ctx context.Context, e ports.Event) error {
        return errs.New(errs.KindUnavailable, "the provider is down")
    })

    id := uniqueEventID()
    publish(t, bus, subject, envelopeJSON(id, subject, `{}`))

    got := dead.await(t, 1)[0]
    var dl event.DeadLetter
    if err := json.Unmarshal(got.Payload, &dl); err != nil {
        t.Fatalf("the dead letter is not readable: %v", err)
    }
    if dl.Event.ID != id {
        t.Fatalf("the dead letter carries another event: %q", dl.Event.ID)
    }
    if len(dl.Attempts) == 0 {
        t.Fatal("the dead letter carries no attempt history — nothing to diagnose")
    }
    if dl.Attempts[len(dl.Attempts)-1].ErrorKind != string(errs.KindUnavailable) {
        t.Fatalf("the failure's kind did not survive: %+v", dl.Attempts)
    }
    if dl.Classification != string(event.Recoverable) {
        t.Fatalf("classified as %q, expected recoverable", dl.Classification)
    }
})

t.Run("7b_a_handler_that_recovers_produces_no_dead_letter", func(t *testing.T) {
    // The queue must hold failures, not attempts. A DLQ that collects
    // everything that ever nacked is a DLQ nobody reads.
    bus := newBus(t)
    subject := uniqueSubject("recupera")

    dead := newCollector()
    subscribe(t, bus, eventbus.DLQSubject, dead.handler)

    var attempts atomic.Int32
    subscribe(t, bus, subject, func(ctx context.Context, e ports.Event) error {
        if attempts.Add(1) < 2 {
            return errs.New(errs.KindUnavailable, "not yet")
        }
        return nil
    })

    publish(t, bus, subject, envelopeJSON(uniqueEventID(), subject, `{}`))

    dead.awaitNone(t, 2*time.Second)
})
```

If `awaitNone` does not exist on the collector, add it beside `await` in the same file:

```go
// awaitNone fails if anything arrives within the window. Proving an absence
// needs a deadline; without one the test passes by being fast.
func (c *collector) awaitNone(t *testing.T, window time.Duration) {
	t.Helper()
	deadline := time.After(window)
	for {
		select {
		case e := <-c.ch:
			t.Fatalf("expected nothing, got %q", e.Type)
		case <-deadline:
			return
		}
	}
}
```

- [ ] **Step 2: Run it and watch both adapters fail**

Run: `go test ./test/contract/ -run EventBus -v`
Expected: FAIL — `event.DeadLetter` and `eventbus.DLQSubject` are undefined.

- [ ] **Step 3: Write the dead-letter record**

Create `internal/domain/event/deadletter.go`:

```go
package event

import (
	"time"

	"github.com/Digital-Business-One/dop-core/internal/domain/ports"
)

// Attempt is one failure, as it happened.
type Attempt struct {
	At           time.Time `json:"at"`
	ErrorKind    string    `json:"error_kind"`
	ErrorCode    string    `json:"error_code"`
	ErrorMessage string    `json:"error_message"`
}

// DeadLetter is what a consumer could not process, with everything needed to
// try again — in ONE payload.
//
// The whole event travels, context included, and not a reference to it: a
// reference would make the retry depend on a second read at the worst possible
// moment, and on that read still answering the same thing.
//
// ── On the frozen plan ──────────────────────────────────────────────────────
//
// P-29 §6 describes this record as carrying the plan `Decide` produced —
// {event, rule_ref, action_name, params}. The reasoning is exact and stands:
// rules are data, data changes, and a rule edited between the failure and the
// retry would make the retry execute something DIFFERENT from what failed.
//
// `rule_ref` and `action_name` do not exist yet — there is no dispatcher, and
// the consumers are wired by hand. So this freezes what exists, {event,
// consumer}, and the two fields are added when the dispatcher lands. They are
// additive: the unit of retry is the same in both designs — one event, one
// handler. The dispatcher changes who decides WHICH handler, not what is
// retried.
type DeadLetter struct {
	Event    ports.Event `json:"event"`
	Consumer string      `json:"consumer"`
	Attempts []Attempt   `json:"attempts"`
	// Classification at the moment of routing. Recorded rather than recomputed
	// so the record says what was decided, not what would be decided today.
	Classification string    `json:"classification"`
	FirstFailedAt  time.Time `json:"first_failed_at"`
	LastFailedAt   time.Time `json:"last_failed_at"`
}
```

- [ ] **Step 4: Publish the dead letter in the NATS adapter**

In `internal/adapter/eventbus/nats.go`, add the constant beside `MaxDeliver`:

```go
	// DLQSubject is where an exhausted event goes. Inside `dop.>`, so the
	// existing stream retains it for the same 30 days — no second stream and no
	// second retention policy to forget about.
	DLQSubject = "dop.dlq"
```

Replace the exhaustion branch inside `Consume`:

```go
		if err := h(ctx, e); err != nil {
			md, _ := msg.Metadata()
			attempts := 1
			if md != nil {
				attempts = int(md.NumDelivered)
			}
			if attempts >= MaxDeliver {
				if dlqErr := n.publishDeadLetter(ctx, durable, e, err, attempts); dlqErr != nil {
					// NAK, not Term. Failing to record a loss must not cause the
					// loss: JetStream keeps the message and tries again. Losing a
					// redelivery is cheaper than losing the record of a loss.
					log.Error("failed to publish the dead letter; the event stays in the queue",
						"error", dlqErr, "event_id", e.ID)
					_ = msg.Nak()
					return
				}
				log.Error("event exhausted its attempts and went to the dead-letter queue",
					"error", err, "type", e.Type, "event_id", e.ID,
					"attempts", attempts, "subject", DLQSubject)
				_ = msg.Term()
				return
			}
			log.Warn("failed to process the event, it will be redelivered",
				"error", err, "type", e.Type, "event_id", e.ID, "attempt", attempts)
			_ = msg.Nak()
			return
		}
		_ = msg.Ack()
```

And add the method:

```go
// publishDeadLetter records a loss on the queue that exists to hold it.
//
// The attempt history has ONE entry here, and that is honest: JetStream
// redelivers without telling the process what the earlier failures were, so
// this is the only one this adapter witnessed. The count is real
// (`NumDelivered`), the history is what it saw.
func (n *NATS) publishDeadLetter(ctx context.Context, consumer string, e ports.Event, cause error, attempts int) error {
	now := time.Now().UTC()
	code, _ := errs.CodeOf(cause)
	dl := event.DeadLetter{
		Event:    e,
		Consumer: consumer,
		Attempts: []event.Attempt{{
			At:           now,
			ErrorKind:    string(errs.KindOf(cause)),
			ErrorCode:    code,
			ErrorMessage: cause.Error(),
		}},
		Classification: string(event.Classify(cause)),
		FirstFailedAt:  now,
		LastFailedAt:   now,
	}
	body, err := json.Marshal(dl)
	if err != nil {
		return errs.Wrap(errs.KindInternal, err, "unreadable dead letter")
	}
	return n.Publish(ctx, ports.Event{
		ID:        e.ID,
		AccountID: e.AccountID,
		Aggregate: "dead_letter",
		Type:      DLQSubject,
		Payload:   body,
	})
}
```

Note: if `NATS.Publish` derives the subject from `Type` via `postgres.Subject`, confirm it produces `dop.dlq` for `Type: "dop.dlq"`; if the adapter publishes on a subject argument instead, pass `DLQSubject` directly and keep the payload identical.

- [ ] **Step 5: Do the same in the memory adapter**

In `internal/adapter/eventbus/memory.go`, at its exhaustion branch (around line 192), call the same shape: build the `event.DeadLetter`, marshal it, and deliver it on `DLQSubject` through the adapter's own delivery path. Both adapters must produce a byte-identical record for the same failure — that is what the contract case asserts.

- [ ] **Step 6: Run the contract suite**

Run: `go test ./test/contract/ -run EventBus -v`
Expected: PASS for both adapters, including `7` and `7b`.

- [ ] **Step 7: Run everything**

Run: `make test`
Expected: green.

- [ ] **Step 8: Commit**

```bash
git add internal/domain/event/deadletter.go internal/adapter/eventbus/ test/contract/eventbus.go
git commit -m "feat(eventbus): o evento esgotado passa a ir para uma DLQ que existe

Antes, a exaustão chamava Term(), que DESCARTA, sob um log dizendo que o
evento tinha ido para uma DLQ. Não havia stream de dead-letter, consumidor
de advisory nem republish — a linha nomeava um destino que nunca foi
construído. Pior que silêncio: quem lia ia procurar uma fila inexistente e
concluía que a mensagem estava guardada.

O registro leva o evento INTEIRO, com contexto, e não uma referência a ele:
referência faria a retentativa depender de uma segunda leitura no pior
momento possível, e de essa leitura ainda responder a mesma coisa.

Se publicar o dead-letter falhar, a mensagem é NAKED e não terminada.
Falhar ao registrar uma perda não pode causar a perda — perder uma
reentrega é mais barato que perder o registro de uma."
```

---

### Task 4: The signatures table learns, and takes evidence back

**Files:**
- Create: `migrations/0025_error_signatures.sql`
- Create: `internal/domain/event/signature.go`
- Create: `internal/domain/event/signature_test.go`
- Create: `internal/adapter/postgres/eventerror.go`

**Interfaces:**
- Consumes: `event.Classification` (Task 2).
- Produces: `event.Signature` struct; `event.Decide(sig Signature, seed Classification) Classification`; the port `event.SignatureStore` with `Get(ctx, consumer, code) (*Signature, error)`, `RecordExhausted(ctx, consumer, code string, seed Classification) error`, `RecordSuccess(ctx, consumer, code string) error`. Task 6 calls all three.

- [ ] **Step 1: Write the migration**

Create `migrations/0025_error_signatures.sql`:

```sql
-- +goose Up
-- ════════════════════════════════════════════════════════════════════════════
-- What the platform has learned about its own failures (spec 2026-09-13 §3).
--
-- The signature is (consumer, code) and NOT (consumer, message). `errs.Error`
-- carries a stable Code separate from the developer-facing message precisely
-- because the message is free text that changes; comparing messages would make
-- the learning brittle, comparing codes makes it exact.
--
-- `classified_by` is what protects a human's judgement. A mark somebody placed
-- by hand survives an accidental success, because they marked it for a reason
-- the system cannot see.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE error_signatures (
  consumer        text NOT NULL,
  code            text NOT NULL,
  classification  text NOT NULL,
  exhausted_count integer NOT NULL DEFAULT 0,
  last_success_at timestamptz,
  classified_by   text NOT NULL,
  first_seen      timestamptz NOT NULL DEFAULT now(),
  last_seen       timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (consumer, code),

  CONSTRAINT error_signature_classification_is_known
    CHECK (classification IN ('recoverable', 'irrecoverable', 'unknown')),
  CONSTRAINT error_signature_origin_is_known
    CHECK (classified_by IN ('seed', 'learned', 'human'))
);

-- Retention: none, deliberately, and that is the exception worth stating. This
-- table is SMALL — one row per (consumer, code) pair the platform has ever
-- seen, not one per failure — and its value is precisely that it remembers
-- across time. Trimming it would throw away the learning it exists to hold.
COMMENT ON TABLE error_signatures IS
  'What the platform learned about its failures. One row per (consumer, code); grows with the VOCABULARY of failures, not with their number. No retention on purpose.';

-- +goose Down
DROP TABLE error_signatures;
```

- [ ] **Step 2: Write the failing test for the learning rules**

Create `internal/domain/event/signature_test.go`:

```go
package event_test

import (
	"testing"
	"time"

	"github.com/Digital-Business-One/dop-core/internal/domain/event"
)

func TestASignatureNobodyHasSeenFollowsTheSeed(t *testing.T) {
	if got := event.Decide(event.Signature{}, event.Recoverable); got != event.Recoverable {
		t.Fatalf("with no history the seed must win, got %s", got)
	}
}

func TestBurningEveryRetryTwiceWithNoSuccessBecomesIrrecoverable(t *testing.T) {
	// Once may be an outage. Twice, with nothing ever working, is a broken
	// call — and continuing to retry it spends the budget that belongs to
	// failures that might actually recover.
	sig := event.Signature{
		Classification: event.Recoverable, ClassifiedBy: event.BySeed,
		ExhaustedCount: 2,
	}
	if got := event.Decide(sig, event.Recoverable); got != event.Irrecoverable {
		t.Fatalf("expected the learning to demote it, got %s", got)
	}
}

func TestASuccessTakesTheMarkBack(t *testing.T) {
	// The learning can be wrong, so it accepts evidence against itself.
	sig := event.Signature{
		Classification: event.Irrecoverable, ClassifiedBy: event.ByLearned,
		ExhaustedCount: 3, LastSuccessAt: time.Now(),
	}
	if got := event.Decide(sig, event.Unknown); got != event.Recoverable {
		t.Fatalf("a success must undo a learned mark, got %s", got)
	}
}

func TestAHumanMarkSurvivesAnAccidentalSuccess(t *testing.T) {
	// Somebody marked it for a reason the system cannot see. One success must
	// not throw that judgement away; another human moves it.
	sig := event.Signature{
		Classification: event.Irrecoverable, ClassifiedBy: event.ByHuman,
		LastSuccessAt: time.Now(),
	}
	if got := event.Decide(sig, event.Recoverable); got != event.Irrecoverable {
		t.Fatalf("a human mark was overwritten by the machine, got %s", got)
	}
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `go test ./internal/domain/event/ -run Signature -v`
Expected: FAIL — `event.Signature` and `event.Decide` are undefined.

- [ ] **Step 4: Write the signature and the rule**

Create `internal/domain/event/signature.go`:

```go
package event

import (
	"context"
	"time"
)

// Origin says who placed a classification, and it is what protects a human's
// judgement from the machine's.
type Origin string

const (
	BySeed    Origin = "seed"
	ByLearned Origin = "learned"
	ByHuman   Origin = "human"
)

// exhaustionsBeforeLearning is how many full retry budgets a signature has to
// burn before the platform stops believing it can recover.
//
// TWO, not one: once may be an outage that ended. Twice, with nothing ever
// having succeeded, is a broken call, and continuing to retry it spends the
// budget that belongs to failures that might actually recover.
const exhaustionsBeforeLearning = 2

// Signature is what the platform has learned about one (consumer, code) pair.
type Signature struct {
	Consumer       string
	Code           string
	Classification Classification
	ExhaustedCount int
	LastSuccessAt  time.Time
	ClassifiedBy   Origin
	FirstSeen      time.Time
	LastSeen       time.Time
}

// SignatureStore persists what was learned. A port: the domain states the rule,
// the adapter keeps the rows.
type SignatureStore interface {
	Get(ctx context.Context, consumer, code string) (*Signature, error)
	// RecordExhausted notes that this signature burned a whole retry budget,
	// creating the row from the seed when it is the first time.
	RecordExhausted(ctx context.Context, consumer, code string, seed Classification) error
	// RecordSuccess is the evidence that contradicts a mark.
	RecordSuccess(ctx context.Context, consumer, code string) error
}

// Decide is the classification in force for a signature, given the seed its
// error kind produces.
//
// The order matters and encodes three rules:
//
//  1. A human's mark wins over everything. They marked it for a reason the
//     system cannot see, and one accidental success must not undo that.
//  2. A success takes a machine's mark back. The learning can be wrong, and it
//     accepts evidence against itself.
//  3. Repetition without success promotes to irrecoverable.
//
// With no history, the seed decides.
func Decide(sig Signature, seed Classification) Classification {
	if sig.ClassifiedBy == ByHuman {
		return sig.Classification
	}
	if !sig.LastSuccessAt.IsZero() {
		return Recoverable
	}
	if sig.ExhaustedCount >= exhaustionsBeforeLearning {
		return Irrecoverable
	}
	if sig.Classification != "" {
		return sig.Classification
	}
	return seed
}
```

- [ ] **Step 5: Run the tests**

Run: `go test ./internal/domain/event/ -v`
Expected: PASS (all seven tests from Tasks 2 and 4).

- [ ] **Step 6: Write the Postgres adapter**

Create `internal/adapter/postgres/eventerror.go` with the store. Follow the file conventions in `internal/adapter/postgres/identity.go`: a `New…` constructor taking `*pgxpool.Pool`, `Translate(err, "…")` on every database error, and `var _ event.SignatureStore = (*EventErrorRepo)(nil)` at the end.

```go
func NewEventErrorRepo(pool *pgxpool.Pool) *EventErrorRepo { return &EventErrorRepo{pool: pool} }

func (r *EventErrorRepo) Get(ctx context.Context, consumer, code string) (*event.Signature, error) {
	var s event.Signature
	var lastSuccess *time.Time
	err := r.pool.QueryRow(ctx, `
		SELECT consumer, code, classification, exhausted_count, last_success_at,
		       classified_by, first_seen, last_seen
		  FROM error_signatures WHERE consumer = $1 AND code = $2`,
		consumer, code).Scan(&s.Consumer, &s.Code, &s.Classification,
		&s.ExhaustedCount, &lastSuccess, &s.ClassifiedBy, &s.FirstSeen, &s.LastSeen)
	if errors.Is(err, pgx.ErrNoRows) {
		// Not an error: a signature nobody has seen yet is the normal case, and
		// the caller falls back to the seed.
		return nil, nil
	}
	if err != nil {
		return nil, Translate(err, "the error signature")
	}
	if lastSuccess != nil {
		s.LastSuccessAt = *lastSuccess
	}
	return &s, nil
}

func (r *EventErrorRepo) RecordExhausted(ctx context.Context, consumer, code string, seed event.Classification) error {
	// The seed only applies on INSERT. On conflict the stored classification is
	// left alone — overwriting it would erase a human's mark on every failure.
	_, err := r.pool.Exec(ctx, `
		INSERT INTO error_signatures (consumer, code, classification, exhausted_count, classified_by)
		VALUES ($1, $2, $3, 1, 'seed')
		ON CONFLICT (consumer, code) DO UPDATE
		   SET exhausted_count = error_signatures.exhausted_count + 1,
		       last_seen = now(),
		       classification = CASE
		         WHEN error_signatures.classified_by = 'human' THEN error_signatures.classification
		         WHEN error_signatures.exhausted_count + 1 >= $4 THEN 'irrecoverable'
		         ELSE error_signatures.classification END,
		       classified_by = CASE
		         WHEN error_signatures.classified_by = 'human' THEN 'human'
		         WHEN error_signatures.exhausted_count + 1 >= $4 THEN 'learned'
		         ELSE error_signatures.classified_by END`,
		consumer, code, string(seed), 2)
	return Translate(err, "the error signature")
}

func (r *EventErrorRepo) RecordSuccess(ctx context.Context, consumer, code string) error {
	// A success is evidence against a machine's mark, and never against a
	// human's.
	_, err := r.pool.Exec(ctx, `
		UPDATE error_signatures
		   SET last_success_at = now(), last_seen = now(),
		       classification = CASE WHEN classified_by = 'human'
		                             THEN classification ELSE 'recoverable' END,
		       classified_by  = CASE WHEN classified_by = 'human'
		                             THEN 'human' ELSE 'learned' END
		 WHERE consumer = $1 AND code = $2`, consumer, code)
	return Translate(err, "the error signature")
}
```

- [ ] **Step 7: Apply the migration locally and run everything**

Run: `make migrate && make test`
Expected: the migration applies; `make test` green.

- [ ] **Step 8: Commit**

```bash
git add migrations/0025_error_signatures.sql internal/domain/event/signature.go internal/domain/event/signature_test.go internal/adapter/postgres/eventerror.go
git commit -m "feat(event): a plataforma aprende com as próprias falhas

A assinatura é (consumer, code) e não (consumer, mensagem): o errs.Error
carrega um Code estável, separado da mensagem de desenvolvedor, justamente
porque mensagem é texto livre que muda. Comparar mensagem tornaria o
aprendizado frágil; comparar código o torna exato.

Duas exaustões sem nenhum sucesso promovem a irrecuperável. DUAS e não uma:
uma pode ser indisponibilidade que passou; duas, sem nada nunca ter
funcionado, é chamada quebrada — e continuar retentando gasta o orçamento
que pertence a falhas que talvez se recuperem.

E o aprendizado aceita prova contra si: um sucesso desfaz a marca. Menos
quando a marca é de um humano, que fica até outro humano movê-la — ele
marcou por um motivo que o sistema não enxerga.

A tabela nasce SEM retenção, e isso é a exceção que vale declarar: ela é
pequena, uma linha por par visto, e cresce com o VOCABULÁRIO de falhas e não
com o número delas. Aparar jogaria fora o aprendizado que ela existe para
guardar."
```

---

### Task 5: The terminal errors table

**Files:**
- Create: `migrations/0026_event_errors.sql`
- Modify: `internal/adapter/postgres/eventerror.go` (add the terminal store)
- Modify: `internal/domain/event/deadletter.go` (add the port)

**Interfaces:**
- Consumes: `event.DeadLetter` (Task 3).
- Produces: `event.ErrorStore` with `Record(ctx context.Context, dl DeadLetter, final Classification) error`. Task 6 calls it.

- [ ] **Step 1: Write the migration**

Create `migrations/0026_event_errors.sql`:

```sql
-- +goose Up
-- ════════════════════════════════════════════════════════════════════════════
-- Where an event ends when nobody could process it (spec 2026-09-13 §4).
--
-- Terminal and read by a person or an agent. There is no panel yet, and this
-- table exists before it on purpose: a table nobody reads is still better than
-- an event nobody kept.
--
-- The WHOLE attempt history travels in `attempts`, DLQ rounds included, because
-- the question this table answers is "what happened, exactly" — and an answer
-- that needs a second query to be useful is an answer nobody looks up.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE event_errors (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id       text NOT NULL,
  consumer       text NOT NULL,
  account_id     uuid,
  event_type     text NOT NULL,
  aggregate      text NOT NULL,
  aggregate_id   text NOT NULL,
  -- The readable handle, as it was AT THE TIME. It may disagree with the
  -- aggregate's current name, and that is correct: this is a log of facts.
  aggregate_key  text,
  actor_kind     text,
  actor_id       text,
  request_id     text,
  attempts       jsonb NOT NULL DEFAULT '[]',
  classification text NOT NULL,
  last_code      text,
  last_message   text,
  state          text NOT NULL DEFAULT 'open',
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT event_error_state_is_known
    CHECK (state IN ('open', 'retrying', 'resolved', 'given_up')),
  CONSTRAINT event_error_classification_is_known
    CHECK (classification IN ('recoverable', 'irrecoverable', 'unknown'))
);

-- The two questions a panel asks: what is open, and what happened to this
-- event.
CREATE INDEX event_errors_open_idx ON event_errors (state, created_at DESC)
  WHERE state IN ('open', 'retrying');
CREATE INDEX event_errors_by_event_idx ON event_errors (event_id);

-- Retention, written now rather than discovered when the table is large: a
-- table fed by failures grows fastest exactly when things are worst. Resolved
-- and given-up rows past 90 days have no reader.
COMMENT ON TABLE event_errors IS
  'Events nobody could process. Terminal. Rows in state resolved or given_up older than 90 days may be deleted; open and retrying rows are never swept.';

-- +goose Down
DROP TABLE event_errors;
```

- [ ] **Step 2: Add the port**

In `internal/domain/event/deadletter.go`, append:

```go
// ErrorStore holds what nobody could process. Terminal: whatever reaches it has
// already burned the retries and the DLQ rounds.
type ErrorStore interface {
	Record(ctx context.Context, dl DeadLetter, final Classification) error
}
```

Add `"context"` to that file's imports.

- [ ] **Step 3: Write the failing test**

In `internal/adapter/postgres/eventerror_test.go`, assert the mapping from a `DeadLetter` to the row's columns without a database, by extracting the column values into a function:

```go
func TestTheTerminalRowCarriesWhoAndWhat(t *testing.T) {
	// The panel's whole value is answering "what happened, exactly" without a
	// second query. If the context does not reach the row, it never will.
	dl := event.DeadLetter{
		Event: ports.Event{
			ID: "ev-1", AccountID: "9a2c", Aggregate: "account",
			AggregateID: "9a2c", AggregateKey: "acme",
			Type: "dop.identity.account.created",
			ActorKind: "user", ActorID: "u-1", RequestID: "req-1",
		},
		Consumer: "notification",
		Attempts: []event.Attempt{
			{ErrorKind: "unavailable", ErrorCode: "mail.provider_down", ErrorMessage: "boom"},
		},
	}

	cols := postgres.EventErrorColumns(dl, event.Irrecoverable)

	if cols.AggregateKey != "acme" || cols.ActorID != "u-1" || cols.RequestID != "req-1" {
		t.Fatalf("the context did not reach the row: %+v", cols)
	}
	if cols.LastCode != "mail.provider_down" || cols.LastMessage != "boom" {
		t.Fatalf("the last failure did not reach the row: %+v", cols)
	}
	if cols.Classification != "irrecoverable" {
		t.Fatalf("the final classification did not reach the row: %q", cols.Classification)
	}
}
```

- [ ] **Step 4: Run it and watch it fail**

Run: `go test ./internal/adapter/postgres/ -run TerminalRow -v`
Expected: FAIL — `postgres.EventErrorColumns` is undefined.

- [ ] **Step 5: Implement the terminal store**

In `internal/adapter/postgres/eventerror.go`, add:

```go
// EventErrorRow is the terminal row's column values, built from a dead letter.
// Exported and separated from the INSERT so the mapping can be asserted without
// a database — the mapping is where the context gets silently dropped.
type EventErrorRow struct {
	EventID, Consumer, AccountID          string
	EventType, Aggregate, AggregateID     string
	AggregateKey, ActorKind, ActorID      string
	RequestID, Classification             string
	LastCode, LastMessage                 string
	Attempts                              []byte
}

func EventErrorColumns(dl event.DeadLetter, final event.Classification) EventErrorRow {
	attempts, _ := json.Marshal(dl.Attempts)
	row := EventErrorRow{
		EventID: dl.Event.ID, Consumer: dl.Consumer, AccountID: dl.Event.AccountID,
		EventType: dl.Event.Type, Aggregate: dl.Event.Aggregate,
		AggregateID: dl.Event.AggregateID, AggregateKey: dl.Event.AggregateKey,
		ActorKind: dl.Event.ActorKind, ActorID: dl.Event.ActorID,
		RequestID: dl.Event.RequestID, Classification: string(final),
		Attempts: attempts,
	}
	if n := len(dl.Attempts); n > 0 {
		row.LastCode = dl.Attempts[n-1].ErrorCode
		row.LastMessage = dl.Attempts[n-1].ErrorMessage
	}
	return row
}

func (r *EventErrorRepo) Record(ctx context.Context, dl event.DeadLetter, final event.Classification) error {
	c := EventErrorColumns(dl, final)
	// An account is not guaranteed: `user.ensured` happens before the personal
	// account exists. An empty string is not a uuid — it goes in as NULL.
	var accountID any
	if c.AccountID != "" {
		accountID = c.AccountID
	}
	_, err := r.pool.Exec(ctx, `
		INSERT INTO event_errors (event_id, consumer, account_id, event_type,
		    aggregate, aggregate_id, aggregate_key, actor_kind, actor_id,
		    request_id, attempts, classification, last_code, last_message)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`,
		c.EventID, c.Consumer, accountID, c.EventType, c.Aggregate, c.AggregateID,
		c.AggregateKey, c.ActorKind, c.ActorID, c.RequestID, c.Attempts,
		c.Classification, c.LastCode, c.LastMessage)
	return Translate(err, "the event error")
}

var _ event.ErrorStore = (*EventErrorRepo)(nil)
```

- [ ] **Step 6: Run the test and everything**

Run: `go test ./internal/adapter/postgres/ -run TerminalRow -v && make migrate && make test`
Expected: PASS, migration applies, `make test` green.

- [ ] **Step 7: Commit**

```bash
git add migrations/0026_event_errors.sql internal/adapter/postgres/eventerror.go internal/adapter/postgres/eventerror_test.go internal/domain/event/deadletter.go
git commit -m "feat(event): a tabela terminal, onde o evento para quando ninguém conseguiu

Terminal e lida por uma pessoa ou um agente. Não existe painel ainda, e a
tabela nasce antes dele de propósito: tabela que ninguém lê ainda é melhor
que evento que ninguém guardou.

O histórico INTEIRO de tentativas viaja no attempts, rodadas de DLQ
incluídas, porque a pergunta que esta tabela responde é 'o que aconteceu,
exatamente' — e resposta que exige uma segunda consulta para ser útil é
resposta que ninguém procura.

O mapeamento sai separado do INSERT e exportado, para ser testável sem
banco: mapeamento é onde o contexto some em silêncio.

Retenção escrita agora e não descoberta quando a tabela estiver grande:
tabela alimentada por falhas cresce mais rápido justamente quando tudo está
pior. Resolvidas e desistidas com mais de 90 dias não têm leitor; abertas
nunca são varridas."
```

---

### Task 6: The DLQ consumer, which retries what deserves it

**Files:**
- Create: `internal/app/dlq.go`
- Create: `internal/app/dlq_test.go`
- Modify: `internal/app/register.go` (register the consumer)
- Modify: `internal/app/wire.go` (build the stores)

**Interfaces:**
- Consumes: `event.DeadLetter`, `event.Classify`, `event.Decide`, `event.SignatureStore`, `event.ErrorStore`, `eventbus.DLQSubject`.
- Produces: `app.NewDLQConsumer(handlers map[string]ports.Handler, sigs event.SignatureStore, errors event.ErrorStore, clock ports.Clock) *DLQConsumer` with method `Handle(ctx context.Context, e ports.Event) error`.

- [ ] **Step 1: Write the failing test**

Create `internal/app/dlq_test.go`:

```go
package app

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/Digital-Business-One/dop-core/internal/domain/event"
	"github.com/Digital-Business-One/dop-core/internal/domain/ports"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

func deadLetterEvent(t *testing.T, dl event.DeadLetter) ports.Event {
	t.Helper()
	body, err := json.Marshal(dl)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	return ports.Event{ID: dl.Event.ID, Type: "dop.dlq", Payload: body}
}

func TestAnIrrecoverableFailureIsNotRetried(t *testing.T) {
	// Retrying what cannot work spends the budget that belongs to what can, and
	// pushes the real failure hours away from the table where somebody sees it.
	var called bool
	sigs := &stubSignatures{sig: &event.Signature{
		Classification: event.Irrecoverable, ClassifiedBy: event.ByHuman,
	}}
	errors := &stubErrors{}
	c := NewDLQConsumer(map[string]ports.Handler{
		"notification": func(context.Context, ports.Event) error { called = true; return nil },
	}, sigs, errors, stubClock{})

	dl := event.DeadLetter{Event: ports.Event{ID: "ev-1"}, Consumer: "notification",
		Attempts: []event.Attempt{{ErrorCode: "mail.no_template"}}}
	if err := c.Handle(context.Background(), deadLetterEvent(t, dl)); err != nil {
		t.Fatalf("Handle: %v", err)
	}

	if called {
		t.Error("an irrecoverable failure was retried")
	}
	if errors.recorded != 1 {
		t.Errorf("it did not reach the terminal table: %d records", errors.recorded)
	}
}

func TestARecoverableFailureIsRetriedAndASuccessIsRecorded(t *testing.T) {
	var called bool
	sigs := &stubSignatures{}
	errors := &stubErrors{}
	c := NewDLQConsumer(map[string]ports.Handler{
		"notification": func(context.Context, ports.Event) error { called = true; return nil },
	}, sigs, errors, stubClock{})

	dl := event.DeadLetter{Event: ports.Event{ID: "ev-1"}, Consumer: "notification",
		Classification: string(event.Recoverable),
		Attempts:       []event.Attempt{{ErrorCode: "mail.provider_down"}}}
	if err := c.Handle(context.Background(), deadLetterEvent(t, dl)); err != nil {
		t.Fatalf("Handle: %v", err)
	}

	if !called {
		t.Error("a recoverable failure was not retried")
	}
	if errors.recorded != 0 {
		t.Error("a successful retry still reached the terminal table")
	}
	if sigs.successes != 1 {
		t.Error("the success was not recorded against the signature")
	}
}

func TestAnUnknownConsumerGoesStraightToTheTable(t *testing.T) {
	// A consumer that no longer exists — renamed, removed — must not make the
	// DLQ loop on something nothing can handle.
	sigs := &stubSignatures{}
	errors := &stubErrors{}
	c := NewDLQConsumer(map[string]ports.Handler{}, sigs, errors, stubClock{})

	dl := event.DeadLetter{Event: ports.Event{ID: "ev-1"}, Consumer: "gone"}
	if err := c.Handle(context.Background(), deadLetterEvent(t, dl)); err != nil {
		t.Fatalf("Handle: %v", err)
	}

	if errors.recorded != 1 {
		t.Errorf("it did not reach the terminal table: %d", errors.recorded)
	}
}

func TestAnUnreadableDeadLetterIsNotRedelivered(t *testing.T) {
	// Returning an error here would put the malformed record back on the queue
	// forever. It is terminal by nature: no retry improves broken JSON.
	c := NewDLQConsumer(map[string]ports.Handler{}, &stubSignatures{}, &stubErrors{}, stubClock{})

	err := c.Handle(context.Background(), ports.Event{ID: "ev-1", Payload: []byte(`{`)})

	if err != nil {
		t.Fatalf("an unreadable dead letter asked to be redelivered: %v", err)
	}
}
```

Add the stubs at the bottom of the same file:

```go
type stubSignatures struct {
	sig       *event.Signature
	exhausted int
	successes int
}

func (s *stubSignatures) Get(context.Context, string, string) (*event.Signature, error) {
	return s.sig, nil
}
func (s *stubSignatures) RecordExhausted(context.Context, string, string, event.Classification) error {
	s.exhausted++
	return nil
}
func (s *stubSignatures) RecordSuccess(context.Context, string, string) error {
	s.successes++
	return nil
}

type stubErrors struct{ recorded int }

func (s *stubErrors) Record(context.Context, event.DeadLetter, event.Classification) error {
	s.recorded++
	return nil
}
```

If `stubClock` is not already defined in package `app`'s tests, add:

```go
type stubClock struct{}

func (stubClock) Now() time.Time { return time.Date(2026, 9, 13, 12, 0, 0, 0, time.UTC) }
```

- [ ] **Step 2: Run it and watch it fail**

Run: `go test ./internal/app/ -run DLQ -v`
Expected: FAIL — `NewDLQConsumer` is undefined.

- [ ] **Step 3: Write the consumer**

Create `internal/app/dlq.go`:

```go
package app

import (
	"context"
	"encoding/json"
	"time"

	"github.com/Digital-Business-One/dop-core/internal/domain/event"
	"github.com/Digital-Business-One/dop-core/internal/domain/ports"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
	"github.com/Digital-Business-One/dop-core/internal/platform/logging"
)

// dlqRetries is how many more times the dead-letter consumer tries, ON TOP of
// the five JetStream already spent. Small on purpose: past this, a person or an
// agent decides, and the table is where they see it.
const dlqRetries = 3

// DLQConsumer re-executes what failed, through the SAME registry the dispatcher
// uses — it has no logic of its own about what an action means.
//
// That is not tidiness: rules are data and data changes, so a consumer that
// decided again could execute something different from what failed. It calls
// the handler the record names, with the event the record froze.
type DLQConsumer struct {
	handlers map[string]ports.Handler
	sigs     event.SignatureStore
	errors   event.ErrorStore
	clock    ports.Clock
}

func NewDLQConsumer(handlers map[string]ports.Handler, sigs event.SignatureStore,
	errors event.ErrorStore, clock ports.Clock) *DLQConsumer {
	return &DLQConsumer{handlers: handlers, sigs: sigs, errors: errors, clock: clock}
}

// Handle processes one dead letter.
//
// It returns nil in every terminal case, INCLUDING the failures — a returned
// error would put the record back on the queue, and the queue is not where an
// unprocessable record belongs. What it returns an error for is its own
// inability to record, which deserves a redelivery.
func (c *DLQConsumer) Handle(ctx context.Context, e ports.Event) error {
	log := logging.From(ctx).With("dlq_event_id", e.ID)

	var dl event.DeadLetter
	if err := json.Unmarshal(e.Payload, &dl); err != nil {
		// Terminal by nature: no retry improves broken JSON. Recorded and
		// dropped, never redelivered.
		log.Error("unreadable dead letter, discarded", "error", err)
		return nil
	}

	code := ""
	if n := len(dl.Attempts); n > 0 {
		code = dl.Attempts[n-1].ErrorCode
	}

	seed := event.Classification(dl.Classification)
	if seed == "" {
		seed = event.Unknown
	}
	var sig event.Signature
	if stored, err := c.sigs.Get(ctx, dl.Consumer, code); err != nil {
		// The store being down is not the event's fault: ask for a redelivery.
		return err
	} else if stored != nil {
		sig = *stored
	}
	final := event.Decide(sig, seed)

	handler, known := c.handlers[dl.Consumer]
	if !known {
		// A consumer that no longer exists — renamed, removed. Looping on it
		// would spend a budget on something nothing can handle.
		log.Warn("dead letter names a consumer that does not exist", "consumer", dl.Consumer)
		return c.errors.Record(ctx, dl, final)
	}
	if final == event.Irrecoverable {
		log.Info("irrecoverable failure, not retried", "consumer", dl.Consumer, "code", code)
		return c.errors.Record(ctx, dl, final)
	}

	for attempt := 1; attempt <= dlqRetries; attempt++ {
		err := handler(ctx, dl.Event)
		if err == nil {
			// Evidence against the mark, and it is recorded even when the mark
			// was right until now.
			if sErr := c.sigs.RecordSuccess(ctx, dl.Consumer, code); sErr != nil {
				log.Warn("the retry worked and the success was not recorded", "error", sErr)
			}
			log.Info("dead letter recovered", "consumer", dl.Consumer, "attempt", attempt)
			return nil
		}
		failedCode, _ := errs.CodeOf(err)
		dl.Attempts = append(dl.Attempts, event.Attempt{
			At:           c.clock.Now(),
			ErrorKind:    string(errs.KindOf(err)),
			ErrorCode:    failedCode,
			ErrorMessage: err.Error(),
		})
		dl.LastFailedAt = c.clock.Now()
		code = failedCode
	}

	if err := c.sigs.RecordExhausted(ctx, dl.Consumer, code, seed); err != nil {
		log.Warn("the exhaustion was not recorded against the signature", "error", err)
	}
	log.Error("dead letter exhausted the recovery budget", "consumer", dl.Consumer, "code", code)
	return c.errors.Record(ctx, dl, final)
}

var _ = time.Second // keep the import if the clock type needs it
```

Remove the trailing `var _ = time.Second` line if `time` is already used.

- [ ] **Step 4: Run the tests**

Run: `go test ./internal/app/ -run DLQ -v`
Expected: PASS (4 tests).

- [ ] **Step 5: Register the consumer**

In `internal/app/register.go`, after the three existing subscriptions, add:

```go
	// The dead-letter consumer. It subscribes to ONE subject and knows every
	// handler by name — the same handlers registered above, so a retry runs
	// exactly what failed.
	dlqHandlers := map[string]ports.Handler{
		"timeline":     timeline.Handle,
		"attention":    attentionProj.Handle,
		"notification": notifier.Handle,
	}
	errorRepo := postgres.NewEventErrorRepo(deps.Pool)
	dlq := NewDLQConsumer(dlqHandlers, errorRepo, errorRepo, relogio)
	if err := deps.Bus.Subscribe(ctx, "", "dlq", []string{eventbus.DLQSubject}, dlq.Handle); err != nil {
		return err
	}
```

Match the names of the existing handler variables in that function — read the three `Subscribe` calls around line 259 and reuse exactly those identifiers.

- [ ] **Step 6: Run everything**

Run: `make test`
Expected: green.

- [ ] **Step 7: Commit**

```bash
git add internal/app/dlq.go internal/app/dlq_test.go internal/app/register.go
git commit -m "feat(app): o consumidor da DLQ, que retenta o que merece

Ele re-executa pelo MESMO registro de handlers que o dispatcher usa, e não
tem lógica própria sobre o que uma ação significa. Isso não é arrumação:
regras são dados e dados mudam, então um consumidor que decidisse de novo
poderia executar coisa diferente da que falhou.

Retorna nil em todo caso terminal, inclusive nas falhas — devolver erro
recolocaria o registro na fila, e fila não é lugar de registro
improcessável. Devolve erro só para a própria incapacidade de registrar,
que aí merece reentrega.

Três casos terminam sem retentativa e cada um por um motivo diferente:
irrecuperável não melhora repetindo; consumidor que não existe mais não tem
quem o execute; e JSON quebrado não melhora com reentrega nenhuma."
```

---

### Task 7: Documentation, and the log that used to lie

**Files:**
- Modify: `docs/adr/0018-postgres-persistence.md`
- Modify: `docs/GLOSSARY.md`

- [ ] **Step 1: Amend ADR-0018**

Its §3 says *"a poisoned message goes to the DLQ"* and, until this plan, no DLQ existed. Append to that section:

```markdown
> **Amendment, 2026-09-13.** This section described the DLQ as if it existed.
> It did not: on exhaustion the adapter called `Term()`, which discards, under
> a log line claiming the message had been saved. The queue, the classification
> and the terminal table were built by
> [the 2026-09-13 spec](../superpowers/specs/2026-09-13-event-context-and-dlq-design.md).
> The stream's 30-day retention was the only thing standing between an
> exhausted event and nothing at all.
```

- [ ] **Step 2: Add the missing glossary entries**

`aggregate` is used throughout the code and defined nowhere. Add to `docs/GLOSSARY.md`, in the file's existing format:

- **aggregate** — the thing a fact belongs to: the noun whose history that event becomes part of. `account`, `demand`, `resource`, `workspace`. Every event carries `aggregate` (the type) and `aggregate_id` (which one); the index `events_aggregate_idx` is what makes "everything that happened to this one" cheap. The test: would you open a screen to see its history?
- **aggregate_key** — the aggregate's readable handle at the time of the event (`acme`), so a person or an agent can discuss a fact without a uuid. A snapshot: renaming the aggregate does not rewrite events already recorded.
- **dead letter** — the record of an event no consumer could process after every retry. One queue for the whole platform, carrying the event, its context and the attempt history in one payload.

- [ ] **Step 3: Run everything and commit**

Run: `make test`

```bash
git add docs/adr/0018-postgres-persistence.md docs/GLOSSARY.md
git commit -m "docs: a ADR-0018 falava da DLQ como se ela existisse

Ela descrevia 'mensagem envenenada vai para a DLQ' desde o início, e a DLQ
nunca foi construída. A emenda registra o que havia de fato — Term(), que
descarta — e aponta para a spec que a construiu.

Entram também três verbetes que o código usa e o glossário não tinha:
aggregate, aggregate_key e dead letter. 'Agregado' apareceu como dúvida
numa conversa sobre o desenho, o que é o sinal de que faltava."
```

# The decider and the executor (plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** make "what should happen when this event arrives" a stored, resolvable, executable piece of data — for events, and for the stages of a demand's frozen flow.

**Architecture:** a new `internal/domain/reaction` package holding the rules, their validation and the decision; the action vocabulary as a closed type; a registry of named handlers wired in the composition root; and an idempotency gate on `(event, rule_ref, action)`. Nothing here subscribes to anything — plan 2 wires it to the bus and retires today's three consumers.

**Tech Stack:** Go 1.27, pgx/v5, goose migrations, Postgres.

**Spec:** [`docs/superpowers/specs/2026-09-06-event-reaction-as-data-design.md`](../specs/2026-09-06-event-reaction-as-data-design.md)

**This is plan 1 of 3.** Plan 2 is the dispatcher and the migration of the attention, notification and timeline consumers. Plan 3 is the failure path — the DLQ carrying the frozen plan, the error classification, and the errors table. Neither is written yet.

## Global Constraints

- **Everything written in the repository is in English** — code, comments, migration comments. Commit messages are Portuguese by house convention; match `git log`.
- House comment style: comments explain WHY a decision was made and what it costs, not what a line does.
- **Multi-tenant isolation:** every repository operation takes `accountID` explicitly.
- **A rule row holds no function, no closure and no `switch`** (P-29). `when` is a map of field to value; parameters are copied from the payload BY NAME. Anything that needs an expression is a new decision, not an `if`.
- **The action vocabulary is closed.** An unknown name is a contract error, not user data — the same stance ADR-0014 §1 takes on stage types.
- Rules **accumulate** down the chain; they do not override. A lower level switches off an inherited rule by id, through `disables`.
- Scope is platform ◁ account ◁ workspace ◁ project. **Never demand** — a demand's reactions come from its frozen flow.
- The domain is tested without a database, using in-memory doubles declared in the domain package's own `_test.go` files.

---

### Task 1: The action vocabulary and the rule entity

**Files:**
- Create: `repos/dop-core/internal/domain/reaction/entity.go`
- Create: `repos/dop-core/internal/domain/reaction/entity_test.go`

**Interfaces:**
- Consumes: `internal/platform/errs`.
- Produces: `reaction.ActionName` (string type) with `ActionOpenAttention`, `ActionCloseAttention`, `ActionSendEmail`, `ActionProvisionBench`; `reaction.ValidActionName(ActionName) bool`; `reaction.Action{Name ActionName; Params map[string]string}`; `reaction.TriggerKind` with `TriggerEvent` and `TriggerSchedule`; `reaction.Rule{ID, AccountID string; OwnerScope, OwnerID string; Trigger TriggerKind; EventType string; When map[string]string; Actions []Action; Disables []string; Enabled bool; Why string}`; `(Rule).Validate() error`.

- [ ] **Step 1: Write the failing test**

`internal/domain/reaction/entity_test.go`:

```go
package reaction_test

import (
	"strings"
	"testing"

	"github.com/Digital-Business-One/dop-core/internal/domain/reaction"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

func good() reaction.Rule {
	return reaction.Rule{
		AccountID: "acct-1", OwnerScope: "account", OwnerID: "acct-1",
		Trigger: reaction.TriggerEvent, EventType: "dop.identity.invite.created",
		Actions: []reaction.Action{{
			Name:   reaction.ActionSendEmail,
			Params: map[string]string{"to_source": "payload", "to_field": "email"},
		}},
		Enabled: true,
		Why:     "the invitee is not a user yet: they have no cockpit to look at",
	}
}

func TestTheActionVocabularyIsClosed(t *testing.T) {
	for _, n := range []reaction.ActionName{
		reaction.ActionOpenAttention, reaction.ActionCloseAttention,
		reaction.ActionSendEmail, reaction.ActionProvisionBench,
	} {
		if !reaction.ValidActionName(n) {
			t.Fatalf("%q has to be accepted", n)
		}
	}
	// An action is CODE. A name outside the vocabulary is a contract error, not
	// something a user typed — the same stance ADR-0014 takes on stage types.
	for _, n := range []reaction.ActionName{"", "send_sms", "run_script", "OPEN_ATTENTION"} {
		if reaction.ValidActionName(n) {
			t.Fatalf("%q must not be accepted", n)
		}
	}
}

func TestARuleThatCouldNotBeAppliedIsRefused(t *testing.T) {
	for name, mutate := range map[string]func(*reaction.Rule){
		"no event type on an event trigger": func(r *reaction.Rule) { r.EventType = "" },
		"no actions and no disables":        func(r *reaction.Rule) { r.Actions = nil },
		"an action outside the vocabulary":  func(r *reaction.Rule) { r.Actions[0].Name = "send_sms" },
		"no owner":                          func(r *reaction.Rule) { r.OwnerScope = "" },
		"the demand scope":                  func(r *reaction.Rule) { r.OwnerScope = "demand" },
		"no reason":                         func(r *reaction.Rule) { r.Why = "" },
	} {
		t.Run(name, func(t *testing.T) {
			r := good()
			mutate(&r)
			if err := r.Validate(); errs.KindOf(err) != errs.KindInvalid {
				t.Fatalf("expected a refusal, got %v", err)
			}
		})
	}
}

func TestARuleThatOnlyDisablesIsLegitimate(t *testing.T) {
	// Switching off an inherited rule is an act of its own. A rule that carries
	// no action but disables one is how an account says "not this one" without
	// having to invent a replacement.
	r := good()
	r.Actions = nil
	r.Disables = []string{"rule-from-the-platform"}
	if err := r.Validate(); err != nil {
		t.Fatalf("a rule that only disables is valid: %v", err)
	}
}

func TestTheReasonIsRequiredAndIsNotARestatement(t *testing.T) {
	// The notification table already carries `Why` for this exact purpose:
	// nobody can disagree with "invite.created -> email", and anybody can
	// disagree with the reason. A policy nobody can argue with is not auditable.
	r := good()
	r.Why = "sends an email when an invite is created"
	if err := r.Validate(); err != nil {
		t.Fatalf("this is a weak reason but not an invalid one: %v", err)
	}
	if !strings.Contains(good().Why, "cockpit") {
		t.Fatal("the fixture's reason should say WHY, so the test above means something")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd repos/dop-core && go test ./internal/domain/reaction/ -v`
Expected: FAIL — the package does not exist.

- [ ] **Step 3: Write minimal implementation**

`internal/domain/reaction/entity.go`:

```go
// Package reaction turns "what should happen when this event arrives" into
// data (P-29).
//
// Until this package existed, every consumer decided in Go: `attention.Apply`
// was a `switch`, and each new reaction meant another one. The cost was not the
// switch itself — it was that a policy written in code cannot be audited by the
// person it affects, cannot be changed without a deploy, and cannot differ
// between two accounts.
//
// House rule, as everywhere in internal/domain: this package knows nothing of
// Postgres, NATS or a mailer. It declares what it needs as a port and the
// composition root wires it.
package reaction

import (
	"strings"

	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

// ActionName is what a rule asks for. The vocabulary is CLOSED because an
// action is code: there is a Go handler behind each name, and a name nobody
// implemented is a contract error rather than something a user typed. It is the
// same stance ADR-0014 §1 takes on stage types.
type ActionName string

const (
	ActionOpenAttention  ActionName = "open_attention"
	ActionCloseAttention ActionName = "close_attention"
	ActionSendEmail      ActionName = "send_email"
	ActionProvisionBench ActionName = "provision_bench"
)

func ValidActionName(n ActionName) bool {
	switch n {
	case ActionOpenAttention, ActionCloseAttention, ActionSendEmail, ActionProvisionBench:
		return true
	}
	return false
}

// Action is one thing to do, with its parameters copied from the event's
// payload BY NAME.
//
// Params is a flat map of strings on purpose. The moment it holds an
// expression, the table stops being data and a loader stops being enough — and
// that is precisely what P-29 exists to prevent.
type Action struct {
	Name   ActionName
	Params map[string]string
}

// TriggerKind is what starts a rule.
//
// TriggerSchedule exists because the notification table already has one row
// that is not event-driven: the attention digest fires on a DELAY after an item
// opens. This package builds the event path; the scheduled path keeps whatever
// drives it today until somebody decides to move it.
type TriggerKind string

const (
	TriggerEvent    TriggerKind = "event"
	TriggerSchedule TriggerKind = "schedule"
)

// Rule is one row of the policy.
type Rule struct {
	ID         string
	AccountID  string // empty at the platform level, which has no owner
	OwnerScope string // platform | account | workspace | project — never demand
	OwnerID    string
	Trigger    TriggerKind
	EventType  string            // with TriggerEvent
	When       map[string]string // every entry must match the payload
	Actions    []Action
	Disables   []string // ids of inherited rules this one switches off
	Enabled    bool
	Why        string
	CreatedBy  string
}

// validScopes excludes `demand` deliberately: a demand's reactions come from
// the flow version it froze, not from this table. Two places deciding for one
// demand is two places to look when it does the wrong thing.
var validScopes = map[string]bool{"platform": true, "account": true, "workspace": true, "project": true}

func (r Rule) Validate() error {
	if !validScopes[r.OwnerScope] {
		return errs.Invalid("rule at an unusable level: %q — a demand's reactions come from its flow", r.OwnerScope)
	}
	if r.Trigger == TriggerEvent && strings.TrimSpace(r.EventType) == "" {
		return errs.Invalid("an event rule with no event type reacts to nothing")
	}
	if len(r.Actions) == 0 && len(r.Disables) == 0 {
		return errs.Invalid("a rule that neither acts nor disables does nothing")
	}
	for i, a := range r.Actions {
		if !ValidActionName(a.Name) {
			return errs.Invalid("action #%d has an unknown name %q: the vocabulary is the platform's", i+1, a.Name)
		}
	}
	if strings.TrimSpace(r.Why) == "" {
		return errs.Invalid(
			"a rule with no stated reason is not auditable: nobody can disagree with " +
				"\"invite.created sends an email\", and anybody can disagree with the reason")
	}
	return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd repos/dop-core && go test ./internal/domain/reaction/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/reaction/
git commit -m "feat(reaction): o vocabulário fechado de ações e a regra"
```

---

### Task 2: The decision — accumulation, `when`, and `disables`

**Files:**
- Create: `repos/dop-core/internal/domain/reaction/decide.go`
- Create: `repos/dop-core/internal/domain/reaction/decide_test.go`

**Interfaces:**
- Consumes: `reaction.Rule`, `reaction.Action`, `ports.Event`.
- Produces: `reaction.PlannedAction{RuleRef string; Name ActionName; Params map[string]string; Event ports.Event}`; `reaction.Decide(e ports.Event, rules []Rule) ([]PlannedAction, error)`. `rules` arrives ordered from the MOST GENERIC level to the most specific, which is the order `Ancestry.ChainOf` already returns.

- [ ] **Step 1: Write the failing test**

```go
package reaction_test

import (
	"encoding/json"
	"testing"

	"github.com/Digital-Business-One/dop-core/internal/domain/ports"
	"github.com/Digital-Business-One/dop-core/internal/domain/reaction"
)

func event(t *testing.T, typ string, payload map[string]any) ports.Event {
	t.Helper()
	raw, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	return ports.Event{ID: "ev-1", AccountID: "acct-1", Type: typ, Payload: raw}
}

func ruleAt(scope, id string, when map[string]string, actions ...reaction.ActionName) reaction.Rule {
	r := reaction.Rule{
		ID: id, OwnerScope: scope, OwnerID: "o", Trigger: reaction.TriggerEvent,
		EventType: "dop.identity.invite.created", When: when, Enabled: true, Why: "because",
	}
	for _, n := range actions {
		r.Actions = append(r.Actions, reaction.Action{Name: n})
	}
	return r
}

func TestRulesAccumulateDownTheChain(t *testing.T) {
	// The whole point: an account adding ONE rule must not silence the
	// platform's. If the nearest level won, as it does for flows, the welcome
	// e-mail would vanish the first time an account wrote a rule of its own.
	got, err := reaction.Decide(
		event(t, "dop.identity.invite.created", map[string]any{"email": "a@b.c"}),
		[]reaction.Rule{
			ruleAt("platform", "r-platform", nil, reaction.ActionSendEmail),
			ruleAt("account", "r-account", nil, reaction.ActionOpenAttention),
		})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("both levels' rules apply, got %d", len(got))
	}
}

func TestALowerLevelDisablesAnInheritedRuleByID(t *testing.T) {
	// Turning something off has to be an ACT. Creating an unrelated rule must
	// never switch off an inherited one as a side effect.
	got, err := reaction.Decide(
		event(t, "dop.identity.invite.created", map[string]any{"email": "a@b.c"}),
		[]reaction.Rule{
			ruleAt("platform", "r-platform", nil, reaction.ActionSendEmail),
			func() reaction.Rule {
				r := ruleAt("account", "r-account", nil)
				r.Disables = []string{"r-platform"}
				return r
			}(),
		})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("the platform's rule was disabled; nothing should be planned, got %v", got)
	}
}

func TestOnlyALOWERLevelCanDisable(t *testing.T) {
	// A rule cannot switch off one that is more specific than itself: the
	// platform must not be able to reach into an account's policy.
	got, err := reaction.Decide(
		event(t, "dop.identity.invite.created", map[string]any{"email": "a@b.c"}),
		[]reaction.Rule{
			func() reaction.Rule {
				r := ruleAt("platform", "r-platform", nil)
				r.Disables = []string{"r-account"}
				return r
			}(),
			ruleAt("account", "r-account", nil, reaction.ActionSendEmail),
		})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 {
		t.Fatalf("the platform must not disable an account's rule, got %d planned", len(got))
	}
}

func TestWhenMatchesEveryEntryOrTheRuleDoesNotApply(t *testing.T) {
	e := event(t, "dop.identity.invite.created", map[string]any{"email": "a@b.c", "role": "admin"})
	cases := map[string]struct {
		when  map[string]string
		plans int
	}{
		"no condition":            {nil, 1},
		"one entry that matches":  {map[string]string{"role": "admin"}, 1},
		"one entry that does not": {map[string]string{"role": "viewer"}, 0},
		"both match":              {map[string]string{"role": "admin", "email": "a@b.c"}, 1},
		"one of two does not":     {map[string]string{"role": "admin", "email": "x@y.z"}, 0},
		"a field the payload lacks": {map[string]string{"absent": "x"}, 0},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			got, err := reaction.Decide(e, []reaction.Rule{
				ruleAt("account", "r", tc.when, reaction.ActionSendEmail)})
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != tc.plans {
				t.Fatalf("wanted %d planned, got %d", tc.plans, len(got))
			}
		})
	}
}

func TestARuleForAnotherEventOrDisabledDoesNotApply(t *testing.T) {
	e := event(t, "dop.identity.invite.created", map[string]any{})
	other := ruleAt("account", "r-other", nil, reaction.ActionSendEmail)
	other.EventType = "dop.demand.stage.advanced"
	off := ruleAt("account", "r-off", nil, reaction.ActionSendEmail)
	off.Enabled = false
	got, err := reaction.Decide(e, []reaction.Rule{other, off})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("neither rule applies, got %d", len(got))
	}
}

func TestThePlanCarriesWhatTheExecutorNeeds(t *testing.T) {
	e := event(t, "dop.identity.invite.created", map[string]any{"email": "a@b.c"})
	r := ruleAt("account", "r-1", nil, reaction.ActionSendEmail)
	r.Actions[0].Params = map[string]string{"to_source": "payload", "to_field": "email"}
	got, err := reaction.Decide(e, []reaction.Rule{r})
	if err != nil {
		t.Fatal(err)
	}
	// RuleRef is what the idempotency key is built from, and what a DLQ record
	// will carry so a retry re-executes what failed rather than what the rules
	// say later.
	if got[0].RuleRef != "r-1" || got[0].Name != reaction.ActionSendEmail {
		t.Fatalf("the plan does not identify its rule or action: %+v", got[0])
	}
	if got[0].Params["to_field"] != "email" || got[0].Event.ID != "ev-1" {
		t.Fatalf("the plan does not carry enough to execute: %+v", got[0])
	}
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/reaction/ -run TestRulesAccumulate -v`
Expected: FAIL — `undefined: reaction.Decide`

- [ ] **Step 3: Implement**

`internal/domain/reaction/decide.go`:

```go
package reaction

import (
	"encoding/json"
	"fmt"

	"github.com/Digital-Business-One/dop-core/internal/domain/ports"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

// PlannedAction is one action, decided, with everything needed to run it.
//
// It carries the event rather than a reference to it because a plan outlives
// the decision: a failed action is retried from a frozen plan, and re-deciding
// later would execute what the rules say THEN instead of what failed.
type PlannedAction struct {
	RuleRef string
	Name    ActionName
	Params  map[string]string
	Event   ports.Event
}

// Decide answers what should happen for one event.
//
// `rules` arrives ordered from the MOST GENERIC level to the most specific —
// the order Ancestry.ChainOf already returns — and that order is what makes
// `disables` directional: a rule can only switch off one that came before it,
// so an account can refuse the platform's rule and the platform cannot reach
// into the account's.
//
// Rules ACCUMULATE. Unlike a flow, where the nearest level wins and there is one
// effective document, every rule in the chain applies: if the nearest won, an
// account writing its first rule would silently switch off the platform's.
func Decide(e ports.Event, rules []Rule) ([]PlannedAction, error) {
	var payload map[string]any
	if len(e.Payload) > 0 {
		if err := json.Unmarshal(e.Payload, &payload); err != nil {
			return nil, errs.Invalid("event %s carries an unreadable payload: %v", e.ID, err)
		}
	}

	disabled := map[string]bool{}
	var planned []PlannedAction
	for _, r := range rules {
		// Applied in chain order: what this rule disables can only be a rule
		// already seen, which is a more generic one.
		for _, id := range r.Disables {
			disabled[id] = true
		}
		if disabled[r.ID] || !r.Enabled {
			continue
		}
		if r.Trigger != TriggerEvent || r.EventType != e.Type {
			continue
		}
		if !matches(r.When, payload) {
			continue
		}
		for _, a := range r.Actions {
			planned = append(planned, PlannedAction{
				RuleRef: r.ID, Name: a.Name, Params: a.Params, Event: e,
			})
		}
	}
	// A rule disabled by a LATER rule has already been planned by the time we
	// see the disable, so the plan is filtered once at the end.
	out := planned[:0]
	for _, p := range planned {
		if !disabled[p.RuleRef] {
			out = append(out, p)
		}
	}
	return out, nil
}

// matches is equality and nothing else. A comparison, a range or a composite
// boolean would make this a DSL — which ADR-0014 §2 already refused for flows,
// for the same reason: the moment the row holds an expression, swapping the
// policy stops being a loader and becomes a rewrite.
func matches(when map[string]string, payload map[string]any) bool {
	for field, want := range when {
		got, ok := payload[field]
		if !ok {
			return false
		}
		if fmt.Sprintf("%v", got) != want {
			return false
		}
	}
	return true
}
```

- [ ] **Step 4: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/reaction/ -v && go vet ./internal/domain/reaction/`
Expected: PASS

- [ ] **Step 5: Prove the directional disable is load-bearing**

Remove the final filtering loop, run `TestALowerLevelDisablesAnInheritedRuleByID`, and confirm it goes RED — then restore. A `disables` that only works when the disabling rule comes first is a rule that works in the test's order and not in the chain's.

- [ ] **Step 6: Commit**

```bash
cd repos/dop-core
git add internal/domain/reaction/
git commit -m "feat(reaction): a decisão — regras acumulam, e desligar é um ato"
```

---

### Task 3: The actions on a stage

**Files:**
- Modify: `repos/dop-core/internal/domain/workflow/entity.go`
- Modify: `repos/dop-core/internal/domain/workflow/entity_test.go` (or wherever `Validate` is tested)

**Interfaces:**
- Consumes: `reaction.ActionName`, `reaction.ValidActionName`.
- Produces: `workflow.StageMoment` with `MomentEnter` and `MomentExit`; `workflow.StageAction{On StageMoment; Name string; Params map[string]string}`; `StageSpec.Actions []StageAction`; `Validate` refusing an unknown moment or action name.

- [ ] **Step 1: Write the failing test**

```go
func TestAStageDeclaresWhatHappensWhenItIsEnteredAndLeft(t *testing.T) {
	f := validFlowFixture(t) // the existing helper in this package
	f.Stages[0].Actions = []workflow.StageAction{
		{On: workflow.MomentExit, Name: "provision_bench",
			Params: map[string]string{"tier": "namespace"}},
	}
	if rep := workflow.Validate(f); !rep.Valid() {
		t.Fatalf("a stage action with a known name and moment is valid: %v", rep.Err())
	}

	for name, action := range map[string]workflow.StageAction{
		"an unknown action name": {On: workflow.MomentExit, Name: "run_script"},
		"an unknown moment":      {On: "midway", Name: "provision_bench"},
		"no name at all":         {On: workflow.MomentEnter, Name: ""},
	} {
		t.Run(name, func(t *testing.T) {
			f := validFlowFixture(t)
			f.Stages[0].Actions = []workflow.StageAction{action}
			if rep := workflow.Validate(f); rep.Valid() {
				t.Fatal("expected a refusal")
			}
		})
	}
}
```

If `validFlowFixture` does not exist under that name, use whatever fixture the file already provides — do not add a second one.

- [ ] **Step 2: Run it and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestAStageDeclares -v`
Expected: FAIL — `undefined: workflow.StageAction`

- [ ] **Step 3: Implement**

In `internal/domain/workflow/entity.go`:

```go
// StageMoment is when a stage's action fires.
//
// Both are derivable from the `from`/`to` the `dop.demand.stage.advanced` event
// already carries, so nothing changes in the emitter. Two moments and not one
// because the two real cases need both: "provision the bench when implementation
// ENDS" is an exit, and "tell the dev when the demand ENTERS spec" is an entry.
// Folding entry into "the exit of the previous stage" is correct and unreadable
// — and unreadable is fatal here, because the flow is authored through a chat.
type StageMoment string

const (
	MomentEnter StageMoment = "enter"
	MomentExit  StageMoment = "exit"
)

func ValidStageMoment(m StageMoment) bool { return m == MomentEnter || m == MomentExit }

// StageAction is what a stage asks the platform to do when it is entered or
// left. The vocabulary is the reaction domain's, so a flow cannot ask for
// something no handler implements.
type StageAction struct {
	On     StageMoment
	Name   string
	Params map[string]string
}
```

Add `Actions []StageAction` to `StageSpec`, and in `Validate`:

```go
	for _, a := range st.Actions {
		if !ValidStageMoment(a.On) {
			rep.add("stage %q: %q is not a moment — use enter or exit", st.Key, a.On)
		}
		if !reaction.ValidActionName(reaction.ActionName(a.Name)) {
			rep.add("stage %q: %q is not an action this platform implements", st.Key, a.Name)
		}
	}
```

Match `Report`'s real method for appending a problem — read the file before writing this.

**On the import:** `workflow` importing `reaction` is a domain importing a domain. It is acceptable here for the same reason `workflow` already declares `RoleOwner`/`RoleAdmin` as plain strings rather than importing `identity`: what travels is a VOCABULARY, not behaviour. If the architecture test refuses the import, copy the validation predicate rather than the package — and say so in your report.

- [ ] **Step 4: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ ./test/contract/ && go build ./...`
Expected: PASS, including the architecture test.

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/workflow/
git commit -m "feat(workflow): uma etapa declara o que acontece ao entrar e ao sair"
```

---

### Task 4: Deciding from a demand's frozen flow

**Files:**
- Create: `repos/dop-core/internal/domain/reaction/stage.go`
- Modify: `repos/dop-core/internal/domain/reaction/decide_test.go`

**Interfaces:**
- Consumes: `ports.Event`, `reaction.PlannedAction`.
- Produces: `reaction.StageActions` (the narrow shape the flow's stages arrive in: `[]StageActionSpec{On, Name, Params}`); `reaction.DecideStage(e ports.Event, flowID string, version int32, stages map[string][]StageActionSpec) ([]PlannedAction, error)`.

The reaction domain does not import `workflow`: the caller reads the frozen flow and hands over the stage actions in this narrow shape. Two domains coupled over one lookup is what the house's narrow ports exist to avoid.

- [ ] **Step 1: Write the failing test**

```go
func TestAStageEventPlansTheExitOfWhereItLeftAndTheEntryOfWhereItArrived(t *testing.T) {
	e := event(t, "dop.demand.stage.advanced", map[string]any{
		"from": "implementation", "to": "test",
	})
	stages := map[string][]reaction.StageActionSpec{
		"implementation": {{On: "exit", Name: reaction.ActionProvisionBench}},
		"test":           {{On: "enter", Name: reaction.ActionOpenAttention}},
		"spec":           {{On: "enter", Name: reaction.ActionSendEmail}},
	}
	got, err := reaction.DecideStage(e, "flow-1", 3, stages)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("the exit of implementation and the entry of test, got %d: %+v", len(got), got)
	}
	// RuleRef names the frozen flow, its version, the stage and the moment —
	// which is what makes the idempotency key unique and a DLQ record
	// re-executable without consulting the rules again.
	if got[0].RuleRef != "flow-1/3/implementation/exit" {
		t.Fatalf("the plan does not identify its origin: %q", got[0].RuleRef)
	}
}

func TestTheFirstStageHasNoExitBeforeIt(t *testing.T) {
	e := event(t, "dop.demand.stage.advanced", map[string]any{"from": "", "to": "context"})
	stages := map[string][]reaction.StageActionSpec{
		"context": {{On: "enter", Name: reaction.ActionSendEmail}},
	}
	got, err := reaction.DecideStage(e, "flow-1", 1, stages)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].RuleRef != "flow-1/1/context/enter" {
		t.Fatalf("a demand starting has an entry and no exit: %+v", got)
	}
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/reaction/ -run TestAStageEvent -v`
Expected: FAIL — `undefined: reaction.StageActionSpec`

- [ ] **Step 3: Implement**

```go
package reaction

import (
	"encoding/json"
	"fmt"

	"github.com/Digital-Business-One/dop-core/internal/domain/ports"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

// StageActionSpec is a flow stage's action, in the narrow shape this domain
// needs. The caller reads the frozen flow version and hands these over; this
// package does not import `workflow`, because it needs one lookup from it and
// not its entities.
type StageActionSpec struct {
	On     string // enter | exit
	Name   ActionName
	Params map[string]string
}

// DecideStage answers what a stage transition should cause.
//
// The demand froze (flow_id, version) when it started (ADR-0014 §4), so the
// actions read here are the ones that were in force when the work began — not
// what somebody edited into the flow this morning.
func DecideStage(e ports.Event, flowID string, version int32, stages map[string][]StageActionSpec) ([]PlannedAction, error) {
	var payload struct {
		From string `json:"from"`
		To   string `json:"to"`
	}
	if len(e.Payload) > 0 {
		if err := json.Unmarshal(e.Payload, &payload); err != nil {
			return nil, errs.Invalid("event %s carries an unreadable payload: %v", e.ID, err)
		}
	}
	var planned []PlannedAction
	add := func(stageKey, moment string) {
		if stageKey == "" {
			return // a demand starting has no stage to leave
		}
		for _, a := range stages[stageKey] {
			if a.On != moment {
				continue
			}
			planned = append(planned, PlannedAction{
				RuleRef: fmt.Sprintf("%s/%d/%s/%s", flowID, version, stageKey, moment),
				Name:    a.Name, Params: a.Params, Event: e,
			})
		}
	}
	add(payload.From, "exit")
	add(payload.To, "enter")
	return planned, nil
}
```

- [ ] **Step 4: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/reaction/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/reaction/
git commit -m "feat(reaction): a etapa da versão congelada decide o que a demanda causa"
```

---

### Task 5: The schema

**Files:**
- Create: `repos/dop-core/migrations/0023_reaction_rules.sql`

**Interfaces:**
- Consumes: `accounts` from `0001_foundation.sql`.
- Produces: tables `reaction_rules` and `applied_actions`.

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- ════════════════════════════════════════════════════════════════════════════
-- Reacting to an event is DATA (P-29).
--
-- Two invariants shape this schema:
--
--  1. A ROW HOLDS NO CODE. `when` and the action parameters are plain maps —
--     no expression, no function, no branch. The moment a row holds an
--     expression, swapping the policy stops being a loader and becomes a
--     rewrite, which is what this change exists to prevent.
--  2. RULES ACCUMULATE. There is no unique index making one rule win per level,
--     because every rule in the chain applies. An account switching off an
--     inherited rule does it by naming its id in `disables` — an act, never a
--     side effect of writing another rule.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TYPE reaction_trigger AS ENUM ('event', 'schedule');

CREATE TABLE reaction_rules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL at the platform level, which has no owner and applies to every
  -- account. Same shape as `flows`.
  account_id  uuid REFERENCES accounts(id) ON DELETE CASCADE,
  owner_scope text NOT NULL,
  owner_id    uuid,
  trigger     reaction_trigger NOT NULL DEFAULT 'event',
  event_type  text,
  -- Equality only. A field to a value, every entry must match.
  when_match  jsonb NOT NULL DEFAULT '{}'::jsonb,
  actions     jsonb NOT NULL DEFAULT '[]'::jsonb,
  disables    uuid[] NOT NULL DEFAULT '{}',
  enabled     boolean NOT NULL DEFAULT true,
  -- The row's REASON, not a restatement of what it does. Nobody can disagree
  -- with "invite.created sends an email"; anybody can disagree with the reason.
  -- Without it the policy is not auditable.
  why         text NOT NULL,
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT reaction_nivel_valido CHECK (owner_scope IN ('platform','account','workspace','project')),
  -- The platform's rules and an account's are mutually exclusive, exactly as in
  -- `flows`: either it has an owner and an account, or it is level 0 and has
  -- neither.
  CONSTRAINT reaction_plataforma_sem_dono CHECK (
    (owner_scope =  'platform' AND account_id IS NULL     AND owner_id IS NULL) OR
    (owner_scope <> 'platform' AND account_id IS NOT NULL AND owner_id IS NOT NULL)
  ),
  CONSTRAINT reaction_evento_tem_tipo CHECK (trigger <> 'event' OR event_type IS NOT NULL),
  CONSTRAINT reaction_faz_alguma_coisa CHECK (
    jsonb_array_length(actions) > 0 OR array_length(disables, 1) > 0
  )
);

-- The resolution's query: every rule of the chain for one event type.
CREATE INDEX reaction_rules_lookup ON reaction_rules (event_type, owner_scope, owner_id)
  WHERE enabled;

-- The idempotency gate. A row is written ONLY on success, so a redelivery
-- re-runs exactly what failed and skips what did not.
--
-- rule_ref is the rule's id, or `<flow_id>/<version>/<stage_key>/<moment>` when
-- the decider was a stage. One column and not two because the executor does not
-- care which decided — it cares that this action, for this event, already ran.
CREATE TABLE applied_actions (
  event_id    uuid NOT NULL,
  rule_ref    text NOT NULL,
  action_name text NOT NULL,
  applied_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, rule_ref, action_name)
);

-- +goose Down
DROP TABLE applied_actions;
DROP TABLE reaction_rules;
DROP TYPE reaction_trigger;
```

- [ ] **Step 2: Apply it against a scratch database, and prove it reverses**

`goose` is not installed and `make migrate` needs a cluster that is stopped. The image must be `pgvector/pgvector:pg16` — plain `postgres:16` lacks the `vector` extension `0001_foundation.sql` requires:

```bash
cd repos/dop-core
docker run --rm -d --name dop-mig -e POSTGRES_PASSWORD=x -e POSTGRES_DB=dop -e POSTGRES_USER=dop -p 55435:5432 pgvector/pgvector:pg16
# wait for it to answer, then apply every migration in order:
for f in migrations/*.sql; do
  sed -n '/-- +goose Up/,/-- +goose Down/p' "$f" | grep -v goose > /tmp/up.sql
  docker exec -i dop-mig psql -U dop -d dop -v ON_ERROR_STOP=1 < /tmp/up.sql || echo "FAILED: $f"
done
# then 0023's Down, then its Up again
docker rm -f dop-mig
```

Paste the real output. A `Down` that fails is a migration that cannot be rolled back in production either.

- [ ] **Step 3: Commit**

```bash
cd repos/dop-core
git add migrations/0023_reaction_rules.sql
git commit -m "feat(db): as regras de reação e o portão de idempotência"
```

---

### Task 6: The repository, and resolving the chain

**Files:**
- Create: `repos/dop-core/internal/domain/reaction/repository.go`
- Create: `repos/dop-core/internal/adapter/postgres/reaction.go`
- Create: `repos/dop-core/test/integration/reaction_test.go`

**Interfaces:**
- Consumes: the schema from Task 5, `reaction.Rule`.
- Produces: the `reaction.Repository` port with `RulesFor(ctx context.Context, accountID, eventType string, chain []ScopeRef) ([]Rule, error)`, `Create`, `SetEnabled`; `reaction.ScopeRef{Scope, ID string}`; `postgres.NewReaction(pool) reaction.Repository`.

`RulesFor` returns the rules ordered from the MOST GENERIC level to the most specific — the order `Decide` requires for `disables` to be directional. The ordering belongs in the query, and a test asserts it.

- [ ] **Step 1: Write the failing integration test**

There are no tests under `internal/adapter/postgres/`; this repo's database tests live in `test/integration/`, behind the `integration` build tag, using `openPool(t)` from `outbox_test.go` and per-file seed helpers, the way `agentmetrics_test.go` does.

```go
//go:build integration

package integration

func TestRulesForReturnsTheChainFromGenericToSpecific(t *testing.T) {
	pool := openPool(t)
	ctx := context.Background()
	repo := postgres.NewReaction(pool)
	account, workspace, project := seedChain(t, pool) // write this helper in this file

	platform := mustCreateRule(t, repo, reaction.Rule{
		OwnerScope: "platform", Trigger: reaction.TriggerEvent,
		EventType: "dop.identity.invite.created",
		Actions:   []reaction.Action{{Name: reaction.ActionSendEmail}},
		Enabled:   true, Why: "the invitee has no cockpit yet",
	})
	projectRule := mustCreateRule(t, repo, reaction.Rule{
		AccountID: account, OwnerScope: "project", OwnerID: project,
		Trigger:   reaction.TriggerEvent, EventType: "dop.identity.invite.created",
		Disables:  []string{platform},
		Enabled:   true, Why: "this project onboards by hand",
	})

	got, err := repo.RulesFor(ctx, account, "dop.identity.invite.created", []reaction.ScopeRef{
		{Scope: "platform"}, {Scope: "account", ID: account},
		{Scope: "workspace", ID: workspace}, {Scope: "project", ID: project},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("both rules of the chain, got %d", len(got))
	}
	// The order is the contract: `disables` is directional, and a project rule
	// arriving BEFORE the platform's would silently fail to switch it off.
	if got[0].ID != platform || got[1].ID != projectRule {
		t.Fatalf("wrong order: %s then %s", got[0].OwnerScope, got[1].OwnerScope)
	}
}

func TestRulesForDoesNotLeakAnotherAccountsRules(t *testing.T) {
	pool := openPool(t)
	ctx := context.Background()
	repo := postgres.NewReaction(pool)
	mine, _, _ := seedChain(t, pool)
	theirs, _, theirProject := seedChain(t, pool)

	mustCreateRule(t, repo, reaction.Rule{
		AccountID: theirs, OwnerScope: "project", OwnerID: theirProject,
		Trigger: reaction.TriggerEvent, EventType: "dop.identity.invite.created",
		Actions: []reaction.Action{{Name: reaction.ActionSendEmail}},
		Enabled: true, Why: "theirs",
	})
	got, err := repo.RulesFor(ctx, mine, "dop.identity.invite.created", []reaction.ScopeRef{
		{Scope: "platform"}, {Scope: "account", ID: mine},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("another account's rule reached this chain: %+v", got)
	}
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `cd repos/dop-core && go test ./test/integration/ -tags=integration -run TestRulesFor -v`
Expected: FAIL — `undefined: postgres.NewReaction`

- [ ] **Step 3: Implement**

`internal/domain/reaction/repository.go`:

```go
package reaction

import "context"

// ScopeRef is one level of the chain. It is declared here rather than imported
// from `workflow` for the reason every narrow port in this codebase exists:
// this domain needs the SHAPE of a level, not the workflow domain's entities.
type ScopeRef struct {
	Scope string
	ID    string
}

// Repository is the reaction domain's persistence PORT.
//
// RulesFor returns the chain's rules ordered from the MOST GENERIC level to the
// most specific. That order is not a convenience: `disables` is directional, and
// a project's rule arriving before the platform's would silently fail to switch
// it off. The ordering belongs in the query, and an integration test asserts it.
type Repository interface {
	RulesFor(ctx context.Context, accountID, eventType string, chain []ScopeRef) ([]Rule, error)
	Create(ctx context.Context, r *Rule, idempotencyKey string) (*Rule, error)
	SetEnabled(ctx context.Context, accountID, ruleID string, enabled bool) error
}
```

Then write the adapter following `internal/adapter/postgres/workflow.go`'s style — the same `Translate` for errors, the same scanning helpers. The query is the part worth stating in full, because the ORDER is the contract:

```sql
SELECT id, COALESCE(account_id::text,''), owner_scope, COALESCE(owner_id::text,''),
       trigger, COALESCE(event_type,''), when_match, actions, disables, enabled, why
  FROM reaction_rules
 WHERE enabled
   AND trigger = 'event'
   AND event_type = $1
   AND ( owner_scope = 'platform'
      OR (account_id = $2 AND (owner_scope, owner_id) = ANY($3::record[])) )
 ORDER BY array_position($4::text[], owner_scope)
```

`$4` is the chain's scope names in order, so the ordering is the caller's chain rather than an alphabetical accident. If `ANY($3::record[])` proves awkward with pgx, pass the scope/id pairs as two parallel arrays and join on their position — and say in your report which you used and why.

- [ ] **Step 4: Run the test**

Run: `cd repos/dop-core && go test ./test/integration/ -tags=integration -run TestRulesFor -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/reaction/ internal/adapter/postgres/reaction.go test/integration/reaction_test.go
git commit -m "feat(postgres): as regras da cadeia, na ordem que torna o disables direcional"
```

---

### Task 7: The executor, and the idempotency gate

**Files:**
- Create: `repos/dop-core/internal/domain/reaction/executor.go`
- Create: `repos/dop-core/internal/domain/reaction/executor_test.go`
- Modify: `repos/dop-core/internal/adapter/postgres/reaction.go`
- Modify: `repos/dop-core/test/integration/reaction_test.go`

**Interfaces:**
- Consumes: `reaction.PlannedAction`, the `Repository` port.
- Produces: `reaction.Handler` (`Run(ctx context.Context, p PlannedAction) error`); `reaction.Registry` (`map[ActionName]Handler`, with `Run(ctx, p) error` refusing an unregistered name); `reaction.Applied` port with TWO methods — `MarkApplied(ctx, eventID, ruleRef, actionName string) (bool, error)`, answering whether THIS caller claimed it, and `Release(ctx, eventID, ruleRef, actionName string) error`, which gives the claim back when the handler fails; `reaction.Execute(ctx, reg Registry, applied Applied, plans []PlannedAction) error`.

- [ ] **Step 1: Write the failing test**

```go
func TestAnActionThatAlreadyRanIsNotRunAgain(t *testing.T) {
	ran := 0
	reg := reaction.Registry{reaction.ActionSendEmail: handlerFunc(func(context.Context, reaction.PlannedAction) error {
		ran++
		return nil
	})}
	applied := newFakeApplied()
	plan := []reaction.PlannedAction{{RuleRef: "r-1", Name: reaction.ActionSendEmail, Event: ports.Event{ID: "ev-1"}}}

	if err := reaction.Execute(context.Background(), reg, applied, plan); err != nil {
		t.Fatal(err)
	}
	if err := reaction.Execute(context.Background(), reg, applied, plan); err != nil {
		t.Fatal(err)
	}
	if ran != 1 {
		t.Fatalf("the same action ran %d times; the gate did not hold", ran)
	}
}

func TestOneActionFailingDoesNotStopTheOthers(t *testing.T) {
	// An e-mail that does not go out must never stop an attention item from
	// opening. The delivery is nacked so the failed one is retried, and the
	// gate means the successful ones are skipped on redelivery.
	var opened bool
	reg := reaction.Registry{
		reaction.ActionSendEmail: handlerFunc(func(context.Context, reaction.PlannedAction) error {
			return errs.New(errs.KindUnavailable, "the mail server is down")
		}),
		reaction.ActionOpenAttention: handlerFunc(func(context.Context, reaction.PlannedAction) error {
			opened = true
			return nil
		}),
	}
	applied := newFakeApplied()
	err := reaction.Execute(context.Background(), reg, applied, []reaction.PlannedAction{
		{RuleRef: "r-1", Name: reaction.ActionSendEmail, Event: ports.Event{ID: "ev-1"}},
		{RuleRef: "r-1", Name: reaction.ActionOpenAttention, Event: ports.Event{ID: "ev-1"}},
	})
	if err == nil {
		t.Fatal("the failure has to reach the caller so the delivery is nacked")
	}
	if !opened {
		t.Fatal("the second action did not run: one failure stopped the others")
	}
	if applied.has("ev-1", "r-1", string(reaction.ActionSendEmail)) {
		t.Fatal("a failed action was marked applied; a retry would skip it")
	}
	if !applied.has("ev-1", "r-1", string(reaction.ActionOpenAttention)) {
		t.Fatal("a successful action was not marked; a retry would run it twice")
	}
}

func TestAnUnregisteredActionIsAContractErrorNotASilentSkip(t *testing.T) {
	// The vocabulary is validated when a rule is written, so reaching here means
	// a rule survived a deploy that removed its handler. Skipping quietly would
	// make a policy stop working with nothing to read.
	reg := reaction.Registry{}
	err := reaction.Execute(context.Background(), reg, newFakeApplied(), []reaction.PlannedAction{
		{RuleRef: "r-1", Name: reaction.ActionSendEmail, Event: ports.Event{ID: "ev-1"}},
	})
	if errs.KindOf(err) != errs.KindInternal {
		t.Fatalf("expected an internal error naming the action, got %v", err)
	}
}
```

Write `handlerFunc` and `newFakeApplied` in the same file.

- [ ] **Step 2: Run it and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/reaction/ -run TestAnActionThatAlreadyRan -v`
Expected: FAIL — `undefined: reaction.Registry`

- [ ] **Step 3: Implement**

```go
// Execute runs a decided plan, once per action.
//
// The gate is claimed BEFORE the handler runs and released if it fails, rather
// than written after success: two deliveries of the same event can be in flight
// at once (JetStream is at-least-once), and a gate written afterwards would let
// both run the same action.
//
// A failure does not stop the plan. The error reaches the caller so the whole
// delivery is nacked, and on redelivery the actions that succeeded are skipped
// by their rows — only the failed one is retried.
func Execute(ctx context.Context, reg Registry, applied Applied, plans []PlannedAction) error {
	var failed []string
	for _, p := range plans {
		claimed, err := applied.MarkApplied(ctx, p.Event.ID, p.RuleRef, string(p.Name))
		if err != nil {
			return err
		}
		if !claimed {
			continue // somebody already did this one
		}
		if err := reg.Run(ctx, p); err != nil {
			if rel := applied.Release(ctx, p.Event.ID, p.RuleRef, string(p.Name)); rel != nil {
				return rel
			}
			failed = append(failed, fmt.Sprintf("%s/%s: %v", p.RuleRef, p.Name, err))
			continue
		}
	}
	if len(failed) > 0 {
		return errs.New(errs.KindUnavailable, "actions failed: %s", strings.Join(failed, "; "))
	}
	return nil
}
```

`Applied` therefore has two methods, and the port's doc comment must say why the claim comes first. The adapter:

```go
// MarkApplied claims the right to run this action. It answers true only for the
// caller that inserted the row — everybody else gets false and skips.
func (r *Reaction) MarkApplied(ctx context.Context, eventID, ruleRef, actionName string) (bool, error) {
	tag, err := r.pool.Exec(ctx, `
		INSERT INTO applied_actions (event_id, rule_ref, action_name)
		VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`, eventID, ruleRef, actionName)
	if err != nil {
		return false, Translate(err, "claiming the action")
	}
	return tag.RowsAffected() == 1, nil
}

// Release gives the claim back after a handler failed, so a redelivery retries
// it. Without this, a transient failure would be remembered as a success and the
// action would never run.
func (r *Reaction) Release(ctx context.Context, eventID, ruleRef, actionName string) error {
	_, err := r.pool.Exec(ctx, `
		DELETE FROM applied_actions
		 WHERE event_id = $1 AND rule_ref = $2 AND action_name = $3`,
		eventID, ruleRef, actionName)
	return Translate(err, "releasing the action")
}
```

Add an integration test proving two concurrent claims yield exactly one execution: run `MarkApplied` from two goroutines on the same triple and assert exactly one gets `true`.

- [ ] **Step 4: Run everything**

Run: `cd repos/dop-core && go build ./... && go test ./internal/... && go vet ./... && go vet -tags=integration ./...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/reaction/ internal/adapter/postgres/reaction.go test/integration/reaction_test.go
git commit -m "feat(reaction): o executor, e o portão que reivindica antes de executar"
```

---

## What this plan does not build

- **The dispatcher** and the retirement of today's three consumers — plan 2, which is where behaviour changes and where the rules reproducing today's rows are seeded.
- **The failure path** — the DLQ carrying the frozen plan, the error classification seeded from `errs.Kind`, and the errors table with its attempt history — plan 3. Until it exists, a failed action is retried by JetStream and then dropped, which is what happens today.
- **The scheduled trigger.** `TriggerSchedule` exists in the vocabulary because the notification table already has a row that fires on a delay rather than on an event (the attention digest). Nothing here executes it; that path keeps whatever drives it today.
- **A cockpit screen for rules.** The model allows one; the screen is later work.
- **Refusing a rule written for an event nobody emits** (spec R-8). It needs the list of event types the aggregates actually emit, which is what plan 2 derives when it builds the subscription's subjects from the rules. Until then a rule for a misspelt event type is accepted and does nothing, silently — the opposite of the guarantee the current subject test provides.

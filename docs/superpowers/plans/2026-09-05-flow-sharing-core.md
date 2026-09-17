# Flow sharing — the core (plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** make a development flow publishable under `@handle/slug@vN`, grantable to a named account, derivable as a copy that records its provenance on both sides, revocable under a policy stamped at grant time, and — where inheritance crosses an ownership boundary — pinned to a version.

**Architecture:** everything lands in `internal/domain/workflow`, which already owns `Flow`, the chain and versioning. Sharing is a second Repository port beside the existing one, so the file that holds today's invariants is not reopened. Nothing here touches `Flow`'s structure, the stage vocabulary or `Resolve`'s chain walk — only which VERSION the walk returns when it crosses an owner.

**Tech Stack:** Go 1.27, pgx/v5, goose migrations, Postgres. Domain tests use in-memory doubles declared in the domain's own `_test.go` files; the adapter is proved separately against a real database.

**Spec:** [`docs/superpowers/specs/2026-09-05-development-flow-sharing-design.md`](../specs/2026-09-05-development-flow-sharing-design.md)

**This is plan 1 of 3.** Plan 2 is the agent's tools (`flow.propose` with its diff, and the four read tools). Plan 3 is the cockpit's renderer. Both depend on what this plan produces and neither is written yet.

## Global Constraints

- **Everything written in the repository is in English** — code, comments, logs, paths, protos, docs. Only what a person reads on screen goes through i18n.
- **Multi-tenant isolation:** every repository operation takes `accountID` explicitly. The one boundary crossing in this plan is resolving a publication reference, and it is authorised by a `flow_shares` row.
- **A version is immutable.** No operation alters a stored version; the way to change a flow is to append a version (existing invariant, enforced by a trigger in `0005_workflow.sql`).
- **Every write carries an idempotency key** (ADR-0013), unique in the database.
- **State and event are written in the same transaction** (ADR-0004/ADR-0014).
- The default revocation policy is `prospective`.
- Account-level settings are changed by **owner or admin** — reuse `identity.Role.CanManageMembers()`, do not invent a permission.

---

### Task 1: The revocation policy, and the account's default

**Files:**
- Create: `repos/dop-core/internal/domain/workflow/sharing.go`
- Create: `repos/dop-core/internal/domain/workflow/sharing_test.go`
- Create: `repos/dop-core/migrations/0020_flow_sharing_policy.sql`
- Modify: `repos/dop-core/internal/domain/identity/entity.go` (add the field to `Account`)
- Modify: `repos/dop-core/internal/domain/identity/service.go` (add `SetDefaultRevocationPolicy`)

**Interfaces:**
- Consumes: `identity.Role.CanManageMembers()`, `ctxutil.MustAccount`, `errs`.
- Produces: `workflow.RevocationPolicy` (string type) with constants `PolicyProspective`, `PolicyDrain`, `PolicyTerminate`; `workflow.ValidRevocationPolicy(RevocationPolicy) bool`; `workflow.DefaultRevocationPolicy` constant; `identity.Account.DefaultRevocationPolicy string`; `identity.Service.SetDefaultRevocationPolicy(ctx, policy string) error`.

- [ ] **Step 1: Write the failing test**

`internal/domain/workflow/sharing_test.go`:

```go
package workflow_test

import (
	"testing"

	"github.com/Digital-Business-One/dop-core/internal/domain/workflow"
)

func TestRevocationPolicyVocabularyIsClosed(t *testing.T) {
	for _, p := range []workflow.RevocationPolicy{
		workflow.PolicyProspective, workflow.PolicyDrain, workflow.PolicyTerminate,
	} {
		if !workflow.ValidRevocationPolicy(p) {
			t.Fatalf("%q has to be accepted", p)
		}
	}
	// An unknown value is a contract error, not user data: whoever sends it is
	// speaking a vocabulary this platform does not have.
	for _, p := range []workflow.RevocationPolicy{"", "soft", "hard", "cascade"} {
		if workflow.ValidRevocationPolicy(p) {
			t.Fatalf("%q must not be accepted", p)
		}
	}
	if workflow.DefaultRevocationPolicy != workflow.PolicyProspective {
		t.Fatal("the default has to be prospective: revoking must not reach a copy unless somebody chose that")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestRevocationPolicy -v`
Expected: FAIL — `undefined: workflow.RevocationPolicy`

- [ ] **Step 3: Write minimal implementation**

`internal/domain/workflow/sharing.go`:

```go
package workflow

// RevocationPolicy is what a revocation DOES to derivations that already exist.
//
// The three names are borrowed, not invented: `prospective` is the legal and
// API-deprecation sense of "applies going forward" (it is crates.io's `yank`);
// `drain` is the load balancer's and `kubectl drain`'s "stop taking new work,
// let current work end"; `terminate` is k8s/systemd's "end now".
type RevocationPolicy string

const (
	// PolicyProspective revokes the GRANT only: no new derivation is possible
	// and every existing one goes on working, untouched.
	PolicyProspective RevocationPolicy = "prospective"
	// PolicyDrain revokes the derivations, but a demand already running finishes
	// under the version it froze on start (ADR-0010 §4).
	PolicyDrain RevocationPolicy = "drain"
	// PolicyTerminate revokes at once: a running demand stops at its current gate
	// and raises an attention item.
	PolicyTerminate RevocationPolicy = "terminate"
)

// DefaultRevocationPolicy is the permissive one, and deliberately so: the
// destructive behaviour has to be chosen, never inherited by omission.
const DefaultRevocationPolicy = PolicyProspective

func ValidRevocationPolicy(p RevocationPolicy) bool {
	switch p {
	case PolicyProspective, PolicyDrain, PolicyTerminate:
		return true
	}
	return false
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestRevocationPolicy -v`
Expected: PASS

- [ ] **Step 5: Write the migration**

`migrations/0020_flow_sharing_policy.sql`:

```sql
-- +goose Up
-- The account's DEFAULT revocation policy (flow sharing spec §3.2).
--
-- It is a default and nothing more: the value that matters is the one COPIED
-- onto the grant when a share is made. Reading the account at revocation time
-- would let the publisher change the terms after somebody accepted them — you
-- adopt under `prospective` and get terminated under `terminate`, with a demand
-- stopping mid-flight.
CREATE TYPE revocation_policy AS ENUM ('prospective', 'drain', 'terminate');

ALTER TABLE accounts
  ADD COLUMN default_revocation_policy revocation_policy NOT NULL DEFAULT 'prospective';

-- +goose Down
ALTER TABLE accounts DROP COLUMN default_revocation_policy;
DROP TYPE revocation_policy;
```

- [ ] **Step 6: Write the failing test for the account setter**

Append to `internal/domain/identity/service_test.go`:

```go
func TestOnlyOwnerOrAdminChangesTheDefaultRevocationPolicy(t *testing.T) {
	svc, env := newServiceForTest(t) // existing helper in this file
	ctx := env.CtxAs(env.DeveloperID, env.AccountID)
	if err := svc.SetDefaultRevocationPolicy(ctx, "terminate"); errs.KindOf(err) != errs.KindPermission {
		t.Fatalf("a developer must not change an account setting: %v", err)
	}
	ctx = env.CtxAs(env.OwnerID, env.AccountID)
	if err := svc.SetDefaultRevocationPolicy(ctx, "terminate"); err != nil {
		t.Fatalf("the owner has to be able to: %v", err)
	}
	if err := svc.SetDefaultRevocationPolicy(ctx, "cascade"); errs.KindOf(err) != errs.KindInvalid {
		t.Fatalf("a value outside the vocabulary has to be refused: %v", err)
	}
}
```

**`newServiceForTest` and `env.CtxAs` do not exist** — the names above are illustrative. Read `internal/domain/identity/service_test.go` first and write this test against the harness that file actually provides. Do not add a second harness for the same domain.

- [ ] **Step 7: Run it and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/identity/ -run TestOnlyOwnerOrAdmin -v`
Expected: FAIL — `svc.SetDefaultRevocationPolicy undefined`

- [ ] **Step 8: Implement the setter**

In `internal/domain/identity/service.go`:

```go
// SetDefaultRevocationPolicy changes the value that will be STAMPED on future
// flow grants. It never touches grants already made: the terms somebody
// accepted are theirs.
func (s *Service) SetDefaultRevocationPolicy(ctx context.Context, policy string) error {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return err
	}
	actor, err := s.actorMembership(ctx, accountID) // existing helper
	if err != nil {
		return err
	}
	if !actor.Role.CanManageMembers() {
		return errs.Permission("changing the account's default requires owner or admin")
	}
	switch policy {
	case "prospective", "drain", "terminate":
	default:
		return errs.Invalid("unknown revocation policy: %q — use prospective, drain or terminate", policy)
	}
	return s.repo.SetDefaultRevocationPolicy(ctx, accountID, policy)
}
```

Add `SetDefaultRevocationPolicy(ctx context.Context, accountID, policy string) error` to `identity.Repository`, implement it in the in-memory double used by the identity tests, and in `internal/adapter/postgres/identity.go` as `UPDATE accounts SET default_revocation_policy = $2, updated_at = now() WHERE id = $1`.

- [ ] **Step 9: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/... && go build ./...`
Expected: PASS

- [ ] **Step 10: Commit**

```bash
cd repos/dop-core
git add internal/domain/workflow/sharing.go internal/domain/workflow/sharing_test.go \
        internal/domain/identity/ internal/adapter/postgres/identity.go migrations/0020_flow_sharing_policy.sql
git commit -m "feat(workflow): a política de revogação e o padrão da conta"
```

---

### Task 2: The publication reference `@handle/slug[@vN]`

**Files:**
- Modify: `repos/dop-core/internal/domain/workflow/sharing.go`
- Modify: `repos/dop-core/internal/domain/workflow/sharing_test.go`

**Interfaces:**
- Consumes: `errs`.
- Produces: `workflow.PublicationRef{Handle, Slug string; Version int32}`; `workflow.ParseRef(string) (PublicationRef, error)`; `(PublicationRef).String() string`; `(PublicationRef).Pinned() bool`. `Version == 0` means "the latest published".

- [ ] **Step 1: Write the failing test**

```go
func TestThePublicationReferenceIsTypeable(t *testing.T) {
	ok := map[string]workflow.PublicationRef{
		"@acme/backend-go":     {Handle: "acme", Slug: "backend-go", Version: 0},
		"@acme/backend-go@v3":  {Handle: "acme", Slug: "backend-go", Version: 3},
		"@ed/meu-fluxo@v12":    {Handle: "ed", Slug: "meu-fluxo", Version: 12},
	}
	for raw, want := range ok {
		got, err := workflow.ParseRef(raw)
		if err != nil {
			t.Fatalf("%q: %v", raw, err)
		}
		if got != want {
			t.Fatalf("%q parsed as %+v, wanted %+v", raw, got, want)
		}
		if got.String() != raw {
			t.Fatalf("%q formats back as %q", raw, got.String())
		}
	}
	// The refusals name what is wrong: somebody typed this by hand.
	for _, raw := range []string{
		"", "acme/backend-go", "@acme", "@acme/", "@/slug",
		"@acme/backend-go@3", "@acme/backend-go@v0", "@acme/backend-go@vx",
		"@ACME/backend-go", "@acme/Backend Go",
	} {
		if _, err := workflow.ParseRef(raw); err == nil {
			t.Fatalf("%q had to be refused", raw)
		}
	}
	if (workflow.PublicationRef{Version: 0}).Pinned() {
		t.Fatal("version zero means the latest published, not a pin")
	}
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestThePublicationReference -v`
Expected: FAIL — `undefined: workflow.ParseRef`

- [ ] **Step 3: Implement**

Append to `internal/domain/workflow/sharing.go`:

```go
import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

// PublicationRef addresses a published flow: `@handle/slug` for the latest
// published version, `@handle/slug@v3` to pin one.
//
// It is typed and read by people, which is why the refusals below name what is
// wrong instead of returning a generic parse error — and why the vocabulary is
// lowercase: two references differing only in case would look identical in a
// chat message and resolve to different flows.
type PublicationRef struct {
	Handle  string
	Slug    string
	Version int32 // 0 = the latest published
}

func (r PublicationRef) Pinned() bool { return r.Version > 0 }

func (r PublicationRef) String() string {
	s := "@" + r.Handle + "/" + r.Slug
	if r.Pinned() {
		s += "@v" + strconv.Itoa(int(r.Version))
	}
	return s
}

// refPart is the shape both a handle and a slug have to fit: lowercase letters,
// digits and hyphens, starting and ending with an alphanumeric.
var refPart = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`)

func ParseRef(raw string) (PublicationRef, error) {
	s := strings.TrimSpace(raw)
	if !strings.HasPrefix(s, "@") {
		return PublicationRef{}, errs.Invalid("a flow reference starts with @: %q", raw)
	}
	s = s[1:]

	var version int32
	if at := strings.LastIndex(s, "@"); at >= 0 {
		v := s[at+1:]
		if !strings.HasPrefix(v, "v") {
			return PublicationRef{}, errs.Invalid("the version in a reference is written @v3, not @%s", v)
		}
		n, err := strconv.Atoi(v[1:])
		if err != nil || n <= 0 {
			return PublicationRef{}, errs.Invalid("%q is not a version number", v)
		}
		version = int32(n)
		s = s[:at]
	}

	handle, slug, found := strings.Cut(s, "/")
	if !found {
		return PublicationRef{}, errs.Invalid("a reference is @handle/name: %q", raw)
	}
	if !refPart.MatchString(handle) {
		return PublicationRef{}, errs.Invalid("%q is not a usable handle: lowercase letters, digits and hyphens", handle)
	}
	if !refPart.MatchString(slug) {
		return PublicationRef{}, errs.Invalid("%q is not a usable name: lowercase letters, digits and hyphens", slug)
	}
	return PublicationRef{Handle: handle, Slug: slug, Version: version}, nil
}

var _ = fmt.Sprintf
```

Remove the `fmt` import and the `var _` line if `fmt` ends up unused.

- [ ] **Step 4: Run it and see it pass**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/workflow/sharing.go internal/domain/workflow/sharing_test.go
git commit -m "feat(workflow): a referência @handle/slug@vN, e o que ela recusa"
```

---

### Task 3: The schema — publications, grants, derivations, pins

**Files:**
- Create: `repos/dop-core/migrations/0021_flow_sharing.sql`

**Interfaces:**
- Consumes: `flows`, `flow_versions`, `accounts`, `users` from earlier migrations; the `revocation_policy` enum from Task 1.
- Produces: tables `flow_publications`, `flow_shares`, `flow_adoptions`, `account_flow_pins`, and the columns `flows.origin_ref`, `flows.origin_version`, `flows.origin_adopted_at`, `flows.revoked_at`.

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- ════════════════════════════════════════════════════════════════════════════
-- Sharing a flow between accounts.
--
-- Three invariants shape this schema:
--
--  1. A PUBLICATION FREEZES A VERSION. Publishing again publishes a newer one;
--     it never mutates what somebody already derived.
--  2. ADOPTION IS A COPY. The derived flow is an ordinary row in `flows`, with
--     the adopter's account_id. Nothing here lets one account read another's
--     flows — the only crossing is resolving a reference, and a `flow_shares`
--     row authorises it.
--  3. THE SAME FACT IS RECORDED ON BOTH SIDES. Provenance lives on the copy
--     (`flows.origin_*`) and the derivation lives with the publisher
--     (`flow_adoptions`), so neither side has to scan across accounts.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE flow_publications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  flow_id     uuid NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- The slug completes @handle/slug. The handle is not stored: it lives on the
  -- account and renaming an account must not orphan its publications.
  slug        text NOT NULL,
  version     int  NOT NULL,
  notes       text,
  withdrawn_at timestamptz,
  published_by uuid REFERENCES users(id),
  published_at timestamptz NOT NULL DEFAULT now(),

  -- (flow_id, version) has to exist: publishing a version that was never
  -- written is how a reference comes to resolve to nothing.
  FOREIGN KEY (flow_id, version) REFERENCES flow_versions(flow_id, version),
  -- One publication per (account, slug, version). Publishing the same version
  -- twice is a retry, not a second publication.
  CONSTRAINT flow_publication_unica UNIQUE (account_id, slug, version)
);

-- Resolving `@handle/slug` to the LATEST published version, in one index scan.
CREATE INDEX flow_publications_lookup
  ON flow_publications (account_id, slug, version DESC)
  WHERE withdrawn_at IS NULL;

CREATE TABLE flow_shares (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid NOT NULL REFERENCES flow_publications(id) ON DELETE CASCADE,
  to_account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- STAMPED at grant time from the publisher account's default. It is not read
  -- from the account at revocation time, so that the terms somebody accepted
  -- cannot be changed under them afterwards.
  revocation_policy revocation_policy NOT NULL,
  granted_by     uuid REFERENCES users(id),
  granted_at     timestamptz NOT NULL DEFAULT now(),
  revoked_at     timestamptz,
  CONSTRAINT flow_share_unico UNIQUE (publication_id, to_account_id)
);

CREATE INDEX flow_shares_to_account ON flow_shares (to_account_id) WHERE revoked_at IS NULL;

-- The PUBLISHER's index of where its flow went. It is the outbound half of the
-- same fact `flows.origin_*` records on the copy.
CREATE TABLE flow_adoptions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  publication_id uuid NOT NULL REFERENCES flow_publications(id) ON DELETE CASCADE,
  version        int  NOT NULL,
  by_account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- The derived flow, in the OTHER account. No FK on purpose: a cascade from
  -- here would let one account's delete reach into another's rows.
  flow_id        uuid NOT NULL,
  derived_at     timestamptz NOT NULL DEFAULT now(),
  revoked_at     timestamptz
);

CREATE INDEX flow_adoptions_by_publication ON flow_adoptions (publication_id);

-- Provenance on the COPY, and the revocation mark.
ALTER TABLE flows
  ADD COLUMN origin_ref        text,
  ADD COLUMN origin_version    int,
  ADD COLUMN origin_adopted_at timestamptz,
  ADD COLUMN revoked_at        timestamptz,
  -- Provenance is all-or-nothing: a flow that says where it came from says which
  -- version it came from. Half a provenance is worse than none, because it looks
  -- answerable.
  ADD CONSTRAINT flow_origem_completa CHECK (
    (origin_ref IS NULL     AND origin_version IS NULL     AND origin_adopted_at IS NULL) OR
    (origin_ref IS NOT NULL AND origin_version IS NOT NULL AND origin_adopted_at IS NOT NULL)
  );

-- The pin: which version of an inherited flow this account is on.
--
-- It exists because inheritance that crosses an OWNERSHIP boundary must not
-- change under the account that inherits it (spec §2.5). Inheritance inside one
-- account stays live and has no row here.
CREATE TABLE account_flow_pins (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  flow_id    uuid NOT NULL REFERENCES flows(id) ON DELETE CASCADE,
  version    int  NOT NULL,
  pinned_by  uuid REFERENCES users(id),
  pinned_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, flow_id),
  FOREIGN KEY (flow_id, version) REFERENCES flow_versions(flow_id, version)
);

-- +goose Down
DROP TABLE account_flow_pins;
ALTER TABLE flows
  DROP CONSTRAINT flow_origem_completa,
  DROP COLUMN revoked_at,
  DROP COLUMN origin_adopted_at,
  DROP COLUMN origin_version,
  DROP COLUMN origin_ref;
DROP TABLE flow_adoptions;
DROP TABLE flow_shares;
DROP TABLE flow_publications;
```

- [ ] **Step 2: Apply it against a scratch database and verify it is reversible**

Run:

```bash
cd repos/dop-core
docker run --rm -d --name dop-mig -e POSTGRES_PASSWORD=x -p 55432:5432 postgres:16
sleep 5
export DATABASE_URL="postgres://postgres:x@127.0.0.1:55432/postgres?sslmode=disable"
goose -dir migrations postgres "$DATABASE_URL" up
goose -dir migrations postgres "$DATABASE_URL" down
goose -dir migrations postgres "$DATABASE_URL" up
docker rm -f dop-mig
```

Expected: three clean runs. A `down` that fails is a migration that cannot be rolled back in production either.

- [ ] **Step 3: Commit**

```bash
cd repos/dop-core
git add migrations/0021_flow_sharing.sql
git commit -m "feat(db): publicação, grant, derivação e pin de fluxo"
```

---

### Task 4: The sharing port, its double, and `Publish` / `Withdraw`

**Files:**
- Create: `repos/dop-core/internal/domain/workflow/sharing_repository.go`
- Modify: `repos/dop-core/internal/domain/workflow/sharing.go` (the entities)
- Modify: `repos/dop-core/internal/domain/workflow/service.go` (the two methods)
- Modify: `repos/dop-core/internal/domain/workflow/sharing_test.go` (the double and the tests)

**Interfaces:**
- Consumes: `Repository.ByID`, `ctxutil.MustAccount`, `ctxutil.From`, `Access.RoleOf`, `canManage`.
- Produces: `workflow.Publication{ID, FlowID, AccountID, Slug string; Version int32; Notes string; PublishedBy string; PublishedAt, WithdrawnAt time.Time}`; the `SharingRepository` port; `Service.Publish(ctx, flowID, slug, notes, idempotencyKey string) (*Publication, error)`; `Service.Withdraw(ctx, publicationID string) error`.

- [ ] **Step 1: Write the failing tests**

```go
func TestPublishingFreezesAVersionAndNeedsManage(t *testing.T) {
	svc, env := newSharingHarness(t)
	// A developer does not publish: publishing exposes the account's work
	// outside it, and that is an act of governance.
	ctx := env.CtxAs(env.DeveloperID)
	if _, err := svc.Publish(ctx, env.FlowID, "backend-go", "", "k1"); errs.KindOf(err) != errs.KindPermission {
		t.Fatalf("a developer must not publish: %v", err)
	}

	ctx = env.CtxAs(env.OwnerID)
	pub, err := svc.Publish(ctx, env.FlowID, "backend-go", "first cut", "k2")
	if err != nil {
		t.Fatal(err)
	}
	if pub.Version != env.CurrentVersion {
		t.Fatalf("publishing has to freeze the CURRENT version, got %d", pub.Version)
	}
	// Repeating with the same key is a retry, not a second publication.
	again, err := svc.Publish(ctx, env.FlowID, "backend-go", "first cut", "k2")
	if err != nil || again.ID != pub.ID {
		t.Fatalf("the same key had to return the same publication: %v", err)
	}
	// A slug outside the reference's alphabet is refused HERE, not when somebody
	// later fails to type the reference.
	if _, err := svc.Publish(ctx, env.FlowID, "Backend Go", "", "k3"); errs.KindOf(err) != errs.KindInvalid {
		t.Fatalf("an unusable slug had to be refused: %v", err)
	}
}

func TestWithdrawStopsNewDerivationsAndNothingElse(t *testing.T) {
	svc, env := newSharingHarness(t)
	ctx := env.CtxAs(env.OwnerID)
	pub, err := svc.Publish(ctx, env.FlowID, "backend-go", "", "k1")
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Withdraw(ctx, pub.ID); err != nil {
		t.Fatal(err)
	}
	if err := svc.Withdraw(ctx, pub.ID); err != nil {
		t.Fatalf("withdrawing what is already withdrawn is success: %v", err)
	}
}
```

`newSharingHarness` goes in the same file. It is the only harness these tasks use, so write it once, here:

```go
type sharingEnv struct {
	AccountID, OtherAccountID, ThirdAccountID string
	OwnerID, DeveloperID, OtherOwnerID        string
	FlowID, PlatformFlowID, OtherProjectID    string
	CurrentVersion                            int32
	AccountDefault                            string // what the AccountDefaults port answers
	roles                                     map[string]string
	events                                    []ports.Event
	sharing                                   *fakeSharing
}

func (e *sharingEnv) CtxAs(userID string) context.Context {
	return ctxutil.With(context.Background(), ctxutil.Call{ActorID: userID, AccountID: e.AccountID})
}
func (e *sharingEnv) CtxAsOther(userID string) context.Context {
	return ctxutil.With(context.Background(), ctxutil.Call{ActorID: userID, AccountID: e.OtherAccountID})
}
func (e *sharingEnv) CtxAsThird() context.Context {
	return ctxutil.With(context.Background(), ctxutil.Call{ActorID: "u-third", AccountID: e.ThirdAccountID})
}
func (e *sharingEnv) FlowRevoked(id string) bool  { return e.sharing.revokedFlows[id] }
func (e *sharingEnv) FlowDeleted(id string) bool  { return e.sharing.deletedFlows[id] }
func (e *sharingEnv) LastEvent() ports.Event      { return e.events[len(e.events)-1] }

func newSharingHarness(t *testing.T) (*workflow.Service, *sharingEnv) {
	t.Helper()
	// Build on the doubles service_test.go already declares — fakeRepo, the
	// lineage double and fixedClock — and add only what sharing needs. A second
	// harness for the same domain is how two sets of tests start disagreeing
	// about what the domain does.
	panic("write me: assemble fakeRepo + fakeSharing + fake Access + fixedClock, seed the platform flow at v1, an account flow, and three accounts")
}
```

The `panic` is there so the first run fails loudly rather than passing empty. Replace it with the assembly before Step 4; `ctxutil.With`/`ctxutil.Call` may have different names in this repo — read `internal/platform/ctxutil/ctxutil.go` first and use whatever `service_test.go` already uses to build a context.

- [ ] **Step 2: Run and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestPublishing -v`
Expected: FAIL — `svc.Publish undefined`

- [ ] **Step 3: Declare the port**

`internal/domain/workflow/sharing_repository.go`:

```go
package workflow

import (
	"context"
	"time"
)

// SharingRepository is the persistence PORT for everything that crosses — or
// prepares to cross — an account boundary.
//
// It is separate from Repository on purpose: that one carries the invariants of
// a flow's identity and versions, and reopening it to add publication would put
// two unrelated sets of rules in one place.
//
// Every operation takes accountID except ResolvePublication, which is the ONE
// deliberate crossing: it reads another account's publication, and it is
// authorised by a share row, not by the caller's word.
type SharingRepository interface {
	CreatePublication(ctx context.Context, p *Publication, idempotencyKey string) (*Publication, error)
	PublicationByID(ctx context.Context, accountID, id string) (*Publication, error)
	Withdraw(ctx context.Context, accountID, id string, at time.Time) error

	// ResolvePublication answers a reference for a caller. It returns NotFound —
	// never Permission — when the caller holds no share: whether a flow exists
	// in another account is not something an outsider gets to learn.
	ResolvePublication(ctx context.Context, callerAccountID string, ref PublicationRef) (*Publication, error)

	CreateShare(ctx context.Context, s *Share, idempotencyKey string) (*Share, error)
	ShareByID(ctx context.Context, accountID, id string) (*Share, error)
	SharesOfPublication(ctx context.Context, accountID, publicationID string) ([]Share, error)

	// RevokeShare does the WHOLE revocation in one transaction: the share, the
	// copies the policy reaches, their adoption records, and both events.
	//
	// It is one call and not four because a crash between four calls leaves a
	// share revoked with its copies untouched — a half-revocation nobody would
	// notice until somebody used a flow that was supposed to be gone. The
	// transaction and the outbox are the adapter's job (ADR-0014); the domain's
	// job is to decide WHAT the policy reaches and hand it over.
	RevokeShare(ctx context.Context, accountID string, rev Revocation) error

	RecordAdoption(ctx context.Context, a *Adoption) error
	AdoptionsOfPublication(ctx context.Context, accountID, publicationID string) ([]Adoption, error)

	Pin(ctx context.Context, accountID, flowID string, version int32, by string, at time.Time) error
	PinOf(ctx context.Context, accountID, flowID string) (int32, bool, error)
}
```

- [ ] **Step 4: Add the entities**

Append to `internal/domain/workflow/sharing.go`:

```go
// Publication is one VERSION of a flow made addressable under @handle/slug.
type Publication struct {
	ID           string
	FlowID       string
	AccountID    string
	Slug         string
	Version      int32
	Notes        string
	PublishedBy  string
	PublishedAt  time.Time
	WithdrawnAt  time.Time // zero = in circulation
}

func (p Publication) Withdrawn() bool { return !p.WithdrawnAt.IsZero() }

// Share is permission for ONE account to derive from a publication, with the
// revocation terms stamped at the moment it was granted.
type Share struct {
	ID               string
	PublicationID    string
	ToAccountID      string
	RevocationPolicy RevocationPolicy
	GrantedBy        string
	GrantedAt        time.Time
	RevokedAt        time.Time
}

func (s Share) Revoked() bool { return !s.RevokedAt.IsZero() }

// Adoption is the PUBLISHER's record that somebody derived a copy. It is the
// outbound half of the provenance the copy carries.
type Adoption struct {
	ID            string
	PublicationID string
	Version       int32
	ByAccountID   string
	FlowID        string // the copy, in the other account
	DerivedAt     time.Time
	RevokedAt     time.Time
}

// Origin is the provenance carried BY the copy.
type Origin struct {
	Ref       string
	Version   int32
	AdoptedAt time.Time
}
```

Add `Origin *Origin` and `RevokedAt time.Time` to the `Flow` struct in `entity.go`.

- [ ] **Step 5: Implement `Publish` and `Withdraw`**

In `internal/domain/workflow/service.go`:

```go
// Publish makes the flow's CURRENT version addressable as @handle/slug@vN.
//
// It freezes a version rather than pointing at the flow: publishing again
// publishes a newer one, and what somebody already derived never moves under
// them.
func (s *Service) Publish(ctx context.Context, flowID, slug, notes, idempotencyKey string) (*Publication, error) {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return nil, err
	}
	call, _ := ctxutil.From(ctx)
	if call.ActorID == "" {
		return nil, errs.New(errs.KindUnauthorized, "actor not identified")
	}
	role, err := s.access.RoleOf(ctx, call.ActorID, accountID)
	if err != nil {
		return nil, err
	}
	if !canManage(role) {
		return nil, errs.Permission("publishing a flow outside the account requires owner or admin")
	}
	// The slug is validated with the SAME rule the reference parser uses: a slug
	// accepted here and unusable in a reference would produce a publication
	// nobody can address.
	if !refPart.MatchString(slug) {
		return nil, errs.Invalid("%q is not a usable name for a reference: lowercase letters, digits and hyphens", slug)
	}
	f, err := s.repo.ByID(ctx, accountID, flowID)
	if err != nil {
		return nil, err
	}
	if f.OwnerScope == ScopePlatform {
		return nil, errs.Precondition("the platform's flow is inherited by the chain, not published for adoption")
	}
	p := Publication{
		FlowID: f.ID, AccountID: accountID, Slug: slug, Version: f.Version,
		Notes: notes, PublishedBy: call.ActorID, PublishedAt: s.now(),
	}
	return s.sharing.CreatePublication(ctx, &p, s.writeKey(idempotencyKey, "publish", *f, f.Version))
}

// Withdraw takes a publication out of circulation. It reaches NOBODY who has
// already derived: that is revocation's job, and it has its own policy.
func (s *Service) Withdraw(ctx context.Context, publicationID string) error {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return err
	}
	call, _ := ctxutil.From(ctx)
	role, err := s.access.RoleOf(ctx, call.ActorID, accountID)
	if err != nil {
		return err
	}
	if !canManage(role) {
		return errs.Permission("withdrawing a publication requires owner or admin")
	}
	return s.sharing.Withdraw(ctx, accountID, publicationID, s.now())
}
```

Add the `sharing SharingRepository` field to `Service` and to `NewService`, and update every construction site (`internal/app/register.go`, the tests).

- [ ] **Step 6: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -v && go build ./...`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
cd repos/dop-core
git add internal/domain/workflow/ internal/app/
git commit -m "feat(workflow): publicar e retirar de circulação uma versão"
```

---

### Task 5: `Grant` and `Revoke` — the policy is stamped, not looked up

**Files:**
- Modify: `repos/dop-core/internal/domain/workflow/service.go`
- Modify: `repos/dop-core/internal/domain/workflow/sharing_test.go`

**Interfaces:**
- Consumes: `SharingRepository.CreateShare` / `RevokeShare` / `SharesOfPublication`, `Publication`, `RevocationPolicy`.
- Produces: `Service.Grant(ctx, publicationID, toAccountID string, idempotencyKey string) (*Share, error)`; `Service.Revoke(ctx, shareID string) error`. A new narrow port `AccountDefaults` with `DefaultRevocationPolicy(ctx context.Context, accountID string) (string, error)`.

- [ ] **Step 1: Write the failing test**

```go
func TestTheGrantStampsThePolicyItWasMadeUnder(t *testing.T) {
	svc, env := newSharingHarness(t)
	ctx := env.CtxAs(env.OwnerID)
	pub, err := svc.Publish(ctx, env.FlowID, "backend-go", "", "k1")
	if err != nil {
		t.Fatal(err)
	}

	env.AccountDefault = "prospective"
	share, err := svc.Grant(ctx, pub.ID, env.OtherAccountID, "g1")
	if err != nil {
		t.Fatal(err)
	}
	if share.RevocationPolicy != workflow.PolicyProspective {
		t.Fatalf("the grant had to carry the default in force, got %q", share.RevocationPolicy)
	}

	// Changing the account's default AFTERWARDS must not change the terms of a
	// grant somebody already accepted.
	env.AccountDefault = "terminate"
	got, err := svc.SharesOf(ctx, pub.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got[0].RevocationPolicy != workflow.PolicyProspective {
		t.Fatal("the account's default changed the terms of an existing grant: the stamp is not being honoured")
	}
}
```

- [ ] **Step 2: Run and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestTheGrantStamps -v`
Expected: FAIL — `svc.Grant undefined`

- [ ] **Step 3: Implement**

```go
// AccountDefaults is the NARROW port into identity: the flow domain needs one
// value from an account and not the account.
type AccountDefaults interface {
	DefaultRevocationPolicy(ctx context.Context, accountID string) (string, error)
}

// Grant lets ONE account derive from a publication.
//
// The revocation policy is COPIED here from the publisher's default and stored
// on the grant. Reading it at revocation time would let the publisher change
// the terms after they were accepted — the difference between "no new
// derivations" and "your running demand stops now".
func (s *Service) Grant(ctx context.Context, publicationID, toAccountID, idempotencyKey string) (*Share, error) {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return nil, err
	}
	call, _ := ctxutil.From(ctx)
	role, err := s.access.RoleOf(ctx, call.ActorID, accountID)
	if err != nil {
		return nil, err
	}
	if !canManage(role) {
		return nil, errs.Permission("granting a flow requires owner or admin")
	}
	if strings.TrimSpace(toAccountID) == "" {
		return nil, errs.Invalid("no account to grant to")
	}
	if toAccountID == accountID {
		return nil, errs.Invalid("an account already sees its own flows: there is nothing to grant")
	}
	pub, err := s.sharing.PublicationByID(ctx, accountID, publicationID)
	if err != nil {
		return nil, err
	}
	if pub.Withdrawn() {
		return nil, errs.Precondition("this publication was withdrawn: publish a version again before granting it")
	}
	raw, err := s.defaults.DefaultRevocationPolicy(ctx, accountID)
	if err != nil {
		return nil, err
	}
	policy := RevocationPolicy(raw)
	if !ValidRevocationPolicy(policy) {
		policy = DefaultRevocationPolicy
	}
	sh := Share{
		PublicationID: pub.ID, ToAccountID: toAccountID,
		RevocationPolicy: policy, GrantedBy: call.ActorID, GrantedAt: s.now(),
	}
	return s.sharing.CreateShare(ctx, &sh, idem.Key(idempotencyKey, "grant", pub.ID, toAccountID))
}

// SharesOf lists who a publication was granted to.
func (s *Service) SharesOf(ctx context.Context, publicationID string) ([]Share, error) {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return nil, err
	}
	return s.sharing.SharesOfPublication(ctx, accountID, publicationID)
}
```

Add a `defaults AccountDefaults` field to `Service` and a parameter to `NewService`, beside the `sharing` field Task 4 added, and update every construction site.

If `idem.Key` does not have that signature, build the key with `strings.Join` as `writeKey` already does in this file.

`Revoke` comes in Task 6, because what it does to derived copies depends on the derivation records that task creates.

- [ ] **Step 4: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/workflow/
git commit -m "feat(workflow): grant com a política carimbada no momento da concessão"
```

---

### Task 6: `Derive` — the copy, and the provenance on both sides

**Files:**
- Modify: `repos/dop-core/internal/domain/workflow/service.go`
- Modify: `repos/dop-core/internal/domain/workflow/sharing_test.go`

**Interfaces:**
- Consumes: `SharingRepository.ResolvePublication` / `RecordAdoption`, `Repository.VersionOf`, `Repository.Create`, `resolveOwner`.
- Produces: `Service.Derive(ctx, rawRef string, target ScopeRef, idempotencyKey string) (*Flow, error)`.

- [ ] **Step 1: Write the failing test**

```go
func TestDerivingCopiesAndRecordsBothSides(t *testing.T) {
	svc, env := newSharingHarness(t)
	pub, err := svc.Publish(env.CtxAs(env.OwnerID), env.FlowID, "backend-go", "", "k1")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Grant(env.CtxAs(env.OwnerID), pub.ID, env.OtherAccountID, "g1"); err != nil {
		t.Fatal(err)
	}

	// The other account derives it at ITS OWN project level.
	ctx := env.CtxAsOther(env.OtherOwnerID)
	target := workflow.ScopeRef{Scope: workflow.ScopeProject, ID: env.OtherProjectID}
	copied, err := svc.Derive(ctx, "@acme/backend-go", target, "d1")
	if err != nil {
		t.Fatal(err)
	}
	if copied.AccountID != env.OtherAccountID {
		t.Fatal("the copy has to belong to whoever derived it")
	}
	if copied.Origin == nil || copied.Origin.Ref != "@acme/backend-go" || copied.Origin.Version != pub.Version {
		t.Fatalf("the copy does not carry where it came from: %+v", copied.Origin)
	}
	// The publisher's side records where it went, so it never has to scan
	// another account to find out.
	ads, err := svc.AdoptionsOf(env.CtxAs(env.OwnerID), pub.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(ads) != 1 || ads[0].ByAccountID != env.OtherAccountID || ads[0].FlowID != copied.ID {
		t.Fatalf("the derivation was not recorded on the publisher's side: %+v", ads)
	}
	// Without a grant, the reference does not even exist for the caller.
	if _, err := svc.Derive(env.CtxAsThird(), "@acme/backend-go", target, "d2"); errs.KindOf(err) != errs.KindNotFound {
		t.Fatalf("an account with no grant has to get not-found, not permission-denied: %v", err)
	}
}
```

- [ ] **Step 2: Run and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestDeriving -v`
Expected: FAIL — `svc.Derive undefined`

- [ ] **Step 3: Implement**

```go
// Derive adopts a published flow: it creates a COPY in the caller's account, at
// the level the caller chooses, carrying where it came from.
//
// A copy and not a reference, because a live reference would let one company's
// edit change how another company's development runs, and revoking it would
// break demands already moving.
func (s *Service) Derive(ctx context.Context, rawRef string, target ScopeRef, idempotencyKey string) (*Flow, error) {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return nil, err
	}
	call, _ := ctxutil.From(ctx)
	if call.ActorID == "" {
		return nil, errs.New(errs.KindUnauthorized, "actor not identified")
	}
	ref, err := ParseRef(rawRef)
	if err != nil {
		return nil, err
	}
	// The one deliberate crossing. It answers NotFound when there is no grant:
	// whether a flow exists in another account is not an outsider's to learn.
	pub, err := s.sharing.ResolvePublication(ctx, accountID, ref)
	if err != nil {
		return nil, err
	}
	// The CONTENT comes from the publisher's frozen version, read by id and
	// version — the same path a demand uses to read what it froze on.
	src, err := s.repo.VersionOf(ctx, pub.AccountID, pub.FlowID, pub.Version)
	if err != nil {
		return nil, err
	}
	owner, err := s.resolveOwner(ctx, accountID, target)
	if err != nil {
		return nil, err
	}
	if owner.Scope == ScopePlatform {
		return nil, errs.Permission("a derived flow does not go into the platform catalogue")
	}
	now := s.now()
	copied := Flow{
		AccountID: accountID, OwnerScope: owner.Scope, OwnerID: owner.ID,
		Name: src.Name, Description: src.Description, Version: 1, Stages: src.Stages,
		Origin:    &Origin{Ref: ref.WithoutVersion().String(), Version: pub.Version, AdoptedAt: now},
		CreatedBy: call.ActorID, CreatedAt: now, UpdatedAt: now,
	}
	out, err := s.repo.Create(ctx, &copied, s.writeKey(idempotencyKey, "derive", copied, 0))
	if err != nil {
		return nil, err
	}
	// The publisher's half of the same fact. It is written after the copy
	// exists, and it carries the copy's id — which is what makes revocation
	// able to reach it later without scanning anything.
	if err := s.sharing.RecordAdoption(ctx, &Adoption{
		PublicationID: pub.ID, Version: pub.Version, ByAccountID: accountID,
		FlowID: out.ID, DerivedAt: now,
	}); err != nil {
		return nil, err
	}
	return out, nil
}

// AdoptionsOf lists who derived from a publication.
func (s *Service) AdoptionsOf(ctx context.Context, publicationID string) ([]Adoption, error) {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return nil, err
	}
	return s.sharing.AdoptionsOfPublication(ctx, accountID, publicationID)
}
```

Add to `sharing.go`:

```go
// WithoutVersion is what gets stored as provenance: the reference identifies
// WHERE it came from, and the version is a field of its own. Storing
// "@acme/backend-go@v3" in Ref would put the same fact in two places and let
// them disagree.
func (r PublicationRef) WithoutVersion() PublicationRef {
	r.Version = 0
	return r
}
```

- [ ] **Step 4: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/workflow/
git commit -m "feat(workflow): derivar uma publicação, com procedência nos dois lados"
```

---

### Task 7: `Revoke`, and what each policy reaches

**Files:**
- Modify: `repos/dop-core/internal/domain/workflow/service.go`
- Modify: `repos/dop-core/internal/domain/workflow/sharing_test.go`

**Interfaces:**
- Consumes: `SharingRepository.ShareByID` / `AdoptionsOfPublication` / `RevokeShare`, `Access.RoleOf`.
- Produces: `Service.Revoke(ctx, shareID string) error`; the types `workflow.Revocation` and `workflow.AdoptionRef`. The events themselves are Task 9's, written in the adapter's transaction.

- [ ] **Step 1: Write the failing test**

```go
func TestWhatARevocationReachesDependsOnTheStampedPolicy(t *testing.T) {
	for _, tc := range []struct {
		policy       workflow.RevocationPolicy
		copyRevoked  bool
	}{
		{workflow.PolicyProspective, false}, // reaches the grant only
		{workflow.PolicyDrain, true},
		{workflow.PolicyTerminate, true},
	} {
		t.Run(string(tc.policy), func(t *testing.T) {
			svc, env := newSharingHarness(t)
			env.AccountDefault = string(tc.policy)
			ctx := env.CtxAs(env.OwnerID)
			pub, _ := svc.Publish(ctx, env.FlowID, "backend-go", "", "k1")
			share, _ := svc.Grant(ctx, pub.ID, env.OtherAccountID, "g1")
			copied, err := svc.Derive(env.CtxAsOther(env.OtherOwnerID),
				"@acme/backend-go", workflow.ScopeRef{Scope: workflow.ScopeProject, ID: env.OtherProjectID}, "d1")
			if err != nil {
				t.Fatal(err)
			}
			if err := svc.Revoke(ctx, share.ID); err != nil {
				t.Fatal(err)
			}
			if got := env.FlowRevoked(copied.ID); got != tc.copyRevoked {
				t.Fatalf("under %s the copy revoked = %v, wanted %v", tc.policy, got, tc.copyRevoked)
			}
			// The copy is never DELETED: the adopter's edits, and the audit of a
			// demand that already ran under it, have to survive.
			if env.FlowDeleted(copied.ID) {
				t.Fatal("revoking deleted the copy — it must only change its state")
			}
			// The events are written by the adapter, in the same transaction
			// (ADR-0014), so what the DOMAIN owes is the decision: which
			// adoptions the policy reaches. Task 9 proves the events exist.
			rev := env.LastRevocation()
			if rev.Policy != tc.policy {
				t.Fatalf("the revocation carried %q, wanted %q", rev.Policy, tc.policy)
			}
			if want := map[bool]int{true: 1, false: 0}[tc.copyRevoked]; len(rev.Adoptions) != want {
				t.Fatalf("under %s the revocation reached %d adoptions, wanted %d", tc.policy, len(rev.Adoptions), want)
			}
		})
	}
}
```

- [ ] **Step 2: Run and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestWhatARevocation -v`
Expected: FAIL — `svc.Revoke undefined`

- [ ] **Step 3: Implement**

```go
// Revoke withdraws a grant. WHAT it reaches is the policy stamped on that grant
// when it was made, never the account's current default.
//
// Under `prospective` it reaches the grant and nothing else. Under `drain` and
// `terminate` it also marks the copies derived under it as revoked — a state
// change, never a deletion: the adopter's own edits and the audit trail of a
// demand that already ran have to survive, or a green becomes uncheckable
// (ADR-0005's argument).
//
// The DIFFERENCE between drain and terminate is what happens to demands already
// running, and that does not happen here: this emits the event carrying the
// policy, and a consumer acts on it. Putting demand control in this service
// would make the flow domain a client of the demand domain over one decision.
func (s *Service) Revoke(ctx context.Context, shareID string) error {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return err
	}
	call, _ := ctxutil.From(ctx)
	role, err := s.access.RoleOf(ctx, call.ActorID, accountID)
	if err != nil {
		return err
	}
	if !canManage(role) {
		return errs.Permission("revoking a grant requires owner or admin")
	}
	share, err := s.sharing.ShareByID(ctx, accountID, shareID)
	if err != nil {
		return err
	}
	if share.Revoked() {
		return nil // idempotent: the outcome asked for is already true
	}
	now := s.now()
	// The domain decides WHAT the policy reaches; the adapter writes it, all of
	// it, in one transaction.
	rev := Revocation{
		ShareID: share.ID, PublicationID: share.PublicationID,
		ToAccountID: share.ToAccountID, Policy: share.RevocationPolicy, At: now,
	}
	if share.RevocationPolicy != PolicyProspective {
		ads, err := s.sharing.AdoptionsOfPublication(ctx, accountID, share.PublicationID)
		if err != nil {
			return err
		}
		for _, a := range ads {
			if a.ByAccountID != share.ToAccountID || !a.RevokedAt.IsZero() {
				continue
			}
			rev.Adoptions = append(rev.Adoptions, AdoptionRef{ID: a.ID, FlowID: a.FlowID})
		}
	}
	return s.sharing.RevokeShare(ctx, accountID, rev)
}

// Revocation is everything one revocation has to write, handed over as one
// value so the adapter can do it in one transaction.
type Revocation struct {
	ShareID       string
	PublicationID string
	ToAccountID   string
	Policy        RevocationPolicy
	// Adoptions is EMPTY under `prospective`: that policy reaches the grant and
	// nothing else.
	Adoptions []AdoptionRef
	At        time.Time
}

// AdoptionRef is one derivation the revocation reaches: the record on the
// publisher's side, and the copy in the other account.
type AdoptionRef struct {
	ID     string
	FlowID string
}
```

Put `Revocation` and `AdoptionRef` in `sharing.go` beside the other entities.

**The events are the ADAPTER's, not this service's** (ruling R1). `internal/adapter/postgres/outbox.go` writes the event and the outbox row inside the transaction that changes the state — that is ADR-0014, and no domain service in this codebase publishes anything. Task 9 emits both events there, inside `RevokeShare`'s transaction, using `ports.Event`'s real fields: `Aggregate: "flow"`, `AggregateID: <share id>`, `Type: "flow.share.revoked"` / `"flow.grant.revoked"`, and `Payload []byte` holding the marshalled JSON.

- [ ] **Step 4: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -v`
Expected: PASS

- [ ] **Step 5: Record what this task deliberately does NOT do**

Append a row to `docs/ROADMAP.md`'s pending table:

```
| P-46 | **Stopping a demand when a flow grant is revoked.** `flow.share.revoked` carries the policy and the flows it reached; nothing consumes it yet, so `drain` and `terminate` behave identically today — the copy is revoked and running demands finish either way. Making `terminate` real means a consumer that stops a demand at its current gate and raises an attention item, which is a reaction to an event and therefore **P-29's mechanism**, not a switch written by hand | dop-core; waits on P-29 |
```

- [ ] **Step 6: Commit**

```bash
cd repos/dop-core && git add internal/domain/workflow/ && \
  git commit -m "feat(workflow): revogar, e o que cada política alcança"
cd ../.. && git add docs/ROADMAP.md && \
  git commit -m "docs: P-46, o consumidor que faz terminate ser diferente de drain"
```

---

### Task 8: The pin — inheritance across an ownership boundary

**Files:**
- Modify: `repos/dop-core/internal/domain/workflow/service.go` (`Resolve`)
- Modify: `repos/dop-core/internal/domain/workflow/sharing_test.go`

**Interfaces:**
- Consumes: `SharingRepository.PinOf` / `Pin`, `Repository.VersionOf`, the existing `Resolve`.
- Produces: `Service.BumpPin(ctx, flowID string, version int32) error`; `Resolve` returning the pinned version when the effective flow's owner is not the caller's account.

- [ ] **Step 1: Write the failing test**

```go
func TestInheritanceAcrossAnOwnerIsPinnedAndInsideOneAccountIsLive(t *testing.T) {
	svc, env := newSharingHarness(t)
	// The platform's flow is at v1 and the account is pinned to it.
	eff, err := svc.Resolve(env.CtxAsOther(env.OtherOwnerID), workflow.ScopeProject, env.OtherProjectID)
	if err != nil {
		t.Fatal(err)
	}
	if eff.Flow.Version != 1 {
		t.Fatalf("started on version %d", eff.Flow.Version)
	}
	// The platform publishes v2. The account must NOT move.
	env.AppendPlatformVersion()
	eff, err = svc.Resolve(env.CtxAsOther(env.OtherOwnerID), workflow.ScopeProject, env.OtherProjectID)
	if err != nil {
		t.Fatal(err)
	}
	if eff.Flow.Version != 1 {
		t.Fatal("a change on the other side of an ownership boundary reached the account by itself")
	}
	// Bumping is deliberate.
	if err := svc.BumpPin(env.CtxAsOther(env.OtherOwnerID), env.PlatformFlowID, 2); err != nil {
		t.Fatal(err)
	}
	eff, _ = svc.Resolve(env.CtxAsOther(env.OtherOwnerID), workflow.ScopeProject, env.OtherProjectID)
	if eff.Flow.Version != 2 {
		t.Fatal("after bumping the pin the new version had to apply")
	}

	// Inside ONE account inheritance stays live: same owner, no pin, no ceremony.
	env.AppendAccountVersion() // the account's own flow moves to v2
	eff, _ = svc.Resolve(env.CtxAsOther(env.OtherOwnerID), workflow.ScopeProject, env.OtherProjectID)
	if eff.Flow.OwnerScope == workflow.ScopeAccount && eff.Flow.Version != 2 {
		t.Fatal("inheritance inside one account must not be pinned")
	}
}
```

- [ ] **Step 2: Run and see it fail**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -run TestInheritanceAcross -v`
Expected: FAIL — `svc.BumpPin undefined`

- [ ] **Step 3: Implement**

At the end of `Resolve`, once the effective flow has been chosen:

```go
	// A flow whose owner is not this account crossed an OWNERSHIP boundary, and
	// the version that applies is the pinned one — not the newest. Whoever
	// changes it is not whoever lives with the change, and an automatic change
	// to how somebody's development runs is what the copy-versus-reference
	// decision refused in the first place (spec §2.5).
	//
	// Inheritance INSIDE one account is deliberately untouched: there, the
	// person changing the flow is the same owner who lives with it, and a pin
	// would be ceremony.
	if chosen.AccountID != accountID {
		version, pinned, err := s.sharing.PinOf(ctx, accountID, chosen.ID)
		if err != nil {
			return nil, err
		}
		if !pinned {
			// A first resolution pins to what is current, so the account starts
			// on a known version instead of on "whatever is newest today".
			version = chosen.Version
			if err := s.sharing.Pin(ctx, accountID, chosen.ID, version, "", s.now()); err != nil {
				return nil, err
			}
		}
		if version != chosen.Version {
			frozen, err := s.repo.VersionOf(ctx, chosen.AccountID, chosen.ID, version)
			if err != nil {
				return nil, err
			}
			chosen = *frozen
		}
	}
```

And:

```go
// BumpPin moves the account onto a newer version of an inherited flow. It is
// the deliberate act that a live reference would have taken away.
func (s *Service) BumpPin(ctx context.Context, flowID string, version int32) error {
	accountID, err := ctxutil.MustAccount(ctx)
	if err != nil {
		return err
	}
	call, _ := ctxutil.From(ctx)
	role, err := s.access.RoleOf(ctx, call.ActorID, accountID)
	if err != nil {
		return err
	}
	if !canManage(role) {
		return errs.Permission("moving the account onto another version requires owner or admin")
	}
	if version <= 0 {
		return errs.Invalid("version has to be positive")
	}
	return s.sharing.Pin(ctx, accountID, flowID, version, call.ActorID, s.now())
}
```

Note for the implementer: the platform catalogue's flows have `AccountID == ""`, so `chosen.AccountID != accountID` is true for them — which is exactly the intended behaviour.

- [ ] **Step 4: Run the tests**

Run: `cd repos/dop-core && go test ./internal/domain/workflow/ -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add internal/domain/workflow/
git commit -m "feat(workflow): herança que cruza dono é pinada; dentro da conta segue viva"
```

---

### Task 9: The Postgres adapter

**Files:**
- Create: `repos/dop-core/internal/adapter/postgres/workflow_sharing.go`
- Create: `repos/dop-core/test/integration/flow_sharing_test.go`

**Interfaces:**
- Consumes: the `SharingRepository` port from Task 4, the schema from Task 3, `pgxpool.Pool`.
- Produces: `postgres.NewWorkflowSharing(pool *pgxpool.Pool) workflow.SharingRepository`.

- [ ] **Step 1: Write the failing integration test**

There are **no tests under `internal/adapter/postgres/`** — this repo's database tests live in `test/integration/`, behind the `integration` build tag, using the `openPool(t)` helper from `outbox_test.go` and per-file seed helpers. Write `test/integration/flow_sharing_test.go` the way `agentmetrics_test.go` and `secondfactor_test.go` are written, including your own `seedThreeAccounts`/`seedFlow`/`handleOf` in that file:

```go
//go:build integration

package postgres_test

func TestResolvePublicationOnlyAnswersToWhoWasGranted(t *testing.T) {
	pool := openPool(t) // test/integration/outbox_test.go
	ctx := context.Background()
	repo := postgres.NewWorkflowSharing(pool)
	pubAccount, otherAccount, third := seedThreeAccounts(t, pool)
	flowID, version := seedFlow(t, pool, pubAccount)

	pub, err := repo.CreatePublication(ctx, &workflow.Publication{
		FlowID: flowID, AccountID: pubAccount, Slug: "backend-go", Version: version,
	}, "k1")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := repo.CreateShare(ctx, &workflow.Share{
		PublicationID: pub.ID, ToAccountID: otherAccount,
		RevocationPolicy: workflow.PolicyProspective,
	}, "g1"); err != nil {
		t.Fatal(err)
	}

	ref := workflow.PublicationRef{Handle: handleOf(t, pool, pubAccount), Slug: "backend-go"}
	if _, err := repo.ResolvePublication(ctx, otherAccount, ref); err != nil {
		t.Fatalf("the granted account had to resolve it: %v", err)
	}
	// No grant, no existence. NotFound and never Permission: whether a flow
	// exists in another account is not an outsider's to learn.
	if _, err := repo.ResolvePublication(ctx, third, ref); errs.KindOf(err) != errs.KindNotFound {
		t.Fatalf("an account with no grant had to get not-found: %v", err)
	}
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `cd repos/dop-core && go test ./test/integration/ -tags=integration -run TestResolvePublication -v`
Expected: FAIL — `undefined: postgres.NewWorkflowSharing`

- [ ] **Step 3: Implement the adapter**

Write `internal/adapter/postgres/workflow_sharing.go`. Two methods are given in full — the write pattern and the read that authorises the crossing. The remaining eleven follow the same two shapes, with the error mapping and `pgx` helpers `internal/adapter/postgres/workflow.go` already uses.

The write pattern, with idempotency handled the way the rest of this adapter handles it — the unique key collides and the existing row comes back, rather than a second row being created:

```go
func (r *WorkflowSharing) CreatePublication(ctx context.Context, p *workflow.Publication, key string) (*workflow.Publication, error) {
	const q = `
INSERT INTO flow_publications (flow_id, account_id, slug, version, notes, published_by)
VALUES ($1, $2, $3, $4, NULLIF($5, ''), $6)
ON CONFLICT (account_id, slug, version) DO UPDATE SET slug = EXCLUDED.slug
RETURNING id, flow_id, account_id, slug, version, COALESCE(notes, ''), published_at, withdrawn_at`
	var out workflow.Publication
	var withdrawn *time.Time
	err := r.pool.QueryRow(ctx, q, p.FlowID, p.AccountID, p.Slug, p.Version, p.Notes, nullUUID(p.PublishedBy)).
		Scan(&out.ID, &out.FlowID, &out.AccountID, &out.Slug, &out.Version, &out.Notes, &out.PublishedAt, &withdrawn)
	if err != nil {
		return nil, mapError(err, "publishing the flow")
	}
	if withdrawn != nil {
		out.WithdrawnAt = *withdrawn
	}
	return &out, nil
}
```

The `DO UPDATE SET slug = EXCLUDED.slug` is a no-op write that exists only so `RETURNING` fires on a conflict: a plain `DO NOTHING` returns no row, and the retry would look like a failure.

The resolution, which is where the boundary crossing is authorised:

```sql
SELECT p.id, p.flow_id, p.account_id, p.slug, p.version, p.notes,
       p.published_by, p.published_at, p.withdrawn_at
  FROM flow_publications p
  JOIN accounts a   ON a.id = p.account_id
  JOIN flow_shares s ON s.publication_id = p.id
 WHERE a.handle = $1
   AND p.slug   = $2
   AND ($3::int IS NULL OR p.version = $3)
   AND p.withdrawn_at IS NULL
   AND s.to_account_id = $4
   AND s.revoked_at IS NULL
 ORDER BY p.version DESC
 LIMIT 1
```

```go
func (r *WorkflowSharing) ResolvePublication(ctx context.Context, callerAccountID string, ref workflow.PublicationRef) (*workflow.Publication, error) {
	var version *int32
	if ref.Pinned() {
		v := ref.Version
		version = &v
	}
	var out workflow.Publication
	err := r.pool.QueryRow(ctx, resolveQuery, ref.Handle, ref.Slug, version, callerAccountID).
		Scan(&out.ID, &out.FlowID, &out.AccountID, &out.Slug, &out.Version, &out.Notes,
			&out.PublishedBy, &out.PublishedAt, &out.WithdrawnAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errs.NotFound("no flow published as %s", ref)
	}
	if err != nil {
		return nil, mapError(err, "resolving the reference")
	}
	return &out, nil
}
```

The join on `flow_shares` is the authorisation: with no share row there is no result, and the caller gets NotFound without the code having to decide anything. It is also why the refusal says "no flow published as @acme/backend-go" and never "you do not have access" — the second sentence confirms the flow exists.

- [ ] **Step 4: Run the test**

Run: `cd repos/dop-core && go test ./test/integration/ -tags=integration -run TestResolvePublication -v`
Expected: PASS

- [ ] **Step 5: Wire it in the composition root**

In `internal/app/register.go` (or wherever `workflow.NewService` is constructed), pass `postgres.NewWorkflowSharing(deps.Pool)` and an `AccountDefaults` implementation reading `accounts.default_revocation_policy`.

- [ ] **Step 6: Run everything**

Run: `cd repos/dop-core && go build ./... && go test ./internal/... && go vet ./...`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
cd repos/dop-core
git add internal/adapter/postgres/ internal/app/
git commit -m "feat(postgres): o adaptador de compartilhamento, com a autorização no join"
```

---

### Task 10: The contract — proto and gRPC

**Files:**
- Modify: `repos/dop-core/api/proto/dop/v1/workflow.proto`
- Modify: `repos/dop-core/internal/app/grpc/workflow.go`

**Interfaces:**
- Consumes: every `Service` method from tasks 4 to 8.
- Produces: RPCs `PublishFlow`, `WithdrawFlow`, `GrantFlow`, `RevokeFlowGrant`, `DeriveFlow`, `BumpFlowPin`, `ListFlowShares`, `ListFlowAdoptions`.

- [ ] **Step 1: Add the messages and RPCs to the proto**

Follow the conventions ADR-0013 fixes and this file already uses: a `Ref` instead of a loose id, identity in the metadata and never in the body, server-side streaming only where something is live (nothing here is).

```proto
message PublishFlowRequest {
  string flow_id = 1;
  string slug    = 2;   // completes @handle/slug
  string notes   = 3;
  string idempotency_key = 4;
}

message FlowPublication {
  string id = 1;
  string flow_id = 2;
  string reference = 3;  // "@acme/backend-go@v3", formatted by the server
  int32  version = 4;
  string notes = 5;
  google.protobuf.Timestamp published_at = 6;
  google.protobuf.Timestamp withdrawn_at = 7;
}

message DeriveFlowRequest {
  string reference = 1;             // "@acme/backend-go" or pinned
  dop.v1.ScopeRef target = 2;       // where to install the copy
  string idempotency_key = 3;
}
```

The reference is formatted by the server rather than assembled by each client: three clients building `@handle/slug@vN` themselves is three places for the format to drift.

- [ ] **Step 2: Regenerate and check the break report**

Run:

```bash
cd repos/dop-core
make proto
make proto-breaking
```

Expected: generation succeeds; the breaking-change report shows only ADDITIONS. Anything else means an existing message was disturbed — fix it before continuing.

- [ ] **Step 3: Implement the handlers**

In `internal/app/grpc/workflow.go`, one thin method per RPC: translate the request, call the service, translate the answer. No rules here — every refusal already lives in the domain, and duplicating one in the handler is how the two drift apart.

- [ ] **Step 4: Run everything**

Run: `cd repos/dop-core && go build ./... && go test ./internal/... && go vet ./...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd repos/dop-core
git add api/ internal/app/grpc/
git commit -m "feat(api): as RPCs de publicação, grant, derivação e pin"
```

---

## What this plan does not build

- **The agent's tools** (`flow.propose` with its diff, `flow.vocabulary`, `flow.effective`, `project.summary`, `demand.history`) — plan 2.
- **The renderer** with its three states — plan 3.
- **Stopping a demand on `terminate`** — P-46, waiting on P-29's event-reaction mechanism. Until it exists, `drain` and `terminate` revoke the copy identically and a running demand finishes under either.
- **The confirmation that names how many demands will stop** (spec §8 R-2). The count comes from `AdoptionsOf`, which this plan builds; showing it before a `terminate` revocation is the cockpit's, and belongs to plan 3. Until then the most destructive act in the design has no guard rail beyond the operator's attention — which is worth knowing while plan 3 is not written.
- **The account tree** (P-44). This plan does not need it: with one platform account, `chosen.AccountID != accountID` already identifies the ownership crossing. When several platform accounts exist, the only change is WHICH flow the chain finds — not how the pin behaves.

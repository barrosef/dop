# Account Sign-up — Core Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the core enforce, against a verified token, that a password credential has a verified e-mail and that one e-mail belongs to one user.

**Architecture:** Four tasks in one Go module. The first closes the hole that would make the other three decorative: `EnsureUser` currently builds its `Principal` from the request body, so any caller can declare `email_verified: true`. The verified identity `callauth` already computes starts travelling on `ctxutil.Call`, and the handler uses it. The remaining three add the two rules the spec asks for and the repository lookup one of them needs.

**Tech Stack:** Go 1.27, pgx, Postgres 16 (pgvector image), gRPC.

**Spec:** `docs/superpowers/specs/2026-09-06-account-signup-design.md`

**Repository:** `repos/dop-core` — every path in this plan is relative to it.

## Global Constraints

- Everything in the repository is written in English — code, comments, identifiers, SQL, test names. Commit messages are Portuguese by house convention.
- Comments explain WHY a decision was made and what it costs, never what the line does.
- The domain is tested without a database; database tests live in `test/integration/` behind the `integration` build tag.
- `openPool` calls `t.Skipf` when Postgres does not answer. A green `ok` in this repo routinely means every test skipped: run integration tests with `-v` and confirm `--- PASS`, never `--- SKIP`.
- No adapter may be imported from `internal/domain` — the architecture test in `test/contract/` enforces it.
- ADR-0022 binds this work: the core verifies a signature, it does not believe a claim.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `internal/platform/ctxutil/ctxutil.go` | Gains `VerifiedIdentity` and the `Call.Verified` field — what the TOKEN proved, as opposed to what the body claimed | 1 |
| `internal/app/callauth.go` | Stashes the verified identity on the `Call`, including when no user exists yet | 1 |
| `internal/app/callauth_test.go` | Proves the verified identity survives the bootstrap case | 1 |
| `internal/app/grpc/identity.go` | `EnsureUser` reads the verified identity and refuses without it | 1 |
| `internal/app/grpc/identity_test.go` | Proves the body can no longer say who the person is | 1 |
| `internal/domain/identity/service.go` | The two rules: password needs a verified e-mail; one e-mail, one user | 2, 4 |
| `internal/domain/identity/service_test.go` | Both rules, and the three existing tests the first one breaks | 2, 4 |
| `internal/domain/identity/repository.go` | The port gains `UserByVerifiedEmail` | 3 |
| `internal/adapter/postgres/identity.go` | Its Postgres implementation | 3 |
| `test/integration/identity_test.go` | Created: proves the lookup matches only verified e-mails, case-insensitively | 3 |

---

### Task 1: The token says who, not the request body

**Files:**
- Modify: `internal/platform/ctxutil/ctxutil.go`
- Modify: `internal/app/callauth.go:112-183`
- Modify: `internal/app/callauth_test.go`
- Modify: `internal/app/grpc/identity.go:27-40`
- Create: `internal/app/grpc/identity_test.go`

**Interfaces:**
- Consumes: `ctxutil.Call`, `ports.Principal`, `callAuth.authenticate(ctx, md, claimed) ctxutil.Call`.
- Produces: `ctxutil.VerifiedIdentity{Subject, Email, EmailVerified, Name, AvatarURL, Providers}`; `ctxutil.Call.Verified *VerifiedIdentity`.

**Why this task is first.** `internal/app/grpc/identity.go:28-35` builds the `Principal` out of `req.GetSubject()`, `req.GetEmail()`, `req.GetEmailVerified()` and `req.GetProvider()`. Tasks 2 and 4 add rules that read exactly those fields. A rule the caller can pass by setting a boolean is not a rule.

`callauth` already verifies the bearer token (`callauth.go:137-138`) and throws the result away, keeping only the resolved user id. In the bootstrap case — a brand-new person, whose subject has no user yet — `userOf` fails, `signed` stays false, and strict mode returns a `Call` with nothing on it. That is why the body was trusted here and nowhere else. **A token can prove the PERSON without proving an ACTOR**, and that distinction is the whole fix.

**Note on `VerifiedIdentity` duplicating `ports.Principal`.** It is deliberate. `ctxutil` is a platform package that today imports only `context`, `errors` and `errs`; making it import the domain to reuse one struct inverts the layering for no gain. This codebase already makes the same trade elsewhere — `reaction.StageActionSpec` restates `workflow.StageAction` so that domain need not import the other. Say so in the comment.

- [ ] **Step 1: Write the failing test for the bootstrap case**

Add to `internal/app/callauth_test.go`. Extend the existing `fakeTokens` so it can return a whole principal — keep the `subject` field working, because seven other tests use it:

```go
type fakeTokens struct {
	subject   string
	principal *ports.Principal
	err       error
}

func (f fakeTokens) VerifyToken(context.Context, string) (*ports.Principal, error) {
	if f.err != nil {
		return nil, f.err
	}
	if f.principal != nil {
		return f.principal, nil
	}
	return &ports.Principal{Subject: f.subject}, nil
}
```

Then the test:

```go
func TestAVerifiedTokenProvesThePersonEvenWhenNoUserExistsYet(t *testing.T) {
	// The bootstrap: EnsureUser is the call that runs BEFORE the user exists, so
	// userOf finds nothing and strict mode proves no actor. The token still
	// proved WHO, and that is what EnsureUser needs — without it the handler
	// falls back to believing the request body, which ADR-0022 exists to stop.
	users := &fakeUsers{bySubject: map[string]string{}}
	a, _ := newAuth(t, "strict", fakeTokens{principal: &ports.Principal{
		Subject: "sub-new", Email: "ana@example.com", EmailVerified: true,
		Providers: []string{"password"},
	}}, users)

	got := a.authenticate(context.Background(),
		mdWith("authorization", "Bearer t"), ctxutil.Call{})

	if got.ActorID != "" {
		t.Fatalf("no user exists yet, so no actor may be proven: %+v", got)
	}
	if got.Verified == nil {
		t.Fatal("the token was verified and its answer was thrown away")
	}
	if got.Verified.Subject != "sub-new" || !got.Verified.EmailVerified {
		t.Fatalf("the verified identity did not survive: %+v", got.Verified)
	}
}

func TestAForgedTokenLeavesNoVerifiedIdentity(t *testing.T) {
	users := &fakeUsers{bySubject: map[string]string{}}
	a, _ := newAuth(t, "strict", fakeTokens{err: errs.New(errs.KindUnauthorized, "forged")}, users)

	got := a.authenticate(context.Background(),
		mdWith("authorization", "Bearer t"), ctxutil.Call{})

	if got.Verified != nil {
		t.Fatal("a token that proved nothing left a verified identity behind")
	}
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `go test ./internal/app/ -run TestAVerifiedTokenProves -v`
Expected: FAIL — `got.Verified undefined (type ctxutil.Call has no field or method Verified)`

- [ ] **Step 3: Add the type and the field**

In `internal/platform/ctxutil/ctxutil.go`, beside `Call`:

```go
// VerifiedIdentity is what the person's TOKEN proved, as opposed to what a
// request body claimed. It exists for exactly one caller: the bootstrap that
// creates a user, which runs before any user exists and therefore cannot be
// authorized by an actor.
//
// It restates ports.Principal instead of importing it. This package is platform
// and today depends on nothing in the domain; inverting that to reuse one struct
// buys nothing. The codebase already makes the same trade where reaction
// restates a workflow stage's action rather than importing the package.
type VerifiedIdentity struct {
	Subject       string
	Email         string
	EmailVerified bool
	Name          string
	AvatarURL     string
	Providers     []string
}
```

and, as a field on `Call`:

```go
	// Verified is non-nil only when a bearer token was verified on this call. It
	// is INDEPENDENT of ActorID: a token proves the person, and the person may
	// not have a user yet. Anything that needs an actor keeps reading ActorID.
	Verified *VerifiedIdentity
```

- [ ] **Step 4: Carry it through `authenticate`**

In `internal/app/callauth.go`, inside the bearer branch that starts at line 137, capture the identity the moment the token verifies — before the `userOf` result decides anything:

```go
	var verified *ctxutil.VerifiedIdentity
	if tok := bearer(md); tok != "" && a.tokens != nil {
		p, err := a.tokens.VerifyToken(ctx, tok)
		if err != nil {
			log.Warn("token refused")
		} else {
			// Kept regardless of what follows: the token proved the PERSON, and
			// the bootstrap that creates their user runs precisely when the
			// lookup below cannot succeed.
			verified = &ctxutil.VerifiedIdentity{
				Subject: p.Subject, Email: p.Email, EmailVerified: p.EmailVerified,
				Name: p.Name, AvatarURL: p.AvatarURL, Providers: p.Providers,
			}
			if userID, err := a.userOf(ctx, p.Subject); err != nil {
				log.Warn("token verified but the subject has no user", "error", err.Error())
			} else {
				// ... the existing block, unchanged ...
			}
		}
	}
```

Then attach it on both exits, so a refusal does not discard the proof:

```go
	if !signed {
		r := a.refuse(claimed)
		r.Verified = verified
		return r
	}
	if proven.ActorKind == "" {
		proven.ActorKind = ctxutil.ActorUser
	}
	proven.Verified = verified
	return proven
```

- [ ] **Step 5: Run the test**

Run: `go test ./internal/app/ -v`
Expected: PASS, including the nine tests that already existed.

- [ ] **Step 6: Write the failing handler test**

Create `internal/app/grpc/identity_test.go`. It is `package grpc`, matching the file already beside it (`workflow_test.go`), so it calls `NewIdentityServer` unqualified.

```go
package grpc

import (
	"context"
	"testing"

	dopv1 "github.com/Digital-Business-One/dop-core/api/gen/dop/v1"
	"github.com/Digital-Business-One/dop-core/internal/domain/identity"
	"github.com/Digital-Business-One/dop-core/internal/platform/ctxutil"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

func TestEnsureUserWithoutAVerifiedTokenIsRefused(t *testing.T) {
	// The service is nil on purpose: the refusal has to happen BEFORE anything
	// is created, so reaching the service at all would panic and fail this test.
	// That is a stronger assertion than any double could make.
	srv := NewIdentityServer(nil)

	_, err := srv.EnsureUser(context.Background(), &dopv1.EnsureUserRequest{
		Subject: "sub-1", Email: "ana@example.com", EmailVerified: true,
	})
	if errs.KindOf(err) != errs.KindUnauthorized {
		t.Fatalf("without a token nothing may be created: %v", err)
	}
}

func TestEnsureUserIgnoresWhatTheBodyClaims(t *testing.T) {
	// The body says the e-mail is verified and the subject is somebody else's.
	// Both are text. Only the token's answer may decide.
	repo := &stubIdentityRepo{users: map[string]*identity.User{}}
	srv := NewIdentityServer(identity.NewService(repo, stubClock{}))
	ctx := ctxutil.Into(context.Background(), ctxutil.Call{
		Verified: &ctxutil.VerifiedIdentity{
			Subject: "sub-real", Email: "ana@example.com", EmailVerified: true,
			Providers: []string{"google"},
		},
	})

	got, err := srv.EnsureUser(ctx, &dopv1.EnsureUserRequest{
		Subject: "sub-someone-else", Email: "victim@example.com",
		EmailVerified: true, Provider: "password",
	})
	if err != nil {
		t.Fatalf("EnsureUser: %v", err)
	}
	if got.GetEmail() != "ana@example.com" {
		t.Fatalf("the body chose the identity: %q", got.GetEmail())
	}
}
```

**The double.** `identity.Repository` has 18 methods and `EnsureUser` exercises five of them. `service_test.go`'s `fakeRepo` is unexported in another package, so this file needs its own — and the honest shape is: real bodies for what is used, and a panic for everything else, so a future test that quietly depends on an unimplemented method fails loudly instead of reading a zero value.

```go
type stubClock struct{}

func (stubClock) Now() time.Time { return time.Date(2026, 9, 6, 12, 0, 0, 0, time.UTC) }

// stubIdentityRepo implements identity.Repository for the five methods
// EnsureUser touches. Every other method panics rather than returning a zero
// value: a double that answers questions nobody taught it makes the test that
// leans on it pass for the wrong reason.
type stubIdentityRepo struct {
	users    map[string]*identity.User
	accounts []identity.Account
	n        int
}

func (s *stubIdentityRepo) UserBySubject(_ context.Context, sub string) (*identity.User, error) {
	if u, ok := s.users[sub]; ok {
		return u, nil
	}
	return nil, errs.NotFound("user")
}

func (s *stubIdentityRepo) UpsertUser(_ context.Context, u *identity.User) (*identity.User, error) {
	if u.ID == "" {
		s.n++
		u.ID = fmt.Sprintf("usr-%d", s.n)
	}
	cp := *u
	s.users[u.Subject] = &cp
	return &cp, nil
}

func (s *stubIdentityRepo) UserByVerifiedEmail(context.Context, string) (*identity.User, error) {
	return nil, errs.NotFound("user")
}

func (s *stubIdentityRepo) AccountsOfUser(context.Context, string) ([]identity.Account, []identity.Membership, error) {
	return s.accounts, nil, nil
}

func (s *stubIdentityRepo) CreateAccountWithOwner(_ context.Context, a *identity.Account, _ string) (*identity.Account, error) {
	s.n++
	a.ID = fmt.Sprintf("acct-%d", s.n)
	s.accounts = append(s.accounts, *a)
	return a, nil
}

func (s *stubIdentityRepo) AccountByHandle(context.Context, string) (*identity.Account, error) {
	return nil, errs.NotFound("account")
}

func (s *stubIdentityRepo) UserByID(context.Context, string) (*identity.User, error) {
	panic("stubIdentityRepo: UserByID is not used by these tests")
}
```

`UserByVerifiedEmail` is on that list because Task 4 adds it to the port; until then the compiler will not ask for it, and leaving it in now costs nothing and saves an edit.

The remaining eleven methods follow the same one-line panic shape. Do not guess their signatures — run `go build ./...`, and the compiler names each one still missing along with the exact type it wants. Add `fmt` and `time` to the imports.

- [ ] **Step 7: Run it and see it fail**

Run: `go test ./internal/app/grpc/ -run TestEnsureUser -v`
Expected: FAIL — the first test returns `victim@example.com`, the second returns no error.

- [ ] **Step 8: Make the handler read the token**

Replace `internal/app/grpc/identity.go:27-40`:

```go
// EnsureUser is the bootstrap: it runs BEFORE the person has a user, so no actor
// can authorize it. What authorizes it is the token, and the token is also the
// only acceptable source for who the person is — the request's fields describe
// an identity the caller merely asserts (ADR-0022). They are ignored, and stay
// in the proto only so an older client is refused rather than misread.
func (s *IdentityServer) EnsureUser(ctx context.Context, _ *dopv1.EnsureUserRequest) (*dopv1.User, error) {
	call, _ := ctxutil.From(ctx)
	if call.Verified == nil {
		return nil, errs.New(errs.KindUnauthorized,
			"EnsureUser needs the person's token: a request body cannot say who they are")
	}
	u, _, err := s.svc.EnsureUser(ctx, ports.Principal{
		Subject:       call.Verified.Subject,
		Email:         call.Verified.Email,
		EmailVerified: call.Verified.EmailVerified,
		Name:          call.Verified.Name,
		AvatarURL:     call.Verified.AvatarURL,
		Providers:     call.Verified.Providers,
	})
	if err != nil {
		return nil, err
	}
	return userToProto(u), nil
}
```

Fix the imports the file needs (`ctxutil`, `errs`) and drop any that fall unused.

- [ ] **Step 9: Run everything**

Run: `go build ./... && go test ./internal/... -v 2>&1 | grep -E '^(ok|FAIL|--- FAIL)' && go vet ./... && go vet -tags=integration ./...`
Expected: no FAIL.

- [ ] **Step 10: Commit**

```bash
git add internal/platform/ctxutil internal/app
git commit -m "fix(identity): o EnsureUser acreditava no corpo da requisição"
```

---

### Task 2: A password credential needs a verified e-mail

**Files:**
- Modify: `internal/domain/identity/service.go:95-145` (`EnsureUser`)
- Modify: `internal/domain/identity/service_test.go:260-318`

**Interfaces:**
- Consumes: `ports.Principal`, `errs.KindPrecondition`.
- Produces: nothing new; `EnsureUser` gains a refusal.

**The rule, and why it is not blanket.** Spec D-5: refusing every unverified e-mail would lock out GitHub, which frequently delivers one. With a **password** credential the e-mail is the only thing tying that credential to a person and nobody checked it. With a **social** credential the provider already authenticated the person and the e-mail is metadata. `Principal.Providers` carries `password` normalized — `internal/adapter/identity/oidc.go:604` rewrites OIDC's `pwd` to Firebase's `password` precisely so this field is comparable across adapters.

**This task breaks three existing tests, and that is expected.** `service_test.go:265`, `:287` and `:307` all pass `Providers: []string{"password"}` and leave `EmailVerified` at its zero value. Update those three to `EmailVerified: true`; they are about the personal account, idempotency and provider merging, and none of them is about verification. Do not weaken the new rule to keep them green.

- [ ] **Step 1: Write the failing tests**

Add to `internal/domain/identity/service_test.go`:

```go
func TestAPasswordCredentialNeedsAVerifiedEmail(t *testing.T) {
	svc := identity.NewService(newFakeRepo(), fixedClock{now})
	_, _, err := svc.EnsureUser(context.Background(), ports.Principal{
		Subject: "sub-1", Email: "ana@example.com", EmailVerified: false,
		Providers: []string{"password"},
	})
	if errs.KindOf(err) != errs.KindPrecondition {
		t.Fatalf("without verification anybody signs up with anybody's address: %v", err)
	}
}

func TestASocialCredentialEntersWithAnUnverifiedEmail(t *testing.T) {
	// GitHub frequently hands over an unverified e-mail. Refusing it here would
	// lock out the provider this platform's users are most likely to have — and
	// the e-mail is not the proof there, the provider's authentication is.
	svc := identity.NewService(newFakeRepo(), fixedClock{now})
	u, acct, err := svc.EnsureUser(context.Background(), ports.Principal{
		Subject: "sub-2", Email: "bruno@example.com", EmailVerified: false,
		Providers: []string{"github"},
	})
	if err != nil {
		t.Fatalf("a social credential does not need the e-mail verified: %v", err)
	}
	if u == nil || acct == nil {
		t.Fatal("the user and the personal account should exist")
	}
}

func TestAPasswordLinkedToASocialProviderEnters(t *testing.T) {
	// Once a social provider is on the same credential, the password is no
	// longer the only thing vouching for the person.
	svc := identity.NewService(newFakeRepo(), fixedClock{now})
	_, _, err := svc.EnsureUser(context.Background(), ports.Principal{
		Subject: "sub-3", Email: "carla@example.com", EmailVerified: false,
		Providers: []string{"password", "google"},
	})
	if err != nil {
		t.Fatalf("password plus a social provider is not a password-only credential: %v", err)
	}
}
```

- [ ] **Step 2: Run them and see them fail**

Run: `go test ./internal/domain/identity/ -run 'TestAPassword|TestASocial' -v`
Expected: `TestAPasswordCredentialNeedsAVerifiedEmail` FAILs (it gets a nil error); the other two pass already.

- [ ] **Step 3: Implement the rule**

In `internal/domain/identity/service.go`, immediately after the existing empty-subject guard in `EnsureUser`:

```go
	if passwordOnly(p.Providers) && !p.EmailVerified {
		return nil, nil, errs.New(errs.KindPrecondition,
			"this e-mail has not been verified yet")
	}
```

and, near `mergeProviders` at the bottom of the file:

```go
// passwordOnly answers whether a password is the ONLY thing vouching for this
// person. It is the distinction the verification rule turns on: with a password
// the e-mail is the sole link between the credential and a human, and nobody
// checked it; with a social provider the provider already did the checking, and
// the e-mail is metadata. Refusing every unverified e-mail would lock out
// GitHub, which frequently delivers one (spec D-5).
func passwordOnly(providers []string) bool {
	if len(providers) == 0 {
		return false // an unknown provider is not a password credential
	}
	for _, p := range providers {
		if p != "password" {
			return false
		}
	}
	return true
}
```

- [ ] **Step 4: Fix the three existing tests the rule breaks**

At `service_test.go:265`, `:287` and `:307`, add `EmailVerified: true` to each `ports.Principal` literal that carries `Providers: []string{"password"}`. Each of those tests is about something else — the personal account, idempotency, provider merging — and verification is now a precondition they have to satisfy to reach what they assert.

- [ ] **Step 5: Run the package**

Run: `go test ./internal/domain/identity/ -v`
Expected: PASS, all of it.

- [ ] **Step 6: Commit**

```bash
git add internal/domain/identity
git commit -m "feat(identity): senha sem e-mail verificado não cria conta"
```

---

### Task 3: Finding a user by a verified e-mail

**Files:**
- Modify: `internal/domain/identity/repository.go:10-13`
- Modify: `internal/adapter/postgres/identity.go:43-57`
- Modify: `internal/domain/identity/service_test.go` (the `fakeRepo`)
- Create: `test/integration/identity_test.go`

**Interfaces:**
- Consumes: `identity.User`, `postgres.Translate`, `postgres.scanUser`, `userCols`.
- Produces: `Repository.UserByVerifiedEmail(ctx context.Context, email string) (*User, error)` — `errs.NotFound` when there is no such user, on the port and in every implementation.

**Why verified only.** Task 4 uses this lookup to decide that two subjects are the same person. An unverified e-mail is an unproven claim, and matching on it would let somebody who typed your address into a provider land in your account. The predicate belongs in the query so no caller can forget it.

The `users` table already carries `CREATE UNIQUE INDEX users_email_uniq ON users (lower(email)) WHERE email IS NOT NULL`, so at most one row can match. `email` is `citext`, and the index is on `lower(email)`: match with `lower(email) = lower($1)` so the index is used rather than relying on the column's collation.

- [ ] **Step 1: Write the failing integration test**

Create `test/integration/identity_test.go`:

```go
//go:build integration

package integration

import (
	"context"
	"testing"

	"github.com/Digital-Business-One/dop-core/internal/adapter/postgres"
	"github.com/Digital-Business-One/dop-core/internal/domain/identity"
	"github.com/Digital-Business-One/dop-core/internal/platform/errs"
)

func TestUserByVerifiedEmailIgnoresAnUnverifiedOne(t *testing.T) {
	pool := openPool(t)
	ctx := context.Background()
	repo := postgres.NewIdentityRepo(pool)

	unverified, err := repo.UpsertUser(ctx, &identity.User{
		Subject: uniqueSubject(t), Email: uniqueEmail(t), EmailVerified: false,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := repo.UserByVerifiedEmail(ctx, unverified.Email); errs.KindOf(err) != errs.KindNotFound {
		t.Fatalf("an unverified e-mail is an unproven claim and must not match: %v", err)
	}
}

func TestUserByVerifiedEmailMatchesRegardlessOfCase(t *testing.T) {
	pool := openPool(t)
	ctx := context.Background()
	repo := postgres.NewIdentityRepo(pool)

	email := uniqueEmail(t)
	saved, err := repo.UpsertUser(ctx, &identity.User{
		Subject: uniqueSubject(t), Email: email, EmailVerified: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	got, err := repo.UserByVerifiedEmail(ctx, strings.ToUpper(email))
	if err != nil {
		t.Fatalf("the unique index is on lower(email); the lookup must agree: %v", err)
	}
	if got.ID != saved.ID {
		t.Fatalf("found the wrong user: %s", got.ID)
	}
}
```

Write `uniqueSubject(t)` and `uniqueEmail(t)` in this file, deriving from `t.Name()` plus a counter so repeated runs against the same database do not collide with the unique indexes — `test/integration/reaction_test.go` already does this for event types; follow its shape. Add `strings` to the imports.

The constructor is `postgres.NewIdentityRepo(pool *pgxpool.Pool) *IdentityRepo`, verified at `internal/adapter/postgres/identity.go:20`.

- [ ] **Step 2: Run it and see it fail**

Start a scratch database first — `goose` is not installed and the stack is stopped:

```bash
docker run --rm -d --name dop-t3 -e POSTGRES_PASSWORD=x -e POSTGRES_DB=dop \
  -e POSTGRES_USER=dop -p 55461:5432 pgvector/pgvector:pg16
for f in migrations/*.sql; do
  sed -n '/-- +goose Up/,/-- +goose Down/p' "$f" | grep -v goose > /tmp/up.sql
  docker exec -i dop-t3 psql -U dop -d dop -v ON_ERROR_STOP=1 < /tmp/up.sql || echo "FAILED: $f"
done
docker exec dop-t3 psql -U dop -d dop -c '\d users'
```

That last line is not optional. An exit code of 0 proves nothing here: four migrations once shipped doing nothing because a missing goose marker made the extraction produce an empty file.

Run: `TEST_DATABASE_URL='postgres://dop:x@localhost:55461/dop?sslmode=disable' go test ./test/integration/ -tags=integration -run TestUserByVerifiedEmail -v`
Expected: FAIL to compile — `repo.UserByVerifiedEmail undefined`. Not SKIP.

- [ ] **Step 3: Add it to the port**

In `internal/domain/identity/repository.go`, under `// Users`:

```go
	// UserByVerifiedEmail finds the user who PROVED this address. The predicate
	// is in the query and not in the caller because the caller that forgets it
	// hands one person's account to another: an unverified e-mail is a claim,
	// and two subjects agreeing on a claim are not the same person.
	UserByVerifiedEmail(ctx context.Context, email string) (*User, error)
```

- [ ] **Step 4: Implement it in Postgres**

In `internal/adapter/postgres/identity.go`, beside `UserBySubject`:

```go
// The unique index is on lower(email); comparing the same way is what makes it
// usable instead of forcing a scan.
func (r *IdentityRepo) UserByVerifiedEmail(ctx context.Context, email string) (*identity.User, error) {
	u, err := scanUser(r.pool.QueryRow(ctx,
		`SELECT `+userCols+` FROM users WHERE lower(email) = lower($1) AND email_verified`, email))
	if err != nil {
		return nil, Translate(err, "user")
	}
	return u, nil
}
```

- [ ] **Step 5: Implement it in the domain's double**

In `internal/domain/identity/service_test.go`, beside `fakeRepo.UserBySubject`:

```go
func (f *fakeRepo) UserByVerifiedEmail(_ context.Context, email string) (*identity.User, error) {
	for _, u := range f.users {
		if u.EmailVerified && strings.EqualFold(u.Email, email) {
			return u, nil
		}
	}
	return nil, errs.NotFound("user")
}
```

Add `strings` to that file's imports if it is not there. Check whether any other type in the repository implements `identity.Repository` — `go build ./...` will name them if so, and each needs the method.

- [ ] **Step 6: Run both suites**

```bash
go build ./... && go test ./internal/... && \
TEST_DATABASE_URL='postgres://dop:x@localhost:55461/dop?sslmode=disable' \
  go test ./test/integration/ -tags=integration -run TestUserByVerifiedEmail -v
```
Expected: PASS, with `--- PASS` on both integration tests and no `--- SKIP`.

- [ ] **Step 7: Commit**

```bash
git add internal/domain/identity internal/adapter/postgres/identity.go test/integration/identity_test.go
git commit -m "feat(identity): achar o usuário que provou um e-mail"
```

---

### Task 4: One e-mail, one user — and a refusal that names its cause

**Files:**
- Modify: `internal/domain/identity/service.go` (`EnsureUser`)
- Modify: `internal/domain/identity/service_test.go`

**Interfaces:**
- Consumes: `Repository.UserByVerifiedEmail` from Task 3, `errs.KindConflict`.
- Produces: nothing new.

**The defect this closes.** `migrations/0001_foundation.sql:27` makes the e-mail unique across the whole system, while `EnsureUser` looks a user up by `subject`. If Firebase is ever configured to allow several accounts per e-mail address, the same person arriving through a second provider carries a different subject, is not found, and the insert violates the unique index — the person receives an opaque failure and cannot get in. `EnsureUser`'s own doc comment says this case resolves to the same user; that is true only because of a setting outside the code that nothing asserts.

The rule stays as the comment describes it — Firebase links, so the subject is stable and this path is not reached in a healthy system. What changes is what happens when the assumption breaks: a refusal that names the provider configuration, instead of a database error escaping as an internal one.

- [ ] **Step 1: Write the failing test**

```go
func TestASecondSubjectOnAVerifiedEmailIsRefusedByName(t *testing.T) {
	// Reaching here means the provider stopped linking accounts that share an
	// e-mail. The e-mail is unique in the schema, so the insert would fail on the
	// index and the person would read "something went wrong". The cause is a
	// configuration, and the error has to say so.
	repo := newFakeRepo()
	svc := identity.NewService(repo, fixedClock{now})
	ctx := context.Background()

	if _, _, err := svc.EnsureUser(ctx, ports.Principal{
		Subject: "sub-google", Email: "ana@example.com", EmailVerified: true,
		Providers: []string{"google"},
	}); err != nil {
		t.Fatal(err)
	}

	_, _, err := svc.EnsureUser(ctx, ports.Principal{
		Subject: "sub-github", Email: "ana@example.com", EmailVerified: true,
		Providers: []string{"github"},
	})
	if errs.KindOf(err) != errs.KindConflict {
		t.Fatalf("expected a conflict naming the configuration, got %v", err)
	}
	if !strings.Contains(err.Error(), "linking") {
		t.Fatalf("the message does not name the cause: %v", err)
	}
}

func TestTheSameSubjectComingBackIsNotAConflict(t *testing.T) {
	// The guard must not fire on the ordinary case: the same person, same
	// subject, signing in again on an e-mail that is already theirs.
	repo := newFakeRepo()
	svc := identity.NewService(repo, fixedClock{now})
	ctx := context.Background()
	p := ports.Principal{Subject: "sub-1", Email: "ana@example.com",
		EmailVerified: true, Providers: []string{"google"}}

	u1, _, _ := svc.EnsureUser(ctx, p)
	u2, _, err := svc.EnsureUser(ctx, p)
	if err != nil {
		t.Fatalf("signing in twice is not a conflict: %v", err)
	}
	if u1.ID != u2.ID {
		t.Fatal("the same subject produced two users")
	}
}
```

- [ ] **Step 2: Run them and see the first fail**

Run: `go test ./internal/domain/identity/ -run 'TestASecondSubject|TestTheSameSubject' -v`
Expected: `TestASecondSubjectOnAVerifiedEmailIsRefusedByName` FAILs — it gets a nil error, because the fake happily writes a second user. `TestTheSameSubjectComingBackIsNotAConflict` passes already.

- [ ] **Step 3: Implement the guard**

In `EnsureUser`, after the `UserBySubject` lookup and before building the `User`:

```go
	// The e-mail is unique across the whole table (0001_foundation.sql), while
	// the lookup above is by subject. Those two only agree because the identity
	// provider links accounts that share an e-mail, which is configuration and
	// not code. When it stops agreeing, say why: without this the insert dies on
	// the unique index and the person reads "something went wrong".
	if existing == nil && p.Email != "" && p.EmailVerified {
		if other, err := s.repo.UserByVerifiedEmail(ctx, p.Email); err == nil && other != nil {
			return nil, nil, errs.New(errs.KindConflict,
				"this e-mail already belongs to another sign-in method; "+
					"the identity provider is not linking accounts that share an e-mail")
		} else if err != nil && errs.KindOf(err) != errs.KindNotFound {
			return nil, nil, err
		}
	}
```

- [ ] **Step 4: Run the package**

Run: `go test ./internal/domain/identity/ -v`
Expected: PASS.

- [ ] **Step 5: Run everything, including the integration suite**

```bash
go build ./... && go vet ./... && go vet -tags=integration ./... && \
go test ./internal/... && \
TEST_DATABASE_URL='postgres://dop:x@localhost:55461/dop?sslmode=disable' \
  go test ./test/integration/ -tags=integration -v 2>&1 | grep -E 'FAIL|SKIP|^ok'
```
Expected: no FAIL, and no `--- SKIP` on the identity or reaction tests.

Then remove the scratch database: `docker rm -f dop-t3`. Nothing else in Docker may be stopped, pruned or removed — the owner's stack is down to free machine resources for another project, and anything that is not DOP is untouchable.

- [ ] **Step 6: Commit**

```bash
git add internal/domain/identity
git commit -m "feat(identity): dois subjects no mesmo e-mail param com a causa dita"
```

---

## What this plan does not build

- **The verification e-mail itself** — the Admin SDK link and the Mailer handoff live in `dop-api`, plan 2.
- **The sign-up screen, the provider buttons and the linking choreography** — `dop-app`, plan 3.
- **Enabling Google and GitHub** — Terraform, `dop-infra`, plan 4. Until it runs, the two providers do not exist to sign in with, and that is expected: this plan is about what the core does with a token once one arrives.
- **Removing the now-ignored fields from `EnsureUserRequest`.** Task 1 stops reading them; the proto keeps them so an older client is refused rather than silently misread. Retiring them is a breaking change and belongs with plan 2, which is what updates the caller.

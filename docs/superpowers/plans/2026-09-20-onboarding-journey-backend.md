# Onboarding Journey — Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the cockpit every operation the onboarding journey needs — journey state in the core, profile, personal workspace at birth, provider and plan catalogues, credential check, phone reminder — so the frontend can be built against a contract on QA.

**Architecture:** Additive changes only. In `dop-core`: one migration (columns + two catalogue tables seeded as upserts), a small read-only `catalog` domain, new identity operations behind new RPCs, a `WorkspaceProvisioner` port so identity can ask hierarchy for the personal workspace without importing it, a `CredentialChecker` port so resource can probe a token without knowing GitHub, two new identity events and two attention rule lines. In `dop-api`: use cases first, then REST routes and gRPC servicers over them (the parity discipline), plus the edge proto. Nothing in `Principal`, in the identity adapters or in the verification contract moves.

**Tech Stack:** Go 1.24 (`dop-core`), protobuf via `make proto`, Postgres migrations (goose-style `-- +goose Up`), Python 3.12 / FastAPI / grpc.aio (`dop-api`), pytest.

**Spec:** `docs/superpowers/specs/2026-09-20-onboarding-journey-design.md`

## Global Constraints

- `make proto-breaking` stays green: only new fields and new RPCs (spec §5).
- Every rule lives in the core; the BFF holds no state and no secret (AGENTS.md invariants 1–2).
- Generated code is regenerated, never hand-edited (invariant 3).
- Every REST route has a gRPC twin over the SAME use case; a parity test proves it (dop-api house rule).
- Code, comments and logs in English; commit subjects in Portuguese describing the finding.
- `make migrate` only against `k3d-dop-local` (the Makefile `guard`); QA migrations go through the data VM, never `kubectl`.
- Attention items: "an item is born from an event and dies from one, never from an RPC" (`internal/app/register.go`).
- Required steps: `profile`, `code`, `plan`; skippable: `contact`, `tasks` (spec D-5).
- Catalogue seeds live inside the migration as upserts (spec §4).

---

## File structure

**dop-core**
- `migrations/0027_onboarding_journey.sql` — columns, tables, seed rows.
- `internal/domain/catalog/{entity,repository,service,service_test}.go` — plans and providers, read-only.
- `internal/adapter/postgres/catalog.go` — the two tables.
- `internal/domain/identity/entity.go` — `User` + `Account` gain fields; `Onboarding` value type and step vocabulary.
- `internal/domain/identity/onboarding.go` — the journey's rules (`RecordStep`, `Complete`, `State`), kept out of the 900-line `service.go`.
- `internal/domain/identity/profile.go` — `UpdateProfile`, `MarkPhoneVerified`, `UpdatePersonalAccount`, `HandleAvailability`, `SetPlan`.
- `internal/domain/identity/repository.go` — new repository methods.
- `internal/domain/identity/service.go` — `WorkspaceProvisioner` port + `EnsureUser` calling it; `Plans` port for `SetPlan`.
- `internal/domain/identity/{onboarding_test,profile_test}.go` + `service_test.go` (fakeRepo grows).
- `internal/adapter/postgres/identity.go` — new columns in `userCols`/`scanUser`, new methods, two events.
- `internal/domain/hierarchy/service.go` — `EnsurePersonalWorkspace`; `repository.go` — `WorkspaceByKey`; adapter.
- `internal/domain/secondfactor/service.go` — `Users` port gains `PhoneVerified`; `Confirm` calls it for SMS.
- `internal/domain/attention/{entity,rules}.go` — kind, impact, key, two rule lines, subject.
- `internal/domain/resource/{service,entity}.go` — `CredentialChecker` port, `Check`.
- `internal/adapter/gitprovider/{github,gitlab}.go` — `Whoami`.
- `internal/app/{register,glue,checkers}.go` — wiring.
- `api/proto/dop/v1/{identity,catalog,resource}.proto` — contract; `internal/app/grpc/{identity,catalog,resource}.go` — servers.

**dop-api**
- `app/usecases/{identity,catalog,resource}.py`, `app/routers/{identity,catalog,resource}.py`, `app/grpcapi/{identity,catalog,resource}.py`, `api/proto/dop/bff/v1/{identity,catalog,resource}.proto`, `tests/{test_onboarding,test_catalog,test_resource_check}.py`, `tests/conftest.py`.

---

### Task 1: The migration

**Files:**
- Create: `repos/dop-core/migrations/0027_onboarding_journey.sql`

**Interfaces:**
- Produces: columns `users.birth_date date`, `users.locale text`, `users.timezone text`, `users.phone text`, `users.phone_verified_at timestamptz`, `users.onboarding jsonb NOT NULL DEFAULT '{}'`, `users.onboarded_at timestamptz`; `accounts.plan_key text REFERENCES plan_catalog(key)`; tables `plan_catalog`, `provider_catalog`.

- [ ] **Step 1: Write the migration**

```sql
-- +goose Up
-- The onboarding journey (spec 2026-09-20): what the journey records on the
-- person and on the personal account, and the two catalogues it reads.

CREATE TABLE plan_catalog (
  key       text PRIMARY KEY,
  name      text NOT NULL,
  tagline   text NOT NULL DEFAULT '',
  features  jsonb NOT NULL DEFAULT '[]',
  sort      int  NOT NULL DEFAULT 0,
  active    boolean NOT NULL DEFAULT true
);

-- category mirrors resource.Category (git | task_manager); a provider row is
-- what the cockpit shows as a tile and what the core knows how to check.
CREATE TABLE provider_catalog (
  key             text PRIMARY KEY,
  category        text NOT NULL CHECK (category IN ('git', 'task_manager')),
  name            text NOT NULL,
  credential_kind text NOT NULL DEFAULT 'token',
  permissions     text[] NOT NULL DEFAULT '{}',
  needs_base_url  boolean NOT NULL DEFAULT false,
  operated        boolean NOT NULL DEFAULT false,
  docs_url        text NOT NULL DEFAULT '',
  brand_color     text NOT NULL DEFAULT '',
  sort            int  NOT NULL DEFAULT 0,
  active          boolean NOT NULL DEFAULT true
);

ALTER TABLE users
  ADD COLUMN birth_date        date,
  ADD COLUMN locale            text,
  ADD COLUMN timezone          text,
  ADD COLUMN phone             text,
  ADD COLUMN phone_verified_at timestamptz,
  ADD COLUMN onboarding        jsonb NOT NULL DEFAULT '{}',
  ADD COLUMN onboarded_at      timestamptz;

ALTER TABLE accounts
  ADD COLUMN plan_key text REFERENCES plan_catalog(key);

-- Seeds, as upserts: a re-run edits, never duplicates (the 0005 pattern).
INSERT INTO plan_catalog (key, name, tagline, features, sort) VALUES
  ('free',       'Free',       'Try the platform on your own projects.',
     '["1 workspace","3 projects","community support"]', 10),
  ('start',      'Start',      'For one developer shipping every week.',
     '["unlimited projects","hosted agent","e-mail support"]', 20),
  ('pro',        'Pro',        'For teams that share flows and integrations.',
     '["everything in Start","organizations and members","flow sharing","priority support"]', 30),
  ('enterprise', 'Enterprise', 'For companies with their own rules.',
     '["everything in Pro","self-hosted providers","dedicated support","custom terms"]', 40)
ON CONFLICT (key) DO UPDATE SET
  name = EXCLUDED.name, tagline = EXCLUDED.tagline, features = EXCLUDED.features,
  sort = EXCLUDED.sort, active = true;

INSERT INTO provider_catalog
  (key, category, name, credential_kind, permissions, needs_base_url, operated, docs_url, brand_color, sort) VALUES
  ('github', 'git', 'GitHub', 'token',
     '{"repo","read:org","read:user"}', false, true,
     'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens', '#24292F', 10),
  ('gitlab', 'git', 'GitLab', 'token',
     '{"api","read_repository","write_repository"}', false, true,
     'https://docs.gitlab.com/user/profile/personal_access_tokens/', '#FC6D26', 20),
  ('gitlab_self_hosted', 'git', 'GitLab self-hosted', 'token',
     '{"api","read_repository","write_repository"}', true, true,
     'https://docs.gitlab.com/user/profile/personal_access_tokens/', '#FC6D26', 30),
  ('bitbucket', 'git', 'Bitbucket', 'token',
     '{"repository:read","repository:write","pullrequest:write"}', false, false,
     'https://support.atlassian.com/bitbucket-cloud/docs/access-tokens/', '#2684FF', 40),
  ('azure_devops', 'git', 'Azure DevOps', 'token',
     '{"vso.code_write","vso.project"}', true, false,
     'https://learn.microsoft.com/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate', '#0078D4', 50),
  ('jira', 'task_manager', 'Jira', 'token',
     '{"read:jira-work","write:jira-work"}', true, false,
     'https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/', '#0052CC', 10),
  ('clickup', 'task_manager', 'ClickUp', 'token',
     '{}', false, false,
     'https://developer.clickup.com/docs/authentication', '#7B68EE', 20)
ON CONFLICT (key) DO UPDATE SET
  category = EXCLUDED.category, name = EXCLUDED.name,
  credential_kind = EXCLUDED.credential_kind, permissions = EXCLUDED.permissions,
  needs_base_url = EXCLUDED.needs_base_url, operated = EXCLUDED.operated,
  docs_url = EXCLUDED.docs_url, brand_color = EXCLUDED.brand_color,
  sort = EXCLUDED.sort, active = true;

-- +goose Down
ALTER TABLE accounts DROP COLUMN plan_key;
ALTER TABLE users
  DROP COLUMN birth_date, DROP COLUMN locale, DROP COLUMN timezone,
  DROP COLUMN phone, DROP COLUMN phone_verified_at,
  DROP COLUMN onboarding, DROP COLUMN onboarded_at;
DROP TABLE provider_catalog;
DROP TABLE plan_catalog;
```

`gitlab_self_hosted` is `operated=true`: the GitLab adapter takes any base URL, so a self-hosted instance is the same code path with `base_url` set.

- [ ] **Step 2: Apply locally and verify**

Run: `kubectl config use-context k3d-dop-local && make migrate` (the guard refuses any other context).
Then: `kubectl exec -n dop-local postgres-0 -- psql -U dop -d dop -c "select key, operated from provider_catalog order by category, sort"` — expected 7 rows, `github`/`gitlab`/`gitlab_self_hosted` true.

- [ ] **Step 3: Commit**

```bash
git add migrations/0027_onboarding_journey.sql
git commit -m "feat(identity): a jornada de onboarding não tinha onde ser gravada — colunas, catálogos de planos e provedores"
```

---

### Task 2: The `catalog` domain

**Files:**
- Create: `internal/domain/catalog/entity.go`, `repository.go`, `service.go`, `service_test.go`
- Create: `internal/adapter/postgres/catalog.go`

**Interfaces:**
- Produces:
```go
package catalog
type Plan struct { Key, Name, Tagline string; Features []string; Sort int; Active bool }
type Provider struct {
    Key, Category, Name, CredentialKind string
    Permissions []string
    NeedsBaseURL, Operated bool
    DocsURL, BrandColor string
    Sort int; Active bool
}
type Repository interface {
    Plans(ctx context.Context) ([]Plan, error)          // active only, ordered by sort
    Providers(ctx context.Context) ([]Provider, error)  // active only, ordered by category, sort
    PlanByKey(ctx context.Context, key string) (*Plan, error)        // NotFound when inactive or absent
    ProviderByKey(ctx context.Context, key string) (*Provider, error)
}
type Service struct{ repo Repository }
func NewService(r Repository) *Service
func (s *Service) Plans(ctx) ([]Plan, error)
func (s *Service) Providers(ctx) ([]Provider, error)
func (s *Service) PlanByKey(ctx, key string) (*Plan, error)
func (s *Service) ProviderByKey(ctx, key string) (*Provider, error)
```
The service is a pass-through on purpose: the catalogue has no rule beyond "active only", and the rule belongs to the query. It exists so the composition root and the gRPC layer depend on a domain, not on Postgres.

- [ ] **Step 1: Failing test** — `service_test.go` with an in-memory repo: `TestPlansReturnsOnlyActiveInOrder` (two active with sort 20/10 and one inactive → keys `[a b]` in sort order — the fake applies the same filter the SQL will), `TestPlanByKeyRefusesUnknown` (`errs.KindOf(err) == errs.KindNotFound`).
- [ ] **Step 2:** `go test ./internal/domain/catalog/` → FAIL (package missing).
- [ ] **Step 3:** Write entity, repository, service.
- [ ] **Step 4:** Adapter:

```go
func (r *CatalogRepo) Plans(ctx context.Context) ([]catalog.Plan, error) {
    rows, err := r.pool.Query(ctx, `SELECT key, name, tagline, features, sort, active
        FROM plan_catalog WHERE active ORDER BY sort, key`)
    ...features scanned from jsonb into []string
}
func (r *CatalogRepo) Providers(ctx) ... `SELECT key, category, name, credential_kind, permissions,
    needs_base_url, operated, docs_url, brand_color, sort, active
    FROM provider_catalog WHERE active ORDER BY category, sort, key`
```
`PlanByKey`/`ProviderByKey` add `AND key = $1` and translate `pgx.ErrNoRows` to `errs.NotFound("plan %q", key)`.

- [ ] **Step 5:** `go test ./internal/domain/catalog/` → PASS; `go build ./...`.
- [ ] **Step 6: Commit** — `feat(catalog): planos e provedores passam a ser dados lidos pela API`

---

### Task 3: Identity entities, repository and the personal workspace

**Files:**
- Modify: `internal/domain/identity/entity.go`, `repository.go`, `service.go`
- Modify: `internal/adapter/postgres/identity.go`
- Modify: `internal/domain/hierarchy/{service,repository}.go`, `internal/adapter/postgres/hierarchy.go`
- Modify: `internal/app/register.go`, `internal/app/glue.go`
- Test: `internal/domain/identity/service_test.go`, `internal/domain/hierarchy/service_test.go`

**Interfaces:**
- Produces (identity):
```go
type User struct {
    ... existing ...
    BirthDate       *time.Time
    Locale, Timezone, Phone string
    PhoneVerifiedAt *time.Time
    Onboarding      Onboarding      // map[Step]StepStatus
    OnboardedAt     *time.Time
}
type Account struct { ... existing ...; PlanKey string }

type Step string
const (
    StepProfile Step = "profile"; StepContact Step = "contact"; StepCode Step = "code"
    StepTasks Step = "tasks"; StepPlan Step = "plan"
)
type StepStatus string
const ( StepDone StepStatus = "done"; StepSkipped StepStatus = "skipped" )
type Onboarding map[Step]StepStatus
func Steps() []Step                       // journey order
func (s Step) Required() bool             // profile, code, plan
func ValidStep(s Step) bool

// Repository additions
UpdateProfile(ctx, u *User) (*User, error)                 // name, birth_date, locale, timezone, phone; emits phone_added when phone changed to non-empty (accountID param below)
SetPhoneVerified(ctx, userID, phone string, at time.Time) error  // only when users.phone = phone; emits phone_verified
SetOnboardingStep(ctx, userID string, step Step, status StepStatus) (*User, error)
SetOnboardedAt(ctx, userID string, at time.Time) (*User, error)
UpdateAccountProfile(ctx, accountID, handle, displayName string) (*Account, error)
SetAccountPlan(ctx, accountID, planKey string) (*Account, error)

// Ports declared in identity (same pattern as StepUpGate / Grants)
type WorkspaceProvisioner interface {
    EnsurePersonalWorkspace(ctx context.Context, accountID, name string) error
}
func (s *Service) WithWorkspaces(w WorkspaceProvisioner) *Service
type Plans interface { PlanExists(ctx context.Context, key string) (bool, error) }
func (s *Service) WithPlans(p Plans) *Service
```
- Produces (hierarchy):
```go
func (s *Service) EnsurePersonalWorkspace(ctx context.Context, accountID, name string) error
// repository: WorkspaceByKey(ctx, accountID, key string) (*Workspace, error) — NotFound when absent
const PersonalWorkspaceKey = "personal"
```

- [ ] **Step 1: Failing tests (identity)**

```go
func TestEnsureUserProvisionsThePersonalWorkspace(t *testing.T) {
    repo := newFakeRepo(); ws := &fakeWorkspaces{}
    svc := identity.NewService(repo, fixedClock{now}).WithWorkspaces(ws)
    _, acct, err := svc.EnsureUser(ctx, principal("sub-1"))
    // ws.calls == [{acct.ID, "Personal"}]
    svc.EnsureUser(ctx, principal("sub-1")) // second login
    // ws.calls still length 2 (the call is repeated; idempotence is the provisioner's) — assert both carry acct.ID
}
func TestEnsureUserWithoutProvisionerStillWorks(t *testing.T)  // domain tests without wiring keep passing
```
`fakeWorkspaces` records `(accountID, name)`; `EnsurePersonalWorkspace` is called AFTER the personal account exists, on every EnsureUser (cheap: the adapter's `WorkspaceByKey` hit), so an account created before this change gains its workspace on next login.

- [ ] **Step 2: Failing tests (hierarchy)** — `TestEnsurePersonalWorkspaceIsIdempotent`: two calls, one workspace with key `personal`, name from the first call.
- [ ] **Step 3:** run both → FAIL.
- [ ] **Step 4: Implement** — entities, repository interface, `EnsureUser` calls `s.workspaces.EnsurePersonalWorkspace(ctx, personal.ID, "Personal")` when wired (a nil provisioner lets through, like `requireStepUp`). The name is the English default; the profile step's locale does not exist yet at first login, so the cockpit shows the workspace name through i18n when `key == "personal"` — the core stores a plain name. Hierarchy: `EnsurePersonalWorkspace` runs with `ctxutil.Into(ctx, call with AccountID=accountID)` because `CreateWorkspace` reads the account from the context and EnsureUser runs before there is an active account.
- [ ] **Step 5: Adapter** — `userCols` gains the seven columns; `scanUser` scans `*time.Time` via `pgtype`/`sql.NullTime`; `onboarding jsonb` → `map[string]string` → `Onboarding`. New methods:

```go
func (r *IdentityRepo) UpdateProfile(ctx, u *identity.User, personalAccountID string) (*identity.User, error) {
    // one tx: read previous phone; UPDATE users SET name=..., birth_date=..., locale=..., timezone=..., phone=NULLIF($,''),
    //   phone_verified_at = CASE WHEN phone IS DISTINCT FROM NULLIF($,'') THEN NULL ELSE phone_verified_at END, updated_at=now()
    // if new phone != "" && new phone != previous: Emit(dop.identity.user.phone_added, AccountID=personalAccountID, Aggregate "user", Payload {"phone_masked": last4})
}
func (r *IdentityRepo) SetPhoneVerified(ctx, userID, phone string, at time.Time, personalAccountID string) error {
    // UPDATE users SET phone_verified_at=$3 WHERE id=$1 AND phone=$2 ; if 0 rows → nil (a factor for another number is not the contact phone)
    // else Emit(dop.identity.user.phone_verified, AccountID=personalAccountID)
}
```
The repository signature carries `personalAccountID` because the adapter has no way to find it and the event must land in that account's box (spec D-8). `SetOnboardingStep`: `UPDATE users SET onboarding = onboarding || jsonb_build_object($2::text, $3::text)`. `SetOnboardedAt`, `UpdateAccountProfile` (translate the unique violation on `handle` to `errs.Conflict` with `KeyHandleTaken`), `SetAccountPlan`. `accountCols` gains `COALESCE(plan_key,'')`. Hierarchy adapter: `WorkspaceByKey`.

- [ ] **Step 6: Wire** — in `register.go` after `hierarchySvc` exists: `identitySvc.WithWorkspaces(personalWorkspaces{hierarchySvc})` and `identitySvc.WithPlans(planLookup{catalogSvc})` (catalog service created in Task 2's wiring — add `catalogSvc := catalog.NewService(postgres.NewCatalogRepo(deps.Pool))` here). Glue types in `glue.go`.
- [ ] **Step 7:** `make test` → PASS; `make lint`.
- [ ] **Step 8: Commit** — `feat(identity): a conta pessoal nasce com o seu workspace, e o usuário ganha o que a jornada grava`

---

### Task 4: Profile, handle, plan and the journey's rules

**Files:**
- Create: `internal/domain/identity/profile.go`, `onboarding.go`, `profile_test.go`, `onboarding_test.go`

**Interfaces:**
```go
type ProfilePatch struct {
    Name *string; BirthDate *time.Time; Locale, Timezone, Phone *string  // nil = untouched
}
func (s *Service) UpdateProfile(ctx, patch ProfilePatch) (*User, error)   // actor from ctx; validates: name ≤ 120 after trim and non-empty when set; locale matches ^[a-z]{2}(-[A-Z]{2})?$; timezone non-empty ≤ 64; phone E.164 ^\+[1-9]\d{6,14}$ or "" to clear; birth date not in the future and after 1900
func (s *Service) MarkPhoneVerified(ctx, userID, phone string) error       // called by the second factor; not by any RPC
type HandleAvailability struct { Handle string; Available bool; Suggestion string }
func (s *Service) HandleAvailability(ctx, handle string) (HandleAvailability, error) // normalized; suggestion = handle + "-" + randomSuffix(4) when taken; ValidateHandle errors are returned as Invalid
func (s *Service) UpdatePersonalAccount(ctx, handle, displayName string) (*Account, error)  // only the actor's PERSONAL account, only by its owner; either field may be ""
func (s *Service) SetPlan(ctx, planKey string) (*Account, error)           // personal account; Plans port must say it exists → else Invalid with KeyPlanUnknown

type OnboardingState struct {
    Steps           map[Step]StepStatus
    Current         Step        // first step in Steps() order that is neither done nor skipped; "" when complete
    EmailVerified   bool
    Phone           string; PhoneVerified bool
    CodeConnections, TaskConnections int
    PlanKey         string
    Complete        bool        // OnboardedAt != nil
    PersonalAccountID string
}
type Connections interface { CountIntegrations(ctx, accountID string) (git, tasks int, err error) }
func (s *Service) WithConnections(c Connections) *Service
func (s *Service) Onboarding(ctx) (*OnboardingState, error)
func (s *Service) RecordStep(ctx, step Step, status StepStatus) (*OnboardingState, error) // ValidStep; skipped only when !step.Required() → else Invalid KeyStepNotSkippable; done on `code` requires git ≥ 1 → else Precondition KeyCodeConnectionRequired; done on `plan` requires PlanKey != "" → Precondition KeyPlanRequired; done on `profile` requires Name != "" → Precondition
func (s *Service) CompleteOnboarding(ctx) (*OnboardingState, error)       // every Required() step done → else Precondition KeyStepMissing with params {"step": ...}; idempotent
```
Translation keys added next to the existing block: `identity.profile.name_required`, `identity.profile.locale_invalid`, `identity.profile.timezone_invalid`, `identity.profile.phone_invalid`, `identity.profile.birth_date_invalid`, `identity.plan.unknown`, `identity.onboarding.step_unknown`, `identity.onboarding.step_not_skippable`, `identity.onboarding.code_connection_required`, `identity.onboarding.plan_required`, `identity.onboarding.step_missing`, `identity.account.not_personal`.

- [ ] **Step 1: Failing tests**

`onboarding_test.go`:
- `TestStepsOrderAndRequirement` — `Steps()` equals `[profile contact code tasks plan]`; `Required()` true exactly for profile/code/plan.
- `TestRecordStepRefusesSkippingARequiredStep` — `RecordStep(ctx, StepCode, StepSkipped)` → `KindInvalid`.
- `TestRecordStepCodeNeedsAConnection` — connections fake returns (0,0) → Precondition; returns (1,0) → done, `Current == StepTasks`.
- `TestCompleteRefusesNamingTheMissingStep` — profile done, code done, plan undone → Precondition with `Params["step"] == "plan"`.
- `TestCompleteIsIdempotent` — two calls, `Complete == true`, `OnboardedAt` set once (clock fixed).
- `TestOnboardingCurrentSkipsSkipped` — contact skipped, profile done → `Current == StepCode`.

`profile_test.go`:
- `TestUpdateProfileValidates` — table: bad locale `"portuguese"`, bad phone `"11999"`, future birth date, empty name → all `KindInvalid` with the right code.
- `TestUpdateProfileClearsVerificationWhenPhoneChanges` — the fake repo mirrors the adapter's rule; set phone A, mark verified, set phone B → `PhoneVerifiedAt == nil`.
- `TestHandleAvailabilitySuggestsWhenTaken` — existing account `dev` → `Available false`, suggestion starts with `dev-`.
- `TestUpdatePersonalAccountRefusesOrganizations` — active account is an organization → `KindPermission` (or Invalid `KeyAccountNotPersonal`).
- `TestSetPlanRefusesUnknown` — plans fake says false → Invalid `KeyPlanUnknown`; says true → `PlanKey == "pro"`.

- [ ] **Step 2:** `go test ./internal/domain/identity/` → FAIL.
- [ ] **Step 3: Implement** the two files; extend `fakeRepo` with the six methods and the `plans`, `connections` fakes.
- [ ] **Step 4:** PASS; `make lint`.
- [ ] **Step 5: Commit** — `feat(identity): perfil, handle, plano e as regras da jornada — o que é obrigatório e o que pode ser pulado`

---

### Task 5: The phone reminder — second factor and attention

**Files:**
- Modify: `internal/domain/secondfactor/service.go` (Users port + Confirm), `internal/app/glue.go`
- Modify: `internal/domain/attention/entity.go`, `rules.go`, `rules_test.go`, `entity_test.go`
- Modify: `internal/app/register.go` (nothing — the subscription reads `attention.Subjects()`)

**Interfaces:**
```go
// secondfactor.Users gains:
PhoneVerified(ctx context.Context, userID, destination string) error
// Confirm: after ActivateFactor, if f.Kind == KindSMS → s.users.PhoneVerified(ctx, userID, f.Destination); an error here is logged and does NOT fail the confirmation (the factor is live; the reminder is the only loser)

// attention
const KindContactPhoneUnverified Kind = "contact_phone_unverified"   // impact 80 (below thread_blocked: a reminder never outranks work)
const EvPhoneAdded = "dop.identity.user.phone_added"; EvPhoneVerified = "dop.identity.user.phone_verified"
const KeyContactPhone = "attention.contact_phone_unverified.title"
Subjects() adds "dop.identity.>"
Apply: EvPhoneAdded → open(e, KindContactPhoneUnverified, "user", e.AggregateID, KeyContactPhone, {"phone_masked": ...}, "Confirm your phone number", ""); EvPhoneVerified → closeFor(KindContactPhoneUnverified, "user", e.AggregateID)
```

- [ ] **Step 1: Failing tests** — `rules_test.go`: `TestPhoneAddedOpensAReminderAndVerifiedClosesIt` (Apply on both events; open item has `TargetKind "user"` and the user id); `entity_test.go`'s table-coverage test must include the new kind (it fails until `Kinds()` and `impact` carry it). `secondfactor/service_test.go`: `TestConfirmingAnSMSFactorReportsThePhone` — the users fake records `(userID, destination)`; confirming a TOTP factor records nothing.
- [ ] **Step 2:** FAIL. **Step 3:** implement. Glue: `secondFactorUsers.PhoneVerified` → `u.id.MarkPhoneVerified(ctx, userID, destination)` (identity resolves the personal account and calls the repo).
- [ ] **Step 4:** `make test` PASS. `make test-integration` for the attention projection if the local cluster is up (optional; the unit rule test is the gate).
- [ ] **Step 5: Commit** — `feat(attention): um telefone não confirmado vira lembrete na caixa, e a confirmação o fecha`

---

### Task 6: Checking a credential

**Files:**
- Modify: `internal/domain/resource/service.go`, `entity.go`, `service_test.go`
- Modify: `internal/adapter/gitprovider/github.go`, `gitlab.go`, and the contract suite `test/contract/gitprovider*.go` (find with `grep -rl "OpenPullRequest" test/`)
- Create: `internal/app/checkers.go`

**Interfaces:**
```go
// resource
type CheckResult struct { Operated bool; OK bool; Identity string; Message string }
type CredentialChecker interface {
    // Check probes the provider with the resolved secret. Operated=false means
    // the platform has no adapter for this provider: the credential is stored,
    // nothing was tried.
    Check(ctx context.Context, spec IntegrationSpec, secret []byte) (CheckResult, error)
}
func (s *Service) WithChecker(c CredentialChecker) *Service
func (s *Service) Check(ctx, resourceID string) (CheckResult, error)
// rules: kind must be integration → else Invalid; authorize(ctx, actor, id, LevelUse); secret from s.secrets.Get(SecretRefFor(accountID, id)); empty → Precondition KeyNoCredential ("store a credential first"); no checker wired → CheckResult{Operated:false, Message:"no checker wired"}

// gitprovider
func (g *GitHub) Whoami(ctx context.Context) (string, error)   // GET /user → login; 401 → errs.Unauthorized("the token was refused")
func (g *GitLab) Whoami(ctx context.Context) (string, error)   // GET /user → username

// app/checkers.go
type integrationCheckers struct{ cfg *config.Config }
func (c integrationCheckers) Check(ctx, spec resource.IntegrationSpec, secret []byte) (resource.CheckResult, error) {
    switch spec.Provider {
    case "github": ... NewGitHub(APIBase: spec.BaseURL or cfg.GitHubAPI, Token: string(secret)).Whoami
    case "gitlab", "gitlab_self_hosted": ... NewGitLab(...)
    default: return resource.CheckResult{Operated: false, Message: "this provider is registered but not operated yet"}, nil
    }
    // a Whoami error of KindUnauthorized → {Operated:true, OK:false, Message:"the token was refused"}, nil ; other errors propagate
}
```

- [ ] **Step 1: Failing tests** — `resource/service_test.go`: `TestCheckRefusesWithoutCredential`, `TestCheckPassesTheResolvedSecretToTheChecker` (fake checker records spec.Provider and secret), `TestCheckOnNonIntegrationIsInvalid`. Contract suite: `TestWhoamiReturnsTheLogin` against the suite's fake HTTP server (`GET /user` → `{"login":"octocat"}`; GitLab `{"username":"gl"}`), and `TestWhoamiRefusedIs401`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** `make test` PASS.
- [ ] **Step 5: Commit** — `feat(resource): uma credencial pode ser testada — quem somos para o provedor, ou a resposta honesta de que ele ainda não é operado`

---

### Task 7: The contract and the gRPC servers

**Files:**
- Modify: `api/proto/dop/v1/identity.proto`, `resource.proto`; Create: `api/proto/dop/v1/catalog.proto`
- Modify: `internal/app/grpc/identity.go`, `resource.go`; Create: `internal/app/grpc/catalog.go`
- Modify: `internal/app/register.go`

- [ ] **Step 1: identity.proto** — `User` gains `string locale = 7; string timezone = 8; string phone = 9; bool phone_verified = 10; bool onboarded = 11; string birth_date = 12;` (ISO date or empty). `Account` gains `string plan_key = 21;`. New messages and RPCs:

```proto
rpc UpdateProfile(UpdateProfileRequest) returns (User);
rpc GetOnboarding(GetOnboardingRequest) returns (OnboardingState);
rpc RecordOnboardingStep(RecordOnboardingStepRequest) returns (OnboardingState);
rpc CompleteOnboarding(CompleteOnboardingRequest) returns (OnboardingState);
rpc CheckHandle(CheckHandleRequest) returns (HandleAvailability);
rpc UpdatePersonalAccount(UpdatePersonalAccountRequest) returns (Account);
rpc SetPlan(SetPlanRequest) returns (Account);

message UpdateProfileRequest {
  optional string name = 1; optional string birth_date = 2;  // "" clears
  optional string locale = 3; optional string timezone = 4; optional string phone = 5;
}
message GetOnboardingRequest {}
message OnboardingStep { string step = 1; string status = 2; }  // status: done | skipped | pending
message OnboardingState {
  repeated OnboardingStep steps = 1;   // in journey order, every step present
  string current = 2; bool complete = 3;
  bool email_verified = 4; string phone = 5; bool phone_verified = 6;
  int32 code_connections = 7; int32 task_connections = 8;
  string plan_key = 9; string personal_account_id = 10;
}
message RecordOnboardingStepRequest { string step = 1; string status = 2; }
message CompleteOnboardingRequest {}
message CheckHandleRequest { string handle = 1; }
message HandleAvailability { string handle = 1; bool available = 2; string suggestion = 3; }
message UpdatePersonalAccountRequest { string handle = 1; string display_name = 2; }
message SetPlanRequest { string plan_key = 1; }
```
`catalog.proto`: `service CatalogService { rpc ListPlans(ListPlansRequest) returns (ListPlansResponse); rpc ListProviders(ListProvidersRequest) returns (ListProvidersResponse); }` with `Plan {key,name,tagline,repeated features,sort}` and `Provider {key,category,name,credential_kind,repeated permissions,needs_base_url,operated,docs_url,brand_color,sort}`. `resource.proto`: `rpc CheckResource(CheckResourceRequest) returns (CheckResult);` with `CheckResourceRequest { reserved 1; string id = 2; }`, `CheckResult { bool operated = 1; bool ok = 2; string identity = 3; string message = 4; }`.

- [ ] **Step 2:** `make proto && make proto-breaking` → both green.
- [ ] **Step 3: Servers** — thin translation only. `GetOnboarding`/`RecordOnboardingStep`/`CompleteOnboarding` read the actor from the context (identity's methods already do). `ListPlans`/`ListProviders` need a session but no active account: check how `GetInvite` is exempted from the account requirement in the interceptor (`grep -n "GetInvite" internal/app/grpc/*.go internal/platform/*/*.go`) and add `CatalogService/*`, `IdentityService/GetOnboarding`, `RecordOnboardingStep`, `CompleteOnboarding`, `UpdateProfile`, `CheckHandle` to the same exemption — the journey runs BEFORE the cockpit has picked an account (it has one, the personal, and the BFF sends it; the exemption is for robustness, not a shortcut — keep the actor requirement).
- [ ] **Step 4:** `make build && make test && make lint`.
- [ ] **Step 5: Commit** — `feat(contract): a jornada de onboarding no contrato — perfil, estado, handle, plano, catálogo e teste de credencial`

Then push the branch, open no PR yet: `git push -u origin feat/onboarding-journey`.

---

### Task 8: The BFF — use cases, routes, gRPC, tests

**Files:**
- Run: `make proto` (core stubs); edit `api/proto/dop/bff/v1/{identity,resource}.proto`, create `catalog.proto`; `make proto-bff`
- Modify: `app/usecases/identity.py`, `app/routers/identity.py`, `app/grpcapi/identity.py`
- Create: `app/usecases/catalog.py`, `app/routers/catalog.py`, `app/grpcapi/catalog.py`
- Modify: `app/usecases/resource.py`, `app/routers/resource.py`, `app/grpcapi/resource.py`, `app/grpcapi/server.py` (register the catalog servicer), `app/main.py` (include the router)
- Modify: `tests/conftest.py` (FakeCore gains `GetUser`, `UpdateProfile`, `GetOnboarding`, `RecordOnboardingStep`, `CompleteOnboarding`, `CheckHandle`, `UpdatePersonalAccount`, `SetPlan`; a `FakeCatalog`; `FakeResource.CheckResource`)
- Create: `tests/test_onboarding.py`, `tests/test_catalog.py`; extend `tests/test_resource.py`

**Interfaces (REST, all under `/api/v1`):**

| route | use case | decorator |
|---|---|---|
| `GET /me` | `me()` — now merges the core's `GetUser(user_id)`: `name`, `avatar_url`, `locale`, `timezone`, `phone`, `phone_verified`, `onboarded` | as today |
| `PATCH /me` body `ProfilePatch{name?, birth_date?, locale?, timezone?, phone?}` | `update_profile(body)` | `@log` (session; the account is irrelevant) |
| `GET /me/onboarding` | `onboarding()` → `OnboardingState` | `@log` |
| `POST /me/onboarding/steps/{step}` body `{status}` | `record_step(step, body)` | `@log` |
| `POST /me/onboarding/complete` | `complete_onboarding()` | `@log` |
| `GET /accounts/handles/{handle}/availability` | `handle_availability(handle)` | `@log` |
| `PATCH /accounts/current` body `{handle?, display_name?}` | `update_personal_account(body)` | `@log @account_scoped` |
| `PUT /accounts/current/plan` body `{plan_key}` | `set_plan(body)` | `@log @account_scoped` |
| `GET /catalog/plans` · `GET /catalog/providers` | `plans()` · `providers()` | `@log` (session only) |
| `POST /resources/{id}/check` | `check_resource(id)` → `CheckResult` | `@log @account_scoped` |

Pydantic models: `ProfilePatch`, `OnboardingStep{step,status}`, `OnboardingState` (fields as the proto), `StepUpdate{status}`, `HandleAvailability`, `AccountPatch`, `PlanChoice`, `PlanSummary{key,name,tagline,features:list[str]}`, `ProviderSummary{key,category,name,credential_kind,permissions:list[str],needs_base_url,operated,docs_url,brand_color}`, `CheckResult{operated,ok,identity,message}`. `MeResponse` gains `avatar_url: str = ""`, `locale`, `timezone`, `phone`, `phone_verified: bool = False`, `onboarded: bool = False`. `AccountSummary` gains `plan_key: str = ""`.

Edge proto: mirror every route as an RPC on the existing services (`IdentityService.UpdateProfile/GetOnboarding/RecordOnboardingStep/CompleteOnboarding/CheckHandle/UpdatePersonalAccount/SetPlan`, `ResourceService.CheckResource`) and a new `CatalogService`.

- [ ] **Step 1: Failing tests** — `test_onboarding.py`: one test per route proving the request the core receives (`core.RecordOnboardingStep.last["request"].step == "code"`), the 412 translation on `FAILED_PRECONDITION` with the core's message, and `TestParityBetweenTransports` (REST and gRPC build the same core request for `record_step` and `set_plan`). `test_catalog.py`: `GET /catalog/plans` maps `features`; no `x-account-id` needed. `test_resource.py`: `POST /resources/r-1/check` passes the id and returns `operated/ok/identity/message`.
- [ ] **Step 2:** `make test` → FAIL on the new files.
- [ ] **Step 3:** implement use cases → routers → servicers.
- [ ] **Step 4:** `make test && make lint` → PASS. Confirm the OpenAPI carries the new routes: `uv run python -c "from app.main import create_app; import json; s=create_app().openapi(); print([p for p in s['paths'] if 'onboarding' in p or 'catalog' in p or 'check' in p])"`.
- [ ] **Step 5: Commit** — `feat(api): a jornada de onboarding chega à borda — REST e gRPC sobre os mesmos casos de uso`

---

### Task 9: Deploy to QA and regenerate the cockpit's client

**Files:**
- Modify: `repos/dop-infra/terraform/stacks/platform/envs/qa.tfvars` (`core_image_tag`, `api_image_tag`)
- Modify: `repos/dop-app/lib/api-spec/openapi.json` and the generated client (via the scripts, never by hand)

- [ ] **Step 1: Migrate QA** — the migration runs on the data VM's Postgres container, never through `kubectl`: find the VM name in `terraform/stacks/platform/vm.tf`; then
```bash
gcloud compute scp repos/dop-core/migrations/0027_onboarding_journey.sql <vm>:/tmp/m.sql --zone <zone> --project dop-qa
gcloud compute ssh <vm> --zone <zone> --project dop-qa --command \
  "sed -n '/-- +goose Up/,/-- +goose Down/p' /tmp/m.sql | grep -v goose > /tmp/up.sql && sudo docker exec -i postgres psql -U dop -d dop -f /tmp/up.sql"
```
Verify with `select count(*) from provider_catalog` → 7.
- [ ] **Step 2: Images** — from `repos/dop-infra`: `make image-core CORE_TAG=0.1.0-19 image-api API_TAG=0.1.0-11` (check the Makefile's registry variable for QA's Artifact Registry — `grep -n REGISTRY Makefile`); bump `qa.tfvars`; `terraform apply -var-file=envs/qa.tfvars` from `terraform/stacks/platform` (after `terraform init -backend-config=envs/qa.backend`).
- [ ] **Step 3: Smoke** — `scripts/qa-smoke.sh`, then `curl -s $API/openapi.json | jq '.paths | keys | map(select(test("onboarding|catalog|check")))'`.
- [ ] **Step 4: Cockpit client** — in `repos/dop-app`: `pnpm --filter @workspace/api-spec run fetch-spec && pnpm --filter @workspace/api-spec run codegen && pnpm typecheck`; commit `chore(api-spec): o contrato alcança a jornada de onboarding — hooks e schemas regenerados`; push `dev`.
- [ ] **Step 5: Umbrella** — advance the three pointers (`dop-core`, `dop-api`, `dop-infra`, `dop-app`) in one commit: `chore: avança os ponteiros (backend da jornada de onboarding no QA)`.

---

## Self-review

**Spec coverage.** §3 steps ↔ Task 4's `Steps()`; §4 data ↔ Task 1; §5 contract row by row: journey state/record/finish → Tasks 4, 7, 8; profile → 4, 7, 8; phone code → existing second factor + Task 5; personal account + handle → 4, 7, 8; providers/plans → 2, 7, 8; connection → existing; test → 6, 7, 8; reminder → 5; `MeResponse`/`AccountSummary` additions → 8. D-3 → Task 3. D-8 → Task 5. §6 dop-infra (SMS credential for QA) is NOT in this plan: it needs the owner's Twilio/Zenvia credential (spec §10.3) — recorded as the one deliberate gap.

**Placeholders.** None: every step names its file, its test and its command. Task 9's `<vm>`/`<zone>` are read from `vm.tf` at execution time, which the step says.

**Type consistency.** `identity.Step`/`StepStatus`/`Onboarding` (Task 3) are what Task 4's `RecordStep` and Task 7's proto translation use; `resource.IntegrationSpec` (exists) is what `CredentialChecker.Check` takes; `CheckResult` field names match the proto and the Pydantic model (`operated, ok, identity, message`); `Connections.CountIntegrations` is satisfied by a glue over `resource.Service.List(ctx, KindIntegration)` filtered by category, wired in `register.go` as `identitySvc.WithConnections(integrationCounts{resourceSvc})` — note it needs the account in the context; the glue builds it from `personalAccountID` the way Task 3's provisioner does.

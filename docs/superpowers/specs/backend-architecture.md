# Backend architecture — skeletons, contracts and schema

> **Status:** Approved for review · **Date:** 2026-08-30 · **Project:** the DOP platform
>
> **Answers:** how the backend is organized, what the contracts are, the database's schema, the
> cross-cutting concerns (logging/security) and the implementation order.
> **Does not answer:** navigation and screens (the navigation spec); the demand's cycle (the
> workflow spec); the executor (its own spec).
>
> **Diagrams:** https://claude.ai/code/artifact/1ec0f828-ac7d-473a-ba5f-7bc0d6503402

The base decisions: [ADR-0012](../../adr/0012-stack-go-core-python-bff.md) (stack and
boundary), [ADR-0013](../../adr/0013-proto-as-source-of-truth.md) (the contract),
[ADR-0014](../../adr/0014-postgres-persistence.md) (the database),
[ADR-0014](../../adr/0014-postgres-persistence.md) (events),
[ADR-0015](../../adr/0015-firebase-emulators-and-single-owner.md) (local and Terraform),
[ADR-0001](../../adr/0001-infrastructure-behind-ports.md) (ports).

## 1. The organizing principle

**A separate service where isolation is a requirement; a module where it is only
organization.** Microservices early buy an operational cost with no benefit. The base is a
**modular monolith** with rigid domain boundaries inside the process, and only two points of
real physical isolation: the **edge** (protocols, the agent's session) and the **execution
plane** (untrusted code, KVM, a long life).

```
THE CONTROL PLANE            THE EXECUTION PLANE
├── dop-app    the SPA       ├── dop-launcher   (a mode of the core)
├── dop-api    the Python BFF└── sandbox        a microVM per demand
└── dop-core   Go — serve · worker · sched · launcher
```

One image of the core, four modes through a subcommand: one artifact, one pipeline.

## 2. Contracts — `proto/dop/v1`

| File | Content |
|---|---|
| `common` | `AccountRef` · `ActorRef` · `Money` · pagination · `idempotency_key` |
| `identity` | User · Account · Membership · Invite |
| `resource` | Resource (`integration`\|`skill`\|`workflow`\|`git_flow`) · Grant |
| `hierarchy` | Workspace · Project · attaching resources |
| `workflow` | Flow · a typed Stage · resolving the inheritance chain |
| `demand` | Demand · Thread · Message · Artifact · Finding |
| `execution` | Sandbox · provision/suspend/resume/destroy · `isolationTier` |
| `delivery` | PullRequest · MergeQueue · Directive (the techlead) |
| `knowledge` | Rules · Index · Memory · ContextPackage · semantic search |
| `cost` | UsageEvent · Budget · RoutingDecision |

ADR-0013's conventions: server-side streaming for everything live (`WatchDemand`,
`StreamLogs`, `WatchAttention` → SSE in the BFF); a `Ref` instead of a loose id; an
`idempotency_key` on every write; `buf breaking` in CI.

## 3. The core's skeleton (Go)

```
dop-core/
├── cmd/dop-core/main.go        # serve | worker | sched | launcher
├── api/proto/                  # .proto + generated (buf)
├── internal/
│   ├── domain/                 # ZERO infra imports
│   │   ├── identity/ resource/ hierarchy/ workflow/
│   │   ├── demand/ execution/ delivery/ knowledge/ cost/
│   │   └── (each one: entity.go · service.go · port.go · errors.go)
│   ├── app/                    # use cases; it opens the transaction; it orchestrates domains
│   ├── adapter/
│   │   ├── grpc/               # the server: proto ↔ domain
│   │   ├── postgres/           # repositories + the outbox (sqlc)
│   │   ├── nats/               # publisher · consumers · DLQ
│   │   ├── k8s/                # the launcher
│   │   ├── objectstore/        # gcs.go (real) · gcs_emulated.go
│   │   ├── secretstore/        # gcpsm.go · k8ssecret.go
│   │   └── gitprovider/        # github · gitlab · azuredevops
│   └── platform/               # log · ctx · errors · idempotency · telemetry
├── migrations/                 # goose
└── test/contract/              # contract tests per port (ADR-0001)
```

**A rule policed in CI:** `internal/domain` does not import `internal/adapter`. An architecture
test breaks the build — that is how the boundary survives time.

## 4. The BFF's skeleton (Python)

```
dop-api/
├── app/
│   ├── main.py                 # the STORAGE_EMULATOR_HOST bridge (ADR-0015 §4)
│   ├── platform/
│   │   ├── context.py          # ContextVar: request_id · principal · the active account
│   │   ├── logging/            # config · middleware · decorator
│   │   ├── security/           # firebase · middleware · decorator
│   │   └── errors.py           # gRPC status ↔ HTTP
│   ├── coreclient/             # generated stubs + a wrapper: deadline, retry, idempotency
│   ├── routers/                # REST + SSE per domain
│   ├── grpc/                   # the gRPC server for the CLI and the sandbox
│   └── agent/                  # AgentRuntime: session, streaming, tools, cost
└── tests/
```

**The BFF opens no connection to Postgres** (ADR-0012). Every write goes through the core.

### 4.1 Cross-cutting concerns through decorators

The pattern adopted: **a ContextVar filled in by middleware + decorators that read the
context** — the handler receives no auth or log parameter; the cross-cutting concern stays
invisible in the business code.

| Decorator | Effect |
|---|---|
| `@log(level=, mask=[])` | entry, exit, error and duration; automatic masking of secrets |
| `@public` | exempt from authentication (registered by a route sweep at boot) |
| `@require_role("admin")` | the role in the active account |
| `@require_grant("use")` | a resource grant (ADR-0009) |
| `@account_scoped` | injects the active account and **refuses a request without one** (SP-0's rule) |

The automatic mask covers `password`, `token`, `secret`, `authorization`, `api_key`,
`private_key`, `client_secret` — secret redaction is a requirement (F-10), not a convenience.

## 5. The schema (the essentials)

```sql
-- identity and ownership
users · accounts(kind) · memberships(user,account,role) · invites
resources(account_id, kind, name, version, config JSONB, credential_ref)
resource_grants(resource_id, user_id, level)            -- use | manage
workspaces(account_id) · projects(workspace_id) · project_resources

-- flow and demand
flows(owner_scope, owner_id, version, spec JSONB)       -- the inheritance chain
demands(project_id, external_key, flow_version_frozen, status)
demand_stages(demand_id, key, type, status, artifact_path)   -- a path in the root repository (ADR-0021); not in migration 0006 yet
threads(demand_id, kind, agent_card JSONB) · messages · findings

-- the spine
events(id, account_id, aggregate, type, payload JSONB, occurred_at)  -- append-only, monthly partition
outbox(event_id, published_at NULL)
idempotency(key, request_hash, response, expires_at)

-- knowledge
knowledge_artifacts(project_id, kind, path, commit, meta JSONB)   -- an INDEX over the root repository; the text is in git (ADR-0021)
project_repositories(project_id, clone_url, mirror_url, mirror_credential_ref)
knowledge_embeddings(artifact_id, embedding vector(1536))

-- delivery and cost
pull_requests(demand_id, repo, state, reviewers JSONB)
merge_queue(repo_id, demand_id, position, state)
directives(project_id, kind, payload JSONB, decided_by)   -- the techlead
usage_events(demand_id, thread_id, model, tokens JSONB, cache JSONB)
budgets(scope, scope_id, limit_cents, spent_cents)
```

Every domain table carries an `account_id` with an FK — isolation is a constraint, not a
convention. Projections are born as *materialized views*; they become tables fed by the worker
only if the cost demands it.

## 6. The local environment

```
dev.sh  →  start · stop · status · logs · reset  (per service)
└── k3d
    ├── postgres + pgvector (CloudNativePG)
    ├── nats jetstream
    ├── firebase emulators   auth :9099 · storage :9199 · ui :4000
    ├── dop-core (serve|worker|sched)
    └── dop-api
```

The emulators' persistence, the variable bridge and Terraform's ownership: ADR-0015.

## 7. The implementation order

1. ✅ **The foundation** — done on 2026-08-31. Both repositories with a skeleton, 10 protos
   generating Go, the initial migration applied, the k3d environment up, the architecture test
   and the contract tests passing. Detail in §9.
2. **A thin vertical slice** — sign in → a personal account → the BFF calls the core → the
   cockpit lists nothing. Four endpoints prove the whole stack end to end.
3. **Resources and hierarchy** — integrations (a SecretStore with two adapters and contract
   tests), workspaces, projects.
4. **The event spine** — the outbox, the relay, NATS, the first projection (the timeline).
5. **Execution** — the launcher, the sandbox, the AgentRuntime, the first real demand.

## 8. Risks

| # | |
|---|---|
| R-1 | **Two languages** double the toolchain and CI — mitigated by a narrow boundary (gRPC only) and one proto as the source |
| R-2 | **The BFF getting fat** and becoming a second owner of the domain — the "no database in the BFF" rule is the test; a violation is an architecture bug |
| R-3 | **The relay's latency** between the commit and the publication — acceptable; `LISTEN/NOTIFY` if it hurts |
| R-4 | **The event load in the same Postgres** — monthly partitioning, retention and vigilance from the first migration |
| R-5 | **Resource ownership in Terraform** — a silent loss on `apply`; `dop-infra`'s single-owner table is the mitigation (ADR-0015 §5) |

## 9. The foundation's state (2026-08-31)

**Built and verified:**

| | |
|---|---|
| Contracts | 10 `.proto`, 9 services, 65 RPCs; `buf lint` clean, Go generated |
| Ports | `SecretStore` (k8s + memory), `ObjectStore` (real/emulated GCS), `IdentityProvider` (Firebase), `EventBus` (NATS JetStream), `ProjectRepository` (the platform's git server + a local bare-repo adapter — ADR-0021) |
| The spine | A transactional outbox + a relay with `FOR UPDATE SKIP LOCKED`; `events` partitioned by month |
| The schema | 16 tables applied in the local Postgres; the owner invariant as a **trigger** |
| Cross-cutting | 5 decorators in the BFF; JSON logging with identical canonical fields in both processes |
| Tests | 7 `SecretStore` contract guarantees, the architecture test, 21 BFF tests |
| Collections | 18 Bruno requests in `docs/api/` |

**Two traps found and solved during the construction:**

1. **A logger bound at import** freezes the default configuration (the `configure()` runs in the
   lifespan) and the lines come out outside the JSON format — **with no visible error**. Fixed
   with late access; the format test now covers it.
2. **Signature verification active in the local environment** rejects the emulator's token
   (`alg: none`, no `kid`) with "a token with no kid". It is correct behaviour — only
   `FIREBASE_AUTH_EMULATOR_HOST` was missing from the environment. Documented in the BFF's
   README.

**What the foundation did not have on 2026-08-31, and has since:** the domain services are
implemented and registered (`internal/app/register.go`), the `AgentRuntime` lives in the core
with two provider adapters (ADR-0016), and the sandbox launcher has its Kubernetes adapter. The
sentence that used to stand here — "the servers are a skeleton" — was true for about a day and
then kept misleading planning; it is corrected rather than deleted, because knowing that the
foundation shipped faster than the document is itself worth recording.

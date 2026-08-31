# Arquitetura de backend — esqueletos, contratos e schema

> **Status:** Aprovada para revisão · **Data:** 2026-08-30 · **Projeto:** plataforma DOP
>
> **Responde:** como o backend é organizado, quais são os contratos, o schema do banco,
> os transversais (log/segurança) e a ordem de implementação.
> **Não responde:** navegação e telas (spec de navegação); ciclo da demanda (spec de
> fluxo); substrato de execução (spec própria).
>
> **Diagramas:** https://claude.ai/code/artifact/1ec0f828-ac7d-473a-ba5f-7bc0d6503402

Decisões de base: [ADR-0016](../../adr/0016-stack-go-core-python-bff.md) (stack e
fronteira), [ADR-0017](../../adr/0017-proto-como-fonte-da-verdade.md) (contrato),
[ADR-0018](../../adr/0018-persistencia-postgres.md) (banco),
[ADR-0019](../../adr/0019-outbox-e-nats.md) (eventos),
[ADR-0020](../../adr/0020-emuladores-firebase-e-dono-unico.md) (local e Terraform),
[ADR-0001](../../adr/0001-infraestrutura-atras-de-portas.md) (portas).

## 1. Princípio de organização

**Serviço separado onde o isolamento é requisito; módulo onde é só organização.**
Microserviços cedo compram custo operacional sem benefício. A base é um **monólito
modular** com fronteiras de domínio rígidas dentro do processo, e apenas dois pontos
de isolamento físico real: a **borda** (protocolos, sessão de agente) e o **plano de
execução** (código não confiável, KVM, vida longa).

```
PLANO DE CONTROLE            PLANO DE EXECUÇÃO
├── dop-app    SPA           ├── dop-launcher   (modo do core)
├── dop-api    BFF Python    └── sandbox        microVM por demanda
└── dop-core   Go — serve · worker · sched · launcher
```

Uma imagem do core, quatro modos por subcomando: um artefato, um pipeline.

## 2. Contratos — `proto/dop/v1`

| Arquivo | Conteúdo |
|---|---|
| `common` | `AccountRef` · `ActorRef` · `Money` · paginação · `idempotency_key` |
| `identity` | User · Account · Membership · Invite |
| `resource` | Resource (`integration`\|`skill`\|`workflow`\|`git_flow`) · Grant |
| `hierarchy` | Workspace · Project · anexação de recursos |
| `workflow` | Flow · Stage tipada · resolução da cadeia de herança |
| `demand` | Demand · Thread · Message · Artifact · Finding |
| `execution` | Sandbox · provision/suspend/resume/destroy · `isolationTier` |
| `delivery` | PullRequest · MergeQueue · Directive (techlead) |
| `knowledge` | Rules · Index · Memory · ContextPackage · busca semântica |
| `cost` | UsageEvent · Budget · RoutingDecision |

Convenções da ADR-0017: streaming server-side para tudo ao vivo (`WatchDemand`,
`StreamLogs`, `WatchAttention` → SSE no BFF); `Ref` em vez de id solto; `idempotency_key`
em toda escrita; `buf breaking` no CI.

## 3. Esqueleto do core (Go)

```
dop-core/
├── cmd/dop-core/main.go        # serve | worker | sched | launcher
├── api/proto/                  # .proto + gerados (buf)
├── internal/
│   ├── domain/                 # ZERO imports de infra
│   │   ├── identity/ resource/ hierarchy/ workflow/
│   │   ├── demand/ execution/ delivery/ knowledge/ cost/
│   │   └── (cada um: entity.go · service.go · port.go · errors.go)
│   ├── app/                    # casos de uso; abre a transação; orquestra domínios
│   ├── adapter/
│   │   ├── grpc/               # servidor: proto ↔ domínio
│   │   ├── postgres/           # repositórios + outbox (sqlc)
│   │   ├── nats/               # publisher · consumers · DLQ
│   │   ├── k8s/                # launcher
│   │   ├── objectstore/        # gcs.go (real) · gcs_emulated.go
│   │   ├── secretstore/        # gcpsm.go · k8ssecret.go
│   │   └── gitprovider/        # github · gitlab · azuredevops
│   └── platform/               # log · ctx · errors · idempotência · telemetria
├── migrations/                 # goose
└── test/contract/              # testes de contrato por porta (ADR-0001)
```

**Regra policiada no CI:** `internal/domain` não importa `internal/adapter`. Um teste de
arquitetura quebra o build — é assim que a fronteira sobrevive ao tempo.

## 4. Esqueleto do BFF (Python)

```
dop-api/
├── app/
│   ├── main.py                 # ponte STORAGE_EMULATOR_HOST (ADR-0020 §4)
│   ├── platform/
│   │   ├── context.py          # ContextVar: request_id · principal · conta ativa
│   │   ├── logging/            # config · middleware · decorator
│   │   ├── security/           # firebase · middleware · decorator
│   │   └── errors.py           # status gRPC ↔ HTTP
│   ├── coreclient/             # stubs gerados + wrapper: deadline, retry, idempotência
│   ├── routers/                # REST + SSE por domínio
│   ├── grpc/                   # servidor gRPC para CLI e sandbox
│   └── agent/                  # AgentRuntime: sessão, streaming, ferramentas, custo
└── tests/
```

**O BFF não abre conexão no Postgres** (ADR-0016). Toda escrita passa pelo core.

### 4.1 Transversais por decorator

Padrão adotado: **ContextVar preenchido por middleware + decorators que leem o
contexto** — o handler não recebe parâmetro de auth nem de log; o transversal fica
invisível no código de negócio.

| Decorator | Efeito |
|---|---|
| `@log(level=, mask=[])` | entrada, saída, erro e duração; máscara automática de segredos |
| `@public` | isenta de autenticação (registrado por varredura de rotas no boot) |
| `@require_role("admin")` | papel na conta ativa |
| `@require_grant("use")` | concessão de recurso (ADR-0013) |
| `@account_scoped` | injeta a conta ativa e **recusa requisição sem ela** (regra do SP-0) |

A máscara automática cobre `password`, `token`, `secret`, `authorization`, `api_key`,
`private_key`, `client_secret` — redação de segredos é requisito (F-10), não conveniência.

## 5. Schema (essencial)

```sql
-- identidade e posse
users · accounts(kind) · memberships(user,account,role) · invites
resources(account_id, kind, name, version, config JSONB, credential_ref)
resource_grants(resource_id, user_id, level)            -- use | manage
workspaces(account_id) · projects(workspace_id) · project_resources

-- fluxo e demanda
flows(owner_scope, owner_id, version, spec JSONB)       -- cadeia de herança
demands(project_id, external_key, flow_version_frozen, status)
demand_stages(demand_id, key, type, status, artifact_ref)
threads(demand_id, kind, agent_card JSONB) · messages · findings

-- a espinha
events(id, account_id, aggregate, type, payload JSONB, occurred_at)  -- append-only, partição mensal
outbox(event_id, published_at NULL)
idempotency(key, request_hash, response, expires_at)

-- conhecimento
knowledge_artifacts(project_id, kind, version, object_ref, meta JSONB)
knowledge_embeddings(artifact_id, embedding vector(1536))

-- entrega e custo
pull_requests(demand_id, repo, state, reviewers JSONB)
merge_queue(repo_id, demand_id, position, state)
directives(project_id, kind, payload JSONB, decided_by)   -- techlead
usage_events(demand_id, thread_id, model, tokens JSONB, cache JSONB)
budgets(scope, scope_id, limit_cents, spent_cents)
```

Toda tabela de domínio carrega `account_id` com FK — isolamento é constraint, não
convenção. Projeções nascem como *views materializadas*; viram tabelas alimentadas pelo
worker só se o custo mandar.

## 6. Ambiente local

```
dev.sh  →  start · stop · status · logs · reset  (por serviço)
└── k3d
    ├── postgres + pgvector (CloudNativePG)
    ├── nats jetstream
    ├── firebase emulators   auth :9099 · storage :9199 · ui :4000
    ├── dop-core (serve|worker|sched)
    └── dop-api
```

Persistência dos emuladores, ponte de variáveis e propriedade do Terraform: ADR-0020.

## 7. Ordem de implementação

1. ✅ **Fundação** — feita em 2026-08-31. Os dois repositórios com esqueleto, 10 protos
   gerando Go, migração inicial aplicada, ambiente k3d de pé, teste de arquitetura e
   testes de contrato passando. Detalhe em §9.
2. **Fatia vertical fina** — sign in → conta pessoal → BFF chama o core → cockpit lista
   vazia. Quatro endpoints provam a stack inteira de ponta a ponta.
3. **Recursos e hierarquia** — integrações (SecretStore com dois adaptadores e testes de
   contrato), workspaces, projetos.
4. **Espinha de eventos** — outbox, relay, NATS, primeira projeção (timeline).
5. **Execução** — launcher, sandbox, AgentRuntime, primeira demanda real.

## 8. Riscos

| # | |
|---|---|
| R-1 | **Dois idiomas** dobram toolchain e CI — mitigado por fronteira estreita (só gRPC) e um proto como fonte |
| R-2 | **O BFF engordar** e virar segundo dono do domínio — a regra "sem banco no BFF" é o teste; violação é bug de arquitetura |
| R-3 | **Latência do relay** entre commit e publicação — aceitável; `LISTEN/NOTIFY` se doer |
| R-4 | **Carga de eventos no mesmo Postgres** — partição mensal, retenção e vigilância desde a primeira migração |
| R-5 | **Propriedade de recursos no Terraform** — perda silenciosa no `apply`; a tabela de dono único do `dop-infra` é a mitigação (ADR-0020 §5) |

## 9. Estado da fundação (2026-08-31)

**Construído e verificado:**

| | |
|---|---|
| Contratos | 10 `.proto`, 9 serviços, 65 RPCs; `buf lint` limpo, Go gerado |
| Portas | `SecretStore` (k8s + memória), `ObjectStore` (GCS real/emulado), `IdentityProvider` (Firebase), `EventBus` (NATS JetStream) |
| Espinha | Outbox transacional + relay com `FOR UPDATE SKIP LOCKED`; `events` particionado por mês |
| Schema | 16 tabelas aplicadas no Postgres local; invariante de owner como **trigger** |
| Transversais | 5 decorators no BFF; log JSON com campos canônicos idênticos nos dois processos |
| Testes | 7 garantias de contrato do `SecretStore`, teste de arquitetura, 21 testes do BFF |
| Coleções | 18 requisições Bruno em `docs/api/` |

**Duas armadilhas encontradas e resolvidas na construção:**

1. **Logger vinculado no import** congela a configuração padrão (o `configure()` roda no
   lifespan) e as linhas saem fora do formato JSON — **sem erro visível**. Corrigido com
   acesso tardio; o teste de formato agora cobre.
2. **Verificação de assinatura ativa no ambiente local** rejeita o token do emulador
   (`alg: none`, sem `kid`) com "token sem kid". É comportamento correto — falta apenas
   `FIREBASE_AUTH_EMULATOR_HOST` no ambiente. Documentado no README do BFF.

**O que a fundação ainda não tem:** implementação dos serviços de domínio (os `.proto`
existem, os servidores são esqueleto), o `AgentRuntime`, e o launcher de sandboxes.

# SP-0 — Integrations and credentials

> **Status:** Approved for review · **Date:** 2026-08-29 · **Project:** the DOP platform
>
> **Answers:** what an integration is, where the credential lives, who may use it, and how a
> project consumes it.
>
> **Does not answer:** accounts, roles and memberships → [`sp0-identity-and-tenancy.md`](sp0-identity-and-tenancy.md).
> Decomposition and phasing → [`ROADMAP.md`](../../ROADMAP.md). Rationales →
> [`adr/`](../../adr/).

The base decisions: [ADR-0001](../../adr/0001-infrastructure-behind-ports.md) (ports),
[ADR-0003](../../adr/0003-organization-credential-human-authorship.md) (the organization
credential and authorship), [ADR-0002](../../adr/0002-account-as-unit-of-ownership.md) (the
account as the unit of ownership).

## 1. The entity

Integrations **are not configured inside a project**. They belong to the account, and the
project only consumes what is already integrated.

> **An integration is a type of resource** (ADR-0013) — the only one with a credential. The
> sharing and grant mechanism described here is the general resource mechanism.

**`Integration`:**

| Field | |
|---|---|
| `accountId` | the owning account — it is what decides sharing |
| `category` | `git`, `task_manager` or `agent` |
| `provider` | `github`, `gitlab`, `gitlab_self_hosted`, `azure_devops`, `bitbucket` / `jira`, `clickup`, `redmine` / `claude`, `codex`, `google_code_assist` |
| `baseUrl` | for self-hosted instances |
| `authMethod` | `oauth_app`, `oauth_user`, `token`, `ssh_key` |
| `credentialRef` | an **opaque logical reference** to the secret — never the secret |
| `connectedByUserId` | who established it |
| `status` | `active`, `expired`, `revoked`, `error` |

## 2. The `SecretStore` port

The platform's first infrastructure port, under ADR-0001's rule.

### 2.1 The surface

```
type SecretRef = {
  accountId: AccountId
  kind: 'integration_credential'
  ownerId: string            // the Integration's id
}

interface SecretStore {
  put(ref: SecretRef, value: SecretValue): Promise<void>
  get(ref: SecretRef): Promise<SecretValue | null>
  delete(ref: SecretRef): Promise<void>
  exists(ref: SecretRef): Promise<boolean>
}
```

Four operations, and nothing beyond that. `SecretValue` is opaque: no implicit serialization,
no useful `toString`, no appearing in a log, an error message or a stack trace.

The `credentialRef` kept on the `Integration` **is** the `SecretRef` — a logical reference only
the adapter knows how to resolve. The domain never knows a path, a namespace or a secret's
name.

### 2.2 Contract guarantees

The contract test suite required by ADR-0001 verifies, in **every** adapter:

1. **Read-after-write** — a `put` followed by a `get` returns the same value, immediately.
2. A `get` of a non-existent reference returns `null`, it does **not** throw.
3. `delete` is idempotent.
4. A `put` over an existing reference replaces it.
5. **Isolation** — account A's reference never resolves account B's secret.
6. The value never appears in a log, an error or a stack trace.

### 2.3 Adapters

Two from day one, per ADR-0001's discipline:

| Adapter | |
|---|---|
| **GCP Secret Manager** | The secret's name is derived from the reference; authorization through a service account with Workload Identity. Versioning stays **hidden** — the port always reads the current version |
| **The k8s Secret** (k3s/Rancher, OKD) | A namespace per account, a name derived from the reference. **It reads through the API, never through the mounted volume**: a volume is eventually consistent (the kubelet syncs in around a minute) and would violate guarantee 1 |

The database keeps **only the reference**. No token, no private key, under no circumstances.

## 3. Sharing

**A personal account's integration is never used in an organization and is never seen by its
other members. Only an organization account's integration is shareable.**

The rule follows from ADR-0002 and needs no special handling: the personal account has a
single member.

**An integration grant** — per user, per integration:

| Level | |
|---|---|
| `use` | May choose that integration when configuring projects |
| `manage` | May edit, reconnect and revoke the integration |

`owner` and `admin` have an implicit `manage` over everything. The others receive what was
composed in the invite and what was edited afterwards — **there is no default**.

**`use` controls configuration, not execution.** Revoking somebody's `use` does not tear down
the projects already configured: the credential is the account's, not the person's. What is
lost is the ability to choose that integration when assembling new projects.

## 4. The credential's holder

Per ADR-0003:

- An **organization account** uses an organization credential — a GitHub App installed on the
  organization, a *group access token* on GitLab, a service principal on Azure DevOps. A
  personal token is allowed as a way out, but the interface **shows whom it depends on**, so
  the risk is visible instead of being discovered on the day it breaks.
- A **personal account** uses any method: the person is the account.

**Authorship in the repository:** the push and the PR's opening use the account's credential,
but each commit carries an `author` with the name and e-mail of the dev who ran the card, and
the PR's body identifies who asked.

### 4.1 Agent providers

The `agent` category connects the account to the model/agent providers — **Claude, Codex,
Google Code Assist** and future ones. The methods: **a personal account's OAuth** (the
provider's subscription) or an **API key**, both kept through the `SecretStore` like any
credential.

- **They are the router's menu**: the models an agent's `card` (ADR-0010) may use are those of
  the account's agent integrations, resolved through the `AgentRuntime` port — one adapter per
  provider (ADR-0001, the second family).
- **Cost:** with the customer's credential (BYO), the model spend lands on their account at the
  provider; **ADR-0011's measurement does not change** — it measures the same, only who pays
  varies.
- In an organization, the same holder rules of §4 apply: prefer a credential that does not die
  with the person; an organizational API key when the provider offers one.

## 5. How the project consumes it

The project keeps **references**, never credentials:

- for each repository: the source integration and the repository's identifier within it, plus
  the base branch and the PR targets;
- for the task manager: the integration, the provider's space and the project inside it.

Configuring a project becomes **choosing from an already authenticated list**, not filling in a
credential again.

The provider belongs to the **repository**, not to the project: one project has a repository
coming from a GitHub integration and another from a GitLab integration, as long as both belong
to the account that owns the workspace. It is the use case of ADR-0001's second family of ports
— several `GitProvider` adapters active at the same time.

## 6. Risks

| # | |
|---|---|
| R-1 | **An organization credential is a single point of failure.** An uninstalled App or a revoked token for every project on that account. It requires monitoring `status` and alerting the `owner` |
| R-2 | **Uploading a private SSH key** sends a secret through the edge. It requires mandatory TLS, no logging of the request's body, and a direct write into the `SecretStore` with no intermediate persistence |
| R-3 | **A k8s adapter reading through a volume** would break the read-after-write guarantee silently — it passes a local test and fails under load. Covered by the contract test |
| R-4 | **A self-hosted `baseUrl` is user-controlled input** pointing at where the platform will make requests. It requires validation against internal targets |

## 7. Open items

Recorded in [`ROADMAP.md`](../../ROADMAP.md):

- **P-1** — the audit trail: who used which credential, when.
- **P-2** — the `status` transitions: who detects `expired`, how often, and what happens to
  work in progress.

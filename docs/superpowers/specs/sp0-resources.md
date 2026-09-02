# SP-0 — The account's resources

> **Status:** Approved for review · **Date:** 2026-08-30 · **Project:** the DOP platform
>
> **Answers:** what a resource is, which types exist, how it is shared and how a project
> consumes it.
>
> **Does not answer:** credentials → [`sp0-integrations-and-credentials.md`](sp0-integrations-and-credentials.md);
> accounts and memberships → [`sp0-identity-and-tenancy.md`](sp0-identity-and-tenancy.md).

The base decision: [ADR-0013](../../adr/0013-resource-as-unit-of-sharing.md).

## 1. The entity

`Resource`: `{id, accountId, kind, name, version, config, credentialRef?}`.

| `kind` | What it describes | Example |
|---|---|---|
| `integration` | A connection to an external provider (`git`, `task_manager`, `agent`) | The org's GitHub; Claude through an API key |
| `skill` | A reusable capability granted to agents | "a forensic reading of a database" |
| `workflow` | A human↔agent workflow: gates, who approves what | "the spec is approved by the dev before implementing" |
| `git_flow` | Declarative git governance: the branch taxonomy per card type, bases, direction (forward/reverse), release composition, policies | a trunk + release model with an epic branch and a reverse hotfix |

Resources with no credential are **versioned** — changing a git flow in use generates a new
version; projects migrate explicitly.

## 2. Sharing

The mechanism is the integrations', generalized (ADR-0013): a personal account's resource is
private; an organization account's resource is shareable through a **`use`/`manage` grant per
user**, composed in the invite and always editable; `owner`/`admin` have an implicit `manage`;
revoking `use` does not tear down what is already configured.

## 3. The platform's global resources

Level 0 keeps the catalogue: the supported providers, the default skills, the reference git
flows. An account **adopts** a global resource:

- `git_flow`, `workflow`, `skill`: a **versioned copy** — the account starts governing its
  own; an update to the catalogue is an offer, never an imposition.
- `integration`: never global — a credential is always the account's.

## 4. Consumption by the project

The project attaches resources of the account that owns the workspace — a single rule, the
same as the integrations':

| Attached resource | Who reads it |
|---|---|
| `git_flow` | the merge queue (ADR-0008), verification and delivery, branch naming per card type |
| `workflow` | the gates and roles of the demand's cycle (SP-4's core) |
| `skill` | the agents' cards (ADR-0010) |
| `integration` | repositories, task manager, the agents' models |

## 5. Risks

| # | |
|---|---|
| R-1 | A badly written git flow breaks delivery for every project that uses it — structural validation at creation and a dry run before activating a new version |
| R-2 | A proliferation of resource types — a new type requires an ADR, it is not free extension |
| R-3 | Adoption by copy diverges from the catalogue — the origin is recorded and the diff is visible |

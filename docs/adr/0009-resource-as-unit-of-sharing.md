# ADR-0009 — The resource as the account's unit of ownership and sharing

- **Status:** Accepted
- **Date:** 2026-08-30
- **Relations:** refines ADR-0002; refined by ADR-0010 (the workflow resource; access defaults per kind), ADR-0016 (agent providers)

## Context

Integrations, skills, human↔agent workflows and git flows are all owned by
an account and shared under authorization. One sharing mechanism serves all
of them.

## Decision

1. **`Resource` is the unit of ownership and sharing:**
   `{id, account_id, kind, name, config, credential_ref?}`.

   | `kind` | content | credential |
   |---|---|---|
   | `integration` | categories `git`, `task_manager`, `agent` | yes |
   | `skill` | a reusable agent capability | no |
   | `workflow` | a human↔agent workflow (ADR-0010) | no |
   | `git_flow` | declarative branch governance: taxonomy per card type, base and direction, release composition, hotfix back-merge, policies | no |

2. **Grants are per resource:** `use` / `manage`, per user, composed in the
   invite and editable at any time. A personal account's resource is
   private; only an organization's resource is shareable; `owner` and
   `admin` hold an implicit `manage`; revoking `use` does not tear down what
   is already configured. The grants table is `resource_grants`.
3. **The platform (level 0) publishes global resources** — providers,
   skills, default flows — which an account adopts (a copy or a versioned
   reference, decided per kind in the resources spec) and then governs as
   its own.
4. **A project consumes the resources of the account that owns its
   workspace:** the attached `git_flow` parameterizes the merge queue and
   verification (ADR-0005); the attached `skill`s and `workflow`
   parameterize the agents' cards (ADR-0007).

## Alternatives considered

- **One sharing mechanism per kind** — rejected: one policy written four
  times.
- **Everything as an integration** — rejected: skills and flows have content
  and versions, not credentials.

## Consequences

- A new resource kind touches neither the sharing mechanism nor the invite.
- The git flow is a versioned, auditable artifact readable by agents.
- Access defaults differ per kind (ADR-0010 §6).

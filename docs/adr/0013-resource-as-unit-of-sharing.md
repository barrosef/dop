# ADR-0013 — The resource as the account's unit of ownership and sharing

- **Status:** Accepted
- **Date:** 2026-08-30

## Context

The sharing model existed for one thing only: integrations, with `use`/`manage` grants
composed in the invite. Other things an account owns and wants to share under authorization
appeared:

- **Skills** — the agents' reusable capabilities;
- **Human↔agent workflows** — how a dev and the agents collaborate on a demand;
- **Git flows** — branch governance as an artifact: a taxonomy per card type, base and
  direction (forward/reverse), release composition, hotfix back-merge, policies. The concept
  comes from real governance in production — e.g. a trunk + release model in which the
  card's type determines the branch's prefix, base and flow, with an epic integration branch
  and a hotfix in reverse flow;
- And integrations themselves gained a third category: **agent providers** (Claude, Codex,
  Google Code Assist…).

Creating a sharing mechanism per type would repeat the mistake ADR-0002 avoided on accounts:
N implementations of the same policy, diverging.

## Decision

1. **`Resource` is the unit of ownership and sharing**: `{id, accountId, kind, name, config,
   credentialRef?}`. The initial types:

   | `kind` | Content | Credential |
   |---|---|---|
   | `integration` | the `git`, `task_manager` and **`agent`** categories | yes |
   | `skill` | an agent's reusable capability | no |
   | `workflow` | a human↔agent workflow | no |
   | `git_flow` | declarative git governance (taxonomy, promotion, policies) | no |

2. **The grant is now per resource** — `use`/`manage`, per user, composed in the invite and
   editable at any time. The existing rules do not change, they generalize: a personal
   account's resource is private; only an organization account's resource is shareable;
   `owner`/`admin` have an implicit `manage`; revoking `use` does not tear down what is
   already configured.
3. **The platform (level 0) offers global resources** — a catalogue of providers, skills and
   default flows — which an account **adopts** (a copy or a versioned reference) and then
   governs as its own.
4. **A project consumes the resources of the account that owns the workspace** — the
   integrations rule, unchanged, now holds for everything: the git flow attached to the
   project parameterizes the merge queue (ADR-0007) and the verification; the skills and the
   workflow attached parameterize the agents (their cards, ADR-0010).

## Alternatives considered

**One sharing mechanism per type.** Rejected: it is the same policy written four times, with
four screens and four bugs.

**Everything as an "integration".** Rejected: a skill and a flow have no credential, they
have a version and they have content — forcing them into the wrong entity would charge for
it on every evolution.

## Consequences

- ➕ A new resource type touches neither the sharing mechanism nor the invite.
- ➕ The git flow becomes a governed and versioned artifact — auditable, shareable between
  projects and accounts, and readable by the agents as a rule.
- ➖ SP-0's grants table generalizes (`resource_grants`); the schema is born that way.
- ➖ Adopting a global resource requires a versioning decision (copy × reference) per type —
  recorded in the resources spec.

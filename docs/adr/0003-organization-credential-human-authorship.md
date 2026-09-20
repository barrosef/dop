# ADR-0003 — An organization credential to act, human authorship on the commit

- **Status:** Accepted
- **Date:** 2026-08-29
- **Relations:** applies to every repository the platform writes to, including the project root repository of ADR-0021

## Context

A person's OAuth token dies with the person's access. An organization
credential survives departures but, used alone, erases from the repository's
history who requested the change.

## Decision

1. **To act, an organization account uses an organization credential:** a
   GitHub App installation, a GitLab group access token, an Azure DevOps
   service principal. A personal token is permitted as a fallback and the
   interface shows whom the integration depends on. A personal account uses
   any method.
2. **Every commit's `author` is the developer who ran the demand** (name and
   e-mail). The pull request body names who requested it.
3. **Every commit's `committer` is the thread that made it**, as a platform
   identity (`<thread-id>@agents.dop`), never a person. A commit made by the
   platform itself (a regenerated index, a rule saved from the cockpit)
   carries the platform as committer and the acting person as author.
4. **Push and pull request creation use the account's credential** as in 1.
5. These rules are stated here only; other ADRs reference them.

## Alternatives considered

- **Everything in the organization's name** — rejected: no human trail in the
  repository.
- **The person's credential when available, the organization's otherwise** —
  rejected: reintroduces the dependency on a person's token.

## Consequences

- An integration survives any member's departure.
- A revoked App or token stops every project of the account: the
  integration's `status` is monitored and the `owner` alerted.
- The push actor and the commit author are different identities.

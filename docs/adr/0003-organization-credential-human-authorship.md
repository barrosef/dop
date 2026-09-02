# ADR-0003 — An organization credential to act, human authorship on the commit

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

A user's OAuth token belongs to the *person*. When they leave the company, revoke access or
change their password, the integration dies — and takes with it every project in the
organization that depended on it. In a personal account that is acceptable, because the
person is the account. In an organization it is a time bomb.

But the obvious alternative creates another problem: if the platform acts with an
organization credential, it shows up in the repository as the App's installation, and the
history stops saying who asked for the change. Traceability is precisely what the card's
dossier promises.

## Decision

**Two independent choices, one for each problem.**

**To act:** an organization account uses an **organization credential** — a GitHub App
installed on the organization, a *group access token* on GitLab, a service principal on
Azure DevOps. It survives departures. A personal token is allowed as a way out, but the
interface shows whom it depends on, so the risk is visible instead of being discovered on
the day it breaks. A personal account uses any method.

**To attribute:** the push and the PR's opening use the organization's credential, but
**each commit carries an `author` with the name and e-mail of the dev who ran the card**,
and the PR's body identifies who asked.

## Alternatives considered

**Everything in the organization's name.** Simpler and uniform. Rejected: the repository
stops keeping who ran the work, and traceability stays trapped inside the platform —
useless to whoever reads the repository's history months later.

**The person's credential when they have one**, falling back to the organization's.
Perfect attribution. Rejected because it contradicts the rule that a personal account's
integration is not used in an organization, and it reintroduces exactly the fragility this
ADR exists to eliminate.

## Consequences

- ➕ The integration survives anybody's departure.
- ➕ The repository's history keeps human traceability without depending on anybody's token.
  It is how serious CI bots operate.
- ➖ **A single point of failure:** if the App is uninstalled or the token revoked, every
  project on that account stops. It requires monitoring the integration's `status` and
  alerting the `owner`.
- ➖ The push's actor and the commit's author are different entities, which may confuse
  whoever reads the provider's interface without context.

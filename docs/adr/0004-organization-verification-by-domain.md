# ADR-0004 — Verifying an organization by domain, not by ownership

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

The original requirement asked, when an organization is created, to validate whether the
signed-in user's national ID is the company's owner or holds a power of attorney — citing
GitHub and GCP as references for fluidity, with the explicit instruction "do not invent, do
not make it hard".

**We went to check what those references actually do:**

- **GitHub** creates an organization instantly and for free, with **no ownership check
  whatsoever**. The verification exists afterwards, is of the **domain** (a TXT record in
  DNS), and earns the verified badge.
- **GCP** requires, to create the organization node, a Cloud Identity or Workspace account
  tied to a **verified domain** — also through DNS.

Neither asks for a national ID or a power of attorney. The requirement's two halves pull in
opposite directions: validating ownership *is* making it hard, and the references cited do
not do it.

## Decision

Adopt the pattern both references actually use: **create instantly, verify domain control
later, gate sensitive capabilities on the verification.**

1. **Instant creation.** A name and a company registration number; the number fills in the
   legal name and address automatically and already confirms that the company exists and is
   active. No waiting, no document.
2. **Optional domain verification.** The platform generates a value, the user publishes a
   TXT record in the company domain's DNS, the platform checks it.
3. **The verification unlocks three capabilities**, deliberately few:
   - automatic entry by domain — any `@domain` e-mail gets in without an invite;
   - the verified badge, with the domain in plain sight;
   - contesting a handle taken by a third party.

Everything else works without the verification: integrations, individual invites,
workspaces, projects, execution. An unverified organization is fully usable — it just
cannot make claims about itself that it has not proven.

## Alternatives considered

**Validating ownership by national ID at creation** — checking whether the ID appears as a
partner or director of the company, or requiring a power of attorney. Rejected: it requires
an integration with a corporate-registry database, handles a power of attorney badly (a
document for a human to review) and creates friction exactly where fluidity was asked for.

**Free creation with no verification at all.** Maximum fluidity and the least effort.
Rejected because it leaves the handle dispute unanswered, which the shared namespace of
[ADR-0002](0002-account-as-unit-of-ownership.md) makes inevitable.

## Consequences

- ➕ Zero paperwork and zero waiting at creation; the autofill by registration number *helps*
  instead of blocking.
- ➕ Control of a corporate domain is strong organizational evidence, resolved in minutes by
  the user themselves.
- ➕ It answers the handle dispute with no manual process.
- ➕ Reusable: the same verification serves as proof when recovering an orphaned account.
- ➖ **It does not prove legal representation.** Whoever controls the DNS is not necessarily
  whoever can sign for the company. If there is ever a contractual or tax obligation that
  requires it, that will be another decision, in another layer.

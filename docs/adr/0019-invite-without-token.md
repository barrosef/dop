# ADR-0019 — The invite has no secret: identity in place of a bearer

- **Status:** Accepted
- **Date:** 2026-09-01
- **Relations:** relies on ADR-0002, ADR-0004, ADR-0014; refines ADR-0018 (the invite e-mail addresses the row); relied on by ADR-0020

## Context

An event's payload is replicated to the event table, the outbox, the broker
stream and the timeline projection. Nothing that grants access on its own
may travel in an event.

## Decision

1. **An invite carries no secret.** There is no token column, no generator;
   `CreateInvite` returns no credential. The invite is addressed by its
   row `id`, which may appear in events, projections, e-mails and logs.
2. **Acceptance requires being the invitee.** `AcceptInvite(inviteID,
   userID)` refuses when: there is no session; the invite is not usable
   (expired, revoked, accepted); the session's e-mail is not verified; the
   session's verified e-mail is not the invite's. The last two are distinct
   errors. The "not yours" error does not reveal the invitee's address.
3. **The e-mail link is `/invites/{invite_id}`**, produced by the
   notification rule's `link_path` (ADR-0018 §8).
4. **TTL:** 14 days (`identity.InviteTTL`).
5. **Contract:** `AcceptInviteRequest.invite_id` (same field number as the
   former `token`).

## Alternatives considered

- **The token in the event** — rejected: a credential at rest in four
  places.
- **A side channel to the notifier** — rejected: a second delivery path.
- **A UUID indexing the token** — rejected: the index becomes the
  credential.
- **E-mail match while keeping the token** — rejected: an unchecked secret.

## Consequences

- No invite secret exists at rest anywhere.
- A person invited at one address and signed in with another cannot
  accept; the error message must say so.
- An identity provider that does not report `email_verified` makes every
  acceptance fail (guarantee 5 of `IdentityProvider`).

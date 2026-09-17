# ADR-0019 — The invite has no secret: identity in place of a bearer

- **Status:** Accepted
- **Date:** 2026-09-01
- **Resolves:** P-30 (the invite carried no acceptance link)
- **Changes:** ADR-0018 (the invite e-mail now addresses the row)

## Context

The invite was born with an opaque token: generated in the service, returned **once** to the
caller, kept in the database only as a hash (`invites.token_hash`). Acceptance checked that
hash, and nothing else. Whoever held the token got into the account.

That is a **bearer credential**, and it had a practical consequence that blocked the product:
the token could not appear anywhere it would sit at rest. And "anywhere" here is large — the
payload of `dop.identity.invite.created` travels to:

| destination | permanence |
|---|---|
| `events` | a partitioned table, indefinite |
| `outbox` | until the relay drains it |
| JetStream | `FileStorage`, a `MaxAge` of 30 days |
| `timeline` | a projection that subscribes to `dop.>` and keeps the whole payload — **made to be displayed** |

That is: putting the token in the event would replicate it to four places, one of them a
screen. Without the token in the event, the notifier (ADR-0018 — it only sees the event) had no
way to build an acceptance link. The e-mail announced the invite and pointed at `/invites` — a
list the invitee, **who is not a user yet**, does not have.

Two bad ways out were on the table: the token in the event (a credential at rest, replicated)
or a side path carrying the token to the notifier outside the log (a second delivery mechanism,
just so as not to use the first).

The proposal that unblocked it came from the product owner: index the token by a uuid and send
only the index. It does not solve it on its own — *if holding the uuid is enough to complete
the acceptance, then the uuid **is** the credential*, and it would be in exactly the same four
places. But it points at the right way out when combined with the second half, which the
product owner added: **"the e-mail has to match too"**.

## Decision

### The invite stops having a secret

`invites.token_hash` is dropped (migration `0013`). `randomToken` and `hashToken` disappear.
`CreateInvite` no longer returns a token — there is nothing to return.

What addresses the invite is the row's `id`. It travels in plain text in the event's payload,
in the timeline, in the e-mail and in the log, because **on its own it grants nothing**.

### Acceptance requires BEING the invitee

`AcceptInvite(ctx, inviteID, userID)` refuses when:

1. there is no session — as before;
2. the invite is not usable (expired, revoked, already accepted) — as before;
3. the signed-in user's e-mail is **not verified**;
4. the signed-in user's verified e-mail **is not the invite's**.

The last two are new, and (4) is the one that changes the nature of the thing: the link stops
being a credential and becomes an **address**. Before, acceptance required a session but never
checked *whose* — any authenticated user with the link got into the account, with the role
granted to somebody else. It was a hole independent of the token, and it dies along with it.

(3) and (4) are **separate** refusals on purpose: "confirm your e-mail" and "this invite is not
yours" send the person to do different things, and a single error would make both look like the
same wall.

The message of (4) **does not say who the invite was for**. Saying so would turn the link into
an e-mail oracle for whoever found it — the secret would have come back through the back door.

### The e-mail's link addresses the row, and that is still data

`Rule.LinkPath` accepts `{field}`, resolved against the same data the template receives. The
invite's rule became `/invites/{invite_id}`.

It is still a table, not code: nobody writes string concatenation in Go to build the link. A
test on the table refuses a `{field}` that is not in `Data`, because the price of getting it
wrong is an e-mail with a literal `{invite_id}` in the middle of the URL. At run time, a
missing field **deletes the whole link** — half a link is worse than no link: the button shows
up and leads nowhere.

### TTL

It stays at 14 days (`identity.InviteTTL`), as it already was. The deadline was not in
question: it limited a secret's window, and now it limits the window of an address that only
works for one person. If it is ever shortened, that is a product decision, not a security one.

## Consequences

**What improves.** There is no invite secret at rest anywhere — not in the event, not in the
projection, not in JetStream, not in the e-mail, not in the log. The invite finally has a
clickable link. And the "any authenticated user with the link gets in" hole closes.

**What becomes more restricted.** Somebody invited at one e-mail who signs in to the platform
with another (a personal Google versus a corporate one) **cannot accept**. That is correct —
the invite is for one person — but it is a new wall that did not exist before, and the error
message has to be good. An issuer that does not report `email_verified` (guarantee 5 of
`IdentityProvider`) makes every acceptance fall into (3): it is the safe failure, and it is
noisy instead of silent.

**What stays open.** There is no acceptance endpoint yet — neither in the core (`AcceptInvite`
exists, but nothing in the cockpit reaches it) nor in the BFF. The link's `/invites/:id` has no
screen yet. It is recorded in the roadmap.

**An old client.** `AcceptInviteRequest.token` became `invite_id`, the same field number. A
client that still sends the token simply does not find the row — a correct failure, and nothing
is in production.

## Alternatives rejected

- **The token in the event.** A credential at rest replicated to four destinations, one of them
  a screen. No revocation reaches JetStream and the timeline.
- **A side path to the notifier.** A second delivery mechanism existing only so as not to use
  the first, and the secret would still exist — just in fewer places.
- **A UUID indexing the token.** It changes nothing while holding the index is enough to
  accept: the index becomes the credential, in the same four places.
- **Only requiring a matching e-mail, keeping the token.** It works, but it keeps the hash of a
  secret nobody checks any more — a surface with no owner.

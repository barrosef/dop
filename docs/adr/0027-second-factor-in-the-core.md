# ADR-0027 — The second factor is the platform's, with three verifiers

- **Status:** Accepted
- **Date:** 2026-09-02
- **Refines:** [ADR-0001](0001-infrastructure-behind-ports.md) (it creates the `SMSer` port), [ADR-0025](0025-communication-trigger-and-channel.md) (a channel without the Notifier), [ADR-0022](0022-agent-provider-as-port.md) (the BFF has no secret)
- **Depends on:** [ADR-0026](0026-invite-without-token.md) (a verified e-mail is already an identity requirement)

## Context

The platform is born with a second factor. The product's requirement fixes the
three options offered to the person: **an authenticator app (TOTP), e-mail and
SMS**.

Where that second factor lives is not a detail — it is the decision, and there
were two candidates.

**The identity provider's.** Firebase, our first `IdentityProvider` adapter,
does have MFA. Three things make it a bad home here:

1. **It does not cover the requirement.** Firebase's second factor is SMS and
   TOTP. **E-mail as a second factor does not exist there**, and it is one of
   the three the product asked for. Half the feature would be ours anyway — and
   then there would be two mechanisms deciding the same thing.
2. **It does not survive an adapter swap.** ADR-0001 exists because the
   `IdentityProvider` port has to answer the same way from Firebase, Keycloak,
   Zitadel or Ory. MFA semantics differ in every one of them: enrolment,
   recovery, what the token asserts and how it asserts it (`amr`, `acr`, a
   custom claim). Putting the gate there means the account's security depends on
   which vendor is wired in.
3. **The local environment cannot exercise it.** Firebase's MFA requires
   Identity Platform, and the Auth emulator does not do TOTP enrolment. We would
   ship a security path that **is never run locally** — the exact divergence
   that already cost this platform two authentication failures and produced
   [ADR-0001](0001-infrastructure-behind-ports.md).

**The platform's.** The TOTP seed is a credential; it belongs in the vault,
which lives in the core (ADR-0022). The Mailer port already exists (ADR-0025).
The event log already exists (ADR-0006). What is missing is one domain and one
channel.

## Decision

**The second factor is a domain concept of the core, with one mechanism and
three verifiers.** The identity provider does the FIRST factor and nothing else.

### 1. The entity

```
SecondFactor {
  id, user_id,
  kind: totp | email | sms,
  label,                       // "iPhone", "work e-mail" — the person's, for telling them apart
  status: pending | active | revoked,
  secret_ref?,                 // TOTP only: a SecretRef into the vault, never the seed
  destination,                 // MASKED at the edge: "j***@acme.com", "+55 ** ****-9012"
  confirmed_at, last_used_at, created_at
}
```

**Enrolment proves possession before activating.** `enroll → challenge →
confirm`: the factor is born `pending` and only becomes `active` when the person
returns the code. A factor that is registered without being proven is a lock
whose key nobody has tested — and it is discovered on the day of the sign-in
that fails.

**An e-mail factor requires a VERIFIED e-mail** (ADR-0026's guarantee 5). An
unverified address as a second factor is not a second factor: it is the same
unproven address that the first factor already trusted.

### 2. The three verifiers

| kind | How it verifies | What it uses |
|---|---|---|
| `totp` | RFC 6238, 30 s step, 6 digits, a ±1 window for clock drift | the seed in the vault (`SecretStore`, kind `second_factor_totp`); the `otpauth://` URI is shown ONCE at enrolment |
| `email` | a numeric code, 6 digits, valid for 10 minutes, single use | the **`Mailer` port** (ADR-0025) |
| `sms` | the same code, the same validity | the **`SMSer` port** — new, §4 |

**A code is single use and dies on the first correct answer**, including when it
is answered late. Reusing a code turns an intercepted message into a permanent
key.

### 3. The code is a CHALLENGE, not a notification

This is where ADR-0025's vocabulary earns its keep, applied in reverse: the
second factor uses the **channel** (`Mailer`, `SMSer`) and does **not** use the
**Notifier**.

The notification table's own header states the test for adding a row: "does this
deserve to INTERRUPT the person outside the platform?". A 2FA code fails that
test in both directions — nobody is being interrupted (the person is staring at
the screen waiting for it), and it cannot pass through the policy that governs
notifications: no digest, no delay, no recipient resolved by membership, no
idempotency by event. It is request/response, synchronous, addressed to the
factor's `destination` and to nothing else.

Putting it in the table would give the person a code fifteen minutes after they
asked for it, and would leak an authentication secret into a policy designed to
be replaced by DATA (P-29). The channel is shared; the trigger is not.

### 4. `SMSer`, the port ADR-0025 foresaw

ADR-0025 left it written: `Pusher` and `SMSer` come "when there is push and SMS,
because channels do not have the same shape". SMS now exists, so the port is
born — with ADR-0001's discipline: **two adapters and a contract suite from day
one**. One of them is a real provider (Twilio is the obvious candidate); the
second exists to prove the port does not leak the first one's vocabulary. WHICH
second provider is an open item (P-33), not a blocker: the discipline is what is
being fixed here.

The port is narrow and different from `Mailer` on purpose: no subject, no HTML,
no attachment, 160 characters and a destination in E.164. Whatever is not
fulfillable by every adapter stays out.

### 5. Where the gate is, and what it gates

Verification runs in the **core**, because that is where the vault is (ADR-0022).
The BFF forwards the challenge and the answer; it stores no seed and no code.

**The core records the step-up per (user, session), with an expiry.** The BFF
sends the session identifier in the metadata, the same way it already sends
`x-actor-id` and `x-account-id` (ADR-0017, convention 5).

What requires a fresh step-up, in v1:

- **signing in**, when the user has an active factor;
- **writing a credential** (`SetCredential`) — it is the operation that puts a
  third party's key into the vault;
- **changing a role, inviting and revoking** — whoever takes over an account
  takes it over through the membership;
- **deleting an account.**

Reading is not gated. A second factor at every request would be theatre: it
would cost a round trip and teach people to answer challenges without reading
them.

**Confirming an enrolment steps the session up.** The person proved possession
seconds ago, in this session; asking again would add nothing and would cost a
second message. This does not contradict "an enrolment challenge does not
authenticate": what steps up is the CONFIRMATION — an operation that names the
factor and activates it — and not answering the enrolment's challenge through
`Verify`, which stays refused.

**Revoking a factor drops every step-up of that person**, in every session.
Whoever revokes is saying "the device I had is no longer mine"; leaving a
session open would keep the door the removal was meant to close. It is all of
them and not the ones that used that factor, because the step-up records the
METHOD, not which factor answered.

### 6. Recovery codes are not optional

Ten single-use codes, shown ONCE at enrolment, kept **hashed** — the platform
cannot show them again, and that is the point.

Without them, a lost phone becomes a support ticket, and support becomes the
bypass: an attacker who convinces a human is worth more than one who breaks
TOTP. With them, the recovery path is a code the person kept, not a conversation
somebody can be talked into.

### 7. The account's policy

An organization account may **require** a second factor of its members
(`require_second_factor`). A member with no active factor can still sign in and
operate their PERSONAL account — what the policy blocks is operating in THAT
account. The account is the boundary of isolation (ADR-0002), so it is also the
boundary of the requirement.

> **A recorded assumption:** for a personal account, enrolment is optional, and
> the platform asks for it without imposing it. Mandating it for everyone from
> day one costs sign-ups; the product may decide otherwise, and the decision is
> a value in the policy, not a code change.

### 8. Every attempt is an event

Enrolment, confirmation, success, failure, lockout and recovery-code use are
events (ADR-0006). Five consecutive failures put the factor in a cool-off. The
attention box gains no item for a failure — a failed attempt is not a decision
for a human — but the timeline shows it, which is what auditing asks for.

### 9. A ceiling on sending, distinct from the ceiling on attempts

Five failures cool the factor off, but that only counts ANSWERS. Asking for a
code sends a message, and with SMS a message is money: without a second
ceiling, a loop that never answers costs nothing to whoever runs it.

So the send has two limits, both per factor: **60 s between messages** and
**5 per hour**. The two answer different attacks — the interval is against the
second click and against the loop, the hourly count is against a script that
walks the clock forward between requests.

The interval hangs off the most recent **PENDING** challenge, not the most
recent one. The floor exists so a second click does not send a second message
while the first is still in flight; once a code has been used, asking for
another is legitimate, and making the person wait would be charging them for
having succeeded. The hourly count, by contrast, counts everything: a consumed
message cost the same as an unanswered one.

TOTP is not limited. It sends nothing, so a limit there would make the screen
refuse for no reason.

## Alternatives considered

**Delegating MFA to Firebase Identity Platform.** The default answer, and the
right one in a product with a single identity provider and no e-mail factor. It
is neither of those things here: it does not cover e-mail, it does not survive
the swap ADR-0001 exists for, and the emulator does not exercise it.

**Accepting a factor asserted by the provider** (a token with `amr` containing
`mfa`) as equivalent to ours. It is convenient — somebody with 2FA on their
Google account would not do ours — and it creates two rulers for the same
decision, which is what this platform keeps refusing (the attention box's
priority, the cost router's policy, the effective flow). Rejected for v1 and
recorded as P-34: the day the port can normalize the assertion, the account's
policy may accept it.

**Only TOTP.** It is the strongest of the three and the cheapest (no channel, no
provider, no per-message cost). Rejected because it excludes whoever does not
use an authenticator app, which in practice means excluding part of the users
from the very protection.

**A magic link instead of an e-mail code.** A link is a bearer credential
travelling in an inbox — exactly what ADR-0026 has just taken out of the invite.
A code has to be typed into the session that asked for it.

## Consequences

- ➕ One mechanism, one place: the gate does not change when the identity
  provider changes.
- ➕ The seed never leaves the core, and the BFF's invariant ("no database, no
  secret") stays whole.
- ➕ TOTP is exercised locally and in production identically — it is pure code,
  with no vendor.
- ➕ `SMSer` is born with two adapters and a contract suite, instead of arriving
  as a Twilio-shaped hole later.
- ➖ **A user with 2FA at their identity provider does it twice** until P-34 is
  decided. It is real friction, and it is the price of a single ruler.
- ➖ **SMS is the weakest of the three** (SIM swap, interception; NIST SP
  800-63B discourages it) and it is the only one that costs money per attempt —
  which also makes it the abuse surface: rate limiting per destination is a
  requirement, not a refinement. The account's policy can disable it.
- ➖ **P-18 stops being a background item.** The core trusts the BFF's metadata;
  a forged session identifier from inside the cluster would skip the step-up.
  The NetworkPolicy makes the assumption hold, and it is not the same as
  authenticating.
- ➖ Locally there is no SMS: the adapter prints the code, the way the mailer
  already does with no credential. The path is exercised; the delivery is not.
- ➖ The notification templates gain nothing, but the code's message needs its
  own text in each channel — and, being a channel and not the Notifier, it does
  not inherit the contract suite that guarantees "every kind resolves in every
  adapter". The suite for `SMSer` has to demand it explicitly.

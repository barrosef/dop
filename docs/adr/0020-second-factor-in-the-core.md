# ADR-0020 — The second factor is the platform's, with three verifiers

- **Status:** Accepted
- **Date:** 2026-09-02
- **Relations:** refines ADR-0001 (the `SMSer` port), ADR-0018 (a channel without the Notifier), ADR-0016 (no secret in the BFF); relies on ADR-0019 (verified e-mail); session identity per ADR-0022

## Context

The product offers three second factors: an authenticator app (TOTP),
e-mail and SMS. The identity provider covers only the first factor; the
second factor must be identical across identity providers and exercisable
locally.

## Decision

**The second factor is a domain of the core** (`secondfactor`). The identity
provider performs the first factor only.

1. **Entity:** `SecondFactor{id, user_id, kind: totp | email | sms, label,
   status: pending | active | revoked, secret_ref?, destination,
   confirmed_at, last_used_at, created_at}`. `destination` is masked at the
   edge. The TOTP seed is a `SecretRef` into the vault (`SecretStore`, kind
   `second_factor_totp`), never returned after enrolment. Enrolment is
   `enroll → challenge → confirm`: a factor becomes `active` only after the
   person returns a valid code. An `email` factor requires a verified e-mail.
2. **Verifiers.**

   | kind | verification | channel |
   |---|---|---|
   | `totp` | RFC 6238, 30 s step, 6 digits, ±1 window | none (the `otpauth://` URI is shown once) |
   | `email` | 6-digit code, valid 10 minutes, single use | `Mailer` |
   | `sms` | same code and validity | `SMSer` |

   A code is consumed on the first correct answer.
3. **Codes are challenges, not notifications:** they use the channel ports
   directly and never the Notifier (no digest, no delay, no rule table).
4. **`SMSer` port:** destination in E.164, 160 characters, no formatting;
   two adapters (Twilio, Zenvia) and a contract suite; the local adapter
   prints the code.
5. **Step-up.** The core records a step-up per `(user, session)` with an
   expiry; the session id arrives in the verified call metadata (ADR-0022).
   Operations requiring a fresh step-up: sign-in when a factor is active;
   `SetCredential`; changing a role, inviting, revoking; deleting an
   account. Reads are not gated. Confirming an enrolment steps the session
   up. Revoking a factor drops every step-up of that user in every session.
6. **Recovery codes:** ten, single use, shown once, stored hashed.
7. **Account policy:** an organization account may set
   `require_second_factor`; it gates operating in that account, not the
   member's personal account. Personal accounts: enrolment optional (a
   policy value, not code).
8. **Every attempt is an event:** enrolment, confirmation, success, failure,
   lockout and recovery-code use. Five consecutive failures put the factor
   in cool-off.
9. **Sending limits, per factor:** one message per 60 s (measured from the
   most recent pending challenge) and 5 per hour; TOTP is not limited.

## Alternatives considered

- **The identity provider's MFA** — rejected: no e-mail factor; semantics
  differ per provider; not exercisable in the emulator.
- **Accepting a provider-asserted factor (`amr: mfa`)** — deferred
  (`ROADMAP.md` P-34).
- **TOTP only** — rejected: excludes users without an authenticator app.
- **Magic links** — rejected: a bearer in an inbox (ADR-0019).

## Consequences

- One gate, independent of the identity provider; the seed never leaves
  the core.
- A user with MFA at their identity provider verifies twice until P-34.
- SMS is the weakest factor and the abuse surface; per-destination limits
  apply and the account policy may disable it.
- The `SMSer` contract suite must require every adapter to deliver the
  challenge message.

# ADR-0022 — The core verifies a signature; it does not believe a header

- **Status:** Accepted
- **Date:** 2026-09-03
- **Relations:** refines ADR-0012, ADR-0013 (convention 5); relies on ADR-0001 (`IdentityProvider.VerifyToken`), ADR-0004

## Context

The core resolves the actor and the account of every call from the call's
metadata. A network boundary alone (a NetworkPolicy) is a property of one
deployment and fails silently; the platform runs agent code inside the same
cluster.

## Decision

1. **The core verifies a signature on every call.**
   - **A call with a person carries the person's token**, forwarded whole by
     the edge in `authorization: Bearer …`, verified through
     `IdentityProvider`. The actor is the token's `subject`, resolved by
     `UserBySubject` (cached 5 minutes).
   - **A call without a person carries a platform assertion** in
     `x-dop-assertion`: `base64url(caller|actor|kind|account|session|expiry)`
     + HMAC-SHA256 (`internal/platform/callauth`), one key per caller,
     expiry 2 minutes.
2. **The account always comes from the assertion**, never from the token.
3. **Token and assertion naming different actors refuses the call.**
4. **Modes:** `strict` (no verified signature → no actor), `permissive`
   (warn and proceed), `off`. The code's default is `permissive`; the
   deployment is `strict`.
5. **A refused call proceeds with an empty actor and fails at
   authorization**, not in the interceptor.
6. **Transport authentication is additional.** On Cloud Run the core
   accepts no unauthenticated invocation and only the BFF's service account
   holds `roles/run.invoker`; the invoker token travels in
   `X-Serverless-Authorization` because `Authorization` carries the
   person's token. On a cluster a NetworkPolicy restricts who can reach the
   gRPC port.
7. **The wire format is pinned by one test vector** asserted in a Go test
   and a Python test.

## Alternatives considered

- **Trust the metadata** — rejected: any caller claims any actor.
- **A shared secret in a header** — rejected: proves knowledge of the
  secret, not the claim.
- **mTLS** — rejected on clusters (issuance and rotation); its Cloud Run
  equivalent is decision 6.
- **Identity-Aware Proxy** — rejected: it authorizes by IAM policy, which
  cannot express per-tenant accounts, roles and grants, and it breaks a
  cross-origin single-page cockpit. Suitable only for team-only surfaces.

## Consequences

- The edge carries the raw token and signs an assertion on every call.
- One HMAC and one token verification per call; signing keys and the
  subject lookup are cached.
- A clock skew above the assertion's expiry refuses calls.
- Not solved: replay within the 2-minute window; a compromised edge signs
  its own claims. Both are why the person's token is preferred where a
  person exists.

## Revisions

- 2026-09-07 — decision 6: Cloud Run IAM for the managed deployment.

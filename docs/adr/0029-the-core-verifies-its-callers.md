# ADR-0029 — The core verifies a signature; it does not believe a header

- **Status:** Accepted
- **Date:** 2026-09-03
- **Refines:** [ADR-0016](0016-stack-go-core-python-bff.md) (the edge stays the one that authenticates the person — what changes is that the core no longer takes its word for the conclusion), [ADR-0017](0017-proto-as-source-of-truth.md) (convention 5: identity travels in the metadata, not in the body — still true, and now the metadata is verified)
- **Depends on:** [ADR-0001](0001-infrastructure-behind-ports.md) (the `IdentityProvider` port already existed and does the heavy half), [ADR-0006](0006-demand-as-event-log.md) (an event's authorship is only worth what the actor behind it is worth)
- **Resolves:** P-18

## Context

The core read `x-actor-id` and `x-account-id` from the gRPC metadata and
believed them. The metadata is text: whoever could open a connection to port
9090 declared themselves **any actor of any account** — no password, no token,
nothing beyond sending the header.

That was a deliberate decision (ADR-0016): one trust boundary, at the edge, and
a core that stays simple. What put it on the list is the KIND of guarantee
behind it. "Only the BFF calls" is not enforced by the code — it is enforced by
a NetworkPolicy. Verified on 2026-09-03, from a loose pod in the namespace:

```
BLOCKED_9090   ← the gRPC port, denied
REACHED_9091   ← health (and, since ADR-0028, the git server), open
```

So it holds **today, here**. Three things make that insufficient:

1. it is a property of the DEPLOYMENT, not of the software. A cluster whose CNI
   ignores NetworkPolicy — several do — has no boundary at all;
2. it fails in **silence**: nothing breaks, the door is simply open;
3. this platform runs **agent code in the same cluster** on purpose. "Someone
   hostile inside the network" is not a hypothesis here, it is a feature.

## The options that were weighed

Discussed with the owner on a canvas, side by side. Summarised because the
argument matters more than the list:

- **Keep as is.** Cost zero, and one misconfiguration is the whole system.
- **A shared secret in a header.** Cheap, and it proves only that the caller
  knows the secret — whoever holds it still claims any actor.
- **mTLS.** Strong, no bearer, and expensive: issuance and rotation. It proves
  the CONNECTION, while the question is about the CLAIM.
- **An assertion signed by the platform.** Binds the claim, works where there is
  no person, cheap to verify.
- **Forwarding the person's JWT** — the owner's proposal, and the strongest of
  the five where it applies: the signature is the identity provider's, an
  authority neither end controls, and the core already has the machinery
  (`IdentityProvider.VerifyToken`, the Firebase adapter, and a contract suite
  that refuses a forged token). It covers only calls with a person behind them.

The question that decided it: **not "who opened the connection", but "who has
the authority to assert who the actor is"**.

## Decision

**The core verifies a signature on every call. Which signature depends on who
is calling.**

### 1. A call with a person carries the person's token

The edge forwards it whole in `authorization: Bearer …`; the core verifies it
through the port it already had. The actor comes from the token's `subject`,
resolved to a user through `UserBySubject` — cached for five minutes, because
otherwise this is a database hit on every call.

### 2. A call with no person carries an assertion signed by the platform

The edge resolving a subject before an actor exists has no token to forward.
What it can offer is `x-dop-assertion`: `base64url(caller|actor|kind|account|session|expiry)`
plus an HMAC-SHA256 over that payload — `internal/platform/callauth`.

**One key per caller.** A compromised component forges only its own calls.

**The signature covers the CLAIM.** A shared secret proves that the sender knew
a secret; this proves *what is being claimed*. A stolen assertion is worth one
actor, in one account, for two minutes.

### 3. The account comes from the assertion, never from the token

It is not in the token — that was the objection to forwarding the JWT alone. The
assertion carries it, and the assertion is signed.

### 4. Where the two disagree, the call is refused

The token proves WHO more strongly than the assertion asserts it, so it wins —
except when both are present and name different actors. That is not a preference
between sources: it is a bug or an attack, and it ends the call with no actor.

### 5. Three modes, and the default is not the strict one

`strict` refuses to fill in an actor without a verified signature. `permissive`
warns and lets the call through. `off` is the previous behaviour.

The DEFAULT is `permissive` and the DEPLOYMENT is `strict`. Flipping it in one
step would break every caller not yet taught to sign — including the contract
suite, which raises a core with no edge in front of it. The code stays usable
for whoever clones the repository; the cluster we run gets the guarantee.

### 6. Refusing means no ACTOR, not an error here

A refused call goes on with an empty actor, and fails at the **authorization**,
where the message means something to whoever reads it. Failing in the
interceptor would produce "unauthenticated" for a call whose real problem is
that it never proved anything.

### 7. The NetworkPolicy stays

None of this replaces it. They add up: the policy narrows who can knock, the
signature decides who is heard.

## Consequences

- **The edge changed too**: `AuthContext` carries the raw token so it can be
  forwarded, and `metadata_for` signs an assertion on every call — including the
  ones with no actor, where what it proves is that the caller is the edge.
- **The wire format is pinned by a shared vector.** The two implementations are
  in different languages and can only agree by accident; the same string is
  asserted in a Go test and in a Python test. A drift here does not fail loudly
  — it makes every call arrive unauthenticated, which is an outage in `strict`
  and silence in `permissive`.
- **A per-call cost**: one HMAC (negligible) and one token verification. The
  Firebase adapter caches the signing keys; the subject → user lookup is cached
  for five minutes.
- **A clock dependency**: an expiry of two minutes assumes the edge's and the
  core's clocks are within that of each other. In a cluster they are; it is
  written down because the day it is not, the symptom is calls being refused for
  no visible reason.
- **What is NOT solved**: an assertion is replayable within its two minutes, and
  a compromised edge signs whatever it likes. Both are inherent in signing one's
  own claims, and both are why the token — signed by a third party — is
  preferred wherever a person exists.

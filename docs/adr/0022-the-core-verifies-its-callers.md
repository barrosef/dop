# ADR-0022 — The core verifies a signature; it does not believe a header

- **Status:** Accepted
- **Date:** 2026-09-03
- **Refines:** [ADR-0012](0012-stack-go-core-python-bff.md) (the edge stays the one that authenticates the person — what changes is that the core no longer takes its word for the conclusion), [ADR-0013](0013-proto-as-source-of-truth.md) (convention 5: identity travels in the metadata, not in the body — still true, and now the metadata is verified)
- **Depends on:** [ADR-0001](0001-infrastructure-behind-ports.md) (the `IdentityProvider` port already existed and does the heavy half), [ADR-0004](0004-demand-as-event-log.md) (an event's authorship is only worth what the actor behind it is worth)
- **Resolves:** P-18

## Context

The core read `x-actor-id` and `x-account-id` from the gRPC metadata and
believed them. The metadata is text: whoever could open a connection to port
9090 declared themselves **any actor of any account** — no password, no token,
nothing beyond sending the header.

That was a deliberate decision (ADR-0012): one trust boundary, at the edge, and
a core that stays simple. What put it on the list is the KIND of guarantee
behind it. "Only the BFF calls" is not enforced by the code — it is enforced by
a NetworkPolicy. Verified on 2026-09-03, from a loose pod in the namespace:

```
BLOCKED_9090   ← the gRPC port, denied
REACHED_9091   ← health (and, since ADR-0021, the git server), open
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

## Amendment · 2026-09-07 — Cloud Run IAM replaces the NetworkPolicy

The Context above records why the NetworkPolicy was not enough: it holds *today,
here*, it is a property of the deployment rather than of the software, and it
fails in silence — nothing breaks, the door is simply open.

The Options weighed mTLS and set it aside: **"strong, no bearer, and expensive:
issuance and rotation. It proves the CONNECTION, while the question is about the
CLAIM."**

On Cloud Run that objection disappears. **IAM invoker permission is the
mTLS-shaped answer with no issuance and no rotation**: Google signs, Google
verifies, and the check happens before the request reaches the process. The core
is deployed with no unauthenticated access, and only the BFF's service account
holds `roles/run.invoker`.

**This does not replace anything decided above.** Three layers now answer three
different questions, and none of them answers another's:

| layer | question |
|---|---|
| Cloud Run IAM | may this *caller* invoke this *service*? |
| `x-dop-assertion` | which *component* asserts, and about which *actor*? |
| the person's token | who is the *person*? |

What it replaces is the NetworkPolicy, which stays in the local cluster because
there is no IAM there — and that asymmetry is the point of the original
decision: the guarantee now belongs to the software's deployment contract in
both places, instead of to one CNI's behaviour.

**One collision to handle when implementing.** Cloud Run reads the invoker's
identity token from `Authorization: Bearer`, and that header is already carrying
the person's token. The service token therefore travels in
`X-Serverless-Authorization`, which exists for exactly this case. Getting it
wrong breaks both at once, and the symptom — everything arriving
unauthenticated — is the same silence this ADR was written about.

### IAP was weighed and refused

Identity-Aware Proxy stopped requiring a load balancer and carries no charge of
its own, so cost is not the reason.

It can authenticate our own users: IAP's *external identities* mode uses
Identity Platform, which is the same service behind Firebase Auth, and it is free
to 50,000 monthly active users. **Cost is not the reason, and an earlier draft of
this amendment was wrong to say it required a paid tier.**

The reason is that IAP decides *who may reach a resource*, by IAM policy, and
this platform lets **anyone sign up**. The policy would have to admit every
authenticated user, which decides nothing. Meanwhile the access question that
actually matters here — which account you belong to, with which role and which
grants — is per-tenant application state that IAM has no vocabulary for.

So it would enforce nothing and change everything: the token this ADR is built on
becomes `x-goog-iap-jwt-assertion`, and with it `VerifyToken`, `Principal`,
`EnsureUser`, the account linking and the verification gate.

Two further findings from Google's own guide for external identities. It requires
a **separate authentication application**, hosted apart from the protected one —
so IAP does not save the sign-in screens we already have, it adds a second app to
maintain. And it describes a flow for **browser-based authentication, by redirect
and session cookie**; our cockpit is a single-page app on another origin calling
the API by XHR, which cannot follow a redirect to a sign-in page and would need a
third-party cookie. IAP in front of the API breaks the front end it is meant to
protect.

It also cannot fence the QA environment: the cockpit is served from outside
Google Cloud and carries no IAP token, so IAP in front of the API would block the
product's own front end.

Where it does fit is a surface only the team uses — an administration screen,
metrics, the cluster's console. Free, and correct there.

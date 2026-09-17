# ADR-0001 — Infrastructure behind ports with pluggable adapters

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

The platform has to run on **GCP Cloud Run** and on a **k3s/Rancher or OKD cluster**, and
the list of infrastructure services is going to grow: secrets, identity, object storage,
persistence, messaging. Each environment offers a different service for the same need —
Secret Manager on one side, a k8s Secret on the other.

Coupling the domain to a vendor would force a rewrite per environment, and would tie the
project to the first choice made under pressure.

## Decision

**All infrastructure is reached exclusively through a port defined by the domain**, with
vendor-specific adapters injected in a *composition root* and chosen by configuration. The
domain imports no vendor SDK.

### Two families of ports

They look alike and have opposite life cycles; confusing them is this design's typical
mistake.

| | **Infrastructure ports** | **Domain provider ports** |
|---|---|---|
| Examples | `SecretStore`, `IdentityProvider`, `ObjectStore`, repositories, `EventBus` | `GitProvider`, `TaskManagerProvider`, `RuntimeOrchestrator` |
| Who chooses | The deployment environment | The account's configuration |
| When | Once, at boot | On every request |
| How many active | One | Several at the same time |

The second family has to support coexistence: one workspace has a repository on GitHub and
one on GitLab at the same time.

### Three mandatory disciplines

Without them, "hexagonal" becomes the name of a folder:

1. **Two adapters per port from day one.** The local adapter is not "for later" — it is
   the proof that the port is right. A port with a single adapter is a guess, and it comes
   out shaped like the vendor that inspired it.
2. **One contract test suite per port**, which every adapter passes. That is what
   guarantees substitutability in fact, not in intention.
3. **A narrow port, in the domain's language.** The domain asks for `SecretStore.get(ref)`,
   not `accessSecretVersion`.

### Handling leakage

When a capability does not map between adapters, it stays **outside** the port. If it is
ever needed, it comes in as an optional capability the domain never assumes.

Cases already decided:

- **Secret versioning stays out.** Secret Manager has versions and per-secret IAM; the k8s
  Secret is flat and has no history.
- **A k8s Secret mounted as a volume is eventually consistent** — the kubelet syncs in
  around a minute. Since the port promises read-after-write, the k8s adapter reads through
  the API, not through the volume.
- **Firebase claims do not cross the boundary.** `IdentityProvider` returns a normalized
  principal: `subject`, `email`, `emailVerified`, linked providers.

### When an adapter cannot meet a guarantee, the ADAPTER pays — it does not lower the bar

*(absorbed from the former ADR 0021 (a number retired by the 2026-09-17 renumbering), 2026-09-04)*

`SecretStore` promises **read-after-write**. The promise was born from the k8s adapter, where
it is true. The second production adapter — GCP Secret Manager — could not meet it: Google's
documentation is explicit that only `AddSecretVersion` followed by access **by the version
number** is strongly consistent, while access by an alias, `latest` included, converges
*"typically within minutes, but may take a few hours"*. And `SecretRef` is flat — account,
kind, owner — with nowhere to keep a version.

The consequence was the worst possible for a vault: on real GCP a `Get` right after a `Put`
could return `(nil, nil)`, which by the port means "it does not exist". A credential just
written would show up as absent, silently, and the caller would conclude the integration had
never been configured. In the local emulator the same case passes in 0.01 s — exactly the kind
of divergence, the local environment hiding the production path, that has already cost this
platform two authentication failures.

**The decision: the guarantee holds and the adapter pays.** The GCP adapter confirms the write
by the version number, then waits for `latest` to catch up, with a configurable ceiling
(`SECRET_PROPAGATION_SECONDS`, 30 s by default). If it does not converge, it **refuses** with
an explicit `KindUnavailable`. Refusing is the part that matters: a `Put` that returns success
while the following `Get` says "it does not exist" is worse than a `Put` that fails — the first
produces a silently broken integration, the second produces an error somebody reads.

Two ways out were rejected, and one is recorded as an evolution:

- **Loosening the guarantee to "eventually consistent"** — rejected: it pushes onto every
  caller the logic of rereading until it shows up, and the caller cannot tell "not propagated
  yet" from "does not exist". A weak guarantee on a vault's port is one nobody uses properly.
- **Caching the value in the process after the `Put`** — rejected: a second place where the
  credential exists, with its own invalidation. It trades a consistency problem for a security
  one.
- **Making `Get` read by version number** — the strongly consistent path. It requires
  `SecretRef` to carry the version, i.e. `Put` returning an identifier the caller keeps. That
  changes the PORT, not one adapter: recorded as an evolution, not rejected.

The residue, written down so it is not a surprise: a `Put` on GCP is slower and may fail on
non-convergence, behaviour the emulator never reproduces — the local test does **not** cover
that path; and if somebody disables or destroys a version from outside, `latest` diverges
between the two (the emulator falls back, real GCP fails), as documented in
`dop-infra/docs/local-environment.md`.

## Alternatives considered

**Couple to GCP and port later.** Faster at the start. Rejected because "later" is when the
coupling is already spread out, and because running locally on k3s is a development
requirement, not a future ambition.

**A generic cloud abstraction layer** (an off-the-shelf multi-cloud library). Rejected
because it delivers the common denominator *of the library's vendor*, not of the domain,
and it trades one coupling for another.

## Consequences

- ➕ The platform runs on Cloud Run and on a cluster with no change to the domain — only
  wiring.
- ➕ The domain becomes testable with no infrastructure: an in-memory adapter is just one
  more.
- ➕ Swapping Firebase for Keycloak, Zitadel or Ory does not touch the domain.
- ➖ The real cost of writing and maintaining **two** adapters per port from the start.
- ➖ One more layer of indirection on every infrastructure call.
- ➖ A vendor's strong capability is inaccessible to the domain by construction. That is the
  price, and it is deliberate.

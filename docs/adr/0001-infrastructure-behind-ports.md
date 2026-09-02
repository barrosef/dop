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

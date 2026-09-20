# ADR-0001 — Infrastructure behind ports with pluggable adapters

- **Status:** Accepted
- **Date:** 2026-08-29
- **Relations:** refined by ADR-0012 (the stack), ADR-0016 (the agent provider port), ADR-0020 (the `SMSer` port), ADR-0021 (the `ProjectRepository` port), ADR-0023 (the `VerificationRunner` port)

## Context

The platform runs on GCP Cloud Run and on a Kubernetes cluster (k3s, Rancher,
OKD). Each environment offers a different service for the same need (Secret
Manager / a Kubernetes Secret; GCS / a filesystem; Identity Platform / OIDC).
The domain must not depend on any of them.

## Decision

1. **The domain reaches infrastructure only through a port it defines**, in
   the domain's vocabulary (`SecretStore.Get(ref)`, not
   `AccessSecretVersion`). The domain imports no vendor SDK.
2. **Adapters are bound in one composition root** (`dop-core`:
   `internal/app/wire.go`) and selected by configuration (`SECRET_BACKEND`,
   `SANDBOX_BACKEND`, `IDENTITY_BACKEND`, `MAIL_BACKEND`, …). No conditional
   on the environment exists outside that file.
3. **Two families of ports.**

   | | Infrastructure ports | Domain provider ports |
   |---|---|---|
   | Examples | `SecretStore`, `IdentityProvider`, `ObjectStore`, `EventBus`, repositories | `GitProvider`, `TaskManagerProvider`, `AgentProvider` |
   | Chosen by | the deployment, at boot | the account's configuration, per request |
   | Active at once | one | several |

4. **Every port has at least two adapters from day one** (a production one
   and a local one) and **one contract test suite** every adapter passes.
5. **A port carries only what every adapter can guarantee.** A capability one
   vendor has and another does not stays outside the port (secret versions,
   provider-specific token claims). The `IdentityProvider` returns a
   normalized principal: `subject`, `email`, `emailVerified`, linked
   providers.
6. **When an adapter cannot meet a guarantee natively, the adapter pays; the
   port's guarantee is not lowered.** `SecretStore` guarantees
   read-after-write. The GCP adapter confirms a write by version number, then
   waits for the `latest` alias to converge up to `SECRET_PROPAGATION_SECONDS`
   (default 30) and returns `KindUnavailable` if it does not. The Kubernetes
   adapter reads through the API, never through a mounted volume.

## Alternatives considered

- **Couple to GCP and port later** — rejected: local execution on a cluster is
  a development requirement.
- **A generic multi-cloud library** — rejected: it abstracts the library's
  vendors, not the domain.
- **Loosening `SecretStore` to eventual consistency** — rejected: callers
  cannot distinguish "not propagated" from "absent".
- **Caching a written secret in-process** — rejected: a second copy of a
  credential.
- **`Get` by version number** (`SecretRef` carrying a version) — recorded as a
  possible evolution of the port; not adopted.

## Consequences

- The same binary runs on Cloud Run and on a cluster; only wiring changes.
- The domain is testable with in-memory adapters.
- Two adapters per port are written and maintained from the start.
- A `Put` on GCP is slower and may fail on non-convergence; the emulator does
  not reproduce that path.

## Revisions

- 2026-09-04 — decision 6 added (read-after-write on GCP Secret Manager).

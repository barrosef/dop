# ADR-0021 — Read-after-write of a secret is not free on GCP

- **Status:** Accepted
- **Date:** 2026-08-31
- **Resolves:** guarantee 1 of `ports.SecretStore`, which the GCP adapter cannot meet as written

## Context

The `SecretStore` port promises **read-after-write**: a `Get` right after a `Put` returns the
value just written. The promise was born from the k8s adapter, where it is true — which is
why its header says, rightly, that it reads through the API and never through a mounted
volume (a volume is eventually consistent).

When the second production adapter was written — GCP Secret Manager, required by ADR-0001 —
the promise did not hold.

Google's documentation is explicit: only `AddSecretVersion` followed by access **by the
version number** is strongly consistent. Access by an alias — including `latest` — is
eventually consistent, and converges *"typically within minutes, but may take a few hours"*.

The only strong path requires carrying the version number from a write to the next read. And
`SecretRef` is **flat**: account, kind and owner. There is nowhere to keep a version.

**The consequence is the worst possible for a vault:** on real GCP, a `Get` right after a
`Put` may return `(nil, nil)` — which, by the port, means "it does not exist". A credential
just written would show up as absent, silently, and the caller would conclude the integration
had not been configured.

In the local emulator the same case passes in 0.01 s. It was exactly this kind of divergence
— the local environment hiding the production path — that has already cost this platform two
authentication failures.

## Decision

**The guarantee still holds, and the adapter pays its price.**

The GCP adapter confirms the write **by the version number** (the strong path) and then
**waits for the `latest` alias to catch up**, with a configurable ceiling
(`SECRET_PROPAGATION_SECONDS`, 30 s by default). If it does not converge within the ceiling,
it refuses with an explicit `KindUnavailable`.

Refusing is the part that matters: a `Put` that returns success while the following `Get`
says "it does not exist" is worse than a `Put` that fails. The first produces a silently
broken integration; the second produces an error somebody reads.

## Alternatives considered

**Making `Get` read by the version number.** It is the strongly consistent path, and it would
require `SecretRef` to carry the version — that is, `Put` would start returning an identifier
the caller keeps. It is probably the right long-term solution, and it changes the PORT, not
one adapter. It is recorded as an evolution, not rejected.

**Loosening the guarantee to "eventually consistent".** Rejected: it would push onto every
caller the logic of rereading until it shows up, and the caller has no way to tell "it has not
propagated yet" from "it does not exist". A weak guarantee on a vault's port is a guarantee
nobody uses properly.

**A local cache of the value after the `Put`.** Rejected: keeping a secret in the process's
memory to work around consistency is creating a second place where the credential exists, with
its own invalidation — it trades a consistency problem for a security one.

## Consequences

- ➕ The port keeps a strong promise, and it holds in both adapters.
- ➕ The divergence between the emulator and real GCP is written down, and does not become a
  surprise in production.
- ➖ A `Put` on GCP is slower and may fail on non-convergence — behaviour the emulator never
  reproduces. The local test does **not** cover that path.
- ➖ If somebody disables or destroys a version from outside, `latest` diverges between the two
  (the emulator falls back; real GCP fails). Documented in
  `dop-infra/docs/local-environment.md`.
- ➖ While the port does not carry a version, the guarantee depends on waiting, not on a
  contract.

# ADR-0015 — Firebase emulators in the local environment; Terraform as the single owner

- **Status:** Accepted
- **Date:** 2026-08-30 · **slimmed 2026-09-04** (the operational recipe moved to the `dop-infra` spec, §4.4)
- **Refines:** the `dop-infra` spec (it replaces MinIO in the local environment)

## Context

The local environment needs identity and object storage. The initial proposal was the
Firebase emulator for Auth and **MinIO** for objects — two different clients (local S3 ×
GCS in production), two signed-URL semantics, and the classic risk of "it works locally, it
breaks in the cloud".

The experience of a sibling project brought two expensive lessons, both incorporated here.

## Decision

**1. Firebase's Emulator Suite covers Auth and Storage locally.** The same SDK as
production, resolved by an environment variable. MinIO does not come in now; it stays as a
third adapter of the `ObjectStore` port when there is a self-hosted customer without GCP.
`functions`, `pubsub` and `eventarc` are available in the same emulator if some case comes
up — a latent capability, not a component (our messaging is NATS and the worker is the core).

**2. The emulator keeps its data across restarts, and its configuration is versioned.** The
mechanics — export on exit, a conditional import, the grace period, the environment-variable
bridge — are operational and live in the `dop-infra` spec, §4.4. What is decided here is that
the local environment **must** survive a restart: an emulator that loses data on every stop
pushes developers back to the cloud for anything that takes more than one session.

**3. The emulator's configuration is the deploy's configuration.** `firebase.json`,
`.firebaserc` and the rules stay **versioned in the repository** and are mounted **read-only**
into the emulator — the same files the deploy uses. An emulator with its own configuration
lies about production.

**4. Terraform is the single owner of what it manages.** Resources created through the
console or the CLI stay out of the state and are reverted or deleted on the next `apply` — a
silent loss of a feature, already observed in a sibling project. The rule: **nothing is
created through the console**; what the Firebase CLI publishes (rules, indexes) lives in
versioned files that Terraform references or imports; where the boundary is ambiguous (e.g.
Auth providers), `dop-infra`'s `README` declares **a single owner** per resource, in an
explicit table.

## Consequences

- ➕ Local and production share the SDK, the configuration and the semantics.
- ➕ One container fewer (no MinIO) and Auth+Storage in the same process.
- ➕ The `ObjectStore` port still has two adapters being exercised (real GCS × emulated).
- ➖ A dependency on the Firebase CLI in the development environment.
- ➖ The resource ownership table has to be maintained — it is what prevents the silent loss
  on `apply`.

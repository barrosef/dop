# ADR-0015 — Firebase emulators in the local environment; Terraform as the single owner

- **Status:** Accepted
- **Date:** 2026-08-30
- **Relations:** relies on ADR-0001; operational detail in the `dop-infra` spec §4.4

## Context

The local environment needs identity and object storage with the same
semantics as production, and infrastructure must not drift between what
Terraform knows and what exists.

## Decision

1. **Firebase's Emulator Suite provides Auth and Storage locally**, with the
   production SDK selected by environment variable. MinIO is not used; it
   remains a possible third `ObjectStore` adapter for a self-hosted customer
   without GCP.
2. **The emulator persists across restarts** (export on exit, conditional
   import, a grace period — `dop-infra` spec §4.4).
3. **The emulator's configuration is the deploy's configuration:**
   `firebase.json`, `.firebaserc` and the rules are versioned and mounted
   read-only into the emulator.
4. **Terraform is the single owner of what it manages.** Nothing is created
   through the console; what the Firebase CLI publishes lives in versioned
   files Terraform references or imports; where ownership is ambiguous, the
   `dop-infra` README declares one owner per resource. Adopted resources are
   imported until `terraform plan` reports no changes.

## Alternatives considered

- **Firebase Auth emulator + MinIO** — rejected: two clients, two signed-URL
  semantics.

## Consequences

- The Firebase CLI is a development dependency.
- The ownership table is maintained by hand.

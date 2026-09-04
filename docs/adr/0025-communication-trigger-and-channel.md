# ADR-0025 — Communication: the trigger and the channel are born together

- **Status:** Accepted
- **Date:** 2026-08-31
- **Resolves:** P-11 (the communication service), in the e-mail slice

## Context

The platform needs to tell people outside the cockpit: an invite, an account verification, a
broken integration, an exceeded budget, a thread waiting for an answer.

The sibling project (spartacus) solves it by writing a document into a Firestore collection,
which triggers a function that sends through SendGrid. Three things from there transfer — the
local rehearsal with no key (it prints instead of sending), the state in the record (`sent` /
`sent_local` / `error`) and templates versioned in the repository. The trigger does not
transfer: here the event spine already exists (ADR-0018), and the spec says communication is
*"a consumer of the event spine, not a system apart"*.

## Decision

### The trigger and the channel are separate things, and they are born together

In the product owner's words: *"A Mailer living without the Notifier would be like a bullet
that could be fired without the trigger."*

The point is not that the `Mailer` **can** live alone — it is that **the trigger exists
either way**. If it is not designed, somebody improvises it: the invite use case calls the
`Mailer` directly and becomes the trigger, with no name and no place, spread over as many use
cases as send e-mail. The risk is not "a channel with no trigger", it is a **diffuse
trigger**.

```
event consumer
   └─ Notifier: decides WHAT to notify and TO WHOM   ← the trigger
        └─ a command: (kind, recipient, data)
             └─ Mailer (a channel port)              ← the firing
                  └─ SendGrid | SMTP
```

The invite use case knows neither of them: it publishes an event and that is it.

### The port is per CHANNEL, not one for everything

Channels do not have the same shape: e-mail has a subject, HTML and an attachment; push has a
title, a badge and a deep link; SMS has 160 characters and no formatting. A single port would
have the union of everything — with most fields never used — or the lowest common denominator,
losing what each channel does well.

The usual rule holds: whatever cannot be met by every adapter stays out of the port. So
`Mailer` today; `Pusher` and `SMSer` when there is push and SMS. One vendor may implement
several — OneSignal would be a package with two or three adapters, which is normal, not odd.

### The adapter is big: index, resolution and sending

An explicit decision by the product owner, and it corrects the initial proposal of rendering in
the domain. **The template index, the resolution and the sending live in the ADAPTER.**

The port speaks INTENT — "an invite was created, to this address, with this data" — and each
adapter decides what that becomes:

| Adapter | How it resolves the template |
|---|---|
| SendGrid | maps kind → `template_id`, sends `dynamic_template_data` |
| SMTP | renders locally, from the repository's files |
| OneSignal (future) | maps kind → its own template |

Rendering in the domain would look cleaner and would be worse: the platform could never use a
provider's template (losing the editor, the versioning and the localization), and the port
would start carrying a blob of HTML — a rendering artifact, not an intent.

It is the same separation the cost router already makes: `routingTable` is POLICY,
`ModelCatalog` is CATALOGUE. Here, the policy is "which notification exists and when"; the
catalogue is "which template of it in this vendor". Changing vendor changes the catalogue, not
the policy.

**A consequence that requires a test:** a notification kind may exist in the policy and have no
template in the vendor, and that would fail in SILENCE — the event happens, the consumer runs,
nobody receives anything. The contract suite requires EVERY adapter to resolve EVERY kind the
domain knows how to emit.

### Two real adapters: SendGrid and SMTP

SMTP is the self-hosted path — the same GCP/OKD pair as the other ports. And it is what
**forces local template resolution**, proving the port speaks intent and not a `template_id`.
With SendGrid alone, nothing would stop the port from leaking its vocabulary.

### Transactional and an attention notice are different things

- **Transactional** — an invite, an account verification. It fires immediately, always, one per
  event.
- **An attention notice** — a blocked thread, a PR waiting for review, an exceeded budget. That
  **already has a map**: the attention box (ADR-0006, a projection) decides what requires a
  human decision. The e-mail hooks onto the BOX, not onto the raw events — two maps diverge on
  the first adjustment.

And then the risk becomes spam. The spec already warns about that regarding the box itself: *"a
noisy box becomes noise and is ignored"*. One e-mail per item makes the inbox useless.

**A digest with a delay, 15 minutes by default, configurable.** The item opens, waits, and only
becomes an e-mail if it is still open — whoever was in the cockpit has already resolved it.
Fifteen minutes is short enough that the urgent does not wait and long enough that the trivial
resolves itself; it is an informed guess, and it becomes a calibrated number when there is
telemetry, like the router's table.

### Idempotency is per (event, rule, action)

The attention box uses a unique index per EVENT, and it works because the relation is 1:1.

With a declarative reaction (P-29), one event will be able to trigger N actions. A key on the
event alone would discard the second as a duplicate — and discarding by idempotency is silent
by design. The key is born composite, even with a single action today.

### It runs in the core

SendGrid's key is a credential, it lives in the vault, and the BFF has no secret (ADR-0022). It
is one more consumer in the worker, next to the timeline and the attention box.

## Consequences

- ➕ Swapping SendGrid for OneSignal is writing an adapter; the policy does not change.
- ➕ When the reaction becomes data (P-29), the decider is swapped — not the caller.
- ➖ SendGrid's visual editor is lost for the SMTP templates, which are repository files.
- ➖ Two places for the same notice's template while both adapters exist. It is the price of the
  port not leaking a vendor's vocabulary, and the contract suite is what prevents one from
  falling behind.
- ➖ The 15-minute delay is a guess. A notice too urgent waits; one too trivial annoys. Only
  telemetry settles it.

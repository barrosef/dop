# ADR-0018 — Communication: the trigger and the channel are born together

- **Status:** Accepted
- **Date:** 2026-08-31
- **Relations:** relies on ADR-0004, ADR-0014, ADR-0016; refined by ADR-0019 (the link addresses the row), ADR-0020 (the `SMSer` port; challenges bypass the Notifier)

## Context

The platform notifies people outside the cockpit: invites, account
verification, a broken integration, an exceeded budget, a thread waiting
for an answer. Communication is a consumer of the event spine.

## Decision

1. **Two components.** The **Notifier**, an event consumer in the worker,
   decides *what* to notify and *to whom* from a table of rules
   `(event type → kind, recipient resolution, data, link path)`; it emits a
   command `(kind, recipient, data)`. A **channel port** delivers it. Use
   cases publish events only; none calls a channel directly.
2. **One port per channel:** `Mailer` (subject, HTML, attachments);
   `SMSer` (160 characters, E.164 destination — ADR-0020); `Pusher` when
   push exists. A vendor may implement several.
3. **Template index, resolution and rendering live in the adapter.** The
   port speaks intent — a kind and its data — and each adapter maps the
   kind to its template (SendGrid: `template_id` + dynamic data; SMTP and
   OneSignal: templates in the repository, rendered locally). The contract
   suite requires every adapter to resolve every kind the domain emits.
4. **Adapters:** SendGrid, SMTP, OneSignal (`MAIL_BACKEND`). With no
   credential configured, the adapter prints instead of sending.
5. **Transactional notices** (invite, verification) send immediately, one
   per event. **Attention notices** (a blocked thread, a PR awaiting review,
   an exceeded budget) hook onto the attention box, not onto raw events,
   and are sent as a **digest after a delay** (default 15 minutes,
   configurable) only if the item is still open.
6. **Idempotency is per `(event, rule, action)`**, so one event may trigger
   several actions without the second being discarded as a duplicate.
7. **The consumer runs in the core** (the channel credentials are in the
   vault).
8. **Link paths are data:** a rule's `link_path` accepts `{field}`
   placeholders resolved against the notification's data; an unresolvable
   placeholder removes the link.

## Alternatives considered

- **Rendering in the domain** — rejected: the port would carry HTML and
  could not use a provider's templates.
- **One port for all channels** — rejected: channels have different shapes.
- **One e-mail per attention item** — rejected: noise.

## Consequences

- Swapping a vendor is an adapter and a configuration value.
- A template exists per adapter; the contract suite keeps them complete.
- The 15-minute delay is calibrated with telemetry.

## Revisions

- 2026-09-01 — decision 8 (link paths as data).
- 2026-09-12 — OneSignal adapter added to decision 4.

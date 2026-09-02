# Debts left by the language rule and by i18n

The board is complete: the 50 stories of the first round, the 9 of the second factor and the
2 of the invite's path are all on ClickUp (space `DOP`, 13 epic folders). This file used to
track what was still missing there; what is left is what does NOT fit on a card.

## What has no story written

Epic **11 💰 Cost and governance** is EMPTY on purpose: there is a domain in the core and there
is ADR-0011, but nobody wrote what the dev sees, what they configure and what happens when the
budget runs out. It is the biggest mismatch between what is built and what is specified — and
organizing into epics served precisely to expose that.

Epics 06 (agents), 07 (the substrate), 10 (communication) and 13 (operation) ended up with 1 or
2 stories each: they are the areas most decided and the least written.

---

## A dependency created by the language rule (2026-09-01)

The notification table's `LinkPath` became **English**: `/invites/{invite_id}` and `/attention`.
The cockpit's routes followed on 2026-09-02 — `/projects/:projectId`, `/demands/:demandId` and
`?stage=` replaced the Portuguese ones in the same pass that translated the platform layer.

`/invites/:inviteId` was built on 2026-09-02 and closes P-32 — the e-mail's link no longer leads
to a 404. **`/attention` still does not exist** (US-8.0.2): the notification's `LinkPath` points
at a route the cockpit does not have, which is the same 404 for the same reason.

## i18n that requires a contract change (recorded on 2026-09-01)

The i18n rule was applied where the change is ADDITIVE and cheap: `errs.Error` gained
`Code`+`Params`, the attention box gained `TitleKey`+`Params` (migration 0014), and the
validation refusals of hierarchy, identity and resource carry a key.

The following were left OUT, because they require changing the `.proto` and regenerating both
sides — it is work of its own, not a translation, and going halfway would leave a decorative
field:

- **`workflow.Report`** — `Errors` and `Warnings` are `repeated string` in the proto. They are
  the messages a person reads when writing a flow ("stage X is a human validation and has no
  gate"), and there are ~15 of them. They have to become `Finding{key, params}` in the domain
  and in the contract.
- **`agent` — the `Warnings`** of assembling a card, the same shape.
- **`workflow.Scope.Label()`** — it returns a screen label ("platform", "account"). It became
  English in the translation; the label itself belongs to the cockpit, not to the core.
- **`EffectiveFlow.ResolvedFrom`** — the trail's sentence ("project ◂ workspace ◂ account —
  stages: …") is assembled in the core and shown on the screen. Either it becomes structured
  data the cockpit composes, or it stays a ready-made sentence in one language. The first is the
  right one.

- **`agent.TruncationNotice`** — the sentence that goes into the THREAD when the context arrived
  truncated. It is read by people, so it should be a key. It is not: it travels as a plain
  message in the thread, and turning it into a key requires giving the messages a structured
  shape. Translated into English; recorded here.

- **The language of the agent's reply.** The runtime's contract (`RuntimeContract`) became
  English, because it is code. So that this would not decide by side effect which language the
  product speaks, the contract gained an explicit line: *"Write `reply` in the language of the
  conversation. These instructions are in English because the code is; the person you are
  answering may not be."* It is the right correction, but it is worth confirming that it is the
  desired behaviour — the alternative would be passing the user's locale as a parameter, which
  changes the prefix and the cache.

## The second factor's own i18n note (2026-09-02)

The code's message goes out through a CHANNEL and not through the Notifier (ADR-0027 §3), so it
does not inherit the notification table's per-locale plan. Its text — in the e-mail and in the
SMS — is born in English like the rest of the code, and it is content a person reads: it enters
the same queue as the mailer's templates, waiting for the per-locale catalogue of ADR-0025.

# ClickUp — what is left to push to the board

**The `DOP` space** has the 13 epic folders and a `Backlog` list in each one. Of the 50 stories
of the first round, **36 were created**; the 14 below and the 9 of the second factor are still
missing, both batches blocked by **ClickUp's API rate limit**.

- First block: 2026-09-01 15:30 -04 (~23 h).
- Second block: hit again on 2026-09-02 11:45 -04 while creating the 2FA cards; the API answered
  "wait 180 minutes", and a retry at 14:29 answered "wait 17 minutes". A read
  (`get_workspace_hierarchy`) went through; a filter and a create did not — the quota is shared
  and nearly exhausted.

Delete this file when both batches are on the board.

---

## Batch A — the second factor (ADR-0027), all in epic 01 🔑 Identidade e Acessos

**List:** `1000350000004920`

The card's body follows the same shape as the ones already created: the story, the base decision
and the criteria that the ADR fixed. Nine cards.

| Card | Summary |
|---|---|
| US-2.3 | Register an authenticator app (TOTP): the `otpauth://` URI shown once, the seed in the vault, `pending` until the first code confirms it |
| US-2.4 | Register the e-mail: a 6-digit code, 10 minutes, single use, through the `Mailer` port — and it requires a VERIFIED address |
| US-2.5 | Register the phone: the same code over the new `SMSer` port, the number always masked |
| US-2.6 | The challenge at SIGN-IN, with the session stepped up for a while — not on every request |
| US-2.7 | A fresh challenge before a sensitive operation: credential, role, invite, revocation, deleting an account. Reading is never gated |
| US-2.8 | Ten recovery codes, shown once, kept hashed — what stops support from becoming the bypass |
| US-2.9 | List, name, add and revoke factors; revoking the last one in an account that requires 2FA is refused |
| US-2.10 | A failure says only that it failed; five in a row put the factor in a cool-off. Every attempt is an event |
| US-4.4 | An organization requires a second factor of its members (`require_second_factor`), and may disable SMS |

**All nine are IMPLEMENTED** (2026-09-02), in the core, the BFF and the cockpit — the cards are
the record of what was decided and built, not a plan. US-2.3 carries one caveat: the enrolment's
QR code does not exist yet (P-36).

Full text: [`user-stories.md`](user-stories.md) §2 and §4.4. Everything the card needs to say is
there — the ADR reference, the criteria and the reason each refusal exists.

## Batch B — the 14 of the first round

### Epic 08 ✅ Verification and delivery — list `1000350000004927`
- US-8.1.4 — The finalization stage with visible steps and a state per step
- US-8.2.1 — The full git view: repos → branches → PRs → files with a diff
- US-8.2.2 — A merge queue per repository, with escalated conflicts
- US-8.4.1 — The product's quality groups (acceptance, tests, coverage, Allure)
- US-8.4.2 — The code's quality groups (standards, duplication, dependencies)

### Epic 09 🧠 Knowledge and context — list `1000350000004928`
- US-7.4 — The project's rules and accumulated knowledge in the configuration
- US-8.5.1 — Architectural and flow diagrams on demand, in a canvas
- US-8.5.2 — A forensic reading becoming an opinion (diagrams + a document)
- US-8.5.3 — Architectural artifacts filtered by the task header

### Epic 10 🔔 Attention and communication — list `1000350000004929`
- US-8.0.2 — The global attention box, each item leading to the place of the resolution

### Epic 12 🖥️ The cockpit — list `1000350000004931`
- US-8.0.1 — Selecting a card narrows the bar, the panel and the centre to the demand
- US-8.0.3 — The ⌘K palette to jump to any project/demand
- US-8.0.4 — The Overview above the task header, immune to the card filter

### Epic 13 ⚙️ The spine, the environment and operation — list `1000350000004932`
- US-8.6.1 — The demand's timeline, filterable by agents, git, gates and cost

## Batch C — the invite's path, also epic 01

**List:** `1000350000004920`. Implemented on 2026-09-02, closing P-32.

| Card | Summary |
|---|---|
| US-5.2 | Accept the invite through the link: `/invites/:id` outside the shell, the preview with no e-mail, the two refusals as different screens |
| US-5.3 | Edit a role and revoke an invite; the account is never left with no active owner |

## Still with no story written
Epic **11 💰 Cost and governance** was left EMPTY on purpose: there is a domain in the core and
there is ADR-0011, but nobody wrote what the dev sees, what they configure and what happens when
the budget runs out. It is the biggest mismatch between what is built and what is specified —
and organizing into epics served precisely to expose that.

Epics 06 (agents), 07 (the substrate), 10 (communication) and 13 (operation) ended up with 1 or
2 stories each: they are the areas most decided this week and the least written.

---

## A dependency created by the language rule (2026-09-01)

The notification table's `LinkPath` became **English**: `/invites/{invite_id}` and `/attention`.
The cockpit's routes followed on 2026-09-02 — `/projects/:projectId`, `/demands/:demandId` and
`?stage=` replaced the Portuguese ones in the same pass that translated the platform layer.

`/invites/:id` and `/attention` still do not exist in the cockpit (that is P-32). When the
acceptance screen is built, it has to be born at `/invites/:id`, or the e-mail's link leads to a
404 again, for the opposite reason.

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

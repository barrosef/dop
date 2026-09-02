# ClickUp — what is left to push to the board

**Created on 2026-09-01.** The `DOP` space was set up with the 13 epic folders and a `Backlog`
list in each one (with the epic's description: what it answers, what already exists in code,
which ADRs and open items govern it).

Of the 50 stories, **36 were created**. The 14 below hit **ClickUp's API rate limit** (a ~23h
block from 2026-09-01 15:30 -04). Nothing else failed — it is only a matter of resuming.

Delete this file when it is finished.

## Epic 08 ✅ Verification and delivery — list `1000350000004927`
- US-8.1.4 — The finalization stage with visible steps and a state per step
- US-8.2.1 — The full git view: repos → branches → PRs → files with a diff
- US-8.2.2 — A merge queue per repository, with escalated conflicts
- US-8.4.1 — The product's quality groups (acceptance, tests, coverage, Allure)
- US-8.4.2 — The code's quality groups (standards, duplication, dependencies)

## Epic 09 🧠 Knowledge and context — list `1000350000004928`
- US-7.4 — The project's rules and accumulated knowledge in the configuration
- US-8.5.1 — Architectural and flow diagrams on demand, in a canvas
- US-8.5.2 — A forensic reading becoming an opinion (diagrams + a document)
- US-8.5.3 — Architectural artifacts filtered by the task header

## Epic 10 🔔 Attention and communication — list `1000350000004929`
- US-8.0.2 — The global attention box, each item leading to the place of the resolution

## Epic 12 🖥️ The cockpit — list `1000350000004931`
- US-8.0.1 — Selecting a card narrows the bar, the panel and the centre to the demand
- US-8.0.3 — The ⌘K palette to jump to any project/demand
- US-8.0.4 — The Overview above the task header, immune to the card filter

## Epic 13 ⚙️ The spine, the environment and operation — list `1000350000004932`
- US-8.6.1 — The demand's timeline, filterable by agents, git, gates and cost

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

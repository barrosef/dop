# Profile onboarding — the wizard after sign-up

- **Date:** 2026-09-06
- **Status:** **superseded on 2026-09-20** by [the onboarding journey](2026-09-20-onboarding-journey-design.md). The phone step lives on in the security screen; tools, social networks and referral are retired; plans are absorbed by the journey. Kept for the record.
- **Depends on:** `2026-09-06-account-signup-design.md` (this begins where that
  ends), [ADR-0020](../../adr/0020-second-factor-in-the-core.md) (the second
  factor, whose SMS machinery this reuses), [ADR-0001](../../adr/0001-infrastructure-behind-ports.md)
- **Built in:** the visual language of `2026-09-06-cockpit-visual-language-design.md`
- **Touches:** `dop-core`, `dop-api`, `dop-app`

## 1. What already exists, and what that saves

**SMS verification is built.** `internal/domain/secondfactor` has
`EnrollCode(ctx, kind, label, destination)`, which sends a code to a
destination, and `Confirm(ctx, factorID, challengeID, code)`, which validates
it — behind `ports.SMSer`, with two real adapters (`twilio.go`, `zenvia.go`) and
a contract suite. ADR-0020 put it in the core for reasons that apply here
unchanged.

So the wizard's first step does **not** build an SMS mechanism. It enrols the
person's phone as an SMS second factor, and the verification of the number is
what enrolment already is. The person gets a working second factor as a side
effect, which is a better outcome than a phone number nobody can use.

The cockpit likewise has `components/ui/input-otp`, which is the code field, and
`components/security/second-factor-settings`, which already drives this flow
from the profile screen.

## 2. Decisions

**D-1. The wizard is mandatory, once.** It appears over the portal — the portal
visible and dimmed behind it — after the account exists, and the person completes
it before using the platform. It never appears again.

**D-2. The phone step can be skipped; the others cannot.** A mandatory step that
depends on a carrier is a locked door: SMS is blocked, the number was typed
wrong, the chip is new, there is no signal. The other steps are choices the
person can always make, so only this one carries that risk.

The step offers resend with growing delay and "correct my number", because most
failures are a wrong digit. When the person skips, the wizard records it and
moves on, and the profile shows the phone as unverified with a way to finish
later. **The step rail shows it as skipped, not as pending** — it was a
legitimate choice, and showing it as an error teaches people to distrust the
rail.

**D-3. Tools require at least one; social networks, referral and plans are
pass-through.** Tools are the only answer the agent will actually operate on, so
an empty answer there empties the point of asking. Social networks may be
genuinely none, and requiring one only teaches people to lie. The referral and
plans steps have nothing to fill in — they are seen, may be acted on, and are
passed.

**D-4. The referral link is real and attribution is recorded; nothing is
rewarded.** Each person gets a code; the link carries it to sign-up; whoever
signs up through it is recorded as referred by whoever shared it. No credit, no
reward, no rules — those are commercial decisions not yet taken. What this buys
is that when the programme exists, the history is already there. The alternative,
a decorative link, silently loses every referral made before the programme.

**D-5. The catalogs are data, seeded by a script.** Tools, social networks and
plans live in Postgres and are read by the API. They are not constants in the
cockpit and not rows written by hand. A versioned file in the repository holds
them, and a `make` target loads it — so adding a tool is an edit and a command,
by anyone, without a deploy of the front end.

**D-6. The gate is in the cockpit only.** Every other refusal in this platform
lives in the core, because the core must not believe a claim. This one is
different: an incomplete profile protects nothing. A core-side refusal would add
no security and one more way to lock somebody out of a product they already paid
to enter. The cockpit routes to the wizard until the profile is complete, and the
core simply records what it is told.

## 3. The data

Four tables and two columns, in one migration.

```
tool_catalog        id, group_key, key, name, brand_color, sort, active
social_catalog      id, key, name, brand_color, sort, active
plan_catalog        id, key, name, tagline, features jsonb, sort, active
user_tools          user_id, tool_id                (PK both)
user_socials        user_id, social_id, handle      (PK user_id, social_id)
users               + referral_code text UNIQUE
                    + referred_by uuid REFERENCES users(id)
                    + onboarded_at timestamptz
```

`group_key` on the tool catalog is what the wizard groups by, so a new group is
data too. `brand_color` is what draws the tile's mark without shipping a logo
file per tool — and avoids the licensing question that shipping real logos
raises.

`referral_code` is short, unambiguous and case-insensitive on lookup: no `O`/`0`,
no `I`/`1`. It is not a secret — it is meant to be pasted into a message — so it
needs no entropy beyond not colliding.

`referred_by` points at a user and is written **once**, at sign-up, from the code
in the link. It is never updated afterwards: attribution that can change is not
attribution.

`onboarded_at` is what the cockpit reads to decide whether to show the wizard.

### 3.1 The seed, and why it is a file

`repos/dop-core/seed/catalog.yml` holds the three catalogs, and
`make seed-catalog` applies it — an upsert by `key`, which makes it idempotent
and makes editing a tool's name a re-run rather than a migration. Removing a
tool sets `active=false` rather than deleting the row, because somebody has
already chosen it and a foreign key does not care about product decisions.

The initial content, which the owner asked to be real:

**Código** — GitHub, GitLab, Bitbucket, Azure Repos, AWS CodeCommit
**Gestão de trabalho** — Jira, ClickUp, Linear, Azure Boards, Trello, Asana
**Documentação** — Confluence, Notion, Google Workspace, SharePoint
**Nuvem** — AWS, Google Cloud, Azure, DigitalOcean, Oracle Cloud, Cloudflare

**Redes** — LinkedIn, GitHub, X, Instagram, YouTube, TikTok, Facebook, Bluesky,
Reddit, Discord

**Planos** — Free, Start, Pro, Enterprise, each with a one-line tagline and a
short feature list, **no price**. Prices are a commercial decision and their
absence is deliberate, not a placeholder.

## 4. The five steps

Built in the control-room direction, as a panel over the dimmed portal, with the
step rail on the left. The tools step uses **tiles grouped by subject**, with
search and a per-group count — the count is what stops somebody believing they
must select everything.

1. **Celular.** Number, then the code, through `secondfactor` enrolment.
   Resend with growing delay, "correct my number", and skip.
2. **Ferramentas.** Tiles by group, at least one. Search filters across groups.
3. **Redes sociais.** The same tiles; an optional handle per selected network.
4. **Indicação.** The person's link, a copy button, and one line saying what it
   is for. Honest about the present: it records who came from whom, and rewards
   are not defined yet.
5. **Planos.** The four plans, side by side, no price, no selection required.

## 5. Errors, and the one that matters

The phone step is the only one that can fail for reasons outside the person's
control, and it is the one to get right:

- **code did not arrive** — resend, with the delay visible and growing, and the
  number editable in place;
- **wrong code** — say so without consuming the attempt count in a way the person
  cannot see; `secondfactor` already limits attempts, and the screen must show
  what remains rather than failing silently at the limit;
- **rate limit** — say when to try again, not "an error occurred";
- **skip** — always available, never buried, and never worded as failure.

Everything a person reads goes through i18n, in both the `pt` and the `en` map.

## 6. What this does not build

- **Rewards for referrals** (D-4) — attribution only.
- **Prices, checkout or plan changes.** The plans step shows what exists; billing
  is a subsystem of its own.
- **A core-side refusal for an incomplete profile** (D-6).
- **Logos for the tools.** A coloured mark with initials, until somebody settles
  the licensing of each brand's asset.
- **Editing the catalogs from the interface.** They are a file and a command;
  a screen for them is later work, if ever.

## 7. Open items for the plan

1. The plans' taglines and feature lists need the owner's words. The plan seeds
   a first draft and the file is edited without a deploy — which is exactly why
   D-5 made them data.
2. Which SMS adapter the local environment uses. Twilio and Zenvia both need
   credentials; the emulator does not send SMS. The plan must say how the phone
   step is exercised locally, or the first real test of it is in production.

# Prompt 1 for Replit — the cockpit's visual language

*Paste everything below the line. It needs no backend change: the API is
untouched, so there is nothing to fetch or regenerate.*

---

Read `RAILS.md` at the root of this repository before you start. It is short,
it is new, and it exists because this cockpit is one of four repositories — the
core, the BFF and the infrastructure are not visible from here, and most of what
can go wrong in this repo is a decision belonging to one of them being taken
here instead. §5 of that file carries the visual direction below in its durable
form; this message is the task.

## The task

Raise the visual quality of the cockpit. The owner's words were that the screens
are poor, simplistic, with ordinary combos and text fields that feel like the
year 2000. That reading is right, and the cause is specific:

**this package already ships 56 components — shadcn/ui over Radix, in
`artifacts/dop/src/components/ui/` — and the screens do not use them.** Measured
today:

| screen | imports from `components/ui` | what it uses instead |
|---|---|---|
| `account.tsx` | 0 | hand-rolled `<button>`, native `<select>` |
| `invite.tsx` | 0 | hand-rolled `<button>` |
| `sign-in.tsx`, `sign-up.tsx` | 0 | bare `<input>` |
| `workspace-wizard.tsx` | 6 | nearly clean — this is what good looks like here |

The native `<select>` is literally the year-2000 combo: the operating system
draws it, it ignores the theme, and it cannot carry an icon or a description.
So most of this work is **adoption, not construction**. The components are
already themed, accessible and in the bundle.

## What is yours

Layout, visual hierarchy, spacing, composition, density, empty and loading
states, micro-interactions, how a busy screen stays readable. This is why the
work is coming to you. Make real design decisions and make them well.

You may **rearrange** anything: move sections, change a table into a different
structure, split a screen, group things differently.

## What is not yours

- **The palette and the typefaces.** The owner chose them from three
  side-by-side mockups. They are in `RAILS.md` §5. Put them in
  `artifacts/dop/src/index.css` as tokens — the existing token names stay,
  only their values change — so every component inherits the direction.
- **What information is on a screen.** Rearranging is yours; adding or removing
  is not. If a screen looks like it is missing something, or showing something
  useless, **say so instead of inventing it**. Data you invent has no source.
- **Where data comes from.** Every backend call goes through a generated hook
  (`RAILS.md` §1). If the hook you would need does not exist, the endpoint does
  not exist — stop and say which one is missing.

## Order, because it matters

**Tokens and type first**, in `index.css`. Every screen inherits them, and a
screen restyled before the tokens land gets restyled twice.

Then, in this order — smallest and newest first, so the direction is proven
before the big screens follow:

1. **`sign-in.tsx` and `sign-up.tsx`** — bare inputs, hand-rolled buttons.
2. **`link-provider.tsx` and `verify-email.tsx`** — same, and see the warning
   below.
3. **`invite.tsx`** — the table the owner called year-2000. It needs hairline
   rows, a real state badge, relative time in tabular mono, a genuine empty
   state, and actions that do not sit in a column of buttons.
4. **`account.tsx`** — the densest, and last. It benefits most from patterns
   settled on the smaller screens.

## The warning that matters most

The four authentication screens carry **behaviour that is easy to destroy while
restyling**, and destroying it is silent — everything typechecks and looks
better. This flow shipped hours ago and was reviewed hard. It must still work
exactly as it does now:

- **`sign-in`/`sign-up` decide from the caught error, not from state.** They call
  `decideFromAuthError(failure)` and branch on `decision.kind`. There is a trap
  here: `pendingLink` is React state set just before the throw, so reading it in
  the same `catch` tick gives the value from *before* the update. If you refactor
  this into "check `pendingLink` after catching", the linking flow stops working
  and nothing errors.
- **`sign-up` splits on whether there is a credential to link.** A password
  collision has none, and goes straight to `/sign-in` carrying `linkEmail` in
  router state; a provider collision goes to `/link-provider`. Sign-in renders an
  explanation banner when that state is present.
- **`link-provider` drops the provider that was just attempted** from the options
  it offers, and falls back to offering all of them when `pendingLink.methods`
  comes back empty — an empty list is a normal answer, not a failure.
- **`verify-email` has a sign-out link.** It is the only way out for somebody who
  typed their address wrong; without it they are trapped, because `/` sends them
  here and `/sign-in` sends them to `/`.
- **The verification gate in `App.tsx` fires only when every entry in
  `providerData` is `password`** and the e-mail is unverified. Gating on
  unverified alone locks out every GitHub user, because GitHub often reports an
  unverified address.

Restyle these screens freely. Do not reorganise their control flow.

## The house rules that no tool checks

- **Every string a person reads goes through i18n**, in `lib/i18n.ts`, in
  **both** the `pt` and the `en` map. A key in one map only renders as the raw
  key to half the users, and neither the compiler nor the build catches it. The
  maps have the same key count today; count them again afterwards.
- **Code, comments and identifiers in English.** Only the strings a person reads
  are translated.
- **No literal colour outside the tokens.** A hex that is not a token will not
  follow the theme; that is how a palette rots one screen at a time.
- **No new UI dependency.** If something is genuinely missing from the 56, say
  so before building it.

## Before you call it done

```bash
pnpm typecheck
pnpm --filter @workspace/dop run test
PORT=5173 BASE_PATH=/ pnpm build      # the build needs both variables
```

Then the checklist in `RAILS.md` §7, which covers what those commands cannot.

## What to report back

- What you changed, screen by screen, and the design decisions you made — the
  ones you would defend, not a list of files.
- Anything you found missing: a field a screen needs and the API does not
  return, a component the library lacks, a rule you could not locate.
- Anything you deliberately left alone, and why.

If something in this message conflicts with what you find in the code, the code
wins — say which, and what you did about it.

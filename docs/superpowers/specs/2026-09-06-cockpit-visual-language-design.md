# The cockpit's visual language — control room

- **Date:** 2026-09-06
- **Status:** direction approved by the owner from side-by-side mockups
- **Touches:** `dop-app` only
- **Produces:** the visual foundation the profile-onboarding wizard is built in
  (see `2026-09-06-profile-onboarding-design.md`)

## 1. The diagnosis, which is cheaper than it looks

The owner's words were that the screens are poor, simplistic, with ordinary
combos and text fields that feel like the year 2000. That reading is correct,
and the cause is specific rather than a matter of taste:

**the package already ships a full component library, and the screens do not use
it.** `src/components/ui/` holds 56 components — shadcn/ui over Radix, including
`select`, `command`, `form`, `field`, `input-otp`, `dialog`, `table`, `sonner` —
and `src/index.css` defines 38 theme tokens. Measured:

| screen | imports from `components/ui` | raw tags |
|---|---|---|
| `account.tsx` | 0 | hand-rolled `<button>`, `<select>` |
| `invite.tsx` | 0 | hand-rolled `<button>` |
| `sign-in.tsx`, `sign-up.tsx` | 0 | native `<input>` |
| `workspace-wizard.tsx` | 6 | nearly clean |

The native `<select>` **is** the year-2000 combo: it renders as the operating
system draws it, ignores the theme, and cannot show an icon or a description.
`workspace-wizard.tsx` already shows what the codebase looks like when the
library is used.

Two consequences. First, most of this work is **adoption, not construction** —
the components exist, tested and accessible. Second, the sign-up screens shipped
earlier today have the same defect, which is the author's own and is repaired
here rather than excused.

## 2. The direction: control room

Chosen by the owner from three mockups, each applied to the same field, combo
and invite rows so the comparison was about substance.

DOP is a platform where an agent does development while a person watches. The
screens are an instrument panel over work in flight, not a marketing surface.
What follows serves that and nothing else.

### 2.1 Ground and colour

Dark, and dark by conviction rather than by fashion: these screens are read for
hours beside an editor, and a light panel between two dark ones is a lamp in the
face.

```
ground        #0E1116    the page
surface       #12171E    panels, cards
surface-2     #0F141A    inset fields, tiles
hairline      #232A34    dividers, borders
hairline-2    #2A323E    interactive borders
text          #D8DEE7    body
text-strong   #F0F4F9    headings, values
text-muted    #7C8798    labels, secondary
text-faint    #5C6879    placeholders, units
accent        #2F81F7    the one action colour
ok            #3FB950    a state, never decoration
attention     #D29922    a state
danger        #F85149    a state
```

The neutrals carry a slight blue bias toward the accent, so the greys read as
chosen rather than inherited. **Colour means state.** A green pill says a thing
is green; it is never used because a row needed brightening. That rule is what
keeps a dense screen readable, and breaking it is how instrument panels turn
into dashboards nobody trusts.

The existing token names in `src/index.css` stay — `--background`, `--card`,
`--primary` and the rest. Only their values change, plus the few state tokens
the palette adds. Every component in `components/ui/` already reads them, so the
library inherits the direction for free.

### 2.2 Type

- **Chivo** for headings and short labels. It has width and a flat, technical
  cut; it is not Inter and not the geometric sans every AI-drawn dashboard uses.
- **IBM Plex Sans** for body and controls. Plain, wide language coverage, and
  designed for interfaces rather than for posters.
- **JetBrains Mono** for every **identifier**: demand ids, hashes, counts,
  durations, versions. Already loaded.

The mono rule is not decoration. A number that changes — a countdown, a count of
selected tools, an elapsed time — must not change width, or the layout dances on
every tick. `font-variant-numeric: tabular-nums` goes on every column of digits.

Scale: 11 / 12 / 13 / 15 / 18 / 24, weights 400 / 500 / 600 / 800. Headings get
`text-wrap: balance`. Running text stays near 65 characters.

### 2.3 Density and edges

- **No shadows.** Separation comes from a 1px hairline. A shadow says "floating
  object", and on a panel of instruments nothing floats.
- **Radius 5–6px** on controls, 9px on panels. Never fully round except pills.
- **Rows, not cards.** Lists of things — invites, members, demands — are rows
  divided by hairlines, with state as a 2px stripe on the left edge. A card per
  invite spends a whole box to say one line.
- Repeated elements share edges, baselines and inner padding. Border, fill and
  radius are spent by role, to lift the one thing that needs lifting, rather than
  stamped on every block.

### 2.4 What replaces the year-2000 controls

| today | becomes | why |
|---|---|---|
| native `<select>` | `components/ui/select`, or `command` when the list passes ~8 items | themed, searchable, can carry an icon and a description |
| bare `<input>` | `field` + `input` | label, hint and error in one place, wired for screen readers |
| hand-rolled `<button>` | `button` | one focus ring, one disabled state, one loading state |
| `alert()`-style feedback | `sonner` toasts | already installed, never blocks |
| a bare table | `table` with hairline rows and a `badge` for state | sortable head, real empty state |
| no empty state | `empty` | a table with nothing in it should say what to do, not show a blank |

## 3. Scope: the four screens the owner named

**Order matters.** Tokens and type first, because every screen inherits them,
and a screen restyled before the tokens land is restyled twice.

1. **Tokens and type** — `index.css` and the font links. Every existing screen
   shifts with them, which is the point.
2. **Sign-in and sign-up** — the smallest surface and the newest code, and the
   proof that the direction works before the bigger screens follow.
3. **Invites** — the table the owner called year-2000: rows with hairlines, a
   state badge, relative time in mono, a real empty state, and the actions
   revealed on the row rather than in a column of buttons.
4. **Profile and organization** — the densest, and last, because they benefit
   most from patterns settled on the smaller screens.

## 4. What this does not do

- **No new components.** If a screen needs something `components/ui/` does not
  have, that is a finding to raise, not a licence to hand-roll another button.
- **No layout rearrangement.** What changes is how things look and which
  primitives draw them, not what is on the screen or where the sections sit.
  Moving things and restyling them at once makes the diff unreviewable.
- **No dark/light toggle.** The direction is dark. `index.css` keeps its light
  token block so nothing breaks, and a light theme is separate work if it is ever
  wanted.
- **No test framework for rendering.** The package's runner covers decision
  logic. These changes are verified by `typecheck`, by the build, and by looking
  at them in the local environment.

## 5. How it is verified

`pnpm typecheck`, `pnpm test` and `PORT=5173 BASE_PATH=/ pnpm build` stay green,
and the flow is exercised at `http://app.localtest.me:8080` after
`make deploy-app`.

Two things a reviewer must check, because neither the compiler nor the tests can:

- **Every string a person reads goes through i18n, in both the `pt` and the `en`
  map.** A key present in one map only renders as the raw key to half the users
  and nothing in the toolchain catches it. The maps hold 650 keys each today and
  must stay identical.
- **No colour outside the tokens.** A literal hex in a component is a colour that
  will not follow the theme, and it is how a palette rots one screen at a time.

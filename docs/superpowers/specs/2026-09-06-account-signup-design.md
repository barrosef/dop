# Account sign-up — e-mail and password, Google, GitHub

- **Date:** 2026-09-06
- **Status:** approved by the owner, section by section
- **Depends on:** [ADR-0002](../../adr/0002-account-as-unit-of-ownership.md) (the account is the unit of ownership), [ADR-0015](../../adr/0015-firebase-emulators-and-single-owner.md) §4 (Terraform is the single owner), [ADR-0018](../../adr/0018-communication-trigger-and-channel.md) (the trigger is separate from the channel), [ADR-0022](../../adr/0022-the-core-verifies-its-callers.md) (the core verifies a signature; it does not believe a header)
- **Touches:** `dop-app` (the cockpit), `dop-api` (the BFF), `dop-core`, `dop-infra`

## 1. Context — most of this already exists

The temptation with a sign-up story is to design an authentication system. This
platform already has one, and the useful work is to find the three places where
it is incomplete rather than to rebuild what is there.

What is already built and tested:

- **The port.** `ports.IdentityProvider` answers one question — who is calling —
  and normalizes the answer into a `Principal`. Two adapters implement it
  (`identity/firebase.go`, `identity/oidc.go`) against a contract suite that
  refuses a forged token.
- **The provisioning.** `identity.Service.EnsureUser` takes a `Principal` and
  produces a user and a personal account, idempotently, on every first login. It
  merges `providers[]` so a second provider shows up on the same user.
- **The trust boundary.** ADR-0022 already decided that the core verifies the
  person's token rather than believing a header.
- **The sign-in screen.** `dop-app`'s `sign-in.tsx` already signs in with e-mail
  and password against Firebase Auth, and already refuses to distinguish "wrong
  password" from "no such account", with a comment saying why.

The consequence worth stating plainly: **adding Google and GitHub as ways in is,
for the core, a non-event.** No `if github`, no new field on `Principal`. That is
what the port was for. What this spec actually delivers is the sign-**up** flow,
the e-mail verification, the account-linking rule, and the provider
configuration — plus one defect found while reading.

### 1.1 The defect

`migrations/0001_foundation.sql` carries:

```sql
CREATE UNIQUE INDEX users_email_uniq ON users (lower(email)) WHERE email IS NOT NULL;
```

The e-mail is already unique across the whole system, while `EnsureUser` looks a
user up by `subject`. So if Firebase is configured to allow several accounts per
e-mail address, the same person arriving through a second provider carries a
**different subject**, is not found, and the insert violates the unique index.
They do not become two users — they receive an opaque failure and cannot get in.

`EnsureUser`'s own doc comment says the same e-mail through a different provider
resolves to the same user. That is true only because of a setting that lives
outside the code, that nothing asserts, and that no test covers. Linking is not a
refinement of the experience here; it is what the schema already demands.

## 2. Decisions

Each of these was settled with the owner, and each is recorded with the reason,
because the reason is what a future reader can disagree with.

**D-1. Signing up produces a person and a personal account, nothing more.**
Creating an organization is a separate, later action. The sign-up form does not
ask for a company registration number from somebody who has not yet seen the
product. This is what `EnsureUser` already does.

**D-2. Three ways in: e-mail and password, Google, GitHub.** LinkedIn was
considered and dropped. It is not a native Firebase provider; the generic OIDC
route exists only on Identity Platform — which, corrected later, is free to
50,000 monthly active users, so the cost clause of this argument does not hold —
and even there LinkedIn
publishes its discovery document at `%issuer%/oauth/.well-known/openid-configuration`
instead of `%issuer%/.well-known/openid-configuration`, which the Firebase and
GCIP discovery will not accept. The remaining route — the BFF running the OAuth
exchange itself and minting a Firebase custom token — works, and costs a
service-account signing key, a callback route, a hand-written account-linking
step that Firebase would otherwise do for us, and a claim-mapping change in
`firebase.go`. It buys one provider. It is deferred, not refused.

**D-3. Signing in with GitHub grants identity and nothing else.** Reading a
person's repositories and organizations is a different grant, with far larger
scopes (`repo`, `read:org` against `read:user user:email`), and it is a grant
many GitHub organizations block outright until an administrator approves. It
also already has a home in this platform that is not authentication:
[ADR-0003](../../adr/0003-organization-credential-human-authorship.md) gives an
organization account a GitHub App installation and allows a personal token in a
personal account, and [ADR-0009](../../adr/0009-resource-as-unit-of-sharing.md)
makes it a resource credential in the vault behind `ports.SecretStore`. The
`gitprovider` adapter already receives a resolved token and does not know a vault
exists. Connecting GitHub therefore belongs to the integrations surface, after
the account exists.

Worth recording because it is the reason this cannot be bolted onto sign-in
later "for free": **Firebase does not keep the GitHub access token.** It hands it
to the client once, in the sign-in result, and never stores or refreshes it.
Whatever connects repositories will run its own grant regardless.

**D-4. The same e-mail through a second provider is the same user — and the
person proves it.** Firebase is configured to link accounts that use the same
e-mail. A person who signed up with Google and later clicks GitHub does not get
a second credential: the SDK raises `auth/account-exists-with-different-credential`
and returns the attempted `AuthCredential`. The cockpit calls
`fetchSignInMethodsForEmail`, asks the person to sign in with the provider they
already have, and then calls `linkWithCredential`.

This is stronger than the rule we set out to build. We wanted "link when both
sides have a verified e-mail"; what Firebase gives is **proof of possession of
the original provider**, which is the difference between believing an assertion
and demanding a demonstration. It costs nothing extra, so we take it.

**D-5. E-mail verification is required for a password credential, and only for
one.** A blanket "refuse an unverified e-mail" would lock out GitHub, which
frequently delivers one. The distinction is substantive rather than a
convenience exception:

- with a **password** credential, the e-mail is the only thing tying that
  credential to a person, and nobody verified it. Without verification, anybody
  creates an account with anybody's e-mail;
- with a **social** credential, the provider already authenticated the person.
  The e-mail is metadata, not the proof.

`Principal.Providers` already carries `password` in normalized form —
`oidc.go`'s `normalizeProviders` deliberately rewrites OIDC's `pwd` to Firebase's
`password` so the field is comparable across adapters. The rule has the input it
needs.

What that list is **not** is a list of providers only. Firebase builds it from
the keys of `firebase.identities`, which are IDENTIFIER TYPES, plus
`sign_in_provider`: a real e-mail/password token arrives as
`["email","password"]`. So the test cannot be "every entry is `password`" — that
answers *false* for the exact credential the rule exists to stop, and any
unfamiliar value switches the rule off silently. It asks instead whether a
**social** provider is present, against a named set (`google.com`,
`github.com`). An unknown value counts as not-social and the rule still fires;
the cost is that enabling a new social provider without adding it to that set
refuses its unverified-e-mail users until somebody does, which is the direction
we want the mistake to point in.

To be exact, because the sentence above describes only half of it: the rule
fires when `password` is present **and** no social provider is. A credential
carrying neither — `["apple.com"]`, say, from a provider nobody has enabled —
is admitted with an unverified e-mail, on the same reasoning that admits GitHub:
some provider authenticated the person, and the e-mail is not the proof. Only
the presence of `password` makes the e-mail the sole link to a human, and that
is the case this rule exists for.

**D-6. The refusal lives in the core.** Blocking only in the cockpit would be
decoration: the token stays valid and anybody calling the core directly walks
past it. Same reasoning as ADR-0022 — the core verifies, it does not believe.
One rule, one place, no way around it.

**D-7. Firebase generates the link; our Mailer sends the message.** The Admin
SDK generates the verification link **without sending it**, and the message goes
out through the Notifier and Mailer (ADR-0018), in the house's i18n and the
house's brand. Password reset uses the same pair. The alternative — Firebase's
built-in e-mail — would give the platform two mail paths with two appearances
and little control over either.

**D-8. Sign-up is open.** Anyone may create an account. The personal account
born with the user grants access to nothing belonging to anybody else, so the
damage a false account can do is contained within itself. A waiting list or a
domain allowlist would each be a feature of its own, and neither buys anything
today.

**D-9. Verifying is part of the transaction; welcoming is a reaction.** The
verification e-mail is synchronous and blocking — the sign-up is not finished
without it. The welcome e-mail is asynchronous: a `reaction_rules` row reacting
to the user being created, which comes alive when P-29's dispatcher lands (its
plan 2). They are different things and must not share a path merely because both
are e-mail.

**D-10. `EnsureUser` reads the verified token, not the request body.** Added
after the owner approved this spec, on finding that D-5 and US-7 would otherwise
be unenforceable.

`internal/app/grpc/identity.go` builds its `Principal` out of `req.GetSubject()`,
`req.GetEmail()`, `req.GetEmailVerified()` and `req.GetProvider()`. Every rule in
this spec reads exactly those fields, so any caller could pass D-5 by sending
`email_verified: true`. That is the thing ADR-0022 was written to end, and it
ended everywhere except here.

The reason it survived here is worth recording, because it also shows the fix.
`callauth` does verify the bearer token, and then keeps only the resolved user
id. `EnsureUser` is the **bootstrap**: it runs before the person has a user, so
the lookup finds nothing, no actor is proven, and in strict mode the call arrives
with an empty `Call` — leaving the body as the only thing to read. But a token
can prove the **person** without proving an **actor**, and the person is exactly
what this call needs. So the verified identity travels on `ctxutil.Call`,
independent of `ActorID`, and the handler refuses when it is absent.

The request's fields stay in the proto and are ignored. An older client that
still fills them in is **not** refused: the handler never looks at the body, so
the call succeeds and is served the token's values. That is the behaviour we
want — the client is asking for the right thing in an outdated way, and there is
nothing for it to do differently — but it is worth saying plainly, because
"ignored" and "refused" are not the same promise, and only one of them is true
here. What IS refused is a call arriving with no verified token at all.

Retiring the fields is a breaking change for every caller at once, so it belongs
with the work that updates them.

## 3. The user stories

### US-1 — Sign up with e-mail and password

**As** somebody who has never used the platform, **I want** to create an account
with my e-mail and a password, **so that** I can get in without depending on
another company's account.

Acceptance:

1. The form takes an e-mail and a password and creates the credential in
   Firebase from the browser; the BFF never sees the password.
2. On success a verification message is sent (US-2) and the person is told to
   check their inbox, naming the address it went to.
3. An e-mail that already has an account produces the linking path (US-5), never
   a second account and never a message that reveals whether that e-mail is
   registered to somebody else.
4. A password that Firebase's policy refuses produces a message naming the
   requirement that failed, in the person's language.

### US-2 — Verify the e-mail before entering

**As** the platform, **I want** a password account's e-mail proven before the
session counts, **so that** nobody creates an account with somebody else's
address.

Acceptance:

1. The BFF generates the verification link with the Admin SDK and does not send
   it; the message goes out through the Notifier and Mailer.
2. A token whose only provider is `password` and whose e-mail is not verified is
   **refused by the core**, with an error that says the e-mail needs verifying —
   distinguishable from any other refusal.
3. A token from a social provider is accepted whether or not its e-mail is
   verified.
4. Following the link and returning lets the person in with no further step.
5. Requesting the message again is possible and rate-limited.

### US-3 — Sign up or sign in with Google

**As** somebody who already has a Google account, **I want** one button,
**so that** I do not invent another password.

Acceptance:

1. One control does both: an unknown person is created, a known one signs in.
   There is no separate "sign up with Google".
2. The scopes requested are the ones sign-in needs, and no more.
3. The user reaching the core carries `google` among its providers.

### US-4 — Sign up or sign in with GitHub

**As** a developer, **I want** to enter with GitHub, **so that** I use the
identity I already work under.

Acceptance:

1. Same single control as US-3; the requested scopes are `read:user` and
   `user:email` and nothing more.
2. The person is **not** asked for repository or organization access anywhere in
   this flow, and no GitHub token is stored (D-3).
3. If the person's GitHub organization blocks third-party applications, the
   message says an organization administrator has to approve it, and does not
   invite a pointless retry.

### US-5 — Arriving through a second provider

**As** somebody who signed up with one provider and later clicks another,
**I want** to land in my existing account, **so that** I do not end up as two
people with two personal accounts.

Acceptance:

1. Firebase is configured to link accounts sharing an e-mail (US-8).
2. On `auth/account-exists-with-different-credential`, the cockpit names the
   provider the person already has, asks them to sign in with it, and links the
   pending credential.
3. After linking, `providers[]` on the user carries both, and there is exactly
   one user and one personal account.
4. Cancelling half way leaves nothing behind: no partial user, no orphan
   account.

### US-6 — Reset a forgotten password

**As** somebody who forgot their password, **I want** to set a new one,
**so that** I am not locked out.

Acceptance:

1. The link is generated by the Admin SDK and the message is sent by the Mailer,
   exactly as US-2.
2. The response is identical whether or not the address has an account.
3. An account with no password credential — social only — is told how it signs
   in, without confirming that the address exists.

### US-7 — The core refuses what it cannot vouch for

**As** the platform, **I want** the linking assumption checked at runtime rather
than trusted, **so that** a configuration change does not surface as a database
error.

Acceptance:

1. `EnsureUser` receiving an unknown subject whose e-mail already belongs to
   another user refuses **explicitly**, naming the provider configuration as the
   cause.
2. That refusal is a distinct error kind, never a unique-index violation
   escaping as an internal error.
3. A test proves it: two principals, different subjects, the same verified
   e-mail.

### US-8 — The providers have one owner

**As** whoever operates this, **I want** the provider configuration owned by
Terraform, **so that** an `apply` does not silently switch authentication off.

Acceptance:

1. Google and GitHub are enabled through Terraform, with their client IDs and
   secrets, and so is the setting that links accounts sharing an e-mail.
2. `dop-infra`'s `README` gains the row declaring the single owner of Auth
   providers, which ADR-0015 §4 requires and names as the ambiguous case.
3. Nothing is created through the Firebase console.

## 4. What changes, by repository

**`dop-core`** — the smallest surface, and the point of the port:

- `identity.Repository` gains a lookup by verified e-mail; there is none today.
- `EnsureUser` gains D-5's rule (a password-only principal needs a verified
  e-mail) and US-7's explicit refusal.
- No adapter changes. `Principal` gains no field.

**`dop-api`** (the BFF) — gains its first Firebase Admin capability:

- a service-account credential, resolved through the vault, used only to
  generate verification and password-reset links;
- the two routes that generate those links and hand the message to the Notifier.

Note it verifies Firebase tokens by hand today (`jwt` + `httpx`, no Admin SDK) —
deliberately, and that stays. What arrives is link generation, not verification.

**`dop-app`** (the cockpit) — where most of the work is:

- the sign-up screen, and the two provider buttons on both screens;
- the linking choreography of US-5;
- the "check your inbox" and "verify to continue" states;
- the three error messages of §5, in i18n.

**`dop-infra`** — the Terraform for the providers, and the ownership row.

## 5. Errors the person actually sees

Three cases earn their own message, because a generic one is expensive here:

- **the e-mail already has an account through another provider** — not an error,
  the linking path: name the provider they have and offer it;
- **the GitHub organization blocks third-party applications** — the person did
  nothing wrong and retrying will not help, and an administrator has to approve.
  **Corrected after implementation:** this case cannot be recognised from a
  Firebase error code. GitHub shows its own restriction page inside the popup,
  and if the person closes it we see `auth/popup-closed-by-user` —
  indistinguishable from somebody changing their mind. So the cockpit must not
  promise this message, and must not guess at it with a heuristic. What explains
  the situation is GitHub's own page, which the person has already read. What we
  can do is not contradict it: the abandoned-popup message says the sign-in did
  not complete, and does not blame a password.

  The code that looked like this one is not this one. `auth/unauthorized-domain`
  means the current origin is missing from OUR project's authorized domains — our
  configuration, which no administrator of theirs can fix. Its message is an
  alert for whoever runs the platform, and must never send the person to ask
  anybody for anything;
- **wrong password against no such account** — indistinguishable, always.
  `sign-in.tsx` already gets this right and says why in a comment: telling them
  apart hands the user list to whoever asks. The same rule binds sign-up and
  password reset.

## 6. Testing, and one thing that cannot be tested locally

The Firebase Auth emulator does not perform a real OAuth handshake. It shows a
fake account picker where a developer types an e-mail and a name, and mints a
token as though Google had answered. That is excellent for daily work, and it
means **the real handshake with Google and GitHub is never exercised locally.**

This is a fact to record rather than a defect to fix, and it has a consequence:
the first time the social path runs for real must not be in production. The
plan must name an environment with a real Firebase project where US-3 and US-4
are exercised end to end before release.

What is testable, and must be:

- the core's rules (D-5, US-7) as domain tests, with no database;
- the linking choreography against the emulator, where the fake picker is enough
  because what is under test is our reaction to Firebase's error, not the
  handshake;
- the contract suite already covering `IdentityProvider` stays green untouched —
  if this work needs to change it, something in the design is wrong.

## 7. What this does not build

- **LinkedIn** (D-2), and the custom-token machinery it would need.
- **Connecting repositories and organizations** (D-3) — the integrations
  surface, on top of ADR-0003 and ADR-0009.
- **The welcome e-mail** (D-9) — a `reaction_rules` row, alive when P-29's
  dispatcher lands.
- **Organization creation** (D-1) — `CreateOrganization` already exists; giving
  it a screen is separate work.
- **A second factor at sign-up.** ADR-0020 puts the second factor in the core
  and it stands on its own; enrolling one is not part of creating an account.

## 8. Open items for the plan

1. Firebase's password policy is configurable. The plan picks the minimum and
   states it, so US-1's message can name the requirement that failed.
2. Rate limits for US-2's resend and US-6's request need a number and a place to
   live.
3. Where the BFF's service-account credential is stored, and who owns it in the
   ADR-0015 §4 table.

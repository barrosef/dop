# Account Sign-up in the Cockpit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a person create an account with e-mail and password, Google or GitHub, land in their existing account when they arrive through a second provider, and be told to verify their address before they get in.

**Architecture:** The Firebase JS SDK does the work in the browser; the cockpit's job is the choreography around it. The one piece with real logic — deciding what an Auth error means and what to do about it — is pulled out as a pure function and tested, because it is where being wrong is invisible. The screens stay thin.

**Tech Stack:** React 18, TypeScript, Vite, `firebase/auth` v10 (already a dependency), react-router, Tailwind, the repo's own flat-key i18n.

**Spec:** `docs/superpowers/specs/2026-09-06-account-signup-design.md` — US-1, US-3, US-4, US-5, and the client half of US-2 and US-6.

**Repository:** `repos/dop-app/artifacts/dop` — every path in this plan is relative to it.

## Global Constraints

- **Code, comments, identifiers and test names are English. Everything a person READS on screen goes through i18n** (`src/lib/i18n.ts`), with both the `pt` and the `en` map filled. Commit messages are Portuguese by house convention.
- Comments explain WHY a decision was made and what it costs, never what the line does.
- `pnpm typecheck` must be green. After Task 1, `pnpm test` must be green too.
- The same code runs against the emulator and against real Firebase; only `VITE_FIREBASE_AUTH_EMULATOR_URL` differs. **Nothing on these screens may assume which one it is talking to.**
- Never distinguish "no such account" from "wrong password" in anything a person can see: telling them apart hands the user list to whoever asks. `src/pages/sign-in.tsx:33-35` already says so.

---

## Why Task 1 exists, and why the cockpit gets a test runner

This package has **no test framework** — `package.json` offers `dev`, `build`, `serve` and `typecheck`, and there is not one test file in the tree. That is a defensible place to have been while the cockpit was screens over mocks. It stops being defensible here: the account-linking choreography decides, from an error code, whether to send somebody to another provider or to refuse them, and getting it wrong is silent.

So this plan adds **vitest** and tests exactly one thing: the pure decision functions. Not the rendering, not the Firebase calls — the logic that says what an error means and what should happen next. Rendering stays covered by `typecheck` and by exercising the flow against the local emulator.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `package.json`, `vitest.config.ts` | The test runner, and only that | 1 |
| `src/lib/platform/auth-errors.ts` | Pure: an Auth error code in, a decision out | 1 |
| `src/lib/platform/auth-errors.test.ts` | Its tests — every branch, including the ones that must NOT collapse | 1 |
| `src/lib/platform/session.tsx` | Gains sign-up, provider sign-in, verification and reset | 2 |
| `src/pages/sign-up.tsx` | The new screen | 3 |
| `src/pages/sign-in.tsx` | Gains the provider buttons and a link to sign-up | 3 |
| `src/App.tsx` | The `/sign-up` route | 3 |
| `src/lib/i18n.ts` | Every new string, in `pt` and `en` | 3, 4 |
| `src/pages/link-provider.tsx` | The choreography screen | 4 |
| `src/pages/verify-email.tsx` | The gate and the resend | 4 |

---

### Task 1: What an Auth error means, decided in one place and tested

**Files:**
- Modify: `package.json`
- Create: `vitest.config.ts`
- Create: `src/lib/platform/auth-errors.ts`
- Create: `src/lib/platform/auth-errors.test.ts`

**Interfaces:**
- Produces: `type AuthDecision`, and `decideFromAuthError(err: unknown): AuthDecision`.

- [ ] **Step 1: Add the runner**

```bash
pnpm add -D vitest@^2
```

Add to `package.json`'s `scripts`:

```json
    "test": "vitest run"
```

Create `vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';

// Node environment on purpose: what is tested here is pure decision logic, not
// rendering. A jsdom environment would invite tests that mount screens, which is
// not what this runner was added for.
export default defineConfig({
  test: { environment: 'node', include: ['src/**/*.test.ts'] },
});
```

- [ ] **Step 2: Write the failing tests**

Create `src/lib/platform/auth-errors.test.ts`:

```ts
import { describe, expect, it } from 'vitest';

import { decideFromAuthError } from './auth-errors';

describe('decideFromAuthError', () => {
  it('collapses a wrong credential into one indistinguishable answer', () => {
    // Telling "no such account" from "wrong password" hands the user list to
    // whoever asks. All three codes Firebase can return here are one answer.
    for (const code of [
      'auth/wrong-password',
      'auth/user-not-found',
      'auth/invalid-credential',
    ]) {
      expect(decideFromAuthError({ code })).toEqual({ kind: 'invalid-credential' });
    }
  });

  it('does NOT collapse an account that exists under another provider', () => {
    // This is not a failure — it is the linking path. Collapsing it into
    // "invalid credential" is the bug this function exists to prevent: the
    // person would be told their password is wrong when they have no password.
    const decision = decideFromAuthError({
      code: 'auth/account-exists-with-different-credential',
      customData: { email: 'ana@example.com' },
    });
    expect(decision).toEqual({ kind: 'link-required', email: 'ana@example.com' });
  });

  it('recognises an organization that blocks third-party applications', () => {
    // The person did nothing wrong and retrying will not help: an administrator
    // has to approve. A generic message would send them round the loop forever.
    expect(decideFromAuthError({ code: 'auth/unauthorized-domain' })).toEqual({
      kind: 'blocked-by-organization',
    });
  });

  it('reports a closed popup as an abandonment, not an error', () => {
    for (const code of ['auth/popup-closed-by-user', 'auth/cancelled-popup-request']) {
      expect(decideFromAuthError({ code })).toEqual({ kind: 'abandoned' });
    }
  });

  it('names a weak password so the person knows what to change', () => {
    expect(decideFromAuthError({ code: 'auth/weak-password' })).toEqual({
      kind: 'weak-password',
    });
  });

  it('keeps an unknown failure distinguishable instead of guessing', () => {
    expect(decideFromAuthError({ code: 'auth/network-request-failed' })).toEqual({
      kind: 'unknown',
      code: 'auth/network-request-failed',
    });
    expect(decideFromAuthError(new Error('boom'))).toEqual({
      kind: 'unknown',
      code: '',
    });
  });

  it('treats an e-mail already in use as the linking path, not a refusal', () => {
    expect(
      decideFromAuthError({ code: 'auth/email-already-in-use' }),
    ).toEqual({ kind: 'link-required', email: '' });
  });
});
```

- [ ] **Step 3: Run them and see them fail**

Run: `pnpm test`
Expected: FAIL — `Failed to resolve import "./auth-errors"`.

- [ ] **Step 4: Implement**

Create `src/lib/platform/auth-errors.ts`:

```ts
/**
 * What a Firebase Auth failure MEANS, decided in one place.
 *
 * The screens used to collapse anything containing `auth/` into "invalid
 * e-mail or password". That is right for a wrong credential and wrong for
 * everything else — most damagingly for the case where the person already has
 * an account under another provider, who would be told their password is wrong
 * when they never had one.
 *
 * The cost of this file is one indirection between an SDK call and a message.
 * What it buys is that the decision is testable without a browser, which is the
 * only way this logic gets exercised at all.
 */

export type AuthDecision =
  | { kind: 'invalid-credential' }
  | { kind: 'link-required'; email: string }
  | { kind: 'blocked-by-organization' }
  | { kind: 'abandoned' }
  | { kind: 'weak-password' }
  | { kind: 'unknown'; code: string };

function codeOf(err: unknown): string {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const code = (err as { code: unknown }).code;
    return typeof code === 'string' ? code : '';
  }
  return '';
}

function emailOf(err: unknown): string {
  if (typeof err === 'object' && err !== null && 'customData' in err) {
    const data = (err as { customData?: { email?: unknown } }).customData;
    if (data && typeof data.email === 'string') return data.email;
  }
  return '';
}

export function decideFromAuthError(err: unknown): AuthDecision {
  const code = codeOf(err);
  switch (code) {
    // Three codes, one answer. Which of them Firebase returns depends on the
    // project's e-mail-enumeration protection, and the person must not be able
    // to tell the difference either way.
    case 'auth/wrong-password':
    case 'auth/user-not-found':
    case 'auth/invalid-credential':
      return { kind: 'invalid-credential' };

    case 'auth/account-exists-with-different-credential':
    case 'auth/email-already-in-use':
      return { kind: 'link-required', email: emailOf(err) };

    // Firebase reports an organization's third-party-application restriction as
    // an unauthorized domain. Retrying cannot help — an administrator has to act.
    case 'auth/unauthorized-domain':
      return { kind: 'blocked-by-organization' };

    case 'auth/popup-closed-by-user':
    case 'auth/cancelled-popup-request':
      return { kind: 'abandoned' };

    case 'auth/weak-password':
      return { kind: 'weak-password' };

    default:
      return { kind: 'unknown', code };
  }
}
```

- [ ] **Step 5: Run the tests and the typecheck**

Run: `pnpm test && pnpm typecheck`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add package.json pnpm-lock.yaml vitest.config.ts src/lib/platform/auth-errors.ts src/lib/platform/auth-errors.test.ts
git commit -m "feat(auth): o que uma falha do Firebase significa, decidido num lugar só"
```

---

### Task 2: The session learns to create, to enter by provider, and to verify

**Files:**
- Modify: `src/lib/platform/session.tsx`

**Interfaces:**
- Consumes: `auth` from `./firebase`, `decideFromAuthError` from `./auth-errors`.
- Produces, on the `Session` value: `signUp(email, password): Promise<void>`, `signInWith(provider: 'google' | 'github'): Promise<void>`, `linkPending(email, password): Promise<void>`, `sendVerification(): Promise<void>`, `resetPassword(email): Promise<void>`, and `pendingLink: { email: string } | null`.

- [ ] **Step 1: Add the imports and the provider map**

At the top of `src/lib/platform/session.tsx`, beside the existing `firebase/auth` import:

```tsx
import {
  GithubAuthProvider,
  GoogleAuthProvider,
  createUserWithEmailAndPassword,
  linkWithCredential,
  sendEmailVerification,
  sendPasswordResetEmail,
  signInWithPopup,
  type AuthCredential,
} from 'firebase/auth';
```

and, above the component:

```tsx
// The scopes are the ones SIGNING IN needs, and nothing more. Reading somebody's
// repositories is a different grant with far larger scopes, and it belongs to
// the integrations surface after the account exists (spec D-3). Asking for it
// here would put a frightening consent screen in front of a stranger, and would
// be blocked outright by organizations that restrict third-party applications.
const providers = {
  google: () => new GoogleAuthProvider(),
  github: () => {
    const p = new GithubAuthProvider();
    p.addScope('read:user');
    p.addScope('user:email');
    return p;
  },
} as const;
```

- [ ] **Step 2: Hold the pending credential**

Inside `SessionProvider`, beside the existing state:

```tsx
  // When a provider sign-in collides with an existing account, Firebase hands
  // back the credential it could not use. It is kept in memory — never in
  // storage — until the person proves the provider they already have, because
  // it is a bearer credential and writing it to disk would outlive the moment
  // it is good for.
  const pending = React.useRef<AuthCredential | null>(null);
  const [pendingLink, setPendingLink] = React.useState<{ email: string } | null>(null);
```

- [ ] **Step 3: Add the operations**

Inside the `React.useMemo` value, beside `signIn` and `signOut`:

```tsx
      signUp: async (email, password) => {
        const created = await createUserWithEmailAndPassword(auth, email, password);
        // Sent immediately, not on the next screen: if the person closes the tab
        // here, the account exists and nothing has told them what to do next.
        await sendEmailVerification(created.user);
      },
      signInWith: async (provider) => {
        try {
          await signInWithPopup(auth, providers[provider]());
        } catch (failure) {
          const decision = decideFromAuthError(failure);
          if (decision.kind === 'link-required') {
            pending.current = credentialFromError(provider, failure);
            setPendingLink({ email: decision.email });
          }
          throw failure;
        }
      },
      linkPending: async (email, password) => {
        // Signing in with the provider they ALREADY have is the proof of
        // possession. Firebase gives us that for free here, and it is stronger
        // than matching a verified e-mail: it is a demonstration, not a claim.
        const existing = await signInWithEmailAndPassword(auth, email, password);
        if (pending.current) {
          await linkWithCredential(existing.user, pending.current);
          pending.current = null;
          setPendingLink(null);
        }
      },
      sendVerification: async () => {
        if (auth.currentUser) await sendEmailVerification(auth.currentUser);
      },
      resetPassword: async (email) => {
        await sendPasswordResetEmail(auth, email);
      },
```

Add `pendingLink` to the value and to the `Session` type, and add `pendingLink` to the `useMemo` dependency array.

Write `credentialFromError` as a small helper above the component — `GoogleAuthProvider.credentialFromError(err)` and `GithubAuthProvider.credentialFromError(err)` are the SDK's own accessors, and which one applies depends on the provider that failed:

```tsx
function credentialFromError(provider: keyof typeof providers, err: unknown) {
  const e = err as Parameters<typeof GoogleAuthProvider.credentialFromError>[0];
  return provider === 'google'
    ? GoogleAuthProvider.credentialFromError(e)
    : GithubAuthProvider.credentialFromError(e);
}
```

- [ ] **Step 4: Typecheck**

Run: `pnpm typecheck && pnpm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/platform/session.tsx
git commit -m "feat(auth): a sessão sabe criar conta, entrar por provedor e verificar"
```

---

### Task 3: The sign-up screen, and one button per way in

**Files:**
- Create: `src/pages/sign-up.tsx`
- Modify: `src/pages/sign-in.tsx`
- Modify: `src/App.tsx`
- Modify: `src/lib/i18n.ts`

**Interfaces:**
- Consumes: `useSession()`'s `signUp` and `signInWith`, `decideFromAuthError`, `useI18n`.

- [ ] **Step 1: Add the strings**

In `src/lib/i18n.ts`, add to BOTH the `pt` and the `en` maps, beside the existing `auth.*` keys (`pt` around line 570, `en` around line 1213):

| key | pt | en |
|---|---|---|
| `auth.signUp.title` | `Criar conta` | `Create an account` |
| `auth.signUp.subtitle` | `Comece com seu e-mail ou por um provedor que você já usa.` | `Start with your e-mail, or with a provider you already use.` |
| `auth.signUp.submit` | `Criar conta` | `Create account` |
| `auth.signUp.submitting` | `Criando…` | `Creating…` |
| `auth.signUp.haveAccount` | `Já tem conta? Entrar` | `Already have an account? Sign in` |
| `auth.signIn.noAccount` | `Não tem conta? Criar` | `No account? Create one` |
| `auth.or` | `ou` | `or` |
| `auth.with.google` | `Continuar com Google` | `Continue with Google` |
| `auth.with.github` | `Continuar com GitHub` | `Continue with GitHub` |
| `auth.error.weakPassword` | `Escolha uma senha mais longa.` | `Choose a longer password.` |
| `auth.error.blockedByOrg` | `Sua organização no GitHub bloqueia aplicativos de terceiros. Um administrador precisa aprovar o DOP — tentar de novo não resolve.` | `Your GitHub organization blocks third-party applications. An administrator has to approve DOP — trying again will not help.` |
| `auth.error.unknown` | `Não foi possível continuar ({code}).` | `Could not continue ({code}).` |

- [ ] **Step 2: Write the sign-up screen**

Create `src/pages/sign-up.tsx`, modelled on `sign-in.tsx` — the same layout, the same `data-testid` convention, the same card. It holds e-mail and password, calls `signUp`, and on success navigates to `/verify-email`. Its error handling calls `decideFromAuthError` and maps:

- `weak-password` → `auth.error.weakPassword`
- `link-required` → navigate to `/link-provider` carrying the e-mail
- `blocked-by-organization` → `auth.error.blockedByOrg`
- `abandoned` → clear the error and do nothing; the person closed a popup on purpose
- `invalid-credential` → `auth.invalid`
- `unknown` → `auth.error.unknown` with the code

Below the form, a divider carrying `auth.or` and the two provider buttons, each calling `signInWith` and mapping failures through the same decision.

- [ ] **Step 3: Put the same two buttons on sign-in**

`src/pages/sign-in.tsx` gets the same divider and the same two buttons — one control does both jobs, since a provider sign-in creates the account when there is none. Replace its current `catch` with the `decideFromAuthError` mapping above, so `account-exists-with-different-credential` stops being collapsed into "invalid e-mail or password". Add the `auth.signIn.noAccount` link to `/sign-up`.

- [ ] **Step 4: Route it**

In `src/App.tsx`, beside the existing unauthenticated routes (the `/invites/:inviteId` route at line 148 shows the shape), add `/sign-up`, `/link-provider` and `/verify-email`. The last two are created in Task 4 — add their routes there rather than pointing at files that do not exist yet.

- [ ] **Step 5: Typecheck and commit**

Run: `pnpm typecheck && pnpm test`

```bash
git add src/pages src/App.tsx src/lib/i18n.ts
git commit -m "feat(auth): a tela de cadastro, e um botão por jeito de entrar"
```

---

### Task 4: Landing in the account you already have, and the gate before you get in

**Files:**
- Create: `src/pages/link-provider.tsx`
- Create: `src/pages/verify-email.tsx`
- Modify: `src/App.tsx`
- Modify: `src/lib/i18n.ts`

- [ ] **Step 1: Add the strings**

| key | pt | en |
|---|---|---|
| `auth.link.title` | `Você já tem conta` | `You already have an account` |
| `auth.link.explain` | `Já existe uma conta com {email}. Entre pelo jeito que você usou da primeira vez e a gente conecta este novo acesso.` | `There is already an account for {email}. Sign in the way you did the first time and we will connect this new one.` |
| `auth.link.submit` | `Entrar e conectar` | `Sign in and connect` |
| `auth.verify.title` | `Confirme seu e-mail` | `Confirm your e-mail` |
| `auth.verify.sent` | `Enviamos um link para {email}. Abra o link e volte aqui.` | `We sent a link to {email}. Open it and come back.` |
| `auth.verify.resend` | `Enviar de novo` | `Send it again` |
| `auth.verify.resent` | `Enviado.` | `Sent.` |
| `auth.verify.check` | `Já confirmei` | `I have confirmed` |
| `auth.verify.notYet` | `Ainda não confirmado. Abra o link do e-mail e tente de novo.` | `Not confirmed yet. Open the link in the e-mail and try again.` |

- [ ] **Step 2: The linking screen**

`src/pages/link-provider.tsx` reads `pendingLink` from the session, shows `auth.link.explain` with the e-mail, and offers the password form calling `linkPending`. With no `pendingLink` in state — someone opened the URL directly, or reloaded — it redirects to `/sign-in`, because the pending credential lives in memory and a reload has already lost it. Say that in a comment: it is a deliberate limit, not an oversight.

- [ ] **Step 3: The verification gate**

`src/pages/verify-email.tsx` shows `auth.verify.sent` with `auth.currentUser?.email`, a resend button calling `sendVerification`, and an "I have confirmed" button that calls `auth.currentUser?.reload()` and then re-reads `emailVerified` — the SDK does not learn about the click on its own. When it is true, navigate to `/`; when it is false, show `auth.verify.notYet`.

- [ ] **Step 4: Send people here who need to be here**

In `src/App.tsx`, the shell that guards authenticated routes must send a signed-in user whose credential is password-only and whose `emailVerified` is false to `/verify-email`. Read how the current shell decides between the app and the sign-in screen, and add the condition there — one place, so no route can forget it.

The provider check matters: `auth.currentUser?.providerData` carries one entry per linked provider, whose `providerId` is `password`, `google.com` or `github.com`. Gate only when **every** entry is `password` — a social provider means somebody already authenticated this person, which is exactly the distinction the core makes (spec D-5). Getting this wrong locks out every GitHub user, since GitHub frequently reports an unverified address.

- [ ] **Step 5: Typecheck and commit**

Run: `pnpm typecheck && pnpm test`

```bash
git add src/pages src/App.tsx src/lib/i18n.ts
git commit -m "feat(auth): cair na conta que você já tem, e o portão antes de entrar"
```

---

## What this plan does not build

- **The verification e-mail through the house's Mailer** (spec D-7). Here it is Firebase's own message, which is what the emulator shows locally. Routing it through the Notifier is its own plan, in the core.
- **Password reset's screen.** `resetPassword` exists on the session from Task 2; the screen that calls it is small and separate.
- **Connecting repositories** (spec D-3) — the integrations surface.
- **Any test of rendering.** The runner added in Task 1 is for decision logic. Screens are covered by `typecheck` and by exercising the flow against the local emulator.

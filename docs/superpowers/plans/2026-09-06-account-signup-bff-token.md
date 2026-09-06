# The BFF Forwards the Person's Token — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `EnsureUser` reach the core carrying the person's bearer token, so the core can verify who is signing up instead of reading it from the request body.

**Architecture:** One change threaded through three files. `CoreResolver.__call__` gains the raw token as a parameter, `_ensure_user` puts it on the metadata, and the two callers — the REST middleware and the gRPC interceptor — pass what they already hold.

**Tech Stack:** Python 3, FastAPI, grpcio, pytest, uv.

**Spec:** `docs/superpowers/specs/2026-09-06-account-signup-design.md` (D-10)

**Repository:** `repos/dop-api` — every path in this plan is relative to it.

## Global Constraints

- Everything in the repository is written in English — code, comments, identifiers, test names. Commit messages are Portuguese by house convention.
- Comments explain WHY a decision was made and what it costs, never what the line does.
- `make test` runs `uv run pytest -q`; `make lint` runs `uv run ruff check app tests`. Both must be green.
- ADR-0029 binds this work: the core verifies a signature, it does not believe a claim.

---

## Why this is urgent

`dop-core` shipped the change that makes `EnsureUser` read the identity a token proved rather than the request body, and refuse when no token was verified. This BFF is its only production caller, and it calls without one:

```python
# app/coreclient/resolver.py:78
user = await stubs.identity_stub().EnsureUser(
    req, metadata=core.metadata_for(), timeout=self._deadline
)
```

`core.metadata_for()` appends `authorization: Bearer …` only when handed a `raw_token` (`app/coreclient/client.py:102`), and none is passed here. So every `EnsureUser` now returns `unauthenticated` — and `_ensure_user` runs on **every authenticated request**, not only the first, so the whole authenticated surface is down until this lands.

The token is not far away. `AuthMiddleware` reads it at `middleware.py:28` and stores it on the `AuthContext` at `:56` — but it calls the resolver at `:43`, before that context exists, and does not pass it. The gRPC interceptor already computes the same value at `interceptors.py:385` and also drops it on the way to `_resolve`.

---

### Task 1: Thread the token from the edge to the core

**Files:**
- Modify: `app/coreclient/resolver.py:41-80`
- Modify: `app/platform/security/middleware.py:43`
- Modify: `app/grpcapi/interceptors.py:386-395`
- Test: `tests/test_identity_routes.py`

**Interfaces:**
- Consumes: `core.metadata_for(..., raw_token=...)` — already exists at `app/coreclient/client.py:67-102` and already appends the `authorization` header when given a non-empty token.
- Produces: `CoreResolver.__call__(self, principal, account_id, raw_token="")` — the third parameter is keyword-friendly and defaults to empty, so any caller not yet updated keeps compiling while failing loudly at the core rather than silently at the edge.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_identity_routes.py`. The suite's `FakeCall` records the metadata each RPC received and exposes it through `.metadata()`, so the assertion is direct:

```python
def test_ensure_user_carries_the_persons_token(client, fake_core):
    """The core stopped believing the request body (ADR-0029, D-10).

    It now reads who the person is from the token it verified itself, and
    refuses when there is none. If this header stops going out, every login
    fails — and it fails on EVERY request, because the resolver runs on all of
    them and not only the first.
    """
    client.get("/accounts", headers=auth_headers())

    md = fake_core.EnsureUser.metadata()
    assert "authorization" in md, f"EnsureUser went out without the token: {md}"
    assert md["authorization"].startswith("Bearer ")
```

Read the top of `tests/test_identity_routes.py` before writing: use whatever fixtures that file already provides for the client, the fake core and the headers, under their real names. `tests/conftest.py` has `metadata_for(token=...)` and the `FakeCore` stub with `EnsureUser`, `ListAccounts` and `ListMemberships`. Do not invent a second set of fixtures.

- [ ] **Step 2: Run it and see it fail**

Run: `uv run pytest tests/test_identity_routes.py -k carries_the_persons_token -q`
Expected: FAIL — `EnsureUser went out without the token: {'x-request-id': ..., 'x-dop-assertion': ...}`

- [ ] **Step 3: Give the resolver the token**

In `app/coreclient/resolver.py`, widen the call signature and pass the value down:

```python
    async def __call__(
        self, principal: Principal, account_id: str, raw_token: str = ""
    ) -> tuple[str, str, dict[str, str]]:
        actor_name = principal.name or principal.email
        user_id = await self._ensure_user(principal, raw_token)
```

and in `_ensure_user`:

```python
    async def _ensure_user(self, principal: Principal, raw_token: str = "") -> str:
        """Idempotent by design — it runs on EVERY login, not only the first.

        It carries the person's TOKEN and not only the edge's assertion, because
        since ADR-0029 the core reads who the person is from the signature it
        verified itself rather than from this request's body. Without the header
        the core refuses, and it refuses on every request, not only the first.
        """
```

leaving the body as it is except for the metadata:

```python
        user = await stubs.identity_stub().EnsureUser(
            req, metadata=core.metadata_for(raw_token=raw_token), timeout=self._deadline
        )
```

Leave the `EnsureUserRequest` fields as they are. The core ignores them now, and removing them is a proto change that belongs with whoever retires the fields.

- [ ] **Step 4: Pass it from the REST middleware**

At `app/platform/security/middleware.py:43`, the raw header is already in hand as `raw`:

```python
                user_id, role, grants = await self.resolver(
                    principal, account_id, raw.removeprefix("Bearer ").strip()
                )
```

- [ ] **Step 5: Pass it from the gRPC interceptor**

`app/grpcapi/interceptors.py:385` already computes the stripped token and returns it as the second element of its tuple. Find where that tuple is unpacked and where `_resolve` is called, and thread the value through:

```python
    async def _resolve(self, principal, account_id: str, raw_token: str = ""):
        if self.resolver is None:
            return "", "", {}
        try:
            return await self.resolver(principal, account_id, raw_token)
```

Read the surrounding code before editing — the caller may name the variable something else, and the code wins over this snippet.

- [ ] **Step 6: Run the test and the suite**

Run: `uv run pytest tests/test_identity_routes.py -k carries_the_persons_token -q && uv run pytest -q && uv run ruff check app tests`
Expected: PASS, and the whole suite green.

- [ ] **Step 7: Prove the gRPC side too**

The REST test above covers one of the two callers. Add the same assertion for the gRPC path, in whichever test file already exercises the interceptor with a token — `tests/test_grpc_identity.py` is the likely home. Two edges call this resolver, and a fix that lands on one of them is half a fix:

```python
async def test_the_grpc_edge_also_carries_the_token(...):
    """Two edges call the same resolver. Fixing one and not the other leaves the
    CLI and the agents unable to sign in while the browser works, which is the
    kind of asymmetry nobody finds until a demo."""
```

Fill in the body using that file's existing fixtures and its established way of invoking an intercepted call; assert `"authorization"` reached `EnsureUser`'s metadata exactly as the REST test does.

- [ ] **Step 8: Commit**

```bash
git add app tests
git commit -m "fix(auth): o EnsureUser ia ao core sem o token da pessoa"
```

---

## What this plan does not build

- **Retiring `EnsureUserRequest`'s now-ignored fields.** The core ignores them; removing them from the proto is a breaking change for any other client and belongs with the work that updates them all.
- **The verification e-mail's route.** It needs the message path, which is its own plan.

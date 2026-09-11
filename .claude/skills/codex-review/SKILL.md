---
name: codex-review
description: Send the current change to Codex for an independent code review against this repository's invariants, and return structured findings. Use after a change of consequence — the core, a contract, a migration, a submodule pointer — before proposing a commit.
disable-model-invocation: false
---

# Independent review by Codex

Codex is a different model family and did not write the code it is reading. That
is the whole value: a reviewer that shares the author's reasoning inherits the
author's blind spots. Findings are evidence, not a verdict.

## 1. Locate the change

The repository is submodule-heavy, so the change is usually inside a component
rather than at the root. Find where it actually is:

```bash
cd /opt/wks/dbo/dop && git status --short
for r in repos/*/; do
  s=$(git -C "$r" status --short 2>/dev/null)
  [ -n "$s" ] && echo "== $r" && echo "$s"
done
```

Review the repository that holds the change. Reviewing the root when the edit is
in `repos/dop-core` shows Codex only a moved pointer.

## 2. Run the review

`REPO` is the directory from step 1 — a component, or the root when the change
really is there. Codex lives under nvm and is often absent from `PATH`, so
resolve it rather than assuming:

```bash
CODEX=$(command -v codex || ls /home/edbarros/.nvm/versions/node/*/bin/codex 2>/dev/null | head -1)
SKILL=/opt/wks/dbo/dop/.claude/skills/codex-review
OUT=$(mktemp /tmp/codex-review-XXXX.json)

cd "$REPO" && time "$CODEX" exec \
  --sandbox read-only \
  --output-schema "$SKILL/findings.schema.json" \
  -o "$OUT" \
  "$(cat "$SKILL/prompt.md")

--- DIFF UNDER REVIEW ---
$(git diff HEAD; git status --porcelain | grep '^??' | cut -c4- | while read f; do echo "--- new file: $f"; cat "$f"; done)"

cat "$OUT"
```

`--sandbox read-only` is not optional. A reviewer that can write is no longer a
reviewer, and read-only also means the call cannot damage the working tree it is
inspecting.

Report the wall time. It is the number that decides whether this belongs in an
automatic gate or stays an explicit call.

## 3. Triage before reporting

Do not relay the JSON. Read it and apply this repository's weighting:

- **A finding naming a broken invariant** — treat as correct until you have a
  specific reason it is not. Fix it.
- **A correctness finding** — verify it yourself against the code. Codex cannot
  run the tests; you can. `make test` in `dop-core` needs no environment.
- **An advisory or style finding** — usually noise here. Say you are declining
  it and why. Do not comply to be agreeable.

State your disagreement in your own words when you disagree. Silently ignoring a
finding and silently obeying one are the same failure.

## 4. Report

Give the human: the verdict, the findings that survived triage, what you
changed, and what you declined with the reason. If Codex returned nothing worth
acting on, say that plainly — a review that finds nothing is a real result, and
inventing work to justify the call is worse than the call being cheap.

## When this fails

- **`refresh_token_reused` / 401** — the Codex session expired. The human must
  run `codex login`; you cannot. Stop and say so.
- **No `--output-schema` support** — the installed Codex is too old. Fall back to
  `codex review --uncommitted`, which is purpose-built but returns prose, and
  summarise it yourself.
- **A trust prompt** — this repository is not in `~/.codex/config.toml`. Add
  `-c 'projects."/opt/wks/dbo/dop".trust_level="trusted"'` for the call, or ask
  the human to trust it once.

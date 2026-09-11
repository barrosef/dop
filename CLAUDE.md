# CLAUDE.md

@AGENTS.md

The briefing above is shared with Codex, which reads `AGENTS.md` natively.
Keep project facts there, so both agents stay in step. What follows is
Claude-specific and has no meaning for the other agent.

## The second opinion

Codex is available in this repository as a reviewer. It is a different model
family, and it did not write the code it is reading — which is the entire
point. A reviewer that shares the author's reasoning inherits the author's
blind spots.

Run `/codex-review` after a change of any consequence, before proposing a
commit. It reviews the working tree against `AGENTS.md`'s invariants and
returns structured findings.

Treat what comes back as evidence, not as a verdict:

- A finding that names a broken invariant is almost always right. Fix it.
- A finding about style or preference is almost always noise here. Say so and
  move on rather than complying to be agreeable.
- When you disagree with a finding, say why in your own words. Do not silently
  ignore it and do not silently obey it.

Two agents reviewing each other is two bills. Use it where a mistake would be
expensive to discover later — a change to the core, a contract, a migration, a
submodule pointer — and not on a typo in a comment.

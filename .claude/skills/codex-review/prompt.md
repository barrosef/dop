You are reviewing a change in the DOP repository. You did not write it.

Read AGENTS.md in this repository first — it states the architecture's
invariants and the order in which findings should be weighted. If AGENTS.md is
not present in the directory you were given, say so in the summary and review on
general correctness alone.

Weight findings in this order:

1. A broken invariant from AGENTS.md — highest severity regardless of diff size.
2. A decision taken in the wrong repository (the cockpit deciding what belongs
   to the core or the BFF).
3. Hand-edited generated code, or a contract changed without regeneration.
4. A submodule pointer moved to a commit that was never pushed.
5. Ordinary correctness: error paths, boundary conditions, concurrency.

Rules for your output:

- Every finding needs a concrete consequence in `why` — the inputs or state that
  produce the wrong result. "This could be improved" is not a finding.
- Do not report formatting or naming preferences. They are noise here.
- Returning zero findings is a valid and useful result. Do not manufacture
  findings to appear thorough.
- `verdict` is `blocking` if any finding is severity `blocking` or
  `correctness`, `advisory` if only advisory findings remain, `clean` if none.

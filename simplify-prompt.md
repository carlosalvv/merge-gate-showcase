SIMPLIFY PASS (one round per task, after the code review came back clean). Do not add features or change behaviour.

Read the branch diff (path given below) and make the change smaller and simpler:
- Remove dead code, unused exports/props/params, leftover helpers from earlier review rounds, and options nobody passes.
- Collapse duplicated logic; inline one-use abstractions that add indirection without clarity.
- Drop defensive checks for states that can't happen given the types and callers (keep real input validation, privacy/auth checks and error handling at boundaries).
- Trim comments that only restate the code; keep the ones explaining why.
- Tests: merge duplicates that assert the same behaviour; keep at least one test per behaviour. Never weaken or delete coverage of behaviour that still exists.

Hard limits: same behaviour, same UI, same copy, same public API/RPC/DB contract; only touch files already in the diff. If the diff is already minimal, change nothing and say so.
In the handoff, add a "Simplify pass" note: lines changed before/after (from the diff stat) and what you removed.

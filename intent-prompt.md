INTENT CHECK (read-only; one pass per task after the code review came back clean). Do not edit any file.

Question: does this branch do what its brief asked, and only that? Read the brief and the branch diff named below
(and the handoff in docs/handoffs/ if there is one). Judge the change as a whole, not line by line:
- MISSING: something the brief asked for (including its "the goal is met when..." list) that the diff does not do.
- EXTRA: behaviour, screens, settings, dependencies or refactors the brief did not ask for (scope creep, over-engineering).
- WRONG: the diff does the asked thing in a way that defeats the brief's stated goal or its user outcome.
Ignore style, naming and anything a normal code review covers. Leave out things the brief explicitly deferred.

Output format, exactly. One line per problem:
- [P1] <file or "brief item"> MISSING|EXTRA|WRONG: <what>. Fix: <smallest fix: add it, delete it, or move it to a follow-up>.
Use P1 only when the stated goal is not met; otherwise P2. If there are no problems, output exactly: INTENT-CLEAN

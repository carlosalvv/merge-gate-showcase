PLAN CHECK (read-only; runs BEFORE any code is written). Do not edit any file. You have no memory of how this plan was made: read it cold.

Read the brief named below, the mockup it links (if any), and only the code it names or that you need to judge feasibility
(AGENTS.md, DESIGN.md, PLAN.md sections it cites, the files in its allowed list). Attack the plan while it is cheap to fix:
- USER: does the plan actually deliver the user outcome / owner's pick it states (the "goal" or "get <who> to <do what>" line,
  the mockup version)? A plan can be internally consistent and still miss what the owner chose. This matters most.
- MISSING: states, data or screens the plan forgets (empty, loading, error, offline, signed-out, big text on iPhone SE,
  dark mode, first launch, 0 / 1 / many items, other users' data, an old app build talking to the new server, or the reverse).
- WRONG: a design choice that will not work with the real code or data (a query, field, RPC or component that does not exist
  or behaves differently; a fingerprint/native change in a task meant to ship by OTA; a lock or file conflict with the allowed list).
- CONFLICT: the plan contradicts itself, AGENTS.md hard rules, DESIGN.md, or a saved owner decision it cites.
- VAGUE: a "done when" item nobody could check pass/fail.
Do not suggest extra features or polish. Do not restate the plan. Cite file:line for every code claim.

Output format, exactly. One line per problem:
- [P1] USER|MISSING|WRONG|CONFLICT|VAGUE: <what is wrong, with evidence>. Fix: <smallest change to the brief>.
Use P1 when building as written would miss the user outcome, break a rule, or need a redo; otherwise P2.
If there are no problems, output exactly: PLAN-CLEAN

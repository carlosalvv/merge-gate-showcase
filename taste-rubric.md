# Dayscent taste rubric (UI review of screenshots)

Used by `taste.sh` to judge every UI PR's simulator screenshots before the owner sees them.
Sources: DESIGN.md §0 (simplicity), §2.2 (colour use), §7 (components), the dayscent-brand skill,
and owner feedback (memory: visual-qa-before-ready, design-laws, and the 2026-10-12 Reactions sheet:
"this looks really busy"). Owner bar: **"must look clean."**

Score each item PASS / FAIL / N/A. Every FAIL is tagged with a tier (two tiers, from Hallmark; owner-approved 2026-11-09):

- **FLOOR** = never ships. Any FLOOR fail sends the PR back to Codex, no exceptions:
  clipping or truncation that hides meaningful text; overlap; horizontal scroll; visible text under 13pt;
  unreadable contrast (below about 4.5:1) in light OR dark; a broken first frame (pop-in, layout jump, blank or
  half-drawn screen); tap targets under 44pt. Items marked **[FLOOR]** below are always FLOOR. A fail of a
  **[mixed]** item is FLOOR when it is one of these problems, else REFLEX.
- **REFLEX** = style and taste (items marked **[REFLEX]**, and the non-floor part of **[mixed]** items). A REFLEX
  fail also goes back to Codex, unless the task handoff has a `## Taste exceptions` section with a line for that
  item: `- #<item>: <one-line reason>` (at least 3 words). Then `taste.sh` moves it to `accepted` and `qagate.sh`
  lists it so the owner sees every accepted exception with the screenshots.
- Always report every fail you see, including ones the handoff lists under Taste exceptions: the script, not the
  judge, applies the exceptions. Taste exceptions are the builder's claim, NOT owner decisions.
- Not sure which tier? Use FLOOR.

## A. Calm (the owner's top complaint)
1. **[REFLEX]** **One idea per screen/sheet.** A first-time user can say what it's for and what to tap next in ~2 seconds (DESIGN §0.1).
2. **[REFLEX]** **No repeated information.** The same fact (a count, a name, a status) is shown once, not as header + summary row + filtered row + list (the Reactions sheet failure).
3. **[REFLEX]** **No data just because we have it** (§0.4). Every element on a first view helps decide or act.
4. **[REFLEX]** **Few choices** (§0.8): one primary action; pickers ≤ 4 options unless DESIGN.md lists the exception.
5. **[REFLEX]** **Nothing competes for attention:** one filled teal (primary) action at most (§0.2, §2.2); brand teal only for state/outlines; vanilla brandSoft only for yours/chosen.

## B. Layout and spacing
6. **[REFLEX]** **Even rhythm:** spacing comes from the 4pt scale and is consistent between siblings; no gaps that look accidental (too big or too tight), no empty bands inside cards or sheets.
7. **[REFLEX]** **Aligned edges:** left edges and baselines line up; nothing floats off-grid.
8. **[FLOOR]** **Fits the iPhone SE (375pt):** no clipping, no truncated labels that hide meaning, **no horizontal scrolling anywhere**; rows wrap cleanly.
9. **[FLOOR]** **No overlap:** controls, stickers, text and safe areas (home indicator, grabber, tab bar) don't collide; last row doesn't hug a rounded bottom.
10. **[FLOOR]** **Stable:** no pop-in, no content jumping between frames when data loads (compare first-frame and settled screenshots when given).

## C. Components and colour
11. **[REFLEX]** **Matches DESIGN.md §7 specs** for the component type (chips, sheets, cards, buttons, segmented controls, avatars, emoji/stickers).
12. **[REFLEX]** **Cards/sheets:** white cards on grey floor in light, surface cards in dark, radius 16–20, no borders (§0.5, §2.2).
13. **[mixed]** **Both themes read well:** contrast is fine in light AND dark; nothing disappears or glares in dark.
14. **[FLOOR]** **Comfortable sizes:** visible text ≥ 13pt; touch targets look ≥ 44pt (§0.7).
14b. **[REFLEX]** **Smooth edges (owner 2026-10-12: "no rough edges"):** outlines, sticker rims, rounded corners and icons are smooth and anti-aliased when zoomed (look closely at sticker rims: no bumps, scallops, jaggies or squared corners).

## D. Brand and copy
15. **[REFLEX]** **Voice:** plain, warm, short; no jargon or system-speak; numbers and units read naturally; no duplicated words (e.g. name + concentration twice).
16. **[REFLEX]** **Recognisable controls:** icons whose meaning isn't obvious have a text label (§0.6).

## E. Premium polish (owner, 2026-10-14)
17. **[REFLEX]** **Icon consistency:** icons in one row/bar/list match in optical size AND stroke weight (not just box size); same family (SF Symbols vs custom) within a group; selected states consistent.
18. **[mixed]** **Quiet text contrast:** secondary/caption text stays easy to read against the real background (incl. glass/transparency); primary and secondary still clearly different.
19. **[REFLEX]** **Corner radius:** same element type → same radius; nested shapes match their container (inner radius ≈ outer − padding); intentional pills excepted. Also: a photo or tile inside a rounded container is clipped to it (no square corners poking out of a rounded tile/card); a sheet docked to the screen bottom rounds only its top corners; a selection/focus ring drawn outside an element uses outer = inner + gap (never the inner radius); radius follows size (small 4–8, medium 12, cards 20, pills only for one-line controls).
20. **[REFLEX]** **Shadows:** depth only where something sits on top of something else; no heavy shadows or glows except owner-approved ones (e.g. the ember streak pill).
21. **[mixed]** **Line spacing:** multi-line text has comfortable line height; fix spacing before enlarging containers; nothing clips at large text.
22. **[REFLEX]** **Type hierarchy:** the main value/title is clearly bigger than its supporting text; details small but readable.
23. **[REFLEX]** **Alignment:** titles/labels share one leading edge; numbers share one trailing column; no ragged edges within a list or card.
24. **[FLOOR]** **Long text:** test the longest real names/brands/amounts on SE width; wrap or truncate deliberately, never collide or overflow.
25. **[REFLEX]** **Buttons:** the label names the action ("Add 3 bottles", "Wear this" — never "Submit"/"OK"/"Continue" when a verb fits); while loading the button keeps its width and height, shows progress in place and ignores a second tap; a disabled button says why nearby ("Pick a bottle first"), never a silent grey button; cancel/secondary actions are visually quieter than the one primary. For actions that write (wear, add, post, buy, invite): the handler itself refuses a second call while one is in flight (a ref or lock, not only `disabled`), the button re-enables only when the real request settles (never on a timer), errors snap back with the reason on or beside the button, and the server call is safe to repeat (idempotent RPC or a client request id).
26. **[REFLEX]** **Success states:** say exactly what happened ("Bleu de Chanel logged for today", not just "Done"); offer the next useful action, never a dead-end check; the dismissal matches the stakes (small things: a brief inline note; purchases/trials: a screen that stays with the receipt details); big celebration only for rare moments (first wear, milestones), small calm confirmation for routine ones.
27. **[REFLEX]** **Choice controls match behaviour:** a switch acts instantly (never behind a Save button); checkboxes/selections that wait for Save are not switches; 2–4 exclusive always-visible options = segmented control; up to ~5 = visible list/radio rows; more = a picker/sheet; the label and whole row toggle the control (44pt row, not just the small box); a parent of mixed children shows a mixed state.
28. **[REFLEX]** **Avatars never break:** photo first; on a missing or failed photo show the name initial (DESIGN §7.9: one initial), then a person symbol. Never a blank or broken square, and never a flash of an empty circle. Online or status shows on the avatar ring, never as a second badge. Use only the app's avatar sizes, with no new one-off sizes. Stacked groups cap the row and show "+N".

## Owner decisions win
Anything DESIGN.md or the task handoff records as an owner decision (e.g. "owner, 2026-10-12", "owner chose option B")
is a requirement, not a defect: never FAIL it. If you think one hurts the screen, say so in `notes` only.
Judge how well the screen executes those decisions (spacing, clutter, clipping, consistency), not whether you'd
have decided differently. Check DESIGN.md before failing a behaviour, not just a look.

## Output
For each FAIL: item number, tier (FLOOR or REFLEX), screen/screenshot, what's wrong in one sentence, and a concrete fix
(e.g. "remove the per-emoji count row; the list already shows each emoji"). Don't fail on taste
alone without naming the rule. Don't invent requirements beyond this rubric and DESIGN.md.

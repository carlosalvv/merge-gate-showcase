#!/bin/zsh
# usage: prgate.sh T  -- for a branch whose fixes are already pushed: wait for CI + the Codex bot on
# the current head; if review threads are open, start a loop round with them, else report READY.
source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
t=$1; d=$(wt $t); cd $d || exit 1; pr=$(pr_of); [ -z "$pr" ] && { echo "== $t no open PR"; exit 1; }
nt=$(zsh $L/prwait.sh $t $pr)
if [ "${nt:-0}" -gt 0 ]; then
  cut -f1 $G/$t-threads.txt > $G/$t-thread-ids.txt
  { cat $Q/$t.base; echo; echo "Open PR #$pr review threads (Codex bot / Greptile) to fix now. Fix each one that is valid; if one is wrong, explain why in the handoff instead (add a regression test for each that fails before the fix; update the handoff):"; cut -f2- $G/$t-threads.txt | sed 's/\t/ | /g'; } > $Q/$t.txt
  echo "== $t PR #$pr: $nt open thread(s), starting a fix loop"; exec zsh $L/qloop.sh $t
fi
# 2026-10-14: CI is now the full-suite gate, so READY needs every check green, not just finished.
bad=$(gh pr view $pr --json statusCheckRollup -q '[.statusCheckRollup[] | select((.conclusion // .state) as $c | ($c != "SUCCESS" and $c != "SKIPPED" and $c != "NEUTRAL"))] | map(.name // .context) | join(", ")' 2>/dev/null)
[ -n "$bad" ] && { echo "== $t PR #$pr NOT READY: CI checks not green: $bad"
  # 2026-10-18 flake protocol (docs/WORKFLOW.md, brain lessons/test-flakes): never rerun CI until green.
  echo "   Unexpected test failure? Rerun it ALONE 3x on base (origin/main) and on the tip: fails on both = flake note in the handoff + the repo's docs/PITFALLS.md if it exists, else brain lessons/test-flakes.md, not this PR's bug; fails only on the tip = blocking regression."; exit 1; }
ui=$(git diff --name-only origin/main...HEAD | grep -vE '/__tests__/' | grep -cE '^src/(app|features|components)/.*\.tsx$')
tam=$(git diff origin/main...HEAD | tamper_state $t)
echo "== $t READY (PR #$pr: CI done, Codex bot on head, 0 open threads)$([ ${ui:-0} -gt 0 ] && echo ' NEEDS-VISUAL-QA')$([ -s $G/$t-outdated.txt ] && echo " OUTDATED-THREADS=$(wc -l < $G/$t-outdated.txt | tr -d ' ') (Lead must verify)")${tam:+ TEST-TAMPER=$tam (Lead: tamperok.sh $t)}"
# 2026-11-09: the merge danger card (Door computed from the diff) goes into the PR body and the READY message.
zsh $L/dangercard.sh $t 2>/dev/null | sed 's/^/   /'

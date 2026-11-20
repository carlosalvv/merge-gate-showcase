#!/bin/zsh
# usage: qagate.sh T  -- after the sim-qa agent wrote logs/<T>-qa.json (functional verdict + screenshots
# in $QA_DIR/<T>/), run the taste judge, then either report QA-PASS for the current head
# or feed every problem back to Codex as the next round, so the owner only sees PRs with clean code AND
# clean screens. If a loop is already running for T, the QA round is queued and starts when it stops.
source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
t=$1; d=$(wt $t); head=$(cd $d && git rev-parse HEAD)
running() { ps -axo command= | grep -qE "^zsh [^ ]*/(qloop|prgate)\.sh $t( |\$)"; }
[ -f $G/$t-qa.json ] || { echo "== $t QA-GATE: no logs/$t-qa.json yet"; exit 2; }
qsha=$(python3 -c "import json;print(json.load(open('$G/$t-qa.json')).get('sha',''))")
[[ $head == $qsha* && -n $qsha ]] || { echo "== $t QA-GATE: QA was on ${qsha:-?}, head is ${head[1,8]}; rerun QA"; exit 2; }
# 2026-10-18 independent QA: tasks started since then record their builder (q/<T>.builder, from newtask.sh);
# the verdict's qa_by must name a different agent, so no builder grades its own screens.
if [ -s $Q/$t.builder ]; then
  qby=$(python3 -c "import json;print(json.load(open('$G/$t-qa.json')).get('qa_by',''))"); b=$(<$Q/$t.builder)
  [ -z "$qby" ] && { echo "== $t QA-GATE: verdict has no qa_by; rerun QA with the sim-qa agent"; exit 2; }
  [[ ${qby:l} == ${b:l} ]] && { echo "== $t QA-GATE: QA by '$qby', who also built $t; an independent agent must rerun QA"; exit 2; }
fi
zsh $L/taste.sh $t; tr=$?
[ $tr -eq 2 ] && { echo "== $t QA-GATE: taste judge couldn't run; Lead reviews screenshots by hand"; exit 2; }
python3 - $G/$t-qa.json $G/$t-taste.json $G/$t-qaissues.txt $G/$t-tasteexceptions.txt <<'PY'
import json,sys
qa=json.load(open(sys.argv[1])); ta=json.load(open(sys.argv[2])); out=[]
for i in qa.get('issues',[]):
    if i.get('severity','P2') in ('P0','P1','P2'):
        out.append(f"- [QA {i.get('severity','P2')}] {i.get('problem')} (screenshot: {i.get('screenshot','')}) Fix: {i.get('fix','')}")
for f in ta.get('fails',[]):
    out.append(f"- [Taste rubric #{f.get('item')} {f.get('tier','FLOOR')}] {f.get('problem')} (screenshot: {f.get('screenshot','')}) Fix: {f.get('fix','')}")
open(sys.argv[3],'w').write("\n".join(out))
# REFLEX fails the handoff's '## Taste exceptions' accepted (taste.sh): listed so the owner sees each one.
open(sys.argv[4],'w').write("\n".join(f"- #{a.get('item')} {a.get('problem')} (screenshot: {a.get('screenshot','')}) Builder's reason: {a.get('exception','')}" for a in ta.get('accepted',[])))
PY
[ -s $G/$t-tasteexceptions.txt ] && { echo "== $t accepted taste exceptions (REFLEX only; show these to the owner with the screenshots):"; cat $G/$t-tasteexceptions.txt; echo; }
if [ ! -s $G/$t-qaissues.txt ] && [ "$(python3 -c "import json;print(json.load(open('$G/$t-qa.json'))['verdict'])")" = PASS ]; then
  echo "== $t QA-PASS on ${head[1,8]} (simulator + taste). Lead: look at the screenshots, then ask the owner."; exit 0
fi
{ cat $Q/$t.base; echo
  echo "Simulator QA (iPhone SE) and the taste review found these problems on ${head[1,8]}. Fix each one; screenshots are in $QA_DIR/$t/ (open them to see the problem). Taste items refer to $L/taste-rubric.md; FLOOR items must be fixed. A REFLEX item you believe is a deliberate, better choice may instead get a line under '## Taste exceptions' in the handoff: '- #<item>: <one-line reason>' (the owner sees every accepted exception). Add a test where the problem is testable; update the handoff:"
  cat $G/$t-qaissues.txt; } > $Q/$t.qa
mv $G/$t-qa.json $G/$t-qa.${head[1,8]}.json   # the next head needs a fresh QA run
n=$(grep -c '^- ' $G/$t-qaissues.txt)
# Lead-owned tasks (a Claude builder or the Lead is fixing them): never auto-restart Codex. Opt in with `touch q/<task>.lead`.
if [ -n "$QA_NO_RESTART" ] || [ -e $Q/$t.lead ]; then
  echo "== $t QA-FAIL: $n problem(s) in $Q/$t.qa (Lead-owned task: no Codex restart)"
  exit 1
fi
if running; then
  # Never run two loops in one worktree: start this round once the running loop (e.g. PR threads) stops.
  ( while running; do sleep 30; done; mv $Q/$t.qa $Q/$t.txt && zsh $L/start.sh $t 4 ) >/dev/null 2>&1 < /dev/null &!
  echo "== $t QA-FAIL: $n problem(s) queued; they go to Codex automatically when the running loop stops"
else
  mv $Q/$t.qa $Q/$t.txt; zsh $L/start.sh $t 4 >/dev/null
  echo "== $t QA-FAIL: $n problem(s) fed back to Codex; loop restarted"
fi

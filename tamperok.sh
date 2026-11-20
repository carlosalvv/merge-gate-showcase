#!/bin/zsh
# usage: tamperok.sh T|PR# "reason"   -- Lead only. Shows the test tamper findings on T's branch; with a reason,
# records an approval of exactly these findings (logs/T-tamper-ok.json, outside every Codex sandbox).
# A later commit that adds a NEW weakened/removed/skipped test changes the hash and needs a new approval.
# Approve only after reading each change and confirming the old test was genuinely wrong (AGENTS.md Hard rules: Tests).
source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
# A PR number instead of T (branches with no task id, e.g. hotfix/ota-*): key pr<N>, diff from GitHub.
if [[ $1 == <-> ]]; then t=pr$1; diff=$(gh pr diff $1 --repo $GH_OWNER/Dayscent) || exit 1
else t=$1; d=$(wt $t); cd $d || exit 1; git fetch -q origin main; diff=$(git diff origin/main...HEAD); fi; f=$(print -r -- "$diff" | python3 -I $L/tamper.py)
[ -z "$f" ] && { echo "== $t no test tamper findings"; exit 0; }
echo "== $t test tamper findings:"; print -r -- "$f" | sed 's/^/  /'
[ -z "$2" ] && { echo "Not approved. Read each one; if the old test was truly wrong: tamperok.sh $t \"why\""; exit 1; }
h=$(print -r -- "$diff" | python3 -I $L/tamper.py --hash)
jq -n --arg h "$h" --arg r "$2" --arg s "$(git rev-parse HEAD 2>/dev/null)" --arg d "$(date +%F)" '{hash:$h,reason:$r,sha:$s,date:$d,by:"Lead"}' > $G/$t-tamper-ok.json
echo "approved ($h) -> logs/$t-tamper-ok.json"

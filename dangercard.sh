#!/bin/zsh
# usage: dangercard.sh T [handoff-name]  -- prints the 4-line "merge danger" card for task T's branch (read-only).
# 2026-11-09 (brain toolkit/trending-repos-2026-11.md top 5 #1): every ready PR body and every READY message to the
# owner carries this card, so he sees in 5 seconds how hard a merge/deploy is to undo. The Door is computed from the
# diff (lib.sh door_of), never typed by hand; mergecheck.sh FAILs a Dayscent PR whose body says two-way when the
# diff is one-way. Paste the output into the PR body (gh pr edit N --body-file) and fill the <...> parts.
source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
t=$1; h=${2:-${t%[a-z]}}; d=$(wt $t); cd $d 2>/dev/null || { echo "no worktree $d"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "$d is not a git worktree"; exit 1; }
diff=$(git diff -M origin/main...HEAD 2>/dev/null) || { echo "could not diff $t against origin/main"; exit 1; }
door=$(print -r -- "$diff" | door_of)
files=$(git diff --name-only origin/main...HEAD)
areas=$(print -r -- "$files" | grep -vE '(/__tests__/|\.test\.[jt]sx?$|^docs/)' \
  | sed -E 's#^src/(features|app|components|lib)/([^/.]+).*#\1/\2#; s#^supabase/(migrations|functions|tests)/([^/.]+).*#supabase/\1/\2#' \
  | sort -u | head -6 | tr '\n' ',' | sed 's/,$//; s/,/, /g')
nt=$(print -r -- "$files" | grep -cE '(/__tests__/|\.test\.[jt]sx?$|^supabase/tests/)')
qa=$QA_DIR/$t; qv=$(jq -r '"\(.verdict) on \(.sha[0:8])"' $G/$t-qa.json 2>/dev/null)
ho=docs/handoffs/$h.md
nc=$(awk '/^## What is NOT claimed/{f=1;next} /^## /{f=0} f && /[^[:space:]]/' $ho 2>/dev/null | head -2 | sed -E 's/^[-*] *//' | tr '\n' ' ' | cut -c1-200)
echo "**Door:** ${door%% *} (${door#* })"
echo "**Blast radius:** <who is affected: all users / signed-in users / one screen / nobody until deploy> (touches: ${areas:-nothing outside tests/docs})"
echo "**Proof:** $nt test file(s) changed; QA: $([ -d $qa ] && echo "${qv:-screenshots} at $QA_DIR/$t/" || echo "none (no UI QA run)")"
echo "**What is NOT claimed:** ${nc:-<see $ho ## What is NOT claimed>}"

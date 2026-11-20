#!/bin/zsh
# Unresolved but outdated threads go to logs/<T>-outdated.txt (not fed to Codex; the Lead checks them before "ready").
# usage (from the task worktree): prwait.sh T PR
# Item 2: after a push, wait for CI and the Codex bot on the CURRENT head, then write the PR's
# unresolved, non-outdated review threads to logs/<T>-threads.txt as "id<TAB>path:line<TAB>author<TAB>body".
# Greptile reviews once per PR (owner rule): its existing threads count, but it is never re-requested.
source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
t=$1; pr=$2; repo=$(repo_of); owner=${repo%/*}; name=${repo#*/}
head=$(git rev-parse HEAD); start=$(date +%s); max=${PRWAIT_MAX:-1800}   # 30 min cap
[ "$max" -gt 0 ] && { sleep 20; codex_request $repo $pr $head >/dev/null; }   # pushes never trigger the bot
while [ "$max" -gt 0 ]; do
  st=$(gh api graphql -f query="{repository(owner:\"$owner\",name:\"$name\"){pullRequest(number:$pr){headRefOid commits(last:1){nodes{commit{statusCheckRollup{contexts(first:40){nodes{... on CheckRun{status} ... on StatusContext{state}}}}}}}}}}" 2>/dev/null)
  pending=$(echo "$st" | jq '[.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]? | select((.status? and .status!="COMPLETED") or .state=="PENDING")] | length' 2>/dev/null)
  ghead=$(echo "$st" | jq -r '.data.repository.pullRequest.headRefOid' 2>/dev/null)
  codex=$(codex_state $repo $pr $head); [ "$codex" = none ] && [ $(( $(date +%s) - start )) -ge 300 ] && codex_request $repo $pr $head >/dev/null
  el=$(( $(date +%s) - start ))
  # Done when GitHub has the head, nothing is pending, and the Codex bot finished reviewing this head.
  total=$(echo "$st" | jq '[.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?] | length' 2>/dev/null)
  # 2026-10-12: "0 pending" with 0 checks is NOT done (CI never ran on #417's head); require at least one check.
  [ "$ghead" = "$head" ] && [ "${total:-0}" -gt 0 ] && [ "${pending:-1}" = 0 ] && [ "$codex" = done ] && break
  # 2026-10-12 speed-up: once the bot has reviewed this head and left open threads, the next round will
  # make a new head anyway, so don't wait ~7 more min for CI on this one. READY still needs CI green.
  if [ "$codex" = done ] && [ "$ghead" = "$head" ]; then
    open=$(gh api graphql -f query="{repository(owner:\"$owner\",name:\"$name\"){pullRequest(number:$pr){reviewThreads(first:100){nodes{isResolved isOutdated}}}}}" 2>/dev/null | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select((.isResolved|not) and (.isOutdated|not))] | length' 2>/dev/null)
    [ "${open:-0}" -gt 0 ] && { echo "prwait: bot done with $open open thread(s); not waiting for CI" >&2; break; }
  fi
  # 2026-10-12: GitHub never runs CI on a PR that conflicts with main; don't wait 30 min for it.
  if [ "$(gh pr view $pr --repo $repo --json mergeable -q .mergeable 2>/dev/null)" = CONFLICTING ] && [ "$codex" = done ]; then
    echo "prwait: PR conflicts with main; CI will not run until main is merged" >&2; echo CONFLICTING > $G/$t-conflicting; break
  fi
  rm -f $G/$t-conflicting
  [ $el -ge $max ] && { echo "prwait: timed out after ${el}s (pending=$pending codex=$codex)" >&2; echo TIMEOUT > $G/$t-prwait-timeout; break; }
  sleep 30
done
gh api graphql -f query="{repository(owner:\"$owner\",name:\"$name\"){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:1){nodes{author{login} body}}}}}}}" \
  | jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | select((.isResolved|not) and (.isOutdated|not))
      | [.id, "\(.path):\(.line)", .comments.nodes[0].author.login,
         (.comments.nodes[0].body | gsub("<[^>]+>";"") | gsub("\n";" ") | sub("Prompt To Fix With AI.*";""))] | @tsv' > $G/$t-threads.txt
gh api graphql -f query="{repository(owner:\"$owner\",name:\"$name\"){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved isOutdated path comments(first:1){nodes{author{login}}}}}}}}" \
  | jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | select((.isResolved|not) and .isOutdated) | "\(.id)\t\(.path)\t\(.comments.nodes[0].author.login)"' > $G/$t-outdated.txt
wc -l < $G/$t-threads.txt | tr -d ' '

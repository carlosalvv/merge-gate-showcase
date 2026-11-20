#!/bin/zsh
# usage: mergecheck.sh <repo> <pr>   e.g. mergecheck.sh dayscent-website 23
# Owner rule 2026-10-15: every PR in every repo (docs, website, starter, legal) is checked before merge.
# Prints OK only if: no conflicts, every CI check SUCCESS/SKIPPED/NEUTRAL, at least one check ran,
# 0 unresolved review threads, the Codex bot has reviewed the current head (no pending review),
# and (Dayscent, app-starter) Greptile has posted its summary.
# 2026-10-23: a security-sensitive Dayscent PR also needs logs/<T>-sec.json verdict PASS on the head (secgate.sh T).
# 2026-11-09: a Dayscent PR body needs the merge danger card (dangercard.sh T), and its Door must match the diff.
r=$1; n=$2; [ -z "$n" ] && { echo "usage: mergecheck.sh <repo> <pr>"; exit 2; }
R=$GH_OWNER/$r; fail=0
j=$(gh pr view $n --repo $R --json headRefOid,headRefName,mergeable,statusCheckRollup,state) || exit 1
head=$(printf "%s" "$j" | jq -r .headRefOid); echo "== $R#$n head ${head[1,8]}"
[ "$(printf "%s" "$j" | jq -r .state)" != OPEN ] && { echo "not open"; exit 1; }
# 2026-11-09 (T-785): a branch migration with the SAME 14-digit timestamp as a different file on main merges
# without a git conflict but breaks db push ordering. Fail on any timestamp clash.
if [ "$r" = Dayscent ]; then
  bm=$(gh pr view $n --repo $R --json files --jq '.files[].path|select(startswith("supabase/migrations/"))' | xargs -n1 basename 2>/dev/null)
  if [ -n "$bm" ]; then mm=$(gh api "repos/$R/contents/supabase/migrations?ref=main" --jq '.[].name' 2>/dev/null)
    for f in ${(f)bm}; do ts=${f[1,14]}; c=$(printf "%s\n" "$mm" | grep "^$ts" | grep -vx "$f"); [ -n "$c" ] && { echo "FAIL migration timestamp clash: $f vs main's $c (rename to a later timestamp)"; fail=1; }; done; fi
fi
[ "$(printf "%s" "$j" | jq -r .mergeable)" = CONFLICTING ] && { echo "FAIL conflicts with main"; fail=1; }
total=$(printf "%s" "$j" | jq '.statusCheckRollup|length')
bad=$(printf "%s" "$j" | jq -r '[.statusCheckRollup[]|select((.conclusion // .state) as $c|($c!="SUCCESS" and $c!="SKIPPED" and $c!="NEUTRAL"))|"\(.name // .context)=\(.conclusion // .state // "PENDING")"]|join(", ")')
[ "$total" = 0 ] && { echo "FAIL no CI checks ran"; fail=1; }
[ -n "$bad" ] && { echo "FAIL checks: $bad"; fail=1; }
open=$(gh api graphql -f query="query{repository(owner:\"$GH_OWNER\",name:\"$r\"){pullRequest(number:$n){reviewThreads(first:100){nodes{isResolved path comments(first:1){nodes{author{login} body}}}}}}}" --jq '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)]')
cnt=$(printf "%s" "$open" | jq length)
[ "$cnt" != 0 ] && { echo "FAIL $cnt open review thread(s):"; printf "%s" "$open" | jq -r '.[]|"  - \(.path) [\(.comments.nodes[0].author.login)]: \(.comments.nodes[0].body|gsub("<[^>]*>";"")|gsub("\n";" ")|.[0:160])"'; fail=1; }
cx=$(gh api repos/$R/pulls/$n/reviews --jq "[.[]|select(.user.login|test(\"codex\";\"i\"))|select(.commit_id==\"$head\")]|length")
# A clean comment or +1 only counts when newer than the head commit. 2026-10-19: #554 merged on a clean
# comment about an older commit, 14s before the bot posted a P1 on the head.
hdate=$(gh api repos/$R/commits/$head --jq .commit.committer.date)
cxc=$(gh api repos/$R/issues/$n/comments --jq "[.[]|select(.user.login|test(\"codex\";\"i\"))|select(.body|test(\"Didn.t find any major issues|no major issues\";\"i\"))|select(.created_at > \"$hdate\")]|length")
# The bot now signals "no findings" with a +1 reaction on the PR (2026-10-18).
cxr=$(gh api repos/$R/issues/$n/reactions --jq "[.[]|select(.user.login|test(\"codex\";\"i\"))|select(.content==\"+1\")|select(.created_at > \"$hdate\")]|length")
[ "${cx:-0}" = 0 ] && [ "${cxc:-0}" = 0 ] && [ "${cxr:-0}" = 0 ] && { echo "WAIT Codex bot has not reviewed head ${head[1,8]} (comment @codex review)"; fail=1; }
# 2026-10-31 (ledger L-004): #601 merged 3 min before Greptile posted 2 valid findings. In repos with Greptile,
# wait for its summary comment (it reviews once per PR). GREPTILE_SKIP=1 only if Greptile is down (say so to the owner).
if [[ " dayscent app-starter " == *" ${r:l} "* && -z $GREPTILE_SKIP ]]; then
  gc=$(gh api repos/$R/issues/$n/comments --paginate --jq '[.[]|select(.user.login|test("greptile";"i"))|select(.body|test("greptile_summary"))]|length')
  [ "${gc:-0}" = 0 ] && { echo "WAIT Greptile has not posted its review yet"; fail=1; }
fi
# Security gate (owner OK 2026-10-23): migrations, Edge Functions, auth, premium, src/lib/supabase*, package/app/eas
# config or RLS/grant/policy text => the adversarial gate must have passed on exactly this head.
if [[ ${r:l} == dayscent ]]; then
  source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
  pd=$(gh pr diff $n --repo $R 2>/dev/null) || { nodiff=1; echo "WARN could not read the PR diff; security trigger checks file paths only"
    pd=$(gh pr view $n --repo $R --json files -q '.files[].path' | sed 's#.*#diff --git a/& b/&#'); }
  sens=$(print -r -- "$pd" | sec_sensitive)
  echo "risk tier: $(print -r -- "$pd" | risk_tier)"
  # 2026-11-09 merge danger card (dangercard.sh): the PR body needs Door / Blast radius / Proof / What is NOT claimed,
  # and its Door may not say two-way when the diff is one-way (door_of: migrations/functions/heavy, unless the handoff
  # adds "Reversible: <how>"). Saying one-way for a two-way diff is only a WARN (over-cautious is safe).
  door=$(print -r -- "$pd" | door_of); echo "door: $door"
  body=$(gh pr view $n --repo $R --json body -q .body 2>/dev/null)
  miss=(); for k in 'door' 'blast radius' 'proof' 'what is not claimed'; do
    print -r -- "$body" | grep -qiE "^[-*#>[:space:]]*(\*\*)?$k" || miss+=("$k"); done
  bd=$(print -r -- "$body" | grep -iE '^[-*#>[:space:]]*(\*\*)?door' | head -1 | grep -oiE 'one-way|two-way' | head -1 | tr A-Z a-z)
  if (( ${#miss} )); then echo "FAIL PR body lacks the merge danger card line(s): ${(j:, :)miss} (dangercard.sh <T>, paste into the body)"; fail=1
  elif [ -z "$bd" ]; then echo "FAIL PR body's Door line says neither one-way nor two-way (diff says ${door%% *})"; fail=1
  elif [ "$bd" != "${door%% *}" ]; then
    if [ "$bd" = two-way ]; then echo "FAIL PR body says Door: two-way but the diff is one-way (${door#* }); fix the body, or add 'Reversible: <how>' to the handoff"; fail=1
    else echo "WARN PR body says Door: one-way, the diff looks two-way (${door#* }); fine if the Lead knows why"; fi
  else echo "door card OK (${door%% *})"; fi
  # 2026-10-31: migrations/pgTAP need dbtest.sh (npm run db:test) to have passed on exactly this head; CI skips pgTAP.
  if print -r -- "$pd" | grep -qE '^diff --git a/.* b/supabase/(migrations|tests)/'; then
    dtid=$(printf "%s" "$j" | jq -r .headRefName | grep -oE 'T-[0-9]+[a-z]?' | head -1); dsha=$(cat $G/$dtid-dbtest 2>/dev/null)
    if [ -z "$dtid" ]; then echo "FAIL changes migrations/SQL tests but no task id in the branch name; run npm run db:test by hand"; fail=1
    elif [[ -z $dsha || $head != $dsha* ]]; then echo "FAIL changes migrations/SQL tests: db:test has not passed on ${head[1,8]}; run dbtest.sh $dtid"; fail=1
    else echo "db:test PASS on ${head[1,8]}"; fi
  fi
  # 2026-11-12 test tamper alarm (tamper.py): weakened/removed/skipped existing tests need tamperok.sh on these findings.
  ttid=$(printf "%s" "$j" | jq -r .headRefName | grep -oE 'T-[0-9]+[a-z]?' | head -1)
  tam=$(print -r -- "$pd" | tamper_state ${ttid:-pr$n})
  if [ -n "$nodiff" ]; then echo "FAIL test tamper: could not read the PR diff to check tests"; fail=1
  elif [ -n "$tam" ]; then echo "FAIL test tamper: $tam in existing tests (Lead reads them: tamperok.sh ${ttid:-$n})"; print -r -- "$pd" | python3 -I $L/tamper.py | head -8 | sed 's/^/  /'; fail=1
  else echo "test tamper: none or approved"; fi
  if [ -n "$sens" ]; then
    tid=$(printf "%s" "$j" | jq -r .headRefName | grep -oE 'T-[0-9]+[a-z]?' | head -1); sf=$G/$tid-sec.json
    why1=$(print -r -- "$sens" | head -1)
    if [ -z "$tid" ]; then echo "FAIL security-sensitive PR ($why1) but no task id in the branch name; run secgate.sh on its worktree"; fail=1
    elif [ ! -f $sf ]; then echo "FAIL security-sensitive PR ($why1): no logs/$tid-sec.json; run secgate.sh $tid"; fail=1
    else
      ssha=$(jq -r .sha $sf); sv=$(jq -r .verdict $sf)
      if [[ $head != $ssha* || -z $ssha ]]; then echo "FAIL security gate ran on ${ssha[1,8]}, head is ${head[1,8]}; rerun secgate.sh $tid"; fail=1
      elif [ "$sv" != PASS ]; then echo "FAIL security gate $sv on head: agreed P1/P2 $(jq -r '.agreed_p1_p2|join(", ")' $sf) (logs/$tid-sec.json)"; fail=1
      else echo "security gate PASS on ${head[1,8]} (round $(jq -r .round $sf))"; fi
      jq -r '.accepted[]? | "INFO accepted risk \(.id) \(.severity) \(.file_line) (by \(.accept.lead) \(.accept.date)): \(.accept.reason)"' $sf 2>/dev/null
      nd=$(jq '.disputed|length' $sf 2>/dev/null); [ "${nd:-0}" -gt 0 ] && echo "WARN $nd disputed security finding(s) in logs/$tid-sec.json: Lead decides before asking the owner"
    fi
  fi
fi
[ $fail = 0 ] && echo "OK ready to merge" || exit 1

#!/bin/zsh
# usage: secgate.sh T  -- adversarial security gate for a security-sensitive branch (owner-approved 2026-10-23).
#   Trigger: the diff vs origin/main touches migrations, Edge Functions, auth, premium, src/lib/supabase*,
#   package/app/eas config, or RLS/grant/policy text (lib.sh sec_sensitive). Otherwise: SEC-SKIP, exit 0.
#   Round: (1) attacker = fresh read-only `claude -p` (Opus) runs the dayscent-security-check skill on the diff;
#   (2) adversary = read-only `codex exec` marks each finding CONFIRMED, LOWERED (real pattern, lower severity;
#   a P2 is by definition not exploitable today, so "blocked by grants" lowers, it never rejects) or REJECTED,
#   with evidence, and adds misses; (3) rebuttal = Claude answers each non-confirmed item/addition once
#   (REJECTED: DROP | LOWER | KEEP; LOWERED: ACCEPT | KEEP; additions: AGREE | DISPUTE).
#   Consensus: CONFIRMED/AGREE keep the worse severity, except a P2-vs-P3 split on a hygiene item (G1/H4),
#   which takes the lower. LOWERED is kept at Codex's severity (disputed only if Claude KEEPs with evidence
#   across the P2/P3 line); REJECTED+LOWER is kept at the lowered severity; REJECTED+DROP is dropped;
#   REJECTED+KEEP with evidence on both sides is disputed (Lead decides). A challenge with no concrete evidence
#   is ignored; concrete = a file:line reference or a bare path to a tracked file.
#   Writes logs/T-sec.json (sha, round, verdict, findings).
#   FAIL (any agreed P1/P2): the findings become the task's next Codex round, like qagate.sh.
#   The next run after a FAIL is round N+1: it re-checks the previous findings plus the diff since that sha.
#   Carry-over (2026-10-24): after a PASS on sha X, a new head whose OWN changes since X (secdelta.py: main
#   merges excluded) are only the migration parity list and/or identical-content migration renames gets PASS
#   with carried_from X and no model calls; any other own change gets a round N+1 review limited to those files.
#   Never edits app code, never reads .env, no network/DB commands (Claude gets Read/Grep/Glob only; Codex runs
#   in the read-only sandbox, which has no network).
#   Accepted risks (2026-10-26): findings matching logs/T-sec-accepted.json (secaccept.sh, Lead-only) move to
#   "accepted" and don't block; also re-applied to a cached FAIL on an unchanged head (no model calls).
# Exit 0 = PASS or SKIP, 1 = FAIL, 2 = could not run.
# Env: SEC_PLAN_ONLY=1 print the plan (skip / carry / round + files) and stop before any model call;
#   SEC_FORCE=1 rerun even if logs/T-sec.json already has this head; SEC_NO_RESTART=1 write the fix prompt
#   (q/T.sec) but don't restart Codex; SEC_FROM_LOOP=1 (set by qloop) only write logs/T-secissues.txt;
#   SEC_MAX_CTX bytes of full-file context (default 300000); SEC_TIMEOUT seconds per model call (default 1500).
source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
t=$1; [ -z "$t" ] && { echo "usage: secgate.sh T"; exit 2; }
d=$(wt $t); cd $d 2>/dev/null || { echo "== $t SEC-ERROR: no worktree at $d"; exit 2; }
SKILL=${SEC_SKILL:?path to the security checklist}
head=$(git rev-parse HEAD); h8=${head[1,8]}; out=$G/$t-sec.json
case "$(git remote get-url origin 2>/dev/null)" in
  */Dayscent.git|*/Dayscent) ;;
  *) echo "== $t SEC-SKIP: not the Dayscent app repo"; exit 0;;
esac
[ -f $SKILL ] || { echo "== $t SEC-ERROR: checklist skill missing ($SKILL)"; exit 2; }
running() { ps -axo command= | grep -qE "^zsh [^ ]*/(qloop|prgate)\.sh $t( |\$)"; }
jget() { python3 -c "import json,sys;j=json.load(open('$out'));print(j.get('$1',''))" 2>/dev/null; }

# 1. Trigger.
MAIN=${SEC_MAIN:-origin/main}   # SEC_MAIN: test hook only (offline fixtures)
why=$(git diff -M $MAIN...HEAD | sec_sensitive)   # -M (2026-10-27): pure moves show as renames, not whole files (T-712 moved 700 docs)
[ -z "$why" ] && { echo "== $t SEC-SKIP on $h8: no security-sensitive paths or RLS/grant/policy text"; exit 0; }

# 7. Cost control: this head was already judged.
if [ -f $out ] && [[ $head == $(jget sha)* ]] && [ -z "$SEC_FORCE" ]; then
  v=$(jget verdict); note=""
  if [ "$v" = FAIL ] && [ -s $G/$t-sec-accepted.json ]; then
    na=$(python3 $L/secaccept.py apply $out $G/$t-sec-accepted.json $G/$t-secissues.txt) && v=$(jget verdict) && note="; ${na} accepted risk(s) applied"
  fi
  echo "== $t SEC-$v on $h8 (cached logs/$t-sec.json$note; SEC_FORCE=1 to rerun)"; [ "$v" = PASS ]; exit $?
fi

# Round 2+ / carry-over: compare against the last gated head X using the branch's OWN changes (secdelta.py:
# main merges excluded; a rebase is fine). After a FAIL: re-check the old findings plus the own changes since X.
# After a PASS: carry it if only the parity list / migration renames changed, else review only the changed files.
round=1; base=$MAIN; prev=""; mode=full; files=()
if [ -f $out ] && [ -z "$SEC_FORCE" ]; then
  psha=$(jget sha); pv=$(jget verdict)
  if git cat-file -e "$psha^{commit}" 2>/dev/null && delta=$(python3 $L/secdelta.py $psha $MAIN 2>/dev/null); then
    files=(${(f)"$(print -r -- "$delta" | python3 -c 'import json,sys;print("\n".join(json.load(sys.stdin)["changed"]))')"})
    carry=$(print -r -- "$delta" | python3 -c 'import json,sys;j=json.load(sys.stdin);print(", ".join(j["carry"]) or "main merge only")')
    if [ "$pv" = PASS ] && [ ${#files} -eq 0 ]; then
      [ -n "$SEC_PLAN_ONLY" ] && { echo "== $t SEC-PLAN carry PASS from ${psha[1,8]} ($carry)"; exit 0; }
      cp $out $G/$t-sec.${psha[1,8]}.json
      python3 -c 'import json,sys;j=json.load(open(sys.argv[1]));j.update(sha=sys.argv[2],carried_from=sys.argv[3],carry_reason=sys.argv[4]);json.dump(j,open(sys.argv[1],"w"),indent=1)' $out $head $psha "$carry"
      echo "== $t SEC-PASS on $h8 carried from ${psha[1,8]} (own changes since then: $carry; no model calls)"; exit 0
    fi
    if [ "$pv" = PASS ] || [ "$pv" = FAIL ]; then
      round=$(( $(jget round) + 1 )); base=$psha; mode=${pv:l}; prev=$G/$t-sec.${psha[1,8]}.json; cp $out $prev
    fi
  fi
fi
[ $mode = fail ] && [ ${#files} -eq 0 ] && { echo "== $t SEC: no branch changes since FAIL on ${base[1,8]}; nothing fixed yet"; exit 1; }
[ -n "$SEC_PLAN_ONLY" ] && { echo "== $t SEC-PLAN round $round mode=$mode base=${base[1,8]} files: ${files:-ALL}"; exit 0; }
r=r$round; pre=$G/$t-sec-$r; ctx=$pre-ctx.txt
# SEC_DIFF_ARGS (Lead only, 2026-10-27): extra diff args for a huge pure-move branch, e.g. --diff-filter=AMT ':(exclude)docs/archive/**'. Never for code deletions.
if [ $mode = full ]; then eval git -c diff.renameLimit=5000 diff -M ${SEC_DIFF_ARGS:-} $MAIN...HEAD -- . "':(exclude)package-lock.json'" ${SEC_DIFF_PATHS:-} > $pre.diff
else git diff -M $base HEAD -- $files > $pre.diff; fi
export SEC_FILES=${(F)files}

# Context: the diff, then the full current text of touched files (new files are already whole in the diff;
# generated types, lockfiles and Markdown are skipped), capped at SEC_MAX_CTX bytes.
python3 - $pre.diff $ctx ${SEC_MAX_CTX:-300000} "$base" <<'PY'
import sys,subprocess,os
diff,ctx,cap,base=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
M=os.environ.get("SEC_MAIN","origin/main"); rng=f"{base}...HEAD" if base==M else f"{base}..HEAD"
st=subprocess.run(["git","diff","--name-status",rng],capture_output=True,text=True).stdout.split("\n")
mine=set(os.environ.get("SEC_FILES","").split("\n"))-{""} or set(subprocess.run(["git","diff","--name-only",f"{M}...HEAD"],capture_output=True,text=True).stdout.split())
d=open(diff).read(); parts=[f"=== BRANCH DIFF ({rng}, lockfile excluded) ===\n{d}"]; used=len(d); skipped=[]
for line in st:
    f=line.split("\t")
    if len(f)<2 or f[0][0] not in "MR": continue
    p=f[-1]
    if p not in mine: continue
    if p.endswith((".md","database.types.ts","package-lock.json")) or "/__tests__/" in p or p.startswith("supabase/tests/"): continue
    if not os.path.isfile(p): continue
    txt=open(p,errors="replace").read()
    if used+len(txt)>cap: skipped.append(p); continue
    parts.append(f"=== FULL FILE (current head): {p} ===\n{txt}"); used+=len(txt)
if skipped: parts.append("=== NOT INLINED (size cap; Read them only if a check needs them): "+", ".join(skipped))
open(ctx,"w").write("\n\n".join(parts)); print(f"context {used} bytes, {len(parts)-1} full files, {len(skipped)} skipped",file=sys.stderr)
PY

# capped SECS IN OUT ERR cmd...: run cmd with explicit stdin/stdout/stderr, killed after SECS seconds.
capped() { local s=$1 i=$2 o=$3 e=$4; shift 4; "$@" < $i > $o 2> $e & local p=$!
  # 2026-11-02 (ledger L-008): the watchdog must not hold the caller's stdout, or a $(secgate.sh) caller (qloop)
  # blocks until the orphaned `sleep` ends (killing the subshell leaves its sleep alive).
  ( sleep $s; kill $p 2>/dev/null ) </dev/null >/dev/null 2>&1 &! local w=$!; wait $p; local rc=$?; kill $w 2>/dev/null; return $rc; }
CLAUDE_RO=(--model ${SEC_CLAUDE_MODEL:-opus} --effort ${SEC_CLAUDE_EFFORT:-xhigh} --tools "Read,Grep,Glob" --allowedTools "Read,Grep,Glob" --disallowedTools "Read(**/.env*)" "Grep(**/.env*)" --strict-mcp-config --output-format json)
claude_json() { # $1 prompt file, $2 output json; extracts the JSON object from the model's reply, records cost
  capped ${SEC_TIMEOUT:-1500} $1 $2.raw $2.err claude -p $CLAUDE_RO
  python3 - $2.raw $2 $G/$t-sec-cost.txt "$t $r $(basename $2)" <<'PY'
import json,sys
w=json.load(open(sys.argv[1])); res=w.get("result","")
j,_=json.JSONDecoder().raw_decode(res[res.index("{"):]); json.dump(j,open(sys.argv[2],"w"),indent=1)
u=w.get("usage",{}); tin=u.get("input_tokens",0)+u.get("cache_creation_input_tokens",0)+u.get("cache_read_input_tokens",0)
open(sys.argv[3],"a").write(f"{sys.argv[4]} claude in={tin} out={u.get('output_tokens',0)} usd={w.get('total_cost_usd',0):.2f} s={w.get('duration_ms',0)//1000}\n")
PY
}
FINDING='{"id":"S1","severity":"P1|P2|P3","file_line":"path:line","checklist":"<item id, e.g. D5>","claim":"<one sentence>","exploit":"<who calls what and what they gain>","evidence":"<quoted line(s) with file:line, or grep output>"}'
t0=$(date +%s)

# 2. Attacker (Claude).
{ echo "You are the ATTACKER in Dayscent's adversarial security gate for task $t (head $h8, round $round). You are read-only: never edit files, never read .env, never run anything. Your job is to break this change: find every way the diff lets a user escalate, leak, bypass, or spend, using the checklist below. Work only from the diff and files below; use Read/Grep inside this worktree only to confirm a specific claim (for example, the previous definition of a function the diff replaces: the latest earlier migration that defines it). Report only problems this diff introduces or copies into new code; pre-existing issues go in notes. Every finding needs a concrete exploit and quoted evidence with file:line; if you can't name the attacker and the call, it is not a P1. Severity: P1 exploitable or data leak, P2 defense gap, P3 hygiene."
  if [ $mode = pass ]; then echo; echo "ROUND $round: the gate PASSED on ${base[1,8]} (result below). Since then the branch's own code changed only in: ${files}. Review ONLY the diff below (changes since ${base[1,8]} in those files) for new problems, with ids N1, N2...; code that already passed is out of scope unless this change affects it. Previous gate result:"; cat $prev; fi
  if [ $mode = fail ]; then echo; echo "ROUND $round: a previous gate run FAILED on ${base[1,8]} with the findings below and the builder has pushed fixes since. Re-check EACH previous finding against the current head: if it is still exploitable, report it again with the SAME id and fresh evidence; if fixed, list it in \"fixed\" with evidence. Then check ONLY the new diff below (changes since ${base[1,8]}) for new problems (new ids starting at N1). Previous gate result:"; cat $prev; fi
  echo; echo "=== CHECKLIST (dayscent-security-check skill) ==="; cat $SKILL
  echo; cat $ctx
  echo; echo "Reply with ONLY one JSON object, no prose, no code fence: {\"findings\":[$FINDING],\"fixed\":[{\"id\":\"S1\",\"evidence\":\"...\"}],\"checked\":[\"A1\",\"B2\"],\"notes\":\"<pre-existing issues, N/A areas>\"}"
} > $pre-claude.prompt
claude_json $pre-claude.prompt $pre-claude.json || { echo "== $t SEC-ERROR: attacker output unreadable (logs/$t-sec-$r-claude.json.raw/.err)"; exit 2; }
nc=$(python3 -c "import json;print(len(json.load(open('$pre-claude.json')).get('findings',[])))")

# 3. Adversary (Codex, read-only sandbox). Shares the ~5-worker cap with qrun.sh.
cat > $G/sec-codex-schema.json <<'JS'
{"type":"object","additionalProperties":false,"required":["verdicts","additions","notes"],"properties":{
 "verdicts":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["id","verdict","severity","reason","evidence"],"properties":{
   "id":{"type":"string"},"verdict":{"type":"string","enum":["CONFIRMED","LOWERED","REJECTED"]},"severity":{"type":"string","enum":["P1","P2","P3"]},"reason":{"type":"string"},"evidence":{"type":"string"}}}},
 "additions":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["id","severity","file_line","checklist","claim","exploit","evidence"],"properties":{
   "id":{"type":"string"},"severity":{"type":"string","enum":["P1","P2","P3"]},"file_line":{"type":"string"},"checklist":{"type":"string"},"claim":{"type":"string"},"exploit":{"type":"string"},"evidence":{"type":"string"}}}},
 "notes":{"type":"string"}}}
JS
{ echo "You are the ADVERSARY in Dayscent's security gate for task $t (head $h8, round $round). Read-only: never edit files, never read .env, no network, no database, no git commands that change anything (reading with rg/sed/cat/git show is fine). Another reviewer (Claude) attacked this diff and produced the findings below. (a) Challenge EACH finding: CONFIRMED only if you can see the exploit path in the code yourself; LOWERED if the pattern is real but less severe than claimed (give your severity); REJECTED only if the claim is wrong, already guarded elsewhere (cite where), or pre-existing and untouched by this diff. A P2 is by definition not exploitable today: never REJECT a finding only because grants, RLS or a missing caller block it now. If it matches a checklist P1/P2 pattern, CONFIRM it at P2; otherwise answer LOWERED to P3 and say why. Give a reason and concrete evidence (file:line plus the quoted code) either way, and your own severity (P1 exploitable or data leak, P2 defense gap, P3 hygiene). (b) Add anything security-relevant the attacker MISSED in this diff, using ids X1, X2..., with the same evidence standard. Do not repeat a finding as an addition. Use the checklist as the standard."
  echo; echo "=== ATTACKER FINDINGS ==="; cat $pre-claude.json
  echo; echo "=== CHECKLIST ==="; cat $SKILL
  echo; cat $ctx; } > $pre-codex.prompt
while [ $(pgrep -f "codex exec --sandbox" | wc -l) -ge 5 ]; do sleep 15; done
rm -f $pre-codex.json
capped ${SEC_TIMEOUT:-1500} $pre-codex.prompt $pre-codex.log $pre-codex.log2 codex exec --sandbox read-only -C $d -m ${SEC_CODEX_MODEL:-gpt-6.2-astra} \
  -c model_reasoning_effort=${SEC_CODEX_EFFORT:-xhigh} --output-schema $G/sec-codex-schema.json -o $pre-codex.json -; cat $pre-codex.log2 >> $pre-codex.log 2>/dev/null; rm -f $pre-codex.log2
python3 -c "import json;json.load(open('$pre-codex.json'))" 2>/dev/null || { echo "== $t SEC-ERROR: adversary output unreadable (logs/$t-sec-$r-codex.log)"; exit 2; }
echo "$t $r codex tokens=$(grep -A1 '^tokens used' $pre-codex.log | tail -1 | tr -d ,) s=$(( $(date +%s) - t0 ))" >> $G/$t-sec-cost.txt

# 4. Rebuttal (Claude, once), only if Codex rejected something or added something.
need=$(python3 -c "import json;c=json.load(open('$pre-codex.json'));print(sum(v['verdict']!='CONFIRMED' for v in c['verdicts'])+len(c['additions']))")
if [ "$need" -gt 0 ]; then
  { echo "You are the ATTACKER from round $round of Dayscent's security gate for task $t (head $h8). Read-only: never edit, never read .env. An adversary (Codex) reviewed your findings. Reply ONCE to each item below, with concrete evidence (file:line plus quoted code) for any position you take:"
    echo "- For each REJECTED finding of yours: decision DROP (the pattern itself is wrong, guarded, or pre-existing), LOWER (the rejection only shows it is not exploitable today; the pattern stands; give the lower severity, P2 if it matches a checklist P1/P2 pattern, else P3) or KEEP (it is still exploitable at your severity; show why the rejection's evidence is wrong or incomplete)."
    echo "- For each LOWERED finding of yours: decision ACCEPT (the adversary's severity is right) or KEEP (your severity stands; show the evidence)."
    echo "- For each ADDITION (X ids): decision AGREE (it is real, at the stated severity or say which) or DISPUTE (show the evidence it is wrong)."
    echo "Be honest: dropping a wrong finding is better than defending it. Use Read/Grep in this worktree only to check specific lines."
    echo; echo "=== YOUR FINDINGS ==="; cat $pre-claude.json
    echo; echo "=== ADVERSARY RESPONSE ==="; cat $pre-codex.json
    echo; echo "=== BRANCH DIFF ==="; cat $pre.diff
    echo; echo "Reply with ONLY one JSON object: {\"responses\":[{\"id\":\"S1 or X1\",\"decision\":\"DROP|LOWER|KEEP|ACCEPT|AGREE|DISPUTE\",\"severity\":\"P1|P2|P3\",\"evidence\":\"...\"}]}"; } > $pre-rebuttal.prompt
  claude_json $pre-rebuttal.prompt $pre-rebuttal.json || { echo "== $t SEC-ERROR: rebuttal output unreadable (logs/$t-sec-$r-rebuttal.json.raw)"; exit 2; }
else echo '{"responses":[]}' > $pre-rebuttal.json; fi

# Consensus -> logs/T-sec.json. Concrete evidence = at least one file:line reference, or a bare path to a file
# tracked in this worktree (2026-10-23 seed test: a valid rejection citing a path without a line was ignored).
python3 - $pre-claude.json $pre-codex.json $pre-rebuttal.json $out $head $round "$why" $G/$t-secissues.txt <<'PY'
import json,sys,re
cl,cx,rb=(json.load(open(p)) for p in sys.argv[1:4]); out,sha,rnd,why,issues=sys.argv[4],sys.argv[5],int(sys.argv[6]),sys.argv[7],sys.argv[8]
import subprocess
tracked=set(subprocess.run(["git","ls-files"],capture_output=True,text=True).stdout.split("\n"))-{""}
PATH=r"[\w./()\[\]-]+\.(?:sql|ts|tsx|js|mjs|json|toml|sh|swift|kt)\b"
concrete=lambda s: bool(re.search(PATH+r":\d+",s or "")) or any(p.lstrip("([./") in tracked for p in re.findall(PATH,s or ""))
rank={"P1":1,"P2":2,"P3":3}; worse=lambda a,b: min([a or "P3",b or "P3"],key=lambda s:rank.get(s,3))
# Noise calibration (2026-10-23): on hygiene-class items (missing tests G1, text filters H4) a P2-vs-P3 split
# takes the lower severity; everything else keeps the worse one.
hygiene=lambda f: bool(re.search(r"\b(G1|H4)\b",str(f.get("checklist",""))))
pick=lambda f,a,b: "P3" if hygiene(f) and {a or "P3",b or "P3"}=={"P2","P3"} else worse(a,b)
ver={v["id"]:v for v in cx.get("verdicts",[])}; resp={r["id"]:r for r in rb.get("responses",[])}
kept,dropped,disputed=[],[],[]
for f in cl.get("findings",[]):
    v=ver.get(f["id"]); f=dict(f,source="claude")
    if v is None: kept.append(dict(f,why_kept="adversary did not challenge it")); continue
    f["codex"]={"verdict":v["verdict"],"severity":v["severity"],"reason":v["reason"],"evidence":v["evidence"]}
    if v["verdict"]=="CONFIRMED": kept.append(dict(f,severity=pick(f,f.get("severity"),v["severity"]),why_kept="both agree")); continue
    if v["verdict"]=="LOWERED":
        r=resp.get(f["id"]); f["rebuttal"]=r; blocks=lambda s: s in ("P0","P1","P2")
        if r and r.get("decision")=="KEEP" and concrete(r.get("evidence")) and blocks(f.get("severity"))!=blocks(v["severity"]):
            disputed.append(dict(f,why="adversary lowered it across the P2/P3 line; attacker kept it with evidence; Lead decides"))
        else: kept.append(dict(f,severity=v["severity"],why_kept="adversary lowered severity; kept at the lower severity"))
        continue
    if not concrete(v["evidence"]): kept.append(dict(f,why_kept="rejection had no concrete file:line evidence")); continue
    r=resp.get(f["id"]); f["rebuttal"]=r
    if r and r.get("decision")=="KEEP" and concrete(r.get("evidence")): disputed.append(dict(f,why="both sides gave concrete evidence; Lead decides"))
    elif r and r.get("decision")=="LOWER": kept.append(dict(f,severity=r.get("severity") if r.get("severity") in rank else "P3",why_kept="not exploitable today; attacker lowered it, pattern stands"))
    else: dropped.append(dict(f,why="attacker accepted the rejection" if r and r.get("decision")=="DROP" else "rejected with evidence; no concrete counter-evidence"))
for a in cx.get("additions",[]):
    a=dict(a,source="codex"); r=resp.get(a["id"]); a["rebuttal"]=r
    if r and r.get("decision")=="DISPUTE" and concrete(r.get("evidence")): disputed.append(dict(a,why="attacker disputed with concrete evidence; Lead decides"))
    else: kept.append(dict(a,severity=pick(a,a.get("severity"),(r or {}).get("severity")) if r and r.get("decision")=="AGREE" else a.get("severity"),
                           why_kept="both agree" if r and r.get("decision")=="AGREE" else "dispute had no concrete evidence"))
block=[f for f in kept if f.get("severity") in ("P0","P1","P2")]
res={"sha":sha,"round":rnd,"verdict":"FAIL" if block else "PASS","trigger":why.split("\n"),"agreed_p1_p2":[f["id"] for f in block],
     "findings":kept,"disputed":disputed,"dropped":dropped,"fixed":cl.get("fixed",[]),"checked":cl.get("checked",[]),
     "notes":{"attacker":cl.get("notes",""),"adversary":cx.get("notes","")}}
json.dump(res,open(out,"w"),indent=1)
open(issues,"w").write("\n".join(f"- [SEC {f['severity']} {f['id']}] {f.get('claim')} ({f.get('file_line')}). Exploit: {f.get('exploit')} Evidence: {f.get('evidence')}" for f in block))
PY
[ $? -ne 0 ] && { echo "== $t SEC-ERROR: consensus step failed"; exit 2; }
na=0; [ -s $G/$t-sec-accepted.json ] && { na=$(python3 $L/secaccept.py apply $out $G/$t-sec-accepted.json $G/$t-secissues.txt) || { echo "== $t SEC-ERROR: applying accepted risks failed"; exit 2; }; }
read v nb np nd ndr <<< "$(python3 -c "import json;j=json.load(open('$out'));k=j['findings'];b=len(j['agreed_p1_p2']);print(j['verdict'],b,len(k)-b,len(j['disputed']),len(j['dropped']))")"
summary="round $round on $h8: $nb agreed P1/P2, $np P3, $nd disputed (Lead decides), $ndr dropped, $na accepted risk(s); attacker found $nc; $(( $(date +%s) - t0 ))s"
[ "$v" = PASS ] && { echo "== $t SEC-PASS $summary"; exit 0; }

# 5. FAIL: agreed P1/P2s go to Codex as the next round, the way qagate.sh does it.
[ -n "$SEC_FROM_LOOP" ] && { echo "== $t SEC-FAIL $summary (qloop feeds logs/$t-secissues.txt to the next round)"; exit 1; }
{ [ -f $Q/$t.base ] && { cat $Q/$t.base; echo; }
  echo "The adversarial security gate (secgate.sh round $round: a Claude attacker and a Codex adversary both agreed) found these problems on $h8. The checklist is $SKILL. Fix each one in this branch; for SQL add a pgTAP case in supabase/tests that fails before the fix (non-friend/blocked/age-unconfirmed fixtures where relevant); update the handoff:"
  cat $G/$t-secissues.txt; } > $Q/$t.sec
if [ -n "$SEC_NO_RESTART" ] || [ -e $Q/$t.lead ]; then
  echo "== $t SEC-FAIL $summary. Fix prompt in $Q/$t.sec (no Codex restart)"; exit 1
fi
if running; then
  ( while running; do sleep 30; done; mv $Q/$t.sec $Q/$t.txt && zsh $L/start.sh $t 4 ) >/dev/null 2>&1 < /dev/null &!
  echo "== $t SEC-FAIL $summary. Queued for Codex when the running loop stops"
else
  mv $Q/$t.sec $Q/$t.txt; zsh $L/start.sh $t 4 >/dev/null
  echo "== $t SEC-FAIL $summary. Fed back to Codex; loop restarted"
fi
exit 1

# Shared paths and helpers for the Codex fix loop (sourced by the other scripts).
# Lives outside /tmp so a Mac restart doesn't wipe the scripts, prompts or logs.
L=${GATE_HOME:?set GATE_HOME to this folder}
Q=$L/q        # prompts: <T>.base (standing rules) and <T>.txt (this round)
G=$L/logs     # <T>-run.log, -verify.log, -rvN.txt, -removed.txt, -threads.txt, -loop.out
wt() { echo ${WORKTREES:?}/$1; }   # task worktree (website/app-starter tasks are symlinks here)

# Item 3: make sure the worktree can see dependencies. Links node_modules to the main checkout's
# copy when it is missing or broken, for any repo (Dayscent, website, app-starter).
ensure_deps() {
  [ -f package.json ] || return 0
  # A real (non-link) node_modules left from an older checkout goes stale when main adds
  # packages: if it lacks any dependency that package.json declares, set it aside and link.
  if [ -d node_modules ] && [ ! -L node_modules ]; then
    local missing=$(node -e 'const p=require("./package.json");const fs=require("fs");console.log(Object.keys({...p.dependencies,...p.devDependencies}).filter(d=>!fs.existsSync("node_modules/"+d)).length)' 2>/dev/null)
    [ "${missing:-0}" -gt 0 ] && mv node_modules "../$(basename $PWD)-node_modules.stale.$(date +%s)"
  fi
  [ -e node_modules ] && return 0
  [ -L node_modules ] && unlink node_modules   # broken link
  local main=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
  [ -d "$main/node_modules" ] && ln -s "$main/node_modules" node_modules
}

# 2026-11-06 (ledger L-2026-11-06b): pids of a running `qloop.sh T` (forked subshells repeat its command line, so
# there can be several). Anchored on the interpreter: a grep or wrapper shell that only mentions qloop.sh T doesn't match.
loop_pids() { ps -axo pid=,command= | grep -E "^ *[0-9]+ ([^ ]*/)?zsh ([^ ]*/)?qloop\.sh $1( |\$)" | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//'; }

# owner/name of the worktree's GitHub repo, and the open PR for its branch (empty if none).
repo_of() { gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null; }
pr_of() { gh pr view --json number,state -q 'select(.state=="OPEN")|.number' 2>/dev/null; }

# The Codex bot reviews only when a PR opens, is marked ready, or gets an "@codex review" comment,
# never on a push. Its status lives in one summary comment table (Status | Commit). Prints the bot's
# state for this head: done (a finished row for the head, or a review on it), running, or none.
codex_state() { local repo=$1 pr=$2 head=$3 body
  [ "$(gh api "repos/$repo/pulls/$pr/reviews?per_page=100" -q "[.[]|select(.user.login|test(\"codex\"))|select(.commit_id==\"$head\")]|length" 2>/dev/null)" -gt 0 ] 2>/dev/null && { echo done; return; }
  body=$(gh api "repos/$repo/issues/$pr/comments?per_page=100" -q '[.[]|select(.user.login|test("codex"))|select(.body|test("codex-pull-request-review-summary"))]|last|.body // ""' 2>/dev/null)
  local row=$(print -r -- "$body" | grep -F "\`${head[1,7]}\`" | tail -1)
  if [ -z "$row" ]; then echo none; elif print -r -- "$row" | grep -q "Running"; then echo running; else echo done; fi
}
# Ask the bot to review the current head unless it already did or is running.
codex_request() { local repo=$1 pr=$2 head=$3
  [ "$(codex_state $repo $pr $head)" = none ] && gh pr comment $pr --repo $repo --body "@codex review" >/dev/null 2>&1 && echo requested
}

# 2026-10-23 security gate (secgate.sh, mergecheck.sh): reads a unified diff on stdin and prints why it is
# security-sensitive (one reason per line; empty = not sensitive). Sensitive = it touches migrations, Edge
# Functions, auth, premium, src/lib/supabase*, package/app/eas config, or adds/removes RLS/grant/policy text
# in a non-Markdown file.
sec_sensitive() { local p=$(cat)
  print -r -- "$p" | sed -nE 's#^diff --git a/.* b/(.*)$#\1#p' \
    | grep -E '^(supabase/(migrations|functions)/|src/features/(auth|premium)/|src/lib/supabase|(package|package-lock|app|eas)\.json$|app\.config\.ts$|metro\.config\.js$|metro-stubs/|babel\.config\.js$|plugins/)' \
    | head -8 | sed 's/^/path: /'
  print -r -- "$p" | awk '/^diff --git/{md=($NF ~ /\.md$/)} !md && /^[+-]/ && !/^(\+\+\+|---) /' \
    | grep -iE '(grant +(select|insert|update|delete|execute|usage|all|references|trigger)|revoke +(select|insert|update|delete|execute|usage|all)|(create|alter|drop) +policy|row level security|security +definer|service_role)' \
    | head -3 | cut -c1-120 | sed 's/^/text: /'
}

# 2026-10-31 risk tiers (owner "do all"; idea from Anthropic's Antique review tool): how many gates a branch needs.
# Reads a unified diff on stdin, prints "<tier> <reason>":
#   heavy  = security-sensitive (sec_sensitive) or SQL tests: + intent check, secgate (when sensitive), db:test (migrations or SQL tests)
#   light  = only Markdown, docs/ or JS tests: no simplify pass, no intent check
#   normal = anything else: + intent check (simulator QA still triggers on UI files)
risk_tier() { local p=$(cat) s files
  s=$(print -r -- "$p" | sec_sensitive | head -1)
  [ -n "$s" ] && { echo "heavy $s"; return; }
  files=$(print -r -- "$p" | sed -nE 's#^diff --git a/.* b/(.*)$#\1#p')
  # SQL tests only run via db:test (CI skips pgTAP), so they are heavy, never light (app-starter #10 review).
  print -r -- "$files" | grep -m1 '^supabase/tests/' | sed 's/^/heavy SQL tests: /' | grep . && return
  [ -z "$files" ] && { echo "light empty diff"; return; }
  # (grep -c, not -vq: macOS grep -vq exits 1 as soon as one line matches)
  if [ "$(print -r -- "$files" | grep -cvE '(\.md$|^docs/|/__tests__/|\.test\.[jt]sx?$)')" -gt 0 ]
  then echo "normal code change"; else echo "light docs/tests only"; fi
}

# 2026-11-09 "merge danger" card (brain toolkit/trending-repos-2026-11.md top 5 #1): is this diff a one-way or a
# two-way door? Reads a unified diff on stdin, prints "<one-way|two-way> <reason>".
#   one-way = touches supabase/migrations or supabase/functions (db push / deploy), or is otherwise heavy
#             (auth, premium = money, RLS/grant text = permissions, package/app/eas config = store build).
#             SQL tests alone stay two-way. A handoff line added in this diff, "Reversible: <how to undo, 15+ chars>",
#             turns it two-way (the Lead/owner reads that reason on the card).
#   two-way = app code that a revert or an OTA undoes.
door_of() { local p=$(cat) why t rev
  why=$(print -r -- "$p" | sed -nE 's#^diff --git a/.* b/(.*)$#\1#p' | grep -vE '(/__tests__/|\.test\.[jt]sx?$)' | grep -m1 -E '^supabase/(migrations|functions)/' | sed 's/^/path: /')
  if [ -z "$why" ]; then t=$(print -r -- "$p" | risk_tier); [[ $t == heavy* && $t != "heavy SQL tests"* ]] && why=${t#heavy }; fi
  [ -z "$why" ] && { echo "two-way app code (a revert or an OTA undoes it)"; return; }
  rev=$(print -r -- "$p" | awk '/^diff --git/{h=($NF ~ /docs\/handoffs\/.*\.md$/)} h && /^\+ *Reversible:/' | sed -E 's/^\+ *Reversible: *//' | head -1)
  [ ${#rev} -ge 15 ] && { echo "two-way $why; handoff says Reversible: ${rev[1,140]}"; return; }
  echo "one-way $why"
}

# 2026-11-10 circuit breaker, WARN-ONLY (owner OK "Do it"). Measured on 12 recent rounds: healthy rounds
# repeat the same failing test 3-28 times (fail-first proof + iteration), so killing on repeats would
# have killed good rounds. qrun only warns when a round runs > BREAKER_MIN_S and an error repeats a lot.
# prints the error that repeats inside one Codex round,
# exit 0 when something repeats enough to stop the round, else exit 1. Thresholds via env:
# BREAKER_TS (default 3 identical "error TS…" lines), BREAKER_FAIL (3 identical "FAIL <suite>"),
# BREAKER_JEST (6 identical "● test name" lines; Jest prints each failing test about twice per run).
repeat_sig() {
  python3 - "$1" "${BREAKER_TS:-15}" "${BREAKER_FAIL:-15}" "${BREAKER_JEST:-30}" <<'PY'
import re,sys,collections
p,ts,fl,js=sys.argv[1],*map(int,sys.argv[2:])
try: lines=open(p,errors='replace').read().splitlines()
except OSError: sys.exit(1)
rules=[(re.compile(r'(error TS\d+: .{0,160})'),ts),(re.compile(r'^\s*(FAIL \S+)'),fl),(re.compile(r'^\s*(● (?!Console\b).{3,160})'),js)]
for rx,n in rules:
  c=collections.Counter(m.group(1).strip() for l in lines if (m:=rx.search(l)))
  if c:
    sig,k=c.most_common(1)[0]
    if k>=n: print(f"{k}x {sig[:140]}"); sys.exit(0)
sys.exit(1)
PY
}
# 2026-11-12 test tamper alarm (tamper.py; ledger L-2026-11-12a): reads a unified diff on stdin, prints
# "" when no existing test was weakened/removed/skipped or the Lead approved exactly these findings
# (tamperok.sh T "reason" -> logs/T-tamper-ok.json), else "N finding(s)" for the READY line / mergecheck.
tamper_state() { local t=$1 f h ok; f=$(cat); h=$(print -r -- "$f" | python3 -I $L/tamper.py --hash)
  [ -z "$h" ] && return 0; ok=$(jq -r .hash $G/$t-tamper-ok.json 2>/dev/null)
  [ "$ok" = "$h" ] && return 0
  echo "$(print -r -- "$f" | python3 -I $L/tamper.py | wc -l | tr -d ' ') finding(s)"; }

# 2026-11-16 macguard (a separate load-watcher script, not included): the Mac's load state, GREEN|YELLOW|RED.
# Fails open: no MAC-STATE, one older than 5 min (macguard not running) or `macguard off` all read as GREEN.
mac_state() { local f=$G/MAC-STATE s
  [ -e $G/macguard-off ] || [ ! -f $f ] && { echo GREEN; return; }
  [ $(( $(date +%s) - $(stat -f %m $f) )) -gt 300 ] && { echo GREEN; return; }
  read s _ < $f; echo ${s:-GREEN}; }
# 2026-11-19 (T-882/T-906 kept running rounds for hours after their PRs merged, rewriting tests and
# burning Codex allowance): a task whose branch has a MERGED PR and no OPEN PR is done. Prints the
# merged PR number and returns 0 when the loop must stop; fails open (returns 1) if gh/git can't tell.
already_merged() { local d=$(wt $1) b open merged
  b=$(git -C $d branch --show-current 2>/dev/null) || return 1; [ -n "$b" ] || return 1
  open=$(cd $d && gh pr list --head "$b" --state open --json number --jq '.[0].number' 2>/dev/null)
  [ -n "$open" ] && return 1
  merged=$(cd $d && gh pr list --head "$b" --state merged --json number --jq '.[0].number' 2>/dev/null)
  [ -n "$merged" ] || return 1; echo "$merged"; return 0; }

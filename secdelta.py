#!/usr/bin/env python3
"""secdelta.py X [MAIN]  -- run inside a task worktree. Prints JSON describing the branch's OWN changes between
an earlier gated head X and HEAD, ignoring everything that came in by merging MAIN (default origin/main).

Own diff at a commit C = diff(merge-base(MAIN, C), C). A file counts as changed only if its own diff at HEAD
differs from its own diff at X (hunk headers and line numbers ignored), so main's edits elsewhere in the
same file don't count. Carry-allowed changes (secgate.sh records PASS without model calls):
  - edits to the migration parity list (PARITY below);
  - migration renames: a supabase/migrations file the branch added at X is gone at HEAD and a file with
    identical content was added under a new name (a version bump).
Output: {"changed": [...real changes...], "carry": [...allowed changes...], "renames": [[old, new], ...]}
"""
import json, subprocess, sys

PARITY = "src/features/friends/__tests__/comments-off-hardening-sql-parity.test.ts"
X = sys.argv[1]; MAIN = sys.argv[2] if len(sys.argv) > 2 else "origin/main"
git = lambda *a: subprocess.run(["git", *a], capture_output=True, text=True).stdout
mbX = git("merge-base", MAIN, X).strip(); mbH = git("merge-base", MAIN, "HEAD").strip()
if not mbX or not mbH: sys.exit("secdelta: no merge base")
names = lambda a, b: set(git("diff", "--no-renames", "--name-only", a, b).split("\n")) - {""}
files = names(mbX, X) | names(mbH, "HEAD")

def own(base, tip, f):
    return [l for l in git("diff", "--no-renames", "-U0", base, tip, "--", f).split("\n")
            if l[:1] in "+-" and not l.startswith(("+++ ", "--- "))]

def blob(c, f):
    return git("rev-parse", "--verify", "-q", f"{c}:{f}").strip() or None

changed = sorted(f for f in files if own(mbX, X, f) != own(mbH, "HEAD", f))
# Renames: added by the branch at X and absent at HEAD, paired with a file added at HEAD with the same blob.
gone = {f: blob(X, f) for f in changed if blob(X, f) and not blob("HEAD", f) and not blob(mbX, f)}
new = {f: blob("HEAD", f) for f in changed if blob("HEAD", f) and not blob(X, f) and not blob(mbH, f)}
renames = []
for g, b in gone.items():
    for n, nb in new.items():
        if nb == b and g.startswith("supabase/migrations/") and n.startswith("supabase/migrations/") and n not in sum(renames, []):
            renames.append([g, n]); break
paired = set(sum(renames, []))
carry = sorted(f for f in changed if f == PARITY or f in paired)
print(json.dumps({"changed": [f for f in changed if f not in carry], "carry": carry, "renames": renames,
                  "merge_base_at_X": mbX[:8], "merge_base_at_head": mbH[:8]}))

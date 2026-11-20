#!/usr/bin/env python3
"""Lead-accepted security risks for secgate.sh (2026-10-26).

  secaccept.py add   SEC_JSON ACCEPTED_JSON ID REASON LEAD   -- record finding ID from SEC_JSON as accepted
  secaccept.py apply SEC_JSON ACCEPTED_JSON ISSUES_TXT       -- move matching findings to "accepted", recompute verdict

Matching, so the same issue re-raised in a later round with a new id (and reworded, or pointed at a sibling file)
still matches:
  - exact: same file AND same normalized-claim hash (sha1 of the claim's lowercase word tokens); or
  - fuzzy: same area (first 3 path parts, e.g. supabase/functions/moderate-photo) AND claim word overlap
    (Jaccard, stopwords removed) >= 0.5. Measured on T-707: S2 r1 vs r2 = 0.63; unrelated claims < 0.05.
A P1 can only be accepted with SEC_ACCEPT_P1=1, and an entry accepted at P2/P3 never covers a finding that is now P1.
"""
import hashlib, json, os, re, sys, datetime

STOP = set("a an the to of and or is are be by that this it its from on in for with one could can still than only "
           "was were has have any then their them which not but so as at into".split())

def path(f): return re.sub(r":[\d\-,]+$", "", (f.get("file_line") or "").strip())
def area(p): return "/".join(p.split("/")[:3])
def toks(s): return {w for w in re.findall(r"[a-z0-9]+", (s or "").lower()) if w not in STOP and len(w) > 2}
def chash(s): return hashlib.sha1(" ".join(sorted(toks(s))).encode()).hexdigest()[:16]
def jac(a, b): return len(a & b) / len(a | b) if a | b else 0.0
def load(p, default):
    try: return json.load(open(p))
    except (OSError, ValueError): return default

def matches(f, e):
    p = path(f)
    if p == e["file"] and chash(f.get("claim")) == e["claim_hash"]: return True
    return area(p) == area(e["file"]) and jac(toks(f.get("claim")), set(e["claim_tokens"])) >= 0.5

def add(sec_p, acc_p, fid, reason, lead):
    sec = load(sec_p, {}); acc = load(acc_p, [])
    pool = sec.get("findings", []) + sec.get("disputed", []) + sec.get("accepted", [])
    f = next((x for x in pool if x.get("id") == fid), None)
    if not f: sys.exit(f"no finding {fid} in {sec_p}")
    sev = f.get("severity", "P2")
    if sev in ("P0", "P1") and os.environ.get("SEC_ACCEPT_P1") != "1":
        sys.exit(f"{fid} is {sev}: accepting a P1 needs SEC_ACCEPT_P1=1")
    if not reason.strip(): sys.exit("a reason is required")
    e = {"id": fid, "severity": sev, "file": path(f), "claim_hash": chash(f.get("claim")),
         "claim_tokens": sorted(toks(f.get("claim"))), "claim": f.get("claim"), "reason": reason, "lead": lead,
         "date": datetime.date.today().isoformat(), "sha": sec.get("sha", "")[:8], "round": sec.get("round")}
    acc.append(e); json.dump(acc, open(acc_p, "w"), indent=1)
    print(f"accepted {fid} ({sev}, {e['file']}) -> {acc_p}")

def apply(sec_p, acc_p, issues_p):
    sec = load(sec_p, None); acc = load(acc_p, [])
    if sec is None: sys.exit(f"cannot read {sec_p}")
    keep, moved = [], sec.get("accepted", [])
    for f in sec.get("findings", []):
        p1 = f.get("severity") in ("P0", "P1")
        e = next((e for e in acc if matches(f, e) and (not p1 or e["severity"] in ("P0", "P1"))), None)
        (moved.append(dict(f, accept={k: e[k] for k in ("id", "reason", "lead", "date")})) if e else keep.append(f))
    block = [f for f in keep if f.get("severity") in ("P0", "P1", "P2")]
    sec.update(findings=keep, accepted=moved, agreed_p1_p2=[f["id"] for f in block], verdict="FAIL" if block else "PASS")
    json.dump(sec, open(sec_p, "w"), indent=1)
    open(issues_p, "w").write("\n".join(f"- [SEC {f['severity']} {f['id']}] {f.get('claim')} ({f.get('file_line')}). "
                                        f"Exploit: {f.get('exploit')} Evidence: {f.get('evidence')}" for f in block))
    print(len(moved))

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["add"] and len(a) == 6: add(*a[1:])
    elif a[:1] == ["apply"] and len(a) == 4: apply(*a[1:])
    else: sys.exit(__doc__)

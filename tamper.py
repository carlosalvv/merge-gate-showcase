#!/usr/bin/env python3
"""Test tamper alarm (2026-11-12, owner "Yes" after a reel: agents rewrite tests to get green).

usage: git diff origin/main...HEAD | python3 -I tamper.py        -> prints one finding per line, exit 0
       ... | python3 -I tamper.py --hash                         -> prints a hash of the findings ("" if none)

Flags, in EXISTING test files only (new test files are free):
  - a test file deleted
  - a removed line that holds an assertion or a test case (expect/assert/pgTAP is()/it()/test() ...),
    unless the exact same line is added back somewhere in the diff (a move, not a removal)
  - an added .skip/.only/xit/xdescribe/.todo/pgTAP skip()/Deno ignore:true
The hash covers file + line text (not line numbers), so a Lead approval survives later commits
that do not add new tamper, and a new tamper needs a new approval.
"""
import hashlib, re, sys

TEST = re.compile(r'(/__tests__/|\.test\.[cm]?[jt]sx?$|\.spec\.[cm]?[jt]sx?$|^supabase/tests/|_test\.ts$|\.deno\.(ts|mjs)$)')
ASSERT = re.compile(r'\bexpect\s*\(|\bassert\w*\s*\(|\.(toBe|toEqual|toStrictEqual|toMatch\w*|toThrow\w*|toHave\w*|toContain\w*|resolves|rejects)\b'
                    r'|\b(ok|is|isnt|throws_ok|throws_like|lives_ok|results_eq|results_ne|set_eq|bag_eq|row_eq|cmp_ok|matches|is_empty|isnt_empty|policies_are|has_\w+|hasnt_\w+)\s*\('
                    r'|^\s*(it|test|describe|Deno\.test)(\.each\S*)?\s*\(')
SKIP = re.compile(r'\.(skip|only|todo)\s*\(|\b(xit|xtest|xdescribe|fit|fdescribe)\s*\(|\bskip\s*\(|\bignore\s*:\s*true|\bonly\s*:\s*true')

def main():
    path, new_file, findings, removed, added = None, False, [], [], set()
    for raw in sys.stdin.read().splitlines():
        if raw.startswith('diff --git '):
            m = re.match(r'diff --git a/(.*) b/(.*)$', raw); path = m.group(2) if m else None; new_file = False; continue
        if path is None or not TEST.search(path): continue
        if raw.startswith('new file mode'): new_file = True; continue
        if raw.startswith('deleted file mode'): findings.append(f'{path}: test file deleted'); continue
        if raw.startswith(('---', '+++', '@@', 'index ')): continue
        if raw.startswith('+'):
            line = raw[1:].strip(); added.add(line)
            if SKIP.search(line): findings.append(f'{path}: skip/only added: {line[:140]}')
        elif raw.startswith('-') and not new_file:
            line = raw[1:].strip()
            if ASSERT.search(line) and not line.startswith(('//', '--', '*')): removed.append((path, line))
    findings += [f'{p}: assertion/test removed or changed: {l[:140]}' for p, l in removed if l not in added]
    if '--hash' in sys.argv:
        print(hashlib.sha256('\n'.join(sorted(findings)).encode()).hexdigest()[:16] if findings else '')
    else:
        print('\n'.join(findings))

main()

#!/bin/zsh
# usage: findings.sh rvN.txt -> prints the review findings section, whatever heading codex review used
# ("Full review comments:", "Review comment:", "Review comments:"); falls back to every [P#] bullet with its text.
f=$1
n=$(grep -nE '^(Full review comments|Review comments?):' $f | tail -1 | cut -d: -f1)
if [ -n "$n" ]; then tail -n +$n $f; else grep -A8 -E '^- \[P[0-9]\]' $f; fi

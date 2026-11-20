#!/bin/zsh
# usage: secaccept.sh T <finding-id> "<reason>"  -- the Lead accepts a security-gate finding as a known risk.
# Appends {id, severity, file, normalized-claim hash + tokens, reason, lead, date} to logs/<T>-sec-accepted.json;
# secgate.sh then moves any matching finding (same issue re-raised later with a new id) to "accepted", where it
# doesn't block. P1 needs SEC_ACCEPT_P1=1. Lead name: SEC_LEAD (default "Lead"). Matching rules: secaccept.py.
# Re-run secgate.sh T afterwards: on an unchanged head it re-applies the list with no model calls.
source "${GATE_HOME:?set GATE_HOME to this folder}/lib.sh"
t=$1; id=$2; reason=$3
[ -z "$reason" ] && { echo "usage: secaccept.sh T <finding-id> \"<reason>\""; exit 2; }
[ -f $G/$t-sec.json ] || { echo "== $t no logs/$t-sec.json; run secgate.sh $t first"; exit 2; }
python3 $L/secaccept.py add $G/$t-sec.json $G/$t-sec-accepted.json "$id" "$reason" "${SEC_LEAD:-Lead}"

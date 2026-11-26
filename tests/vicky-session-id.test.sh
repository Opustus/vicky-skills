#!/usr/bin/env bash
# VICKY_SESSION_ID acts as the session-id fallback when CLAUDE_CODE_SESSION_ID
# is unset (for run_command shells in Antigravity).
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
otu="$root/plugins/vicky-skills/skills/building/over-to-you/scripts"
ipage="$root/plugins/vicky-skills/skills/writing/interactive-page/scripts"
fx="$(mktemp -d)"; trap 'rm -rf "$fx"' EXIT
export TMPDIR="$fx/tmp"
mkdir -p "$TMPDIR/v1/over-to-you-receipts"
fails=0

check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "ok   $name"; else echo "FAIL $name"; fails=1; fi
}

env -u CLAUDE_CODE_SESSION_ID env -u VICKY_SESSION_ID bash "$otu/kit.sh" left >/dev/null 2>&1; rc_kit=$?
env -u CLAUDE_CODE_SESSION_ID env -u VICKY_SESSION_ID bash "$otu/ran.sh" rv true >/dev/null 2>&1; rc_ran=$?
check "both session vars unset still exits 2 for kit.sh and ran.sh" '[ "$rc_kit" = 2 ] && [ "$rc_ran" = 2 ]'

env -u CLAUDE_CODE_SESSION_ID VICKY_SESSION_ID=v1 bash "$otu/kit.sh" left >/dev/null 2>&1; rc_k1=$?
env -u CLAUDE_CODE_SESSION_ID VICKY_SESSION_ID=v1 bash "$otu/ran.sh" rv true >/dev/null 2>&1; rc_r1=$?
check "VICKY_SESSION_ID works for kit.sh and ran.sh when CLAUDE_CODE_SESSION_ID is unset" \
  '[ "$rc_k1" = 0 ] && [ "$rc_r1" = 0 ] && [ -f "$TMPDIR/v1/over-to-you-receipts/rv.json" ]'

printf '#!/usr/bin/env bash\ntrue\n' > "$TMPDIR/v1/s.sh"; chmod +x "$TMPDIR/v1/s.sh"
jq -n --arg cmd "$TMPDIR/v1/s.sh" '{id:"rs", command:$cmd, exit:0, at:"2026-01-01T00:00:00Z", head:"", cwd:"/", tail:""}' > "$TMPDIR/v1/over-to-you-receipts/rs.json"
jq -n '{name:"Bob", open:"Open.", signed_off:"none", proven_by:"no server", sections:[{title:"P", items:[{do:"D", see:"S", person:"real client", ran:"rs"}]}]}' > "$fx/spec.json"
out_chk="$(env -u CLAUDE_CODE_SESSION_ID VICKY_SESSION_ID=v1 python3 -I "$otu/checklist.py" "$fx/spec.json" "$TMPDIR/v1/c.md" 2>&1)"
rc_chk=$?
check "checklist.py enforces session scratch path under VICKY_SESSION_ID" \
  '[ "$rc_chk" = 1 ] && [[ "$out_chk" == *"session folder"* ]]'

out_scr="$(env -u CLAUDE_CODE_SESSION_ID VICKY_SESSION_ID=v1 PYTHONPATH="$ipage" python3 -c "import scratch; print(scratch.loose_page('$TMPDIR/loose.md'))" 2>&1)"
check "scratch.py refuses loose page in TMPDIR under VICKY_SESSION_ID" \
  '[[ "$out_scr" == *"v1/"* ]]'

exit "$fails"

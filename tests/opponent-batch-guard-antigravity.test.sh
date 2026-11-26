#!/usr/bin/env bash
# shellcheck disable=SC2016 # check() evals its single-quoted condition later
# shellcheck disable=SC2034 # names set here are read inside check()'s eval
# Antigravity opponent-batch-guard decisions: batch.sh cap (default 1, ceiling 3),
# holds-opponent fights alone, Model="pro" refused, finished opponent frees slot,
# and non-opponents / malformed input pass.
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$root/plugins/vicky-skills/scripts/opponent-batch-guard-antigravity.py"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0

run_guard() {
  local state="$1" payload="$2"
  PLUGIN_DATA="$state" python3 "$hook" <<<"$payload" 2>/dev/null
}

check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "ok   $name"; else echo "FAIL $name"; fails=1; fi
}

out="$(run_guard "$tmp/s0" '{"conversationId":"c0","toolCall":{"id":"t0","name":"run_command","args":{"TypeName":"intent-opponent","Model":"pro"}}}')"
check "non-invoke_subagent tool is allowed even with opponent args" '[[ "$out" == *'\''"decision": "allow"'\''* ]]'

out="$(run_guard "$tmp/s1" '{"conversationId":"c1","toolCall":{"id":"t1","name":"invoke_subagent","args":{"TypeName":"research","Model":"pro"}}}')"
check "non-opponent subagent is allowed even with Model=pro" '[[ "$out" == *'\''"decision": "allow"'\''* ]]'

out="$(run_guard "$tmp/s2" '{"conversationId":"c2","toolCall":{"id":"t1","name":"invoke_subagent","args":{"TypeName":"intent-opponent","Model":"pro"}}}')"
check "opponent with Model=pro is denied" '[[ "$out" == *'\''"decision": "deny"'\''* && "$out" == *"Nothing was dispatched"* ]]'

out1="$(run_guard "$tmp/s3" '{"conversationId":"c3","toolCall":{"id":"t1","name":"invoke_subagent","args":{"TypeName":"intent-opponent"}}}')"
out_retry="$(run_guard "$tmp/s3" '{"conversationId":"c3","toolCall":{"id":"t1","name":"invoke_subagent","args":{"TypeName":"intent-opponent"}}}')"
out2="$(run_guard "$tmp/s3" '{"conversationId":"c3","toolCall":{"id":"t2","name":"invoke_subagent","args":{"TypeName":"cause-opponent"}}}')"
out_other="$(run_guard "$tmp/s3" '{"conversationId":"c3-other","toolCall":{"id":"t3","name":"invoke_subagent","args":{"TypeName":"cause-opponent"}}}')"
check "default limit allows first opponent and writes state under PLUGIN_DATA" '[[ "$out1" == *'\''"decision": "allow"'\''* ]] && [ -d "$tmp/s3/opponent-batch" ]'
check "same tool id is not double-counted" '[[ "$out_retry" == *'\''"decision": "allow"'\''* ]]'
check "default limit denies second concurrent opponent" '[[ "$out2" == *'\''"decision": "deny"'\''* && "$out2" == *"at most 1"* ]]'
check "separate conversationId has its own slot" '[[ "$out_other" == *'\''"decision": "allow"'\''* ]]'

cat >"$tmp/t4.jsonl" <<'EOF'
not json
{"type":"GENERIC","content":"batch.sh: at once: 2\nmemory cap: 4096M"}
EOF
out1="$(run_guard "$tmp/s4" "{\"conversationId\":\"c4\",\"transcriptPath\":\"$tmp/t4.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"intent-opponent\"}}}")"
out2="$(run_guard "$tmp/s4" "{\"conversationId\":\"c4\",\"transcriptPath\":\"$tmp/t4.jsonl\",\"toolCall\":{\"id\":\"t2\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"cause-opponent\"}}}")"
out3="$(run_guard "$tmp/s4" "{\"conversationId\":\"c4\",\"transcriptPath\":\"$tmp/t4.jsonl\",\"toolCall\":{\"id\":\"t3\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"claims-opponent\"}}}")"
check "at once: 2 allows first two opponents" '[[ "$out1" == *'\''"decision": "allow"'\''* && "$out2" == *'\''"decision": "allow"'\''* ]]'
check "at once: 2 denies third opponent" '[[ "$out3" == *'\''"decision": "deny"'\''* && "$out3" == *"at most 2"* ]]'

cat >"$tmp/tcap.jsonl" <<'EOF'
{"type":"GENERIC","content":"at once: 9"}
EOF
out1="$(run_guard "$tmp/scap" "{\"conversationId\":\"ccap\",\"transcriptPath\":\"$tmp/tcap.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"intent-opponent\"}}}")"
out2="$(run_guard "$tmp/scap" "{\"conversationId\":\"ccap\",\"transcriptPath\":\"$tmp/tcap.jsonl\",\"toolCall\":{\"id\":\"t2\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"cause-opponent\"}}}")"
check "at once above ceiling falls back to default 1" '[[ "$out1" == *'\''"decision": "allow"'\''* && "$out2" == *'\''"decision": "deny"'\''* ]]'

out_h1="$(run_guard "$tmp/s5" "{\"conversationId\":\"c5\",\"transcriptPath\":\"$tmp/t4.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"intent-opponent\"}}}")"
out_h2="$(run_guard "$tmp/s5" "{\"conversationId\":\"c5\",\"transcriptPath\":\"$tmp/t4.jsonl\",\"toolCall\":{\"id\":\"t2\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"holds-opponent\"}}}")"
check "holds-opponent is denied while another opponent fights" '[[ "$out_h1" == *'\''"decision": "allow"'\''* && "$out_h2" == *'\''"decision": "deny"'\''* && "$out_h2" == *"fights alone"* ]]'

out_h3="$(run_guard "$tmp/s6" "{\"conversationId\":\"c6\",\"transcriptPath\":\"$tmp/t4.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"holds-opponent\"}}}")"
out_h4="$(run_guard "$tmp/s6" "{\"conversationId\":\"c6\",\"transcriptPath\":\"$tmp/t4.jsonl\",\"toolCall\":{\"id\":\"t2\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"intent-opponent\"}}}")"
check "another opponent is denied while holds-opponent fights" '[[ "$out_h3" == *'\''"decision": "allow"'\''* && "$out_h4" == *'\''"decision": "deny"'\''* && "$out_h4" == *"holds-opponent fights alone"* ]]'

cat >"$tmp/t7.jsonl" <<'EOF'
{"type":"GENERIC","content":"at once: 1"}
{"type":"GENERIC","content":"Created the following subagent: {\"conversationId\":\"99999999-2222-3333-4444-555555555555\"}"}
{"type":"GENERIC","content":"Created the following subagent: no id here"}
{"type":"PLANNER_RESPONSE","tool_calls":[{"name":"invoke_subagent","args":{"TypeName":"intent-opponent"}}]}
{"type":"SYSTEM_MESSAGE","content":"Created the following subagent: {\"conversationId\":\"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\"}"}
{"type":"GENERIC","content":"Created the following subagent: {\"conversationId\":\"11111111-2222-3333-4444-555555555555\"}"}
EOF
out_busy="$(run_guard "$tmp/s7" "{\"conversationId\":\"c7\",\"transcriptPath\":\"$tmp/t7.jsonl\",\"toolCall\":{\"id\":\"t2\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"cause-opponent\"}}}")"
check "active opponent in transcript blocks next launch" '[[ "$out_busy" == *'\''"decision": "deny"'\''* && "$out_busy" == *"intent-opponent"* ]]'

cat >>"$tmp/t7.jsonl" <<'EOF'
{"type":"SYSTEM_MESSAGE","content":"Subagent 11111111-2222-3333-4444-555555555555 finished"}
EOF
out_free="$(run_guard "$tmp/s7" "{\"conversationId\":\"c7\",\"transcriptPath\":\"$tmp/t7.jsonl\",\"toolCall\":{\"id\":\"t3\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"cause-opponent\"}}}")"
check "finished opponent frees slot for next opponent" '[[ "$out_free" == *'\''"decision": "allow"'\''* ]]'

out="$(echo 'not json' | PLUGIN_DATA="$tmp/s8" python3 "$hook" 2>/dev/null)"
check "malformed JSON allows cleanly" '[[ "$out" == *'\''"decision": "allow"'\''* ]]'

cat >"$tmp/t_claude.jsonl" <<'EOF'
{"type":"PLANNER_RESPONSE","model":"claude-sonnet-4-5"}
EOF
out_cf="$(run_guard "$tmp/sc1" "{\"conversationId\":\"cc1\",\"transcriptPath\":\"$tmp/t_claude.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\",\"Model\":\"flash\"}}}")"
out_cfl="$(run_guard "$tmp/sc2" "{\"conversationId\":\"cc2\",\"transcriptPath\":\"$tmp/t_claude.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\",\"Model\":\"flash_lite\"}}}")"
out_ci="$(run_guard "$tmp/sc3" "{\"conversationId\":\"cc3\",\"transcriptPath\":\"$tmp/t_claude.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\",\"Model\":\"inherit\"}}}")"
check "Claude parent denies Model=flash" '[[ "$out_cf" == *'\''"decision": "deny"'\''* && "$out_cf" == *"inherit"* && "$out_cf" == *"Nothing was dispatched"* ]]'
check "Claude parent denies Model=flash_lite" '[[ "$out_cfl" == *'\''"decision": "deny"'\''* && "$out_cfl" == *"inherit"* ]]'
check "Claude parent allows Model=inherit" '[[ "$out_ci" == *'\''"decision": "allow"'\''* ]]'

cat >"$tmp/t_gpro.jsonl" <<'EOF'
{"type":"PLANNER_RESPONSE","model":"gemini-2.5-pro"}
EOF
out_gpi="$(run_guard "$tmp/sgp1" "{\"conversationId\":\"cgp1\",\"transcriptPath\":\"$tmp/t_gpro.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\",\"Model\":\"inherit\"}}}")"
out_gpo="$(run_guard "$tmp/sgp2" "{\"conversationId\":\"cgp2\",\"transcriptPath\":\"$tmp/t_gpro.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\"}}}")"
out_gpf="$(run_guard "$tmp/sgp3" "{\"conversationId\":\"cgp3\",\"transcriptPath\":\"$tmp/t_gpro.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\",\"Model\":\"flash\"}}}")"
check "Gemini Pro parent denies Model=inherit" '[[ "$out_gpi" == *'\''"decision": "deny"'\''* && "$out_gpi" == *"flash"* && "$out_gpi" == *"instead of '\''inherit'\''"* && "$out_gpi" == *"Nothing was dispatched"* ]]'
check "Gemini Pro parent denies omitted Model" '[[ "$out_gpo" == *'\''"decision": "deny"'\''* && "$out_gpo" == *"flash_lite"* && "$out_gpo" == *"instead of '\''inherit'\''"* ]]'
check "Gemini Pro parent allows Model=flash" '[[ "$out_gpf" == *'\''"decision": "allow"'\''* ]]'

cat >"$tmp/t_gflash.jsonl" <<'EOF'
{"type":"PLANNER_RESPONSE","model":"gemini-2.5-flash"}
EOF
out_gfi="$(run_guard "$tmp/sgf1" "{\"conversationId\":\"cgf1\",\"transcriptPath\":\"$tmp/t_gflash.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\",\"Model\":\"inherit\"}}}")"
check "Gemini Flash parent allows Model=inherit" '[[ "$out_gfi" == *'\''"decision": "allow"'\''* ]]'

cat >"$tmp/t_switch.jsonl" <<'EOF'
{"type":"PLANNER_RESPONSE","model":"gemini-2.5-pro"}
{"type":"PLANNER_RESPONSE","model":"claude-sonnet-4-5"}
EOF
out_sw="$(run_guard "$tmp/ssw" "{\"conversationId\":\"csw\",\"transcriptPath\":\"$tmp/t_switch.jsonl\",\"toolCall\":{\"id\":\"t1\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"simplicity-opponent\",\"Model\":\"flash\"}}}")"
check "mid-session switch to Claude uses latest model" '[[ "$out_sw" == *'\''"decision": "deny"'\''* && "$out_sw" == *"Claude"* ]]'

cat >"$tmp/t_denied.jsonl" <<'EOF'
{"type":"GENERIC","content":"OK"}
{"type":"GENERIC","content":"at once: 2\nmemory cap: 1.9G"}
{"type":"PLANNER_RESPONSE","tool_calls":[{"id":"c1","name":"invoke_subagent","args":{"TypeName":"holds-opponent"}},{"id":"c2","name":"invoke_subagent","args":{"TypeName":"intent-opponent"}}]}
{"type":"GENERIC","content":"tool call denied by pre-tool hook"}
{"type":"GENERIC","content":"Created the following subagent:\n{\"conversationId\": \"11111111-1111-1111-1111-111111111111\"}"}
EOF
out_den="$(run_guard "$tmp/sden" "{\"conversationId\":\"cden\",\"transcriptPath\":\"$tmp/t_denied.jsonl\",\"toolCall\":{\"id\":\"c3\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"standards-opponent\"}}}")"
check "denied invoke_subagent does not shift subsequent pending opponent types" '[[ "$out_den" == *'\''"decision": "allow"'\''* ]]'

cat >"$tmp/t_cross_turn.jsonl" <<'EOF'
{"type":"GENERIC","content":"at once: 2\nmemory cap: 1.9G"}
{"type":"PLANNER_RESPONSE","tool_calls":[{"id":"c1","name":"invoke_subagent","args":{"TypeName":"holds-opponent"}}]}
{"type":"GENERIC","content":"unexpected failure"}
{"type":"PLANNER_RESPONSE","tool_calls":[{"id":"c2","name":"invoke_subagent","args":{"TypeName":"intent-opponent"}}]}
{"type":"GENERIC","content":"Created the following subagent:\n{\"conversationId\": \"22222222-2222-2222-2222-222222222222\"}"}
EOF
out_ct="$(run_guard "$tmp/sct" "{\"conversationId\":\"cct\",\"transcriptPath\":\"$tmp/t_cross_turn.jsonl\",\"toolCall\":{\"id\":\"c3\",\"name\":\"invoke_subagent\",\"args\":{\"TypeName\":\"standards-opponent\"}}}")"
check "new PLANNER_RESPONSE clears stale uncreated pending opponents" '[[ "$out_ct" == *'\''"decision": "allow"'\''* ]]'

exit "$fails"

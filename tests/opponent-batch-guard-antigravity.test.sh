#!/usr/bin/env bash
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

exit "$fails"

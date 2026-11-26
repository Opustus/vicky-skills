#!/usr/bin/env bash
# shellcheck disable=SC2016 # check() evals its single-quoted condition later
# shellcheck disable=SC2034 # names set here are read inside check()'s eval
# skill-ledger.sh also records Read / read_file calls that open a skill's SKILL.md
# (both grouped and flattened Antigravity layouts), and ignores non-SKILL.md reads.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/plugins/vicky-skills/scripts/skill-ledger.sh"
data=$(mktemp -d); trap 'rm -rf "$data"' EXIT
ledger="$data/skill-ledger.tsv"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
run() { CLAUDE_PLUGIN_OPTION_SKILL_LEDGER=true CLAUDE_PLUGIN_DATA="$data" bash "$hook" <<<"$1"; }

run '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/x/plugins/vicky-skills/skills/captains-log/SKILL.md"}}'
check "flattened Antigravity Read on SKILL.md records skill name" \
  '[ "$(wc -l < "$ledger")" = 1 ] && [ "$(cut -f2 "$ledger")" = "captains-log" ]'

run '{"hook_event_name":"PreToolUse","tool_name":"read_file","tool_input":{"Path":"/x/plugins/vicky-skills/skills/shipping/deathmatch/SKILL.md"}}'
check "grouped read_file on SKILL.md records skill name" \
  '[ "$(wc -l < "$ledger")" = 2 ] && [ "$(tail -1 "$ledger" | cut -f2)" = "deathmatch" ]'

run '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/x/plugins/vicky-skills/skills/shipping/deathmatch/OPPONENT.md"}}'
check "non-SKILL.md read is ignored" '[ "$(wc -l < "$ledger")" = 2 ]'

exit $fail

#!/usr/bin/env bash
# install-antigravity.py flattens skills into skills/<name>/SKILL.md, rewrites
# ${CLAUDE_PLUGIN_ROOT} and ${CLAUDE_PLUGIN_DATA}, copies hooks.json and
# .claude-plugin/plugin.json, and converts agents/*.md to Antigravity format.
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/scripts/install-antigravity.py"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0

check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "ok   $name"; else echo "FAIL $name"; fails=1; fi
}

dest="$tmp/plugins/vicky-skills"
data="$tmp/plugin_data/vicky-skills"
out="$(python3 "$installer" --src "$root" --dest "$dest" --data-dir "$data" 2>&1)"
rc=$?
check "installer exits 0" '[ $rc = 0 ] && [[ "$out" == *"Installed vicky-skills"* ]]'

expected=$(jq '.skills | length' "$root/plugins/vicky-skills/.claude-plugin/plugin.json")
actual=$(find "$dest/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)
check "flattened skill count matches plugin.json" '[ "$expected" = "$actual" ]'

check "valid plugin.json and hooks.json at plugin root" \
  'jq empty "$dest/plugin.json" && jq empty "$dest/hooks.json" && [ -f "$dest/.claude-plugin/plugin.json" ]'

check "no unrewritten CLAUDE_PLUGIN_ROOT or CLAUDE_PLUGIN_DATA in skills" \
  '! grep -rnE "\$\{CLAUDE_PLUGIN_(ROOT|DATA)\}" "$dest/skills"'

check "converted agent has subagent frontmatter and execution footer" \
  'grep -q "^subagent: true$" "$dest/agents/simplicity-opponent.md" && grep -q "WaitMsBeforeAsync: 10000" "$dest/agents/simplicity-opponent.md"'

exit "$fails"

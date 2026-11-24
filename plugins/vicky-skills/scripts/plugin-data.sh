# shellcheck shell=bash
# Sourced by a script an agent runs from its own shell (lesson-ledger,
# a skill's own scripts such as the security kit's).
# Hooks get CLAUDE_PLUGIN_DATA (or PLUGIN_DATA in Antigravity) and the agent's
# shell does not. An installed Claude Code copy sits at
# <plugins>/cache/<marketplace>/<plugin>/<version>(/skills/<group>/<skill>)?/scripts,
# and its data folder is <plugins>/data/<plugin>-<marketplace>. An Antigravity
# copy sits at <gemini>/config/plugins/<plugin>(/skills/<skill>)?/scripts, and
# its data folder is <gemini>/antigravity/plugin_data/<plugin>. Leaves
# CLAUDE_PLUGIN_DATA empty when none of these say where.
if [ -z "${CLAUDE_PLUGIN_DATA:-}" ]; then
  if [ -n "${PLUGIN_DATA:-}" ]; then
    CLAUDE_PLUGIN_DATA="$PLUGIN_DATA"
  else
    here=$(cd "$(dirname "$0")" && pwd)
    if [[ "$here" =~ ^(.*)/cache/([^/]+)/([^/]+)/[^/]+(/skills/[^/]+/[^/]+)?/scripts$ ]]; then
      CLAUDE_PLUGIN_DATA="${BASH_REMATCH[1]}/data/${BASH_REMATCH[3]}-${BASH_REMATCH[2]}"
    elif [[ "$here" =~ ^(.*/\.gemini)/config/plugins/([^/]+)(/skills/[^/]+)?/scripts$ ]]; then
      CLAUDE_PLUGIN_DATA="${BASH_REMATCH[1]}/antigravity/plugin_data/${BASH_REMATCH[2]}"
    fi
  fi
fi

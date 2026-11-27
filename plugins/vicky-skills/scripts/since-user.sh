# shellcheck shell=bash
# Sourced by hooks that ask what happened since the user's last real message
# (publish-guard). Claude Code injects skill text and hook feedback as
# user messages marked isMeta, so those never count as the user speaking.
# Antigravity writes USER_INPUT records wrapping typed text in <USER_REQUEST>.
# last_user_message <transcript> prints the user's last typed message.
_user_text='if .type == "user" and (.isMeta | not) then
    (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end)
  elif .type == "USER_INPUT" then
    ((.content // "") | strings | sub("<ADDITIONAL_METADATA>[\\s\\S]*$"; "") | gsub("</?USER_REQUEST>"; "") | gsub("^\\s+|\\s+$"; ""))
  else "" end'
last_user_message() {
  tail -n 400 "$1" 2>/dev/null | jq -rs "[.[] | ($_user_text) | select(. != \"\")] | last // \"\"" 2>/dev/null
}
# last_user_time <transcript> prints when the user's last typed message was sent, as epoch seconds.
last_user_time() {
  local ts # mutant-ok delete: no caller uses the name ts
  ts=$(tail -n 400 "$1" 2>/dev/null | jq -rs "[.[] | select(($_user_text) != \"\") | (.timestamp // .created_at // empty)] | last // \"\"" 2>/dev/null)
  [ -n "$ts" ] && date -d "$ts" +%s 2>/dev/null
}

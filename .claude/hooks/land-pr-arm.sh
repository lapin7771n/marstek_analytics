#!/bin/bash
# PostToolUse(Bash): after a successful `gh pr create` in marstek_analytics, tell
# Claude to run the land-pr skill so the merge watch gets armed.
set -uo pipefail

input=$(cat)

case "$input" in *"gh pr create"*) ;; *) exit 0 ;; esac

command -v jq >/dev/null 2>&1 || exit 0

# The prefilter also matches when the words only appear in a command's output.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' || exit 0

# `gh pr create` prints the new PR's URL. No URL means it failed.
url=$(printf '%s' "$input" | jq -r '.tool_response | tostring' \
      | grep -oE 'https://github\.com/[^[:space:]"\\]+/pull/[0-9]+' | head -1)
[ -n "$url" ] || exit 0

num=${url##*/}

jq -nc --arg num "$num" --arg url "$url" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("PR #\($num) was just opened (\($url)). Invoke the `land-pr` skill now, for PR #\($num), to arm its merge watch. Do this before replying to the user.")
  },
  systemMessage: ("land-pr: arming merge watch for PR #" + $num)
}'

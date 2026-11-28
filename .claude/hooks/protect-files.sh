#!/usr/bin/env bash
# PreToolUse (Edit|MultiEdit|Write): block edits to protected files.
# Exit 2 = block the tool call; stderr is shown to Claude.
set -u

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
elif command -v python3 >/dev/null 2>&1; then
  file_path="$(printf '%s' "$input" | python3 -c \
    'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))')"
else
  file_path="$(printf '%s' "$input" |
    sed -nE 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')"
fi

[ -z "$file_path" ] && exit 0

case "$(basename "$file_path")" in
  .env | .env.* | *.key | *.pem | firestore.rules | storage.rules)
    echo "ملف محمي، اعرض التعديل على مصطفى بدل تنفيذه ($file_path)" >&2
    exit 2
    ;;
esac

exit 0

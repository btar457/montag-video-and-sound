#!/usr/bin/env bash
# PreToolUse (Bash): block destructive commands.
# Exit 2 = block the tool call; stderr is shown to Claude.
# This is a safety net based on pattern matching, not a sandbox.
set -u

input="$(cat)"

if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
elif command -v python3 >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | python3 -c \
    'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"
else
  cmd="$input"
fi

[ -z "$cmd" ] && exit 0

block() {
  echo "أمر ممنوع: $1" >&2
  echo "إذا كان ضرورياً فعلاً، اشرح السبب لمصطفى ودعه ينفّذه بنفسه." >&2
  exit 2
}

# Split on shell separators so each command is checked on its own.
segments="$(printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\||`|\$\()/\n/g')"

while IFS= read -r seg; do
  # rm with both recursive and force flags (-rf, -fr, -r -f, --recursive --force…)
  if printf '%s' "$seg" | grep -Eq "(^|[[:space:]/\"'(])rm[[:space:]]"; then
    args="$(printf '%s' "$seg" | sed -E "s/.*(^|[[:space:]\/\"'(])rm[[:space:]]+//")"
    if printf '%s' " $args" | grep -Eq '[[:space:]](-[A-Za-z]*[rR][A-Za-z]*|--recursive)([[:space:]]|$)' &&
      printf '%s' " $args" | grep -Eq '[[:space:]](-[A-Za-z]*f[A-Za-z]*|--force)([[:space:]]|$)'; then
      block "rm -rf يحذف الملفات نهائياً بدون تأكيد."
    fi
  fi

  # git push with force (--force, --force-with-lease, -f, or a +refspec)
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]])git[[:space:]].*push([[:space:]]|$)'; then
    if printf '%s' " $seg" | grep -Eq '[[:space:]](--force[A-Za-z=-]*|-[A-Za-z]*f[A-Za-z]*|\+[^[:space:]]+)([[:space:]]|$)'; then
      block "git push --force يعيد كتابة تاريخ الفرع على GitHub وقد يضيّع عمل غيرك."
    fi
  fi

  # Shell writes to protected files (the Edit/Write hook can't see these)
  protected='(AndroidManifest\.xml|firestore\.rules|storage\.rules)'
  if printf '%s' "$seg" | grep -Eq ">[[:space:]]*[^[:space:]]*$protected" ||
    printf '%s' "$seg" | grep -Eq "(^|[[:space:]])(sed|perl)[[:space:]].*-i.*$protected" ||
    printf '%s' "$seg" | grep -Eq "(^|[[:space:]])(tee|mv|cp|rm|truncate|dd)[[:space:]].*$protected"; then
    block "تعديل ملف محمي من الطرفية. اعرض التعديل على مصطفى بدل تنفيذه."
  fi

  # firebase deploy
  if printf '%s' "$seg" | grep -Eq '(^|[[:space:]/])firebase[[:space:]](.*[[:space:]])?deploy([[:space:]]|$)'; then
    block "firebase deploy ينشر على السيرفر الحقيقي مباشرة."
  fi
done <<<"$segments"

exit 0

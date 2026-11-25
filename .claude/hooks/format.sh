#!/usr/bin/env bash
# PostToolUse (Edit|MultiEdit|Write): format Dart code.
# Never fails the session: skips silently if dart is not installed.
cat >/dev/null # consume hook input

command -v dart >/dev/null 2>&1 || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

dirs=()
[ -d lib ] && dirs+=(lib)
[ -d test ] && dirs+=(test)
[ ${#dirs[@]} -eq 0 ] && exit 0

dart format "${dirs[@]}" >/dev/null 2>&1 || true
exit 0

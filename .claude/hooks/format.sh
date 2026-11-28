#!/usr/bin/env bash
# PostToolUse (Edit|MultiEdit|Write): format Python code with ruff.
# Never fails the session: skips silently if ruff is not installed.
cat >/dev/null # consume hook input

command -v ruff >/dev/null 2>&1 || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

dirs=()
[ -d studio ] && dirs+=(studio)
[ -d tests ] && dirs+=(tests)
[ ${#dirs[@]} -eq 0 ] && exit 0

ruff format --quiet "${dirs[@]}" >/dev/null 2>&1 || true
exit 0

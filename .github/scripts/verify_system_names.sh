#!/bin/bash
# USAGE:
# bash .github/scripts/verify_system_names.sh
# Fails if any check emits a system name config.yml does not declare; cState
# treats that mismatch silently and the component never leaves operational.
# A component with no check is reported but not an error (external links).

set -uo pipefail

# comm needs both inputs sorted the same way; don't let the locale decide
export LC_ALL=C

CHECKS_WORKFLOW=".github/workflows/checks.yaml"
CONFIG="config.yml"

for f in "$CHECKS_WORKFLOW" "$CONFIG"; do
  if [ ! -f "$f" ]; then
    echo "error: $f not found. Run this from the repository root." >&2
    exit 2
  fi
done

# Last single-quoted argument of each web_check_and_report.sh invocation;
# backslash continuations are joined first
check_names() {
  awk '{ if (sub(/\\[[:space:]]*$/, "")) { buf = buf $0; next } print buf $0; buf = "" }' "$CHECKS_WORKFLOW" \
    | grep 'web_check_and_report\.sh' \
    | sed -n "s/.*'\([^']*\)'[[:space:]]*\$/\1/p" \
    | sort -u
}

# Component names under `systems:` only, scoped by indentation; `- name:`
# also appears under `categories:`
system_names() {
  awk '
    /^[[:space:]]*systems:[[:space:]]*$/ {
      match($0, /^[[:space:]]*/); sys_indent = RLENGTH
      in_systems = 1
      next
    }
    in_systems {
      if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) next
      match($0, /^[[:space:]]*/)
      if (RLENGTH <= sys_indent) { in_systems = 0; next }
      if ($0 ~ /^[[:space:]]*-[[:space:]]*name:/) {
        sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "")
        sub(/[[:space:]]*$/, "")
        gsub(/^["'"'"']|["'"'"']$/, "")
        print
      }
    }
  ' "$CONFIG" | sort -u
}

CHECKS=$(check_names)
SYSTEMS=$(system_names)

if [ -z "$CHECKS" ]; then
  echo "error: found no check invocations in $CHECKS_WORKFLOW" >&2
  exit 2
fi
if [ -z "$SYSTEMS" ]; then
  echo "error: found no systems under 'systems:' in $CONFIG" >&2
  exit 2
fi

echo "Names emitted by checks ($(echo "$CHECKS" | wc -l | tr -d ' ')):"
echo "$CHECKS" | sed 's/^/  /'
echo
echo "Components declared in config.yml ($(echo "$SYSTEMS" | wc -l | tr -d ' ')):"
echo "$SYSTEMS" | sed 's/^/  /'
echo

STATUS=0

MISSING=$(comm -23 <(echo "$CHECKS") <(echo "$SYSTEMS"))
if [ -n "$MISSING" ]; then
  STATUS=1
  echo "ERROR: these checks report against names config.yml does not declare."
  echo "Incidents they create will never be displayed:"
  echo "$MISSING" | sed 's/^/  /'
  echo
fi

UNCHECKED=$(comm -13 <(echo "$CHECKS") <(echo "$SYSTEMS"))
if [ -n "$UNCHECKED" ]; then
  echo "Note: these components have no check. Expected for external links:"
  echo "$UNCHECKED" | sed 's/^/  /'
  echo
fi

if [ "$STATUS" -eq 0 ]; then
  echo "OK: every check maps to a declared component."
fi
exit "$STATUS"

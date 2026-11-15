#!/usr/bin/env bash
# Runs every headless check in debug/ and prints one PASS/FAIL line each.
# A check that freezes (failed assert in headless Godot) is killed after LIMIT s.
# QA1: a check also FAILS when Godot logged an error while it ran (ERROR, SCRIPT
# ERROR, USER ERROR), even if the check printed PASS. Warnings are counted and
# shown; WARN_FAILS=1 makes them fail too. A check that triggers an error on
# purpose lists it in a line "## QA_EXPECT: <regex>"; matching lines are ignored.
# Exit-time leak notes ("still in use at exit", "leaked at exit") count as warnings.
# Full logs: $LOGS/<check>.log (default /tmp/qa_logs).
# Usage: debug/run_all.sh [godot_binary] [name_filter]
GODOT="${1:-/tmp/godot_bin/Godot_v4.7.2-stable_linux.x86_64}"
FILTER="${2:-}"
LIMIT="${LIMIT:-240}"
LOGS="${LOGS:-/tmp/qa_logs}"
WARN_FAILS="${WARN_FAILS:-0}"
cd "$(dirname "$0")/.." || exit 1
mkdir -p "$LOGS"
EXIT_NOTES='still in use at exit|leaked at exit'
shopt -s nullglob
checks=(debug/verify_*${FILTER}*.gd)
[ ${#checks[@]} -eq 0 ] && { echo "no checks match '$FILTER'"; exit 1; }
fails=0
for f in "${checks[@]}"; do
  name=$(basename "$f" .gd)
  log="$LOGS/$name.log"
  start=$(date +%s)
  timeout "$LIMIT" "$GODOT" --headless --path . -s "$f" > "$log" 2>&1
  code=$?
  secs=$(( $(date +%s) - start ))
  expect=$(grep -oP '^## QA_EXPECT: \K.*' "$f" | paste -sd'|')
  [ -z "$expect" ] && expect='^$NEVER'
  errs=$(grep -E '^(ERROR|SCRIPT ERROR|USER ERROR|USER SCRIPT ERROR):' "$log" | grep -vE "$EXIT_NOTES" | grep -cvE "$expect")
  warns=$(grep -E '^(WARNING|USER WARNING|SCRIPT WARNING|ERROR):' "$log" | grep -E "^(WARNING|USER WARNING|SCRIPT WARNING)|$EXIT_NOTES" | grep -cvE "$expect")
  note=""
  [ "$warns" -gt 0 ] && note="  ($warns warnings)"
  why=""
  if [ $code -eq 124 ]; then why="froze, killed after ${LIMIT}s"
  elif ! grep -q "PASS" "$log" || grep -qE "FAIL" "$log"; then why=$(grep -E 'FAIL|SCRIPT ERROR|Assertion' "$log" | head -1)
  elif [ "$errs" -gt 0 ]; then why="passed but logged $errs errors: $(grep -E '^(ERROR|SCRIPT ERROR|USER ERROR|USER SCRIPT ERROR):' "$log" | grep -vE "$EXIT_NOTES" | grep -vE "$expect" | head -1 | cut -c1-120)"
  elif [ "$WARN_FAILS" = 1 ] && [ "$warns" -gt 0 ]; then why="passed but logged $warns warnings"
  fi
  if [ -z "$why" ]; then
    echo "PASS  ${secs}s  $f$note"
  else
    echo "FAIL  ${secs}s  $f   $why"
    fails=$((fails + 1))
  fi
done
echo "failed: $fails   (logs in $LOGS)"
exit $fails

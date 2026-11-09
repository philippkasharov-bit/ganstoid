#!/usr/bin/env bash
# Runs every headless check in debug/ and prints one PASS/FAIL line each.
# A check that freezes (failed assert in headless Godot) is killed after LIMIT s.
# Usage: debug/run_all.sh [godot_binary] [name_filter]
GODOT="${1:-/tmp/godot_bin/Godot_v4.3-stable_linux.x86_64}"
FILTER="${2:-}"
LIMIT="${LIMIT:-240}"
cd "$(dirname "$0")/.." || exit 1
fails=0
for f in debug/verify_*${FILTER}*.gd; do
  start=$(date +%s)
  out=$(timeout "$LIMIT" "$GODOT" --headless --path . -s "$f" 2>&1)
  secs=$(( $(date +%s) - start ))
  if echo "$out" | grep -q "PASS" && ! echo "$out" | grep -qE "FAIL|SCRIPT ERROR"; then
    echo "PASS  ${secs}s  $f"
  else
    echo "FAIL  ${secs}s  $f   $(echo "$out" | grep -E 'FAIL|SCRIPT ERROR|Assertion' | head -1)"
    fails=$((fails + 1))
  fi
done
echo "failed: $fails"
exit $fails

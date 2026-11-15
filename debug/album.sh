#!/usr/bin/env bash
# QA4 photo album: takes every picture in debug/album.txt (needs xvfb-run),
# then compares them with the approved set in debug/album/ and writes a report.
#   debug/album.sh [godot_binary] [name_filter]      take + compare (filter is a regex: "street|3d_")
#   APPROVE=1 debug/album.sh ...                      also make these the approved pictures
# Output: $ALBUM (default /tmp/qa_album): <name>.png, <name>.log, changed/<name>.png
# (approved | now | difference side by side), report.txt. A picture FAILS when its
# tool crashed, logged an error, or came out blank; CHANGED pictures need a look.
GODOT="${1:-/tmp/godot_bin/Godot_v4.7.2-stable_linux.x86_64}"
FILTER="${2:-}"
ALBUM="${ALBUM:-/tmp/qa_album}"
JOBS="${JOBS:-2}"
LIMIT="${LIMIT:-300}"
cd "$(dirname "$0")/.." || exit 1
command -v xvfb-run >/dev/null || { echo "album needs xvfb-run (a virtual screen)"; exit 1; }
mkdir -p "$ALBUM"
rm -f "$ALBUM"/*.png "$ALBUM"/*.log
export GODOT ALBUM LIMIT
shoot() {
  local name="$1" script="$2" args="$3" out="$ALBUM/$1.png"
  if grep -q 'get_cmdline_user_args()\[0\]' "$script"; then set -- "$out"; else set -- --out="$out" $args; fi
  timeout "$LIMIT" xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
    --path . -s "$script" -- "$@" > "$ALBUM/$name.log" 2>&1
  echo "exit $?" >> "$ALBUM/$name.log"
}
export -f shoot
grep -vE '^\s*(#|$)' debug/album.txt | grep -E "^\s*\S*(${FILTER})" | while IFS='|' read -r name script args; do
  printf '%s\0%s\0%s\0' "$(echo $name)" "$(echo $script)" "$(echo $args)"
done | xargs -0 -r -n3 -P "$JOBS" bash -c 'shoot "$0" "$1" "$2"'
python3 -I tools/qa/album_compare.py debug/album "$ALBUM" ${APPROVE:+--approve}

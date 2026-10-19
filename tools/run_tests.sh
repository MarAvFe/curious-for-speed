#!/usr/bin/env bash
# One command: rebuild assets (budget/geometry/audio asserts), import, compile-check, input/save self-test,
# good+bad bots on every track. Screenshots only run on an invisible display (xvfb-run), never on your screen.
# Usage: tools/run_tests.sh [--no-build] [--no-cars]
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-godot}
declare -a ROWS; FAIL=0
row() { ROWS+=("$(printf '%-24s %-5s %s' "$1" "$2" "$3")"); [ "$2" = PASS ] || [ "$2" = SKIP ] || FAIL=1; }

if [[ " $* " != *" --no-build "* ]]; then
  out=$(python3 tools/build_all.py $([[ " $* " == *" --no-cars "* ]] && echo --no-cars) 2>&1)
  echo "$out" | grep -q "BUILD OK" && row build PASS "budgets, curve radius, loop closure, audio peak/seam" || row build FAIL "$(echo "$out" | tail -3 | tr '\n' ' ')"
fi
$GODOT --headless --path . --import >/dev/null 2>&1 && row import PASS "" || row import FAIL ""
out=$($GODOT --headless --path . -- --check 2>&1 | grep CHECK); [[ $out == *"failed=0"* ]] && row scripts PASS "$out" || row scripts FAIL "$out"
out=$($GODOT --headless --path . -- --test 2>&1 | grep "TEST"); [[ $out == *PASS* ]] && row "input+save+pause" PASS "" || row "input+save+pause" FAIL "$out"
for f in tracks/track_*.json; do
  n=$(basename "$f" .json | cut -d_ -f2)
  for b in good bad; do
    out=$(timeout 600 $GODOT --headless --path . --fixed-fps 60 -- --level=$n --bot=$b --speed=1.0 2>&1)
    res=$(echo "$out" | grep BOT_RESULT | cut -d' ' -f2-)
    errs=$(echo "$out" | grep -c "SCRIPT ERROR")
    [[ $res == *'"ok":true'* && $errs == 0 ]] && row "track $n bot:$b" PASS "$res" || row "track $n bot:$b" FAIL "errors=$errs $res"
    echo "$res" > "docs/bot_track${n}_${b}.json"
  done
  if command -v xvfb-run >/dev/null; then
    timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --rendering-method gl_compatibility --path . -- --level=$n --shots 2>&1 | grep -q SHOTS \
      && row "track $n screenshots" PASS "docs/shots/track_${n}_*.png" || row "track $n screenshots" FAIL ""
  fi
done
command -v xvfb-run >/dev/null || row screenshots SKIP "install xvfb (sudo apt install xvfb) for invisible screenshots"
echo; echo "== curious-for-speed tests =="; printf '%s\n' "${ROWS[@]}"; echo
[ $FAIL = 0 ] && echo "ALL PASS" || echo "SOME FAILED"; exit $FAIL

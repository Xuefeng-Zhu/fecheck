#!/usr/bin/env bash
# Captures real CLI output and renders docs/media/fecheck-demo.mp4 from it.
# Needs out/fecheck (scripts/build.sh), python3 with Pillow, and ffmpeg.
set -uo pipefail
cd "$(dirname "$0")/.."
FE="${FE:-fe}"; BIN="${BIN:-./out/fecheck}"
R=out/rec; mkdir -p "$R" failures docs/media
rm -f failures/permissions.case failures/queue.case
run() { local k=$1; shift; "$@" >"$R/$k.out" 2>&1; echo $? >"$R/$k.rc"; }
run 01 "$FE" --version
run 02 $BIN run permissions --seed 12345
run 03 $BIN replay failures/permissions.case
run 04 $BIN replay failures/permissions.case --against permissions-fixed
run 05 $BIN run queue --seed 12345
run 06 $BIN replay failures/queue.case --against queue-fixed
run 07 "$FE" test examples/contract
cp scripts/render_demo.py "$R/render.py"
python3 "$R/render.py" docs/media/fecheck-demo.mp4

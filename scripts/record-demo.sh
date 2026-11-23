#!/usr/bin/env bash
# Captures real CLI output into out/rec/ and renders docs/media/fecheck-demo.mp4
# from it. Needs out/fecheck (scripts/build.sh), Fe 26.6.0, python3 with
# Pillow, and ffmpeg. Set NO_RENDER=1 to capture only (render later with
# `python3 scripts/render_demo.py docs/media/fecheck-demo.mp4 out/rec`).
# The published video is narrated: `python3 scripts/narrate_demo.py out/rec
# <piper-voice.onnx> docs/media/fecheck-demo.mp4` (see that script).
set -uo pipefail
cd "$(dirname "$0")/.."
FE="${FE:-fe}"; BIN="${BIN:-./out/fecheck}"
R=out/rec; rm -rf "$R"; mkdir -p "$R" failures docs/media
rm -f failures/permissions.case
# Each step: NN.cmd (the command line shown), NN.out (stdout+stderr), NN.rc,
# NN.ms (wall-clock milliseconds).
run() {
    local k=$1; shift
    printf '%s\n' "$*" >"$R/$k.cmd"
    local t0; t0=$(date +%s%N)
    "$@" >"$R/$k.out" 2>&1; echo $? >"$R/$k.rc"
    echo $(( ($(date +%s%N) - t0) / 1000000 )) >"$R/$k.ms"
}
git rev-parse --short HEAD >"$R/sha" 2>/dev/null || true
run 01 "$FE" --version
run 02 "$BIN" run permissions --seed 12345
run 03 head -n 7 failures/permissions.case
run 04 "$BIN" replay failures/permissions.case
run 05 "$BIN" replay failures/permissions.case --against permissions-fixed
run 06 ./scripts/native-to-evm.sh
run 07 "$FE" test examples/erc20 --filter mutant --color never
for f in "$R"/*.rc; do echo "$(basename "$f" .rc): exit $(cat "$f"), $(cat "${f%.rc}.ms") ms"; done
if [ "${NO_RENDER:-0}" != "1" ]; then
    python3 scripts/render_demo.py docs/media/fecheck-demo.mp4 "$R"
fi

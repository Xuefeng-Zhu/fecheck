#!/usr/bin/env bash
# Builds the native `fecheck` executable into out/fecheck.
set -euo pipefail
cd "$(dirname "$0")/.."
FE="${FE:-fe}"
mkdir -p out
"$FE" build cli --out-dir out
mv -f out/fecheck_cli out/fecheck
echo "built out/fecheck"

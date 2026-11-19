#!/usr/bin/env bash
# Proves FeCheck works as a dependency of an ingot outside this repository:
# copies examples/external to a fresh temporary directory, points its
# `fecheck` dependency at this checkout (Fe 26.6 requires a relative path),
# and runs its tests.
set -euo pipefail
cd "$(dirname "$0")/.."
FE="${FE:-fe}"
ROOT="$(pwd)"
DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
cp -r examples/external "$DIR/my_project"
REL="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$ROOT/ingots/fecheck" "$DIR/my_project")"
sed -i.bak "s#^fecheck = .*#fecheck = { path = \"$REL\" }#" "$DIR/my_project/fe.toml"
rm -f "$DIR/my_project/fe.toml.bak"
echo "== external ingot at $DIR/my_project"
grep '^fecheck' "$DIR/my_project/fe.toml"
"$FE" test "$DIR/my_project"

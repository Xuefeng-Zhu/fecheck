#!/usr/bin/env bash
# Runs every FeCheck test suite, builds the CLI, and runs the end-to-end demo.
#
#   FE=fe ./scripts/test.sh
#
# Requires Fe 26.6.0. Native builds need an x86-64 Linux or AArch64 macOS
# host (a Fe 26.6 limitation); on other hosts set SKIP_NATIVE=1 to run only
# the Sonatina (EVM) test suites.
set -euo pipefail
cd "$(dirname "$0")/.."
FE="${FE:-fe}"

echo "== compiler"
"$FE" --version

echo "== fe test (Sonatina / EVM backend)"
for ingot in ingots/fecheck examples/permissions examples/queue examples/contract examples/differential examples/erc20 examples/recipes examples/abi; do
    echo "-- $ingot"
    "$FE" test "$ingot"
done

echo "== FeCheck as a dependency of an ingot outside this repository"
FE="$FE" ./scripts/external-check.sh

echo "== Demo C: EVM contract counterexample, end to end"
FE="$FE" ./scripts/contract-demo.sh

if [ "${SKIP_NATIVE:-0}" = "1" ]; then
    echo "== skipping native suites (SKIP_NATIVE=1)"
    exit 0
fi

# SKIP_NATIVE_TESTS=1 still builds and checks the CLI, for hosts that run an
# x86-64 Fe under qemu-user without binfmt (fe test cannot exec the test binary).
if [ "${SKIP_NATIVE_TESTS:-0}" = "1" ]; then
    echo "== skipping fe test --backend native (SKIP_NATIVE_TESTS=1)"
else
    echo "== fe test --backend native"
    for ingot in ingots/fecheck examples/permissions examples/queue examples/differential examples/differential_deep examples/recipes examples/abi; do
        echo "-- $ingot"
        "$FE" test --backend native "$ingot"
    done
fi

echo "== build CLI"
./scripts/build.sh

echo "== CLI checks"
FE_EVM="$FE" ./scripts/cli-checks.sh

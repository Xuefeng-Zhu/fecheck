#!/usr/bin/env bash
# Find natively, confirm on chain.
#
#   ./scripts/native-to-evm.sh        (needs out/fecheck, fe 26.6.0, python3)
#
# 1. The native CLI searches the registry logic (Demo A) and writes a case.
# 2. The case must be byte-identical to examples/contract/cases/permissions-native.case,
#    and that file to the text embedded in examples/contract/src/native_case.fe.
# 3. `fe test` on the EVM parses the embedded case and replays it against a
#    freshly deployed CachedRegistry (must reproduce) and FixedRegistry
#    (must pass). Both contracts run the same Fe registry functions as the
#    native search.
# 4. For scale, the native CLI then runs 1,000,000 cases against the fixed
#    logic and reports the time.
set -euo pipefail
cd "$(dirname "$0")/.."
FE="${FE:-fe}"
BIN="${BIN:-./out/fecheck}"
CASE=examples/contract/cases/permissions-native.case
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "== 1. native search (fecheck run permissions --seed 12345)"
status=0
$BIN run permissions --seed 12345 --save "$tmp/native.case" >"$tmp/run.txt" || status=$?
if [ "$status" -ne 1 ]; then
    cat "$tmp/run.txt"
    echo "native-to-evm: expected the native search to fail (exit 1), got $status" >&2
    exit 1
fi
grep -E "^(Property failed|Shrunk)" "$tmp/run.txt"

echo "== 2. the native case is the checked-in case, and the embedded one"
cmp "$tmp/native.case" "$CASE"
python3 - "$CASE" examples/contract/src/native_case.fe <<'PY'
import re, sys
case = open(sys.argv[1]).read()
src = open(sys.argv[2]).read()
body = src[src.index("pub fn native_case_text"):]
body = body[:body.index("\n}\n")]
lines = re.findall(r'writeln!\(\s*mut out,\s*"((?:[^"\\]|\\.)*)"', body)
embedded = "".join(l + "\n" for l in lines)
if embedded != case:
    sys.exit("native-to-evm: the case embedded in native_case.fe differs from " + sys.argv[1])
print("identical: native CLI output, " + sys.argv[1] + ", native_case.fe")
PY

echo "== 3. replay on the EVM against deployed contracts"
"$FE" test examples/contract --filter native_case --color never

echo "== 4. native scale: 1,000,000 cases against the fixed logic"
start=$(date +%s)
$BIN run permissions-fixed --seed 1 --cases 1000000 | grep "^Property passed"
end=$(date +%s)
echo "native: 1,000,000 cases in $((end - start)) s"

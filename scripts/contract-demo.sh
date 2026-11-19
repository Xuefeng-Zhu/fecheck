#!/usr/bin/env bash
# Demo C end to end: FeCheck finds, shrinks and replays a permission bug in
# a real Fe contract running in the `fe test` EVM.
#
#   ./scripts/contract-demo.sh            (needs fe 26.6.0 and python3)
#
# It runs `contract_counterexample_report` (examples/contract/src/tests.fe)
# with `--show-logs`. That test searches CachedRegistry with seed 12345,
# deploying a fresh contract for every case and every shrink candidate,
# shrinks the failure, then replays the shrunk transactions against both
# CachedRegistry and FixedRegistry, emitting one event per line of the
# report. This script only decodes those events; every value comes from
# the EVM run. It then runs the checked-in regression tests against both
# contracts.
#
# Exit status: 0 when the bug is found, the shrunk case fails on
# CachedRegistry with the recorded code and passes on FixedRegistry, and
# both regression tests pass; 1 otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."
FE="${FE:-fe}"

log=$(mktemp)
trap 'rm -f "$log"' EXIT
"$FE" test examples/contract --filter contract_counterexample_report --show-logs --color never >"$log" 2>&1 || {
    cat "$log"
    echo "contract-demo: the report test failed" >&2
    exit 1
}

python3 - "$log" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
words = []
for data in re.findall(r"data: 0x([0-9a-f]+) \}", text):
    words.append([int(data[i:i + 64], 16) for i in range(0, len(data), 64)])
if not words:
    print(text)
    sys.exit("contract-demo: no event logs found")

names = {0: "CachedRegistry", 1: "FixedRegistry"}
kinds = {0: "grant", 1: "revoke", 2: "execute"}
codes = {1: "REVOKED_AGENT_EXECUTED", 2: "GRANTED_AGENT_DENIED"}
truth = {0: "false", 1: "true"}

print("FeCheck - EVM contract test (fe test, Sonatina EVM)")
print("Property: a revoked agent can never execute; a granted agent always can")
ok = True
verdicts = {}
current = None
for w in words:
    tag = w[0]
    if tag == 2:
        _, seed, cases_run, failing, orig, shrunk, attempts, code = w
        print(f"Seed {seed}: CachedRegistry failed on case {failing + 1} "
              f"({cases_run - 1} passing cases before it; a fresh deployment each)")
        print(f"Shrunk: {orig} choices -> {shrunk} choices after {attempts} candidates, "
              f"each one a fresh deployment")
    elif tag == 1:
        _, target, step, kind, agent, skipped, expected, actual = w
        if current != target:
            current = target
            print()
            if target == 0:
                print(f"Minimized transaction sequence against {names[target]}:")
            else:
                print(f"The same transactions against {names[target]}:")
        call = f"{kinds[kind]}({agent})"
        if skipped:
            line = f"  {step + 1}. {call:<12} (skipped: precondition false)"
        elif expected == 2:
            line = f"  {step + 1}. {call:<12} -> ok"
        else:
            exp = truth[expected] + ","
            line = f"  {step + 1}. {call:<12} -> expected {exp:<6} got {truth[actual]}"
            if expected != actual:
                line += "   <-- violation"
        print(line)
    elif tag == 3:
        _, target, kind, code = w
        verdicts[target] = (kind, code)
        if kind == 0:
            print(f"Result on {names[target]}: PASS")
        else:
            print(f"Result on {names[target]}: FAIL, code {code} ({codes.get(code, '?')})")

if verdicts.get(0) != (2, 1) or verdicts.get(1, (None,))[0] != 0:
    ok = False
print()
print("Shrunk case fails on CachedRegistry and passes on FixedRegistry:",
      "yes" if ok else "NO")
sys.exit(0 if ok else 1)
PY

echo
echo "Checked-in regression (examples/contract/src/tests.fe), run against both contracts:"
reg=$("$FE" test examples/contract --filter regression_stale_cache --color never 2>&1) || { echo "$reg"; exit 1; }
echo "$reg" | grep -E "PASS|FAIL|test result"
echo "Rerun it yourself: fe test examples/contract --filter regression_stale_cache"

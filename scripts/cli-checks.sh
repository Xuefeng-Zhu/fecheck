#!/usr/bin/env bash
# End-to-end checks of the native CLI: exit codes, determinism, replay, and
# rejection of damaged case files. Run after scripts/build.sh.
#
#   BIN=./out/fecheck FE_EVM=fe ./scripts/cli-checks.sh
#
# FE_EVM is the compiler used to compile the regression test the CLI prints
# (Sonatina backend); set it to "" to skip that check.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="${BIN:-./out/fecheck}"
FE_EVM="${FE_EVM-fe}"
ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

expect() { # expect <code> <description> <command...>
    local want="$1" what="$2"; shift 2
    "$@" >"$TMP/out.txt" 2>&1
    local got=$?
    if [ "$got" = "$want" ]; then
        echo "ok   [$got] $what"
    else
        echo "FAIL [$got, wanted $want] $what"; sed 's/^/     | /' "$TMP/out.txt"; fail=1
    fi
}

expect 0 "list"                               $BIN list
expect 2 "no arguments is a usage error"      $BIN
expect 2 "unknown command"                    $BIN frobnicate
expect 2 "unknown test"                       $BIN run nope
expect 2 "bad --seed"                         $BIN run permissions --seed x
expect 2 "--cases 0 is an invalid config"     $BIN run permissions --cases 0
expect 2 "largest --cases is rejected, not aborted" $BIN run permissions --cases 18446744073709551615
expect 2 "--steps 0 is rejected (no vacuous pass)" $BIN run permissions-fixed --steps 0
expect 2 "--steps above the maximum is rejected"   $BIN run permissions --steps 1001
expect 1 "buggy permissions fail"             $BIN run permissions --seed 12345 --save "$TMP/p.case" --json "$TMP/p.json"
expect 0 "fixed permissions pass"             $BIN run permissions-fixed --seed 12345 --cases 2000
expect 1 "buggy queue fails"                  $BIN run queue --seed 7 --save "$TMP/q.case"
expect 0 "fixed queue passes"                 $BIN run queue-fixed --seed 7 --cases 2000
expect 0 "replay reproduces"                  $BIN replay "$TMP/p.case"
expect 3 "replay against fix passes (exit 3 = fixed)" $BIN replay "$TMP/p.case" --against permissions-fixed
expect 0 "queue replay reproduces"            $BIN replay "$TMP/q.case"
expect 3 "queue replay against fix"           $BIN replay "$TMP/q.case" --against queue-fixed
expect 4 "replay against wrong family"        $BIN replay "$TMP/p.case" --against queue
expect 4 "missing file"                       $BIN replay "$TMP/missing.case"
expect 2 "--save and --json on one path"      $BIN run permissions --seed 12345 --save "$TMP/same" --json "$TMP/same"
expect 6 "unwritable --save is not success"   $BIN run permissions --seed 12345 --save "$TMP/no/such/dir/p.case"

# Determinism: the same seed gives byte-identical output and case files.
$BIN run permissions --seed 777 --save "$TMP/a.case" >"$TMP/a.txt"
$BIN run permissions --seed 777 --save "$TMP/b.case" >"$TMP/b.txt"
sed -i "s#$TMP/[ab].case#CASE#" "$TMP/a.txt" "$TMP/b.txt"
if cmp -s "$TMP/a.case" "$TMP/b.case" && cmp -s "$TMP/a.txt" "$TMP/b.txt"; then
    echo "ok   same seed -> identical report and case file"
else
    echo "FAIL same seed produced different output"; fail=1
fi

# Damaged case files must be rejected, never replayed as a pass.
head -n 5 "$TMP/p.case" > "$TMP/truncated.case"
expect 4 "truncated case file"                $BIN replay "$TMP/truncated.case"
sed 's/^fecheck-case 3/fecheck-case 9/' "$TMP/p.case" > "$TMP/schema.case"
expect 4 "unsupported schema version"         $BIN replay "$TMP/schema.case"
sed 's/^choices \(.*\)/choices \1 x/' "$TMP/p.case" > "$TMP/badnum.case"
expect 4 "non-numeric choice"                 $BIN replay "$TMP/badnum.case"
sed '0,/^op /s/^op .*/op Execute(agent=3)/' "$TMP/p.case" > "$TMP/drift.case"
expect 4 "edited op line is reported as drift" $BIN replay "$TMP/drift.case"
sed 's/^test .*/test some_other_test/' "$TMP/p.case" > "$TMP/unknown.case"
expect 4 "unknown test identifier"            $BIN replay "$TMP/unknown.case"
printf 'not a case file\n' > "$TMP/garbage.case"
expect 4 "garbage file"                       $BIN replay "$TMP/garbage.case"

# The full recorded trace is verified: a missing or extra operation is drift.
awk '/^op /{last=NR} {line[NR]=$0} END{for(i=1;i<=NR;i++) if(i!=last) print line[i]}' "$TMP/p.case" > "$TMP/short.case"
expect 4 "case missing its final operation is drift" $BIN replay "$TMP/short.case"
awk '/^op /{last=$0} /^violation /{print last} {print}' "$TMP/p.case" > "$TMP/extra.case"
expect 4 "case with an extra operation is drift"     $BIN replay "$TMP/extra.case"
# A different failure has its own exit code, distinct from "fixed".
sed 's/^verdict fail [0-9]*/verdict fail 999/' "$TMP/p.case" > "$TMP/other.case"
expect 5 "different failure exits 5, not 3"   $BIN replay "$TMP/other.case"

# Long runs replay with the settings they were found with (was: DRIFT at 40).
expect 1 "41-operation queue failure, --steps 80" $BIN run queue --seed 2388 --steps 80 --no-shrink --save "$TMP/long.case"
if grep -q '^steps 80 12$' "$TMP/long.case" && [ "$(grep -c '^op ' "$TMP/long.case")" = 41 ]; then
    echo "ok   long case records steps 80 and all 41 operations"
else
    echo "FAIL long case settings or length"; fail=1
fi
expect 0 "long case replay reproduces"        $BIN replay "$TMP/long.case"
expect 3 "long case against fixed queue passes" $BIN replay "$TMP/long.case" --against queue-fixed

# Schema-1 files written by FeCheck 0.1.0 (commit ce4c6dd) still replay.
expect 0 "0.1.0 case file reproduces"         $BIN replay tests/fixtures/permissions-0.1.0.case
expect 3 "0.1.0 case file against fix passes" $BIN replay tests/fixtures/permissions-0.1.0.case --against permissions-fixed

# The regression test `run` prints compiles and passes against the fixed
# target, and fails against the buggy one.
if [ -n "$FE_EVM" ]; then
    for t in permissions queue; do
        $BIN run $t --seed 12345 --save "$TMP/snip-$t.case" > "$TMP/snip-$t.txt"
        ing="$TMP/snip-$t"
        mkdir -p "$ing/src"
        rel_fc="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$ROOT/ingots/fecheck" "$ing")"
        rel_ex="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$ROOT/examples/$t" "$ing")"
        printf '[ingot]\nname = "snippet_%s"\nversion = "0.1.0"\n\n[dependencies]\nfecheck = "%s"\n%s = "%s"\n' "$t" "$rel_fc" "$t" "$rel_ex" > "$ing/fe.toml"
        : > "$ing/src/lib.fe"
        sed -n '/^  #\[test\]/,/^  }/p' "$TMP/snip-$t.txt" | sed 's/^  //' > "$ing/src/tests.fe"
        if "$FE_EVM" test "$ing" >"$TMP/out.txt" 2>&1 && grep -q "1 passed; 0 failed" "$TMP/out.txt"; then
            echo "ok   printed $t regression compiles and passes on the fixed target"
        else
            echo "FAIL printed $t regression"; sed 's/^/     | /' "$TMP/out.txt"; fail=1
        fi
        sed -i 's/against_fixed()/against_cached()/; s/against_mod()/against_masked()/' "$ing/src/tests.fe"
        "$FE_EVM" test "$ing" >"$TMP/out.txt" 2>&1
        if grep -q "0 passed; 1 failed" "$TMP/out.txt" && grep -q "^FAIL.*regression_" "$TMP/out.txt"; then
            echo "ok   printed $t regression fails (assertion, not compile error) on the buggy target"
        else
            echo "FAIL printed $t regression on the buggy target"; sed 's/^/     | /' "$TMP/out.txt"; fail=1
        fi
    done
fi

# The JSON trace is valid JSON (checked with python when available).
if command -v python3 >/dev/null; then
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["schemaVersion"]==3 and d["maxSteps"]==40 and len(d["operations"])>0' "$TMP/p.json"; then
        echo "ok   trace JSON parses"
    else
        echo "FAIL trace JSON"; fail=1
    fi
    # `replay --json` describes the replay run, not the recorded one.
    $BIN replay "$TMP/p.case" --against permissions-fixed --json "$TMP/r.json" >/dev/null || true
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["target"]=="permissions-fixed" and d["failure"]["verdict"]=="pass"' "$TMP/r.json"; then
        echo "ok   replay JSON describes the replay (target and verdict)"
    else
        echo "FAIL replay JSON mixes the recorded case with the replay"; sed 's/^/     | /' "$TMP/r.json"; fail=1
    fi
fi

expect 0 "scripted demo"                      $BIN demo --dir "$TMP/demo"

if [ "$fail" = 0 ]; then echo "all CLI checks passed"; fi
exit $fail

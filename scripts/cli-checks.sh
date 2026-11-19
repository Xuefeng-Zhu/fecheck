#!/usr/bin/env bash
# End-to-end checks of the native CLI: exit codes, determinism, replay, and
# rejection of damaged case files. Run after scripts/build.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=./out/fecheck
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
expect 1 "buggy permissions fail"             $BIN run permissions --seed 12345 --save "$TMP/p.case" --json "$TMP/p.json"
expect 0 "fixed permissions pass"             $BIN run permissions-fixed --seed 12345 --cases 2000
expect 1 "buggy queue fails"                  $BIN run queue --seed 7 --save "$TMP/q.case"
expect 0 "fixed queue passes"                 $BIN run queue-fixed --seed 7 --cases 2000
expect 0 "replay reproduces"                  $BIN replay "$TMP/p.case"
expect 3 "replay against fix does not"        $BIN replay "$TMP/p.case" --against permissions-fixed
expect 0 "queue replay reproduces"            $BIN replay "$TMP/q.case"
expect 3 "queue replay against fix"           $BIN replay "$TMP/q.case" --against queue-fixed
expect 4 "replay against wrong family"        $BIN replay "$TMP/p.case" --against queue
expect 4 "missing file"                       $BIN replay "$TMP/missing.case"

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
sed 's/^fecheck-case 1/fecheck-case 9/' "$TMP/p.case" > "$TMP/schema.case"
expect 4 "unsupported schema version"         $BIN replay "$TMP/schema.case"
sed 's/^choices \(.*\)/choices \1 x/' "$TMP/p.case" > "$TMP/badnum.case"
expect 4 "non-numeric choice"                 $BIN replay "$TMP/badnum.case"
sed '0,/^op /s/^op .*/op Execute(agent=3)/' "$TMP/p.case" > "$TMP/drift.case"
expect 4 "edited op line is reported as drift" $BIN replay "$TMP/drift.case"
sed 's/^test .*/test some_other_test/' "$TMP/p.case" > "$TMP/unknown.case"
expect 4 "unknown test identifier"            $BIN replay "$TMP/unknown.case"
printf 'not a case file\n' > "$TMP/garbage.case"
expect 4 "garbage file"                       $BIN replay "$TMP/garbage.case"

# The JSON trace is valid JSON (checked with python when available).
if command -v python3 >/dev/null; then
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["schemaVersion"]==1 and len(d["operations"])>0' "$TMP/p.json"; then
        echo "ok   trace JSON parses"
    else
        echo "FAIL trace JSON"; fail=1
    fi
fi

expect 0 "scripted demo"                      $BIN demo --dir "$TMP/demo"

if [ "$fail" = 0 ]; then echo "all CLI checks passed"; fi
exit $fail

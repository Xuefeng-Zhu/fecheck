# Testing

All results below were produced with `fe 26.6.0 (5b3f96a)` on 2026-11-18
(PST). Raw logs: [evidence/test-run.txt](evidence/test-run.txt),
[evidence/cli-checks.txt](evidence/cli-checks.txt),
[evidence/demo.txt](evidence/demo.txt).

## How to run

```sh
./scripts/test.sh                 # everything; SKIP_NATIVE=1 for EVM-only hosts
fe test ingots/fecheck            # one suite
fe test --backend native ingots/fecheck
./scripts/cli-checks.sh           # after ./scripts/build.sh
for d in ingots/fecheck examples/permissions examples/queue examples/contract cli; do fe fmt --check "$d"; done
```

## Results

| Suite | Sonatina (EVM) | Native |
|---|---|---|
| `ingots/fecheck` (core) | 44 passed, 0 failed | 44 passed, 0 failed |
| `examples/permissions` (Demo A) | 5 passed | 5 passed |
| `examples/queue` (Demo B) | 5 passed | 5 passed |
| `examples/contract` (Demo C) | 2 passed | n/a (EVM contract) |
| `scripts/cli-checks.sh` | | 25 of 25 checks passed |
| `fe fmt --check` (all five ingots) | clean | |

## What the core tests cover (`ingots/fecheck/src/tests_*.fe`)

* **PRNG**: SplitMix64 against reference outputs for seed 0
  (0xE220A8397B1DCDAF, ...), `up_to` bounds including 0 and u64::MAX, seed
  independence.
* **Source**: recording, replay, clamping of out-of-range choices, zero past
  the end, `max_choices` overrun, shortlex order.
* **Generators**: bounds of `uint_in`/`int_in`/`one_of`/`vec_of`, `int_in`
  shrinking toward zero, list length limits.
* **Runner**: `Passed`, `Failed`, `InvalidConfig` (0 cases), `GaveUp` on excessive discards, `Error` kept distinct from `Fail`,
  identical reports for identical seeds, different cases for different seeds.
* **Shrinker**: finds minimal integer counterexamples (e.g. a failure for
  `x > 500000` shrinks to exactly 500001), deletes irrelevant list elements, respects the
  candidate budget and reports attempts/accepted, never switches to a
  different failure code, is deterministic.
* **State machines**: finds and shrinks a seeded counter bug, executes
  commands in order, starts each run from fresh state, skips commands whose
  precondition fails consistently, records traces.
* **Artifacts and replay**: encode/decode round trip, rejection of
  truncated files, unsupported schema, out-of-order keys, bad and overflowing
  numbers, bad verdicts, junk choices, data after `end`, too many choices; replay outcomes
  `Reproduced`, `NoLongerFails`, `DifferentFailure`, `Drift`, and an `Error`
  verdict is never replayed as success.

## Demos (seed 12345, 1000 cases, from `evidence/demo.txt`)

| Demo | Found on case | Original | Shrunk | Candidates / accepted | Replay buggy | Replay fixed |
|---|---|---|---|---|---|---|
| A permissions | 45 | 7 ops (21 choices) | 4 ops (12 choices) | 217 / 2 | reproduced at op 4 | not reproduced |
| B queue | 4 | 20 ops (45 choices) | 8 ops (20 choices) | 358 / 9 | reproduced | not reproduced |
| C contract (300 cases) | asserted in test | | 4 calls (12 choices) | | | fixed contract passes the shrunk case |

The bugs are real code defects, not hard-coded results: Demo A's cache is not
invalidated by `revoke`; Demo B's ring buffer wraps with `& 3` at capacity 3;
Demo C repeats Demo A's defect in contract storage. The fixed versions pass
the same random runs (`permissions-fixed` and `queue-fixed` with 2000 cases)
and the shrunk cases.

## Proving the tests can fail

During development a deliberately failing test (`sanity_must_fail`) was added
and observed to fail under `fe test` before being removed, and every demo has
a test asserting that the buggy implementation **is** caught
(`finds_stale_cache_bug`, `finds_wraparound_bug`,
`contract_bug_is_found_and_shrunk`).

## CLI checks (`scripts/cli-checks.sh`)

Exit codes for usage errors (2), invalid config (2), property failures (1),
passing fixed targets (0), reproduced replays (0), fixed replays (3), and bad
cases (4: wrong family, missing file, truncated, unsupported schema,
non-numeric choice, edited op line (drift), unknown test, garbage);
byte-identical output and case files for repeated seeds; the JSON trace
parses; the scripted demo exits 0.

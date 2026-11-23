# Testing

EVM results for the core and Demos A to C come from a clean clone of commit
`5ede679`, run with `fe 26.6.0 (5b3f96a)` on 2026-11-19 (PST); native results
and Demo D come from GitHub Actions CI on 2026-11-22 (see the note under
Results). Raw logs:
[evidence/test-run.txt](evidence/test-run.txt),
[evidence/cli-checks.txt](evidence/cli-checks.txt),
[evidence/contract-demo.txt](evidence/contract-demo.txt). The 0.1.0 bugs
these changes fix are reproduced against the old binary in
[evidence/before-fix-0.1.0.txt](evidence/before-fix-0.1.0.txt).

## How to run

```sh
./scripts/test.sh                 # everything; SKIP_NATIVE=1 for EVM-only hosts
fe test ingots/fecheck            # one suite
fe test --backend native ingots/fecheck
./scripts/contract-demo.sh        # Demo C end to end
fe test examples/differential     # Demo D on the EVM (and with --backend native)
fe test examples/erc20            # Demo E: CoolCoin against an ERC-20 model
./scripts/external-check.sh       # FeCheck from an ingot outside the repo
./scripts/cli-checks.sh           # after ./scripts/build.sh
for d in ingots/fecheck examples/permissions examples/queue examples/contract examples/differential examples/differential_deep examples/erc20 examples/external cli; do fe fmt --check "$d"; done
```

## Results

| Suite | Sonatina (EVM) | Native |
|---|---|---|
| `ingots/fecheck` (core) | 52 passed, 0 failed | 52 passed, 0 failed (CI) |
| `examples/permissions` (Demo A) | 5 passed | 5 passed (CI) |
| `examples/queue` (Demo B) | 5 passed | 5 passed (CI) |
| `examples/contract` (Demo C: closure, `EffectfulMachine`, hand-written comparison) | 14 passed | n/a (EVM contract) |
| `examples/erc20` (Demo E, 1,000 sequences + mutant check) | 6 passed | n/a (EVM contract) |
| `examples/differential` (Demo D, 110,000 cases) | 29 passed | 29 passed (CI) |
| `examples/differential_deep` (Demo D, 11,000,000 cases) | n/a (exceeds the EVM test gas cap) | 29 passed (CI) |
| `examples/recipes` (eight property patterns) | 10 passed | 10 passed (CI) |
| `examples/external` (copied outside the repo) | 5 passed (CI) | |
| `scripts/contract-demo.sh` | shrunk case fails on Cached, passes on Fixed | |
| `scripts/cli-checks.sh` (native CLI, built from the clone) | | 41 of 41 checks passed |
| `fe fmt --check` (all ten ingots) | clean | |

Native results come from GitHub Actions (`ubuntu-latest`, x86-64), which runs
`./scripts/test.sh` on every push. Run
[45103740959](https://github.com/Xuefeng-Zhu/fecheck/actions/runs/45103740959)
on commit `caa2a56` passed every step: format check, all EVM and native
suites, the external ingot, Demo C and 41 of 41 CLI checks. The raw log is in
`docs/evidence/ci-run-caa2a56.txt`. Demo D was added after that run; its
results come from run
[45105951179](https://github.com/Xuefeng-Zhu/fecheck/actions/runs/45105951179)
(`docs/evidence/ci-run-differential.txt`). The development host was AArch64 Linux,
where Fe 26.6 has no native backend; there the CLI was built with an x86-64 Fe
under qemu-user and the native `fe test` suites were left to CI.

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

41 checks. Exit codes for usage errors and invalid settings (2: no
arguments, unknown command or test, bad `--seed`, `--cases 0`, the largest
`--cases`, `--steps 0`, `--steps 1001`), property failures (1), passing fixed
targets (0), reproduced replays (0), fixed replays (3), different failures
(5) and bad cases (4: wrong family, missing file, truncated, unsupported
schema, non-numeric choice, edited op, missing final op, extra op, unknown
test, garbage). Also: identical output for identical seeds; the 41-operation
queue failure found with `--steps 80` records its settings and all 41 ops,
reproduces, and passes against the fix; a schema-1 file written by 0.1.0
reproduces and passes against the fix; the regression test `run` prints for
each bundled target compiles, passes on the fixed implementation and fails
(by assertion) on the buggy one; JSON export; the scripted demo.

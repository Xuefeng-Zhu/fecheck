# Testing

The final code commit `bae50dc` passed [CI run 45141895706](https://github.com/Xuefeng-Zhu/fecheck/actions/runs/45141895706/job/137581666909) on x86-64 Linux with Fe 26.6.0: every EVM suite, every native suite, all 54 native CLI checks, Demo C and the native-to-EVM replay. Locally on aarch64 Linux, all 181 EVM suite tests passed on both Fe 26.6.0 and Fe 26.7.0 ([26.7 log](evidence/fe-26.7.0.txt)).

The checked-in [EVM test log](evidence/test-run.txt), [CLI log](evidence/cli-checks.txt) and [Demo C log](evidence/contract-demo.txt) are historical runs. The [native timing log](evidence/ci-run-native-to-evm.txt) records 507 ms at `c8acf71`; CI on `bae50dc` measured 525 ms for the same one-million-case workload.

## How to run

```sh
./scripts/test.sh                 # everything; SKIP_NATIVE=1 for EVM-only hosts
fe test ingots/fecheck            # one suite
fe test --backend native ingots/fecheck
./scripts/contract-demo.sh        # Demo C end to end
fe test examples/differential     # Demo D on the EVM (and with --backend native)
fe test examples/erc20            # Demo E: CoolCoin against an ERC-20 model
fe test examples/abi              # Demo F: Fe's Solidity ABI encoder/decoder vs the spec
fe test examples/recipes          # eight property patterns (docs/recipes.md)
./scripts/external-check.sh       # FeCheck from an ingot outside the repo
./scripts/cli-checks.sh           # after ./scripts/build.sh
for d in ingots/fecheck examples/permissions examples/queue examples/contract examples/differential examples/differential_deep examples/erc20 examples/recipes examples/abi examples/external cli; do fe fmt --check "$d"; done
```

## Results at `bae50dc`

| Suite | Sonatina (EVM) | Native |
|---|---|---|
| `ingots/fecheck` (core) | 87 passed, 0 failed | 87 passed, 0 failed (CI) |
| `examples/permissions` (Demo A) | 5 passed | 5 passed (CI) |
| `examples/queue` (Demo B) | 5 passed | 5 passed (CI) |
| `examples/contract` (Demo C: closure, `EffectfulMachine`, hand-written comparison, native case replayed on the `fe test` EVM) | 17 passed | n/a (EVM contract) |
| `examples/erc20` (Demo E, `EffectfulMachine` and closure: 1,000 sequences each + mutant checks) | 13 passed | n/a (EVM contract) |
| `examples/differential` (Demo D, 29 properties + 1 oracle test, 110,000 cases) | 30 passed | 30 passed (CI) |
| `examples/differential_deep` (Demo D, 11,000,000 cases) | n/a (exceeds the EVM test gas cap) | 29 passed (CI) |
| `examples/abi` (Demo F, Solidity ABI vs the spec, 18,000 cases) | 9 passed | 9 passed (CI) |
| `examples/recipes` (eight property patterns) | 10 passed | 10 passed (CI) |
| `examples/external` (copied outside the repo) | 5 passed | |
| `cli` (unit) | | 1 passed (CI) |
| `scripts/contract-demo.sh` | shrunk case fails on Cached, passes on Fixed | |
| `scripts/cli-checks.sh` (native CLI, built from the clone) | | 54 checks passed (CI) |
| `fe fmt --check` (all eleven ingots) | clean | |

AArch64 Linux runs the EVM suites (`SKIP_NATIVE=1`). Native suites and the CLI run on x86-64 Linux and AArch64 macOS.

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
  numbers, bad verdicts, junk choices, non-comment content after `end`, too many choices; replay outcomes
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

With Python and the Fe compiler available, the current CLI script has 54 checks. It covers JSON write errors, equivalent output paths, preservation of the input, maximum case-index formatting, and an emitted test run against a precondition that skips every command. The native CLI unit test also exercises the exit codes for GaveUp and Unstable.

Other CLI checks cover exit codes for usage errors and invalid settings (2: no
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

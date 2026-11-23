# FeCheck

**Find the failure. Shrink the story. Replay the proof.**

FeCheck brings deterministic property-based and state-machine testing to Fe,
turning complex failures into small, reproducible regression cases.

Everything that matters (the PRNG, generators, the property runner, the
state-machine executor, the shrinker, the case-file parser and replay) is
written in Fe and runs inside `fe test` on both the EVM (Sonatina) and native
backends. A small native Fe CLI adds `run`, `replay` and `demo` commands.

Built for the [Fe Builders Challenge 2026](https://fe-lang.org/contest/) with
**Fe 26.6.0**.
Every EVM test suite also passes on Fe 26.7.0
([docs/evidence/fe-26.7.0.txt](docs/evidence/fe-26.7.0.txt)); CI pins 26.6.0.

## What's new here

FeCheck isn't just Hypothesis ported to Fe. Three properties of the design
come from Fe itself:

* **One registry over memory and over contract storage.** Demo A's
  in-memory system and Demo C's contracts call the same Fe functions
  (`permissions::registry_*`), generic over a `Grants` trait: an array
  natively, a `StorageMap` in the contracts. `OnChainPermissions` is Demo A's
  state machine with only the system swapped for a deployed contract. The
  engine doesn't care which: `check` declares `uses F::E`, so it forwards
  whatever effects the test holds (`mut Evm`, a ledger, nothing), and the
  same shrinker drives a pure ring buffer, native code and a deployed
  contract.
* **Counterexamples that mean the same thing on both backends.** A `.case`
  file is plain text, written and parsed by pure Fe that runs (with its
  tests) on Sonatina and native alike. Replay reads the recorded choices, not
  a seed. A case the native CLI writes replays unchanged against a deployed
  contract in the `fe test` EVM (next section).
* **No I/O in the engine, by construction.** `Source`, the generators and
  the case parser declare no effects, and the runner and shrinker declare
  only the test's own (`uses F::E`). Fe has no ambient
  I/O, so the compiler rejects a generator that tries to read a file or a
  clock. That narrows where nondeterminism can come from, but doesn't remove
  it: a test that holds an effect (`mut Evm`, `Fs`) can still behave
  differently from run to run. `check` reruns every failure on its own
  choices before shrinking and checks the final normalized choices again. A
  change in failure kind, code or choice consumption yields `Unstable`.

## Find natively, confirm on the `fe test` EVM

The `fe test` EVM is gas-capped; native code isn't. Demo C's contracts and
Demo A's in-memory system call the same Fe registry functions
(`permissions::registry_*`), so FeCheck can search at native speed and
confirm against deployed contracts in the `fe test` EVM:

1. `fecheck run permissions --seed 12345` (native CLI) fails on case 45,
   shrinks to 4 operations and writes a `.case` file. (The file's `case`
   field is the 0-based index, so it reads `case 44`.)
2. That file is checked in as
   [examples/contract/cases/permissions-native.case](examples/contract/cases/permissions-native.case).
   `fe test` on the EVM has no filesystem effect, so a test can't open it;
   [scripts/embed-case.py](scripts/embed-case.py) generates its lines into
   `native_case_text()` in
   [examples/contract/src/native_case.fe](examples/contract/src/native_case.fe).
3. On the EVM, the test decodes that text with the pure Fe parser and calls
   `replay_machine_with` against freshly deployed contracts: it reproduces
   on `CachedRegistry` (same failure, same step, same `op` lines) and passes
   on `FixedRegistry`.

[scripts/native-to-evm.sh](scripts/native-to-evm.sh) runs all of this in CI
and fails if the native CLI's case differs by a byte from the checked-in
file or the embedded text. It also runs 1,000,000 cases against the fixed
logic natively: 507 ms at `c8acf71` on GitHub's x86-64 runner, process start
included ([docs/evidence/ci-run-native-to-evm.txt](docs/evidence/ci-run-native-to-evm.txt)).

## The headline: a bug in a deployed EVM contract, found and minimized

`CachedRegistry` ([examples/contract/src/lib.fe](examples/contract/src/lib.fe))
is a Fe contract that caches its last authorization decision and forgets to
invalidate it on `revoke`. FeCheck finds that with no hint of the failing
sequence: every generated case and every shrink candidate deploys a fresh
contract into the `fe test` EVM and drives it with real message calls. One
command shows the whole story:

```
$ ./scripts/contract-demo.sh
FeCheck - EVM contract test (fe test, Sonatina EVM)
Property: a revoked agent can never execute; a granted agent always can
Seed 12345: CachedRegistry failed on case 78 (77 passing cases before it; a fresh deployment each)
Shrunk: 24 choices -> 12 choices after 225 candidates, each one a fresh deployment

Minimized transaction sequence against CachedRegistry:
  1. grant(1)     -> ok
  2. execute(1)   -> expected true,  got true
  3. revoke(1)    -> ok
  4. execute(1)   -> expected false, got true   <-- violation
Result on CachedRegistry: FAIL, code 1 (REVOKED_AGENT_EXECUTED)

The same transactions against FixedRegistry:
  1. grant(1)     -> ok
  2. execute(1)   -> expected true,  got true
  3. revoke(1)    -> ok
  4. execute(1)   -> expected false, got false
Result on FixedRegistry: PASS

Shrunk case fails on CachedRegistry and passes on FixedRegistry: yes

Checked-in regression (examples/contract/src/tests.fe), run against both contracts:
PASS  [0.0002s] regression_stale_cache_fails_on_cached_registry
PASS  [0.0001s] regression_stale_cache_passes_on_fixed_registry
test result: ok. 2 passed; 0 failed
Rerun it yourself: fe test examples/contract --filter regression_stale_cache
```

That output is decoded from EVM event logs emitted by
`contract_counterexample_report` in
[examples/contract/src/tests.fe](examples/contract/src/tests.fe); the script
adds no values of its own and exits non-zero unless the shrunk case fails on
`CachedRegistry` and passes on `FixedRegistry`. The checked-in Fe regression
(`STALE_CACHE`, two tests, one per contract) reruns with
`fe test examples/contract --filter regression_stale_cache`.

Five hand-written unit tests for the same contract, including "a revoked
agent cannot execute", all pass on the buggy version: the bug needs an
`execute` before the `revoke`. See
[docs/vs-hand-written.md](docs/vs-hand-written.md).

## Pointed at Fe itself: both backends, 11 million cases

Demos A to C find bugs that were planted for them. Demo D
([docs/differential.md](docs/differential.md)) tests code this project did
not write: Fe 26.6's `core::num` and the compiler's lowering of integer
operators. 29 properties check shifts past the type's width, signed division,
saturation, `wrapping_pow`, narrowing casts, `addmod`/`mulmod`, the 512-bit
`full_mul` and `checked_mul_div`, `isqrt`, `gcd`, bit counts and `swap_bytes`
against Fe references, under each backend. Each backend is
checked against the references; the two backends are not compared with each
other directly.

| Run | Backend | Passing-case target | Result |
|---|---|---|---|
| `fe test examples/differential` | Sonatina EVM | 110,000 | agreed with reference |
| `fe test --backend native examples/differential` | native x86-64 (CI) | 110,000 | agreed with reference |
| `fe test --backend native examples/differential_deep` | native x86-64 (CI) | 11,000,000 | agreed with reference |

No Fe bug turned up. The suite stays in CI as a regression net for the
compiler and the core library, and it is a template for running the same
arithmetic checks on both backends.

## An ERC-20 we didn't write

Demo E ([examples/erc20](examples/erc20)) model-tests CoolCoin, the ERC-20
from the Fe compiler's own test suite, taken with its logic unchanged. Three
`Actor` contracts hold tokens, so `transfer`, `approve` and `transferFrom`
come from three real `msg.sender`s. Each generated sequence (up to 25
transactions, amounts biased to exactly the balance or allowance and one
more) runs on a fresh deployment. After every transaction the return value,
all balances and allowances, and the total supply must match a plain-array
model, and the balances must sum to the total supply.

1,000 sequences pass. The same model catches a one-line mutant
(`transferFrom` that never spends the allowance) and shrinks it to an
allowance mismatch, so the check has teeth.

The test is an `EffectfulMachine`
([examples/erc20/src/machine_tests.fe](examples/erc20/src/machine_tests.fe)):
`type Env = Evm`, a `Deployed` SUT holding the token and actor addresses, and
an invariant that queries the token after every transaction. For the mutant it
shrinks to two transactions, an `approve` and a `transferFrom`. The original
hand-rolled closure stays in `tests.fe` and uses the same choice encoding.

## Fe's Solidity ABI

Demo F ([examples/abi](examples/abi)) checks Fe's ABI encoder and decoder
against the layout in the Solidity ABI specification, computed independently
in the test, across uint8 to uint256, int8 to int256 including MIN and MAX, the
custom widths (uint24, int72, int248 and others), bool, address, `bytes`,
`string`, `uint256[]`, static arrays and return values. 18,000 cases pass on
both backends, so no bug was found. A development experiment changed two
references and observed five failing properties ([docs/abi.md](docs/abi.md)).

## The same idea from the CLI

```
$ ./out/fecheck run permissions --seed 12345
FeCheck - Property Testing for Fe
Test:    revoked_agent_cannot_execute
Target:  permissions
Seed:    12345
Cases:   1000 (up to 40 operations each)

Property failed on case 45 of 1000.
Original: 7 operations (21 choices)
Shrunk:   4 operations (12 choices) after 217 candidates, 2 accepted
Counterexample:
  1. Grant(agent=2)   -> ok
  2. Execute(agent=2)   -> allowed
  3. Revoke(agent=2)   -> ok
  4. Execute(agent=2)   -> expected denied, got allowed   <-- violation
Violation:
  revoked_agent_cannot_execute: an agent without a current grant was allowed to execute
Replay artifact:
  failures/permissions.case
Reproduce with:
  fecheck replay failures/permissions.case
```

`run` then prints a regression test that compiles as-is (see
[below](#turning-a-failure-into-a-regression-test)). Watch the 66-second
recording: [docs/media/fecheck-demo.mp4](docs/media/fecheck-demo.mp4)
(rendered from real CLI output by `scripts/record-demo.sh`; recorded with
0.1.0, before the replay fixes in 0.2.0).

## Why

Example-based tests check the cases you thought of. Bugs like stale caches,
ring-buffer wrap-around or permission races only appear after a particular
*sequence* of operations. Property-based testing (QuickCheck, Hypothesis,
fast-check, proptest) and invariant fuzzing (Foundry, Echidna) find those
sequences automatically. FeCheck brings the same ideas to Fe as a Fe library,
so Fe developers can write the model, the commands and the properties in Fe,
next to the code they test, and run them with `fe test`. See
[docs/architecture.md](docs/architecture.md) for an honest comparison with
those tools.

## What is implemented

| Area | Status |
|---|---|
| Seeded SplitMix64 PRNG, unbiased bounded draws, per-case seeds | done, tested against reference vectors |
| Choice-sequence `Source` (record / replay / budget) | done |
| Generators: `uint_in`, `int_in` (shrinks to 0), `booleans`, `one_of`, `vec_of`, `pair`, custom via the `Gen` trait | done |
| `check(test, Config)` with `Passed` / `Failed` / `InvalidConfig` / `GaveUp` and `Fail` vs `Error` vs `Discard` verdicts | done |
| Shrinker: run deletion, value minimisation (0 then binary search), pair lowering; failure-identity preserving; budgeted; deterministic | done |
| `StateMachine` trait: model, SUT, command generation, preconditions, postconditions, invariants, traces | done |
| `EffectfulMachine` trait: the same, with a SUT that runs under an effect such as `Evm` | done |
| Versioned `.case` regression files (schema 4 records generation settings and a separate execution flag for each operation; reads schemas 1–4), strict parser that also rejects contradictory files | done |
| Replay that verifies the whole recorded trace, with outcomes `Reproduced` / `NoLongerFails` / `DifferentFailure` / `Invalid` / `Drift` | done |
| JSON trace export | done (write-only) |
| Native CLI: `list`, `run`, `replay`, `demo`, documented exit codes (3 = fixed) | done (x86-64 Linux, AArch64 macOS) |
| Demo A: agent permissions with a stale-cache bug | done |
| Demo B: bounded ring-buffer queue with a wrap-around bug | done |
| Demo C: the permission bug in a deployed **EVM contract**, end to end with `scripts/contract-demo.sh` | done |
| Demo D: differential properties for Fe's core arithmetic on both backends (`examples/differential`, native deep run in `examples/differential_deep`) | done, sampled results agreed with their references |
| Demo E: model-based test of the Fe test suite's ERC-20 (CoolCoin) with three holder contracts | done, 1,000 sequences pass; a one-line mutant is caught |
| Demo F: Fe's Solidity ABI encoder/decoder checked against the ABI spec (`examples/abi`) | done, 18,000 cases pass |
| A stand-alone ingot using FeCheck as a dependency, tested from outside the repo | done (`examples/external`, `scripts/external-check.sh`) |
| Web visualisation | not built (deliberately; see limitations) |

The [test results](docs/testing.md) identify the revision and backend for
each run. [CI run 45247761227](https://github.com/Xuefeng-Zhu/fecheck/actions/runs/45247761227)
passed every EVM and native suite and all 54 CLI checks on the last code
change, `36df3c7`; later commits touch documentation only.

## Quick start

Requirements: Fe 26.6.0 and python3 (used by the helper scripts for relative paths
and log decoding). The native CLI needs an x86-64 Linux or AArch64 macOS host
(a Fe 26.6 native-backend restriction); the `fe test` suites run anywhere Fe
runs.

```sh
curl -fsSL https://raw.githubusercontent.com/argotorg/fe/master/feup/feup.sh | bash -s -- --version v26.6.0
export PATH="$HOME/.fe/bin:$PATH"

git clone https://github.com/Xuefeng-Zhu/fecheck.git && cd fecheck
./scripts/contract-demo.sh   # Demo C: EVM contract bug, minimized, replayed on both contracts
./scripts/test.sh            # every suite, the external ingot, the CLI build and the CLI checks
SKIP_NATIVE=1 ./scripts/test.sh  # EVM suites only (Linux AArch64, where native can't run)
./out/fecheck demo           # find -> shrink -> save -> replay -> fixed, twice
```

Individual steps:

```sh
fe test ingots/fecheck                      # core library tests (EVM backend)
fe test --backend native ingots/fecheck     # same, native
fe test examples/contract                   # Demo C: contract under test
./scripts/external-check.sh                 # FeCheck as a dependency of an outside ingot
./scripts/build.sh                          # builds out/fecheck
./out/fecheck run queue --seed 7            # exits 1, writes failures/queue.case
./out/fecheck replay failures/queue.case    # exits 0: reproduced
./out/fecheck replay failures/queue.case --against queue-fixed   # exits 3: fixed
```

### Exit codes

| Code | `run` | `replay` |
|---|---|---|
| 0 | property passed | the recorded failure reproduced |
| 1 | property failed (case file written) | |
| 2 | usage or configuration error (`--cases 0`, `--steps 0`, ...) | usage error |
| 3 | | every recorded operation now passes: **fixed** |
| 4 | | malformed or incompatible case file, invalid case, or drift |
| 5 | | still fails, but differently (kind, code or step) |
| 6 | case or JSON write failed | JSON write failed |
| 7 | too many discarded cases (`GaveUp`) | |
| 8 | failure did not replay exactly (`Unstable`) | |

The library's `Report::exit_code` uses 3 for `GaveUp` and 4 for `Unstable`.
The CLI uses 7 and 8 for these outcomes and writes no case.

Only 3 means "fixed". `fecheck demo` and `scripts/cli-checks.sh` treat any
other replay result as a failure.

## Using FeCheck in your ingot

New to FeCheck? [docs/first-test.md](docs/first-test.md) takes five minutes, and
[docs/recipes.md](docs/recipes.md) has eight property patterns to copy.

[examples/external](examples/external) is a complete stand-alone ingot (a
capped adder and a `Meter` built on it, each with a seeded bug; one property,
one state machine, a pinned regression). `scripts/external-check.sh`
copies it outside this repository and runs it, so the snippets below are
tested. Fe 26.6 needs a relative dependency path:

```toml
[dependencies]
fecheck = { path = "../fecheck/ingots/fecheck" }
```

### A property

From [examples/external/src/tests.fe](examples/external/src/tests.fe):

```fe
use fecheck::{Source, Config, Gen, Verdict, check, ensure, uint_in, choices_from, run_choices}
use ingot::{add_capped, add_capped_buggy}

const CAP: u64 = 1000
const OVER_CAP: u64 = 1

fn capped_property(_ src: mut Source, buggy: bool) -> Verdict {
    let value = uint_in(0, CAP).generate(mut src)
    let n = uint_in(0, 100000).generate(mut src)
    let got = if buggy {
        add_capped_buggy(value, n, CAP)
    } else {
        add_capped(value, n, CAP)
    }
    let want = if value + n > CAP { CAP } else { value + n }
    ensure(got == want, OVER_CAP)
}

#[test]
fn fecheck_finds_and_shrinks_the_buggy_version() {
    let report = check(
        |src: mut Source| capped_property(mut src, buggy: true),
        Config::new(seed: 1, cases: 1000),
    )
    assert!(report.failed())
    // The shrinker reduces this failing input to a small counterexample:
    // value 0, n = CAP + 256.
    assert!(report.shrunk[0] == 0 && report.shrunk[1] == CAP + 256)
}
```

A test is any closure `Fn(mut Source) -> Verdict`. Return `Verdict::Pass`,
`Verdict::Fail { code }` (property violated), `Verdict::Error { code }`
(evaluation failed, e.g. an overflow you detected) or `Verdict::Discard`
(`assume`). The `code` is the failure's identity: the shrinker only accepts
smaller inputs that fail with the same kind and code.

### A state machine

Implement `fecheck::StateMachine` for a struct (see
[examples/queue/src/machine.fe](examples/queue/src/machine.fe), ~170 lines):

```fe
impl StateMachine for MyMachine {
    type Cmd = Cmd        // Copy + Display, e.g. an enum Push { value } / Pop
    type Obs = Obs        // Copy + Eq + Display: what a command visibly returned
    type Model = MemVec<u64>
    type Sut = MyQueue
    fn new_model(self) -> MemVec<u64> { .. }
    fn new_sut(self) -> MyQueue { .. }
    fn gen_cmd(self, _ src: mut Source, _ model: MemVec<u64>) -> Cmd { .. }
    fn precondition(self, _ model: MemVec<u64>, _ cmd: Cmd) -> bool { .. }
    fn run_model(self, _ model: mut MemVec<u64>, _ cmd: Cmd) -> Obs { .. }
    fn run_sut(self, _ sut: mut MyQueue, _ cmd: Cmd) -> Obs { .. }
    fn invariant(self, _ model: MemVec<u64>, _ sut: MyQueue) -> Verdict { .. }
    fn describe_failure(self, _ code: u64, _ out: mut MemBuffer) { .. }
}

#[test]
fn queue_matches_model() {
    let report = check(|src: mut Source| run_steps(MyMachine {}, mut src, steps(40, 12)),
                       Config::new(seed: 2026, cases: 1000))
    assert!(report.passed())
}
```

### Effects: testing a contract

The engine forwards the test's effects (`uses F::E`), so a test can deploy and
call contracts:

```fe
#[test]
fn registry_never_lets_revoked_agents_execute() uses (evm: mut Evm) {
    let report = check(|src: mut Source| registry_case<CachedRegistry>(mut src),
                       Config::new(seed: 12345, cases: 300))
    assert!(report.passed())
}
```

Every case and every shrink candidate deploys a fresh contract
([examples/contract/src/tests.fe](examples/contract/src/tests.fe)).

For a contract with a model, implement `fecheck::EffectfulMachine` instead of
`StateMachine`. It is the same trait with one more associated type, `Env`,
the effect the SUT runs with; `new_sut`, `run_sut` and `invariant` run with
it, and the model stays pure. The engine then does the loop, preconditions,
postconditions and traces for a deployed contract
([examples/contract/src/machine_tests.fe](examples/contract/src/machine_tests.fe)):

```fe
impl EffectfulMachine for RegistryMachine {
    type Sut = Address
    type Env = Evm
    fn new_sut(self) -> Address uses (env: mut Evm) {
        if self.fixed { env.create<FixedRegistry>(value: Wei::zero(), args: ()) }
        else { env.create<CachedRegistry>(value: Wei::zero(), args: ()) }
    }
    fn run_sut(self, _ sut: mut Address, _ cmd: RegCmd) -> u64 uses (env: mut Evm) { .. }
    // Cmd, Obs, Model and the other methods as in StateMachine
}

#[test]
fn cached_registry_breaks_the_model() uses (evm: mut Evm) {
    let report = check(|src: mut Source| run_steps_with(RegistryMachine { fixed: false }, mut src, steps(30, 10)),
                       Config::new(seed: 12345, cases: 300))
    assert!(report.failed())   // grant, execute, revoke, execute
}
```

The closure and `RegistryMachine` share a choice encoding. Their comparison
test supplies a literal choice array, and they use different failure codes.
The file-based contract regression uses `OnChainPermissions`, which shares
Demo A's generator, model and failure codes.

### Turning a failure into a regression test

For either bundled target, `fecheck run` prints a Fe test with the saved case
embedded. The test decodes it, calls `replay_machine` with the fixed
implementation and asserts `ReplayOutcome::NoLongerFails`. Copy the printed
test into an ingot that depends on FeCheck and the target. The same assertion
works for a custom machine with its own decoded case.

For `fecheck run permissions --seed 12345` it prints (case lines shortened):

```fe
#[test]
fn regression_revoked_agent_cannot_execute_seed_12345() {
    var text = core::MemBuffer::new(0)
    writeln!(mut text, "fecheck-case 4")
    // ... the rest of the .case file, one writeln! per line ...
    writeln!(mut text, "op run \"Execute(agent=2)\"")
    writeln!(mut text, "end")
    let case = match fecheck::decode(text.span()) { Result::Ok(c) => c, Result::Err(_) => panic() }
    let (outcome, _) = fecheck::replay_machine(permissions::against_fixed(), fecheck::case_steps(case), case)
    assert!(match outcome { fecheck::ReplayOutcome::NoLongerFails => true, _ => false })
}
```

The test passes only if the fixed machine runs every recorded operation,
with the same text, run/skip status and choice consumption, and none fails.
`scripts/cli-checks.sh` compiles the printed test and checks that it passes
on the fixed implementation and fails on the buggy one.

### Replay guarantees

Schema 4 records the choices, rendered command text, a separate run/skip field
per operation, failure kind and code, failed step and generation settings. A
machine recording must contain choices and finish at an executed failing
operation. The parser rejects contradictory fields and non-comment content
after `end`. Trailing blank and comment lines are allowed.

Both `Reproduced` and `NoLongerFails` require the complete recorded command
sequence and exact operand consumption. Machine replay may stop at EOF between
commands after the final operation. Missing operands, clamped choices, extra
choices and changed command text produce drift. An earlier failure on a
matching prefix is `DifferentFailure`, and a discarded run on a matching
prefix is `Invalid`. Passing properties and properties reproducing the
recorded failure must consume exactly their choices too.

With schema 4, a changed precondition result produces drift even if the
command displays identically. The comparison uses `Display` text and skip
status. The file does not store expected or actual observations, and two
distinct commands can have the same display. Schemas 1 and 2 have only command
text, so earlier skip status is unknown. Replay still requires the failed
operation to execute. Schema 3 used an ambiguous `(skipped) ` prefix. The
parser rejects it on the failed operation and replay treats it as drift
elsewhere.

Re-encoding retains the recorded schema. Schema 1 omits settings. The CLI uses
the historical defaults of 40 operations and mean 12, while library callers
can supply a fallback.

## Repository layout

```
fe.toml                     workspace
ingots/fecheck/src/         the library (all Fe)
  rng.fe                      SplitMix64, unbiased bounded draws, case seeds
  source.fe                   the choice sequence (record, replay, budget, order)
  verdict.fe                  Pass / Discard / Fail / Error
  gen.fe                      Gen trait and generators
  runner.fe                   Config, Report, check
  shrink.fe                   the shrinker
  machine.fe                  StateMachine and EffectfulMachine, executors, traces
  artifact.fe                 .case format: encoder and strict parser
  replay.fe                   replay and outcome classification
  json.fe                     JSON trace export
  tests_*.fe                  88 tests
examples/permissions/       Demo A (library state machine)
examples/queue/             Demo B (state machine + plain properties)
examples/contract/          Demo C (EVM contract via the Evm effect)
examples/erc20/             Demo E (Fe's own ERC-20 fixture vs an ERC-20 model)
examples/recipes/           Eight property patterns from docs/recipes.md
examples/abi/               Demo F (Solidity ABI encode/decode vs the spec)
examples/differential/      Demo D (Fe core arithmetic vs references, both backends)
examples/differential_deep/ Demo D at 100x the case count, native only
cli/                        native `fecheck` executable (Fe)
examples/external/          a stand-alone ingot depending on fecheck
tests/fixtures/             case files written by earlier FeCheck versions
scripts/                    test.sh, build.sh, cli-checks.sh, contract-demo.sh, external-check.sh
.github/workflows/ci.yml    CI: format, every suite, external ingot, CLI checks, demos
docs/                       architecture, compatibility, testing, limitations, submission
```

## Documentation

* [docs/architecture.md](docs/architecture.md): design and comparison with Hypothesis, proptest, fast-check, Foundry and Echidna
* [docs/fe-compatibility.md](docs/fe-compatibility.md): what was verified in Fe 26.6 and how the design adapted
* [docs/first-test.md](docs/first-test.md): your first FeCheck test in five minutes
* [docs/vs-hand-written.md](docs/vs-hand-written.md): the same bug, hand-written tests vs FeCheck
* [docs/recipes.md](docs/recipes.md): eight property patterns, each a tested example
* [docs/abi.md](docs/abi.md): Demo F, Fe's Solidity ABI against the specification
* [docs/differential.md](docs/differential.md): Demo D, Fe's own arithmetic on EVM and native
* [docs/testing.md](docs/testing.md): test inventory and recorded results
* [docs/limitations.md](docs/limitations.md): known limitations and follow-up work
* [docs/submission.md](docs/submission.md): pitch, Fe highlight, AI disclosure

## License

Apache-2.0 (see [LICENSE](LICENSE)). SplitMix64 follows the public-domain
reference by Sebastiano Vigna; the choice-sequence design follows Hypothesis
(MacIver and Donaldson, ECOOP 2020). No code was copied from either.

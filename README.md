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

Watch the 66-second recording: [docs/media/fecheck-demo.mp4](docs/media/fecheck-demo.mp4)
(rendered from real CLI output by `scripts/record-demo.sh`).

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

That output is real (see [docs/testing.md](docs/testing.md) for how to
regenerate it). FeCheck was never told the failing sequence: it found that the
system's decision cache survives a revoke, needs a cache-warming `Execute`
before the `Revoke`, and cut a 7-operation run down to those 4.

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
| Versioned `.case` regression files, strict untrusted-input parser | done |
| Replay with outcomes `Reproduced` / `NoLongerFails` / `DifferentFailure` / `Invalid` / `Drift` | done |
| JSON trace export | done (write-only) |
| Native CLI: `list`, `run`, `replay`, `demo`, CI exit codes | done (x86-64 Linux, AArch64 macOS) |
| Demo A: agent permissions with a stale-cache bug | done |
| Demo B: bounded ring-buffer queue with a wrap-around bug | done |
| Demo C: the permission bug in a deployed **EVM contract**, tested through the `Evm` effect | done |
| Web visualisation | not built (deliberately; see limitations) |

Test evidence: 44 core tests + 5 + 5 + 2 example tests pass on Sonatina, the
core and Demo A/B suites also pass with `--backend native`, and 25 end-to-end
CLI checks pass. See [docs/testing.md](docs/testing.md).

## Quick start

Requirements: Fe 26.6.0. The native CLI needs an x86-64 Linux or AArch64
macOS host (a Fe 26.6 native-backend restriction); the `fe test` suites run
anywhere Fe runs.

```sh
curl -fsSL https://raw.githubusercontent.com/argotorg/fe/master/feup/feup.sh | bash -s -- --version v26.6.0
source ~/.fe/env

git clone <this repo> fecheck && cd fecheck
./scripts/test.sh          # every suite, the CLI build, and the CLI checks
./out/fecheck demo         # find -> shrink -> save -> replay -> fixed, twice
```

Individual steps:

```sh
fe test ingots/fecheck                      # core library tests (EVM backend)
fe test --backend native ingots/fecheck     # same, native
fe test examples/contract                   # Demo C: contract under test
./scripts/build.sh                          # builds out/fecheck
./out/fecheck run queue --seed 7            # exits 1, writes failures/queue.case
./out/fecheck replay failures/queue.case    # exits 0: reproduced
./out/fecheck replay failures/queue.case --against queue-fixed   # exits 3: fixed
```

## Using FeCheck in your ingot (five minutes)

Add the dependency:

```toml
[dependencies]
fecheck = { path = "../fecheck/ingots/fecheck" }
```

### A property

```fe
use fecheck::{Source, Config, Gen, check, ensure, uint_in, vec_of}

#[test]
fn sum_is_order_independent() {
    let report = check(|src: mut Source| {
        let xs = vec_of(uint_in(0, 1000), max_len: 20).generate(mut src)
        ensure(sum_forward(xs) == sum_backward(xs), 1)
    }, Config::new(seed: 1, cases: 500))
    assert!(report.passed())
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

### Turning a failure into a regression test

`fecheck run` prints a paste-ready test containing the shrunk choices:

```fe
#[test]
fn regression_stale_cache_fixed() {
    let choices = fecheck::choices_from([1, 0, 2, 1, 2, 2, 1, 1, 2, 1, 2, 2])
    var src = fecheck::Source::replay(choices, fecheck::DEFAULT_MAX_CHOICES)
    assert!(fecheck::run_steps(against_fixed(), mut src, fecheck::steps(40, 12)).is_pass())
}
```

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
  machine.fe                  StateMachine trait, executor, traces
  artifact.fe                 .case format: encoder and strict parser
  replay.fe                   replay and outcome classification
  json.fe                     JSON trace export
  tests_*.fe                  44 tests
examples/permissions/       Demo A (library state machine)
examples/queue/             Demo B (state machine + plain properties)
examples/contract/          Demo C (EVM contract via the Evm effect)
cli/                        native `fecheck` executable (Fe)
scripts/                    test.sh, build.sh, cli-checks.sh
docs/                       architecture, compatibility, testing, limitations, submission
```

## Documentation

* [docs/architecture.md](docs/architecture.md): design and comparison with Hypothesis, proptest, fast-check, Foundry and Echidna
* [docs/fe-compatibility.md](docs/fe-compatibility.md): what was verified in Fe 26.6 and how the design adapted
* [docs/testing.md](docs/testing.md): test inventory and recorded results
* [docs/limitations.md](docs/limitations.md): known limitations and follow-up work
* [docs/submission.md](docs/submission.md): pitch, Fe highlight, AI disclosure, checklist

## License

Apache-2.0 (see [LICENSE](LICENSE)). SplitMix64 follows the public-domain
reference by Sebastiano Vigna; the choice-sequence design follows Hypothesis
(MacIver and Donaldson, ECOOP 2020). No code was copied from either.

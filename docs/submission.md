# Fe Builders Challenge 2026: submission notes

## Pitch

FeCheck brings deterministic property-based and state-machine testing to Fe,
turning complex failures into small, reproducible regression cases. You write
a model and commands in Fe; FeCheck generates operation sequences, finds a
violation, shrinks it to a short story, saves it as a portable `.case` file,
and replays it after the fix, from `fe test` or a native CLI.

Beyond the planted-bug demos, FeCheck was pointed at code it did not write:
Fe 26.6's own integer arithmetic, checked against independent Fe references
on each backend (29 differential properties, 110,000 cases per backend plus
11 million native, no divergence), Fe's Solidity ABI encoder and decoder
against the spec (18,000 cases, no bug) and the ERC-20 from the Fe compiler's test suite (1,000
model-checked transaction sequences across three holder contracts, no bug;
a one-line mutant is caught).

## Fe-specific highlight

One registry, two worlds. Demo A's in-memory permission system and Demo C's
contracts call the same Fe registry functions, generic over a `Grants`
trait (an array natively, a `StorageMap` in the contract). FeCheck's engine
is generic over the test's effects (`uses F::E`), so the same `check`,
shrinker and replay that test the pure system also drive the deployed
contracts through `uses (evm: mut Evm)`, deploying a fresh contract for
every generated case and shrink candidate, inside plain `fe test`. A case
the native CLI finds replays byte-for-byte against those contracts on the
`fe test` EVM, checked in CI (`scripts/native-to-evm.sh`).

The engine itself declares no concrete effects, and Fe has no ambient I/O,
so no generator, shrinker or parser can read a file or a clock; only the CLI
file declares `Stdout`, `Args` and `Fs`. A test that holds an effect can
still be nondeterministic, which the shrinker checks for.

## What to run

```sh
./scripts/contract-demo.sh   # Demo C: minimized EVM transaction sequence, both contracts
./scripts/native-to-evm.sh   # native CLI finds the case; fe test EVM replays it on deployed contracts
fe test examples/differential                   # Demo D on the EVM
fe test --backend native examples/differential  # Demo D native
fe test examples/erc20       # Demo E: Fe's ERC-20 fixture vs an ERC-20 model
fe test examples/abi         # Demo F: Fe's Solidity ABI encoder/decoder vs the spec
./scripts/test.sh            # all suites, external ingot, CLI build, CLI checks
./out/fecheck demo           # Demo A and B end to end
```

## Required details

* Repository: https://github.com/Xuefeng-Zhu/fecheck
* License: Apache-2.0
* Compiler: `fe 26.6.0 (5b3f96a)`
* Commit SHA: the full SHA given in the submission form
* CI: https://github.com/Xuefeng-Zhu/fecheck/actions (EVM and native suites, Demo C, CLI checks)
* Project manifest: `fe.toml` (workspace) and each ingot's `fe.toml`

## Pre-existing work and reuse

All FeCheck code was written during the contest window (first commit
2026-11-19 UTC), with these exceptions:

* `examples/erc20/src/coolcoin.fe` (Demo E's token under test) is the
  CoolCoin ERC-20 from the Fe compiler's own test fixtures,
  `crates/fe/tests/fixtures/fe_test/erc20.fe` in
  [argotorg/fe](https://github.com/argotorg/fe) at commit 5b3f96a
  (Apache-2.0). Its logic is unchanged; the only edits are `pub` on two
  message types, imports and `fe fmt` layout. It was reused on purpose, as
  code this project did not write. `examples/erc20/src/mutant.fe` is a copy
  with one line removed.
* The `LICENSE` file is the Apache-2.0 text from the official starter
  repository.

Algorithms follow published work, credited in the sources: SplitMix64
(Steele, Lea, Flood 2014; Vigna's public-domain reference) and Hypothesis's
choice-sequence reduction (MacIver, Donaldson 2020). No code was copied from
either.

## AI assistance

FeCheck was built with substantial help from an AI coding agent. I set the
direction, scope and design decisions; the agent read the Fe 26.6 docs and
standard-library sources, drafted the Fe code, tests, scripts and docs, and
compiled and ran everything against the real compiler. I reviewed the code
and can walk through any part of it.

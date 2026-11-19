# Limitations and follow-up work

Living list. Items are honest constraints of the current implementation.

## Shrinking

* Results are **locally minimal**, not globally minimal. Example: the
  permission demo shrinks to `Grant(2), Execute(2), Revoke(2), Execute(2)`
  rather than agent 0, because lowering the agent requires changing four
  choices at once and the value 2 also encodes the `Execute` command kind.
  A Hypothesis-style "lower duplicated values together" pass with smarter
  grouping would fix this.
* No coverage guidance. Generation is purely random within the configured
  distributions; deep bugs that need specific values may be missed where
  Echidna or Foundry would find them.
* The failure identity is (verdict kind, code). Two distinct bugs that share
  a code can be conflated.

## Execution model

* A **native panic cannot be caught** in Fe 26.6, so a SUT that panics (for
  example on checked-arithmetic overflow) aborts the whole run rather than
  being classified as `Error`. Tests should detect such conditions and
  return `Verdict::Error { code }`. On the EVM backend a revert inside an
  `evm.call` likewise aborts the test.
* The `StateMachine` trait methods declare no effects, so a machine whose SUT
  needs an effect (such as `Evm`) is written as a test closure (Demo C)
  rather than a `StateMachine` impl. A trait-level effect parameter is the
  natural follow-up.
* Command observations are compared with `Eq`; there is no generic diffing of
  model and SUT state.

## Tooling

* The native CLI needs an x86-64 Linux or AArch64 macOS host (Fe 26.6
  native backend restriction). `fe test` integration works on every host.
* The CLI knows the bundled demo tests through a static registry. Users
  integrate through `fe test` and the printed regression snippet; there is
  no plug-in mechanism for third-party test binaries.
* `fecheck replay` uses fixed step settings (`steps(40, 12)`) matching
  `fecheck run`'s defaults; a case produced with a different `--steps` value
  still replays (the stop flag ends the sequence) but the setting is not
  recorded in the file.
* JSON is export-only; the `.case` text format is the replayable source of
  truth.
* No web visualiser. It was optional and was skipped in favour of the CLI
  and the tests.
* No example database (Hypothesis-style automatic re-run of past failures);
  regressions are checked in as Fe tests instead.

## Determinism scope

Sequences are stable for the same seed, generator code, configuration and
FeCheck version. Changing a generator (for example the order of command
kinds) changes what recorded choices mean; replay detects this for state
machines through the recorded `op` lines (`Drift`) but cannot for plain
properties, whose inputs are not rendered into the case file.

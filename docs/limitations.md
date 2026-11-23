# Limitations and follow-up work

Living list. Items are honest constraints of the current implementation.

## Shrinking

* Shrinking returns the best case found by its budgeted search. Example: the
  permission demo shrinks to `Grant(2), Execute(2), Revoke(2), Execute(2)`
  rather than agent 0, because lowering the agent requires changing four
  choices at once and the value 2 also encodes the `Execute` command kind.
  A Hypothesis-style "lower duplicated values together" pass with smarter
  grouping could explore more candidates.
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
* A machine whose SUT needs an effect (such as `Evm`) implements
  `EffectfulMachine`, a separate trait from `StateMachine`. One trait with an
  adapter would be cleaner, but Fe 26.6.0 rejects the generic adapter impl
  (error 6-0009, fixed upstream in 26.7.0 by
  [argotorg/fe#2000](https://github.com/argotorg/fe/pull/2000); the compiler behavior is summarized in [fe-compatibility.md](fe-compatibility.md)), so the two executors are kept as
  copies; `effectful_and_pure_engines_agree` compares selected trace fields over 60 seeds. The native CLI replays pure machines only, since it has no EVM; an
  effectful machine replays a `.case` inside `fe test` with
  `replay_machine_with`, which applies the same checks as `replay_machine`
  (examples/contract/src/native_case.fe).
* Command observations are compared with `Eq`; there is no generic diffing of
  model and SUT state.

* The value-lowering pass uses binary search. When failure is non-monotone it can miss a smaller failing value, even with budget left.
* Replay compares commands by their rendered text (`Display`), not
  semantically, and the engine requires `Copy + Display` on commands and
  observations.

## Demos D, E and F

* Demo D (differential) found **no** Fe bug. It covers integer operators and
  `core::num` helpers only, not memory, storage, ABI encoding or control
  flow. Each backend is held to the same Fe reference rather than to the
  other backend's raw output, so a bug shared by the reference and the
  operation (both built on the same primitive) would go unnoticed; the degree of independence varies by property.
* The 11-million-case deep run is native only: the `fe test` EVM caps gas at
  10^9 per test.
* Demo E (ERC-20) runs on the EVM only and found no bug in CoolCoin. Its
  model covers `transfer`, `approve`, `transferFrom`, `mint`, balances,
  allowances and supply for three holders; it does not check events or
  `name`/`symbol`/`decimals`. Each test is capped at 200 sequences by the
  per-test gas limit, so five seeds give the 1,000.
* Demo F (ABI) found no bug. It doesn't check rejection of non-canonical
  input (a revert aborts the test), nested dynamic types, `bytes` longer than
  32, or packed encoding ([abi.md](abi.md)).

## Tooling

* The native CLI needs an x86-64 Linux or AArch64 macOS host (Fe 26.6
  native backend restriction). `fe test` integration works on every host.
* The CLI knows the bundled demo tests through a static registry. Users
  integrate through `fe test` and the printed regression snippet; there is
  no plug-in mechanism for third-party test binaries.
* Case files record the generation settings (`steps <max> <mean>`, since schema
  2) and replay uses them. Schema-1 files from 0.1.0 did not record them and
  use a caller fallback (CLI defaults 40, 12). A different step limit can regenerate the same trace. Drift requires an observable difference.
* Case files store generator choices plus the rendered commands, not typed
  commands. A regression therefore survives only as long as the generator
  maps the same choices to matching displays and execution flags. A semantic change with the same display can escape detection. Saving typed
  commands (a per-machine `Cmd` encoding) is the planned follow-up.
* JSON is export-only; the `.case` text format is the replayable source of
  truth.
* No web visualiser. It was optional and was skipped in favour of the CLI
  and the tests.
* No example database (Hypothesis-style automatic re-run of past failures);
  regressions are checked in as Fe tests instead.

## Determinism scope

Sequences are stable for the same seed, generator code, configuration and
FeCheck version when the callback and initial state are deterministic. Changing a generator (for example the order of command
kinds) changes what recorded choices mean; replay detects this for state
machines through the recorded `op` lines (`Drift`) but cannot for plain
properties, whose inputs are not rendered into the case file.

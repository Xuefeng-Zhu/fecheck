# Fe Builders Challenge 2026: submission notes

## Pitch

FeCheck brings deterministic property-based and state-machine testing to Fe,
turning complex failures into small, reproducible regression cases. You write
a model and commands in Fe; FeCheck generates operation sequences, finds a
violation, shrinks it to a short story, saves it as a portable `.case` file,
and replays it after the fix, from `fe test` or a native CLI.

## Fe-specific highlight

Determinism is enforced by Fe's effect system. The FeCheck core declares no
effects, so the compiler proves no generator, shrinker or replay can touch
the clock, the filesystem or host randomness. The engine is generic over the
test's effects (`uses F::E`), so the very same `check` and shrinker that test
a pure ring buffer also drive a deployed contract through `uses (evm: mut
Evm)`, deploying a fresh contract for every generated case and every shrink
candidate, inside plain `fe test`. Only the CLI file declares `Stdout`,
`Args` and `Fs`.

## What to run

```sh
./scripts/contract-demo.sh   # Demo C: minimized EVM transaction sequence, both contracts
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

None. All code was written during the contest window (first commit
2026-11-19 UTC). The `LICENSE` file is the Apache-2.0 text from the official
starter repository. Algorithms follow published work, credited in the
sources: SplitMix64 (Steele, Lea, Flood 2014; Vigna's public-domain
reference) and Hypothesis's choice-sequence reduction (MacIver, Donaldson
2020). No code was copied from either.

## AI assistance

FeCheck was built with substantial help from an AI coding agent. I set the
direction, scope and design decisions; the agent read the Fe 26.6 docs and
standard-library sources, drafted the Fe code, tests, scripts and docs, and
compiled and ran everything against the real compiler. I reviewed the code
and can walk through any part of it.

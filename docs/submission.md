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

* Repository: https://github.com/Xuefeng-Zhu/fecheck (private until the owner makes it public)
* License: Apache-2.0
* Compiler: `fe 26.6.0 (5b3f96a)`
* Commit SHA: see `git rev-parse HEAD` (recorded in the final handoff)
* Project manifest: `fe.toml` (workspace) and each ingot's `fe.toml`

## Pre-existing work and reuse

None. All code was written during the contest window (first commit
2026-11-19 UTC). The `LICENSE` file is the Apache-2.0 text from the official
starter repository. Algorithms follow published work, credited in the
sources: SplitMix64 (Steele, Lea, Flood 2014; Vigna's public-domain
reference) and Hypothesis's choice-sequence reduction (MacIver, Donaldson
2020). No code was copied from either.

## AI assistance

This project was built with substantial AI assistance (an AI coding agent
operating in a sandbox under the entrant's direction). The agent read the Fe
26.6 documentation and standard-library sources, wrote the Fe code, tests,
scripts and documentation, and compiled and ran everything against the real
compiler. The entrant is the responsible human contact and should review the
code before submission so they can explain it to the judges, as the contest
rules require.

## Readiness checklist

| Item | Status | Evidence |
|---|---|---|
| Core in compiling Fe | yes | `ingots/fecheck`, `fe test` passes on Sonatina and native |
| Property exercised on generated input | yes | `tests_core.fe` |
| Genuine failure detected | yes | Demos A, B, C find their bugs from random seeds |
| Failure shrunk | yes | 7 -> 4 ops (permissions), 20 -> 8 ops (queue) at seed 12345 |
| Deterministic replay | yes | `cli-checks.sh` determinism and replay checks |
| Fixed implementation no longer reproduces | yes | replay `--against permissions-fixed` / `queue-fixed` exit 3; checked-in regression tests |
| Two independent examples | yes (three) | permissions, queue, contract |
| Automated tests pass | yes | `docs/testing.md`, `docs/evidence/test-run.txt` |
| Documented, verified commands | yes | README, `scripts/` |
| OSI license and disclosures | yes | `LICENSE`, this file |
| README explains scope and gaps | yes | README, `docs/limitations.md` |
| No credentials needed | yes | |
| Registration (closed 2026-11-17 23:59 UTC) | **unknown: entrant must confirm** | |
| Public repository and submission form | **not done: needs the entrant** | |

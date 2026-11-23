# FeCheck vs hand-written tests

The same bug, tested both ways. Everything below is real code in
`examples/contract` and runs in CI.

## The bug

`CachedRegistry` remembers its last `execute` decision to save a storage
read. `grant` invalidates that cache; `revoke` does not. A revoked agent
can still execute, but only if an `execute` for that agent filled the cache
before the `revoke`.

## Five hand-written tests

[examples/contract/src/handwritten_tests.fe](../examples/contract/src/handwritten_tests.fe)
holds the tests a careful developer would write first. They run against the
buggy contract.

| Test | Sequence | Result on the buggy contract |
|---|---|---|
| granted agent can execute | grant(1), execute(1) | passes |
| unknown agent cannot execute | execute(1) | passes |
| **revoked agent cannot execute** | grant(1), revoke(1), execute(1) | **passes: bug missed** |
| revoke is per agent | grant(1), grant(2), revoke(1), execute(1), execute(2) | passes |
| re-grant restores access | grant(1), revoke(1), grant(1), execute(1) x2 | passes |

All five pass. The third test targets exactly the property that is broken,
and it still passes, because the `grant` just before the `revoke` left the
cache invalid. Hand-written tests check the sequences their author thought
of. This bug lives in a sequence nobody writes first.

## The FeCheck test

[examples/contract/src/machine_tests.fe](../examples/contract/src/machine_tests.fe)
describes the registry once, as an `EffectfulMachine`: the commands, a
four-bit model of who is granted, and a precondition that only an existing
grant can be revoked. The test itself is one call:

```fe
let report = check(|src: mut Source| run_steps_with(RegistryMachine { fixed: false }, mut src, steps(30, 10)),
                   Config::new(seed: 12345, cases: 300))
```

With seed 12345 it fails on case 78, after 77 passing random sequences, each
against a freshly deployed contract. It then shrinks the 24-choice failure to
12 choices in 225 candidates and reports:

```
1. grant(1)     -> ok
2. execute(1)   -> expected true,  got true
3. revoke(1)    -> ok
4. execute(1)   -> expected false, got true   <-- violation
```

The same four transactions pass on `FixedRegistry`. The sequence is checked
in as a regression test (`regression_stale_cache_*`), and as a sixth
hand-written test, `hand_the_sequence_fecheck_found`, written only after
FeCheck showed it.

## Side by side

| | Hand-written | FeCheck |
|---|---|---|
| Found the stale-cache bug | no (5 of 5 pass on the buggy contract) | yes, case 78 of seed 12345 |
| Sequences checked per run | 5, fixed | 300 random sequences of up to 30 transactions |
| Failure report | the assert that failed | the shortest sequence, with expected and actual per step |
| Reproduce | rerun the test | the same seed, or the 12-choice case as a regression test |
| Code | about 65 lines | about 130 lines for the machine, plus a few for the test |
| A new command (say, `pause`) | new tests for each interaction you think of | one enum variant, one model rule; every interleaving is generated |

## Where hand-written tests still win

* **Cost.** The machine is about twice the code of five unit tests. For a
  contract with two or three independent functions, unit tests are cheaper.
* **Exact scenarios.** A known exploit, a specific upgrade path or a
  regression is best pinned as a plain test, which is what FeCheck's
  regression output produces.
* **The model is code too.** A wrong model gives false alarms, and a model
  that copies the contract's logic repeats its bugs. FeCheck finds sequences
  you didn't think of, not properties you didn't write.

The two work together: write the machine once, and turn each failure it finds
into a hand-written regression test.

# Your first FeCheck test, in five minutes

[`examples/external`](../examples/external) is a complete stand-alone ingot:
a capped adder, a `Meter` built on it, one property, one state machine, and a
pinned regression. Each has a seeded bug. `scripts/external-check.sh` copies
it outside this repository and runs it in CI, so every step below is tested.

## 1. Install Fe 26.6 and get FeCheck

```sh
curl -fsSL https://raw.githubusercontent.com/argotorg/fe/master/feup/feup.sh | bash -s -- --version v26.6.0
git clone https://github.com/Xuefeng-Zhu/fecheck.git
cp -r fecheck/examples/external my_project
```

## 2. Point your ingot at FeCheck

In `my_project/fe.toml`. Fe 26.6 needs a relative path:

```toml
[dependencies]
fecheck = { path = "../fecheck/ingots/fecheck" }
```

## 3. Run it

```sh
fe test my_project
```

```
PASS  add_capped_never_exceeds_the_cap
PASS  fecheck_finds_and_shrinks_the_buggy_version
PASS  regression_add_capped_wraps
PASS  fecheck_finds_the_buggy_meter
PASS  meter_matches_its_model
```

All five pass: two check the correct code, and the other three confirm that
FeCheck catches the buggy versions.

## 4. Write a property

A property is a function from a `Source` to a `Verdict`. Draw inputs from
generators, call your code, and `ensure` what must hold
([tests.fe](../examples/external/src/tests.fe)):

```fe
fn capped_property(_ src: mut Source, buggy: bool) -> Verdict {
    let value = uint_in(0, CAP).generate(mut src)
    let n = uint_in(0, 100000).generate(mut src)
    let got = if buggy { add_capped_buggy(value, n, CAP) } else { add_capped(value, n, CAP) }
    let want = if value + n > CAP { CAP } else { value + n }
    ensure(got == want, OVER_CAP)
}

#[test]
fn add_capped_never_exceeds_the_cap() {
    let report = check(|src: mut Source| capped_property(mut src, buggy: false),
                       Config::new(seed: 1, cases: 1000))
    assert!(report.passed())
}
```

Switch `buggy: false` to `buggy: true` and the test fails. `report.shrunk`
holds the shrunk choices: `[0, 1256]`, so value 0 and n 1256, the
first input past the cap plus 255.

## 5. Pin the failure as a regression test

Replay those choices with `run_choices`. The result fails on the buggy
version and passes on the fixed one:

```fe
#[test]
fn regression_add_capped_wraps() {
    let fixed = run_choices(|src: mut Source| capped_property(mut src, buggy: false),
                            choices_from([0, 1256]), 4096)
    assert!(fixed.0.is_pass() && fixed.1.len() == 2)
}
```

`run_choices` also returns the choices the test actually read. Checking
that both were read keeps the pin honest: if the generator later stops
reading the saved operand, the regression goes red instead of passing on
something else.

## 6. Test something stateful

For code with state, copy [machine.fe](../examples/external/src/machine.fe)
(about 130 lines). It holds a model (the spec), the real `Meter`, the commands
(`Add`, `Read`, `Reset`), and an invariant. FeCheck generates command
sequences, compares every result with the model, and shrinks a failing
sequence:

```fe
#[test]
fn meter_matches_its_model() {
    let report = check(
        |src: mut Source| run_steps(MeterMachine { buggy: false }, mut src, steps(20, 6)),
        Config::new(seed: 7, cases: 300),
    )
    assert!(report.passed())
}
```

To test a contract, implement `EffectfulMachine` instead: the same methods,
plus `type Env = Evm`, with `new_sut` and `run_sut` declared
`uses (env: mut Evm)`. Run it with `run_steps_with` from a test that
`uses (evm: mut Evm)`; each case deploys a fresh contract. See
`examples/contract/src/machine_tests.fe`.

## 7. Run it in CI

```yaml
- run: curl -fsSL https://raw.githubusercontent.com/argotorg/fe/master/feup/feup.sh | bash -s -- --version v26.6.0 --no-modify-path
- run: echo "$HOME/.fe/bin" >> "$GITHUB_PATH"
- run: fe test my_project
```

A fixed seed reproduces the generated choices with the same code and configuration. Reproducing the verdict also requires consistent callback behavior and initial state.

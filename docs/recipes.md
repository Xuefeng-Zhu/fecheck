# Property recipes

Eight patterns that cover most properties worth writing, each as a test you
can copy. Every snippet comes from
[examples/recipes/src/tests.fe](../examples/recipes/src/tests.fe), which CI
runs on both backends. The functions under test are in
[examples/recipes/src/lib.fe](../examples/recipes/src/lib.fe).

Every property is a closure `|src: mut Source| -> Verdict`. Draw values from
generators, then return `ensure(condition, code)`. `check` runs it on many
inputs and shrinks the first failure.

## 1. Round trip

For an encoder and a decoder: decoding what you encoded gives back the input.

```fe
let x = uint_in(0, MAX).generate(mut src)
ensure(from_be(to_be(x)) == x, 1)
```

Against `from_be_buggy`, which drops the top byte, FeCheck fails and shrinks
to `x = 2^56`, the smallest input with a top byte.

**Use for** ABI encoding, serialization, compression, packing structs into
storage words.

## 2. Oracle

A fast or clever implementation agrees with a slow, obvious one.

```fe
let x = uint_in(0, MAX).generate(mut src)
ensure(popcount_fast(x) == popcount_slow(x), 1)
```

Against a version that never counts bit 63, it shrinks to exactly
`0x8000000000000000`. Demo D uses this recipe at scale, testing Fe's own
arithmetic against independent references
([differential.md](differential.md)).

**Use for** gas-optimised rewrites, assembly-style tricks, a new version
against the old one.

## 3. Idempotence

Doing it twice is the same as doing it once.

```fe
let x = uint_in(0, 1000).generate(mut src)
let (lo, hi) = pair(uint_in(0, 500), uint_in(500, 1000)).generate(mut src)
let once = clamp(x, lo, hi)
ensure(clamp(once, lo, hi) == once && once >= lo && once <= hi, 1)
```

**Use for** normalisation, clamping, rounding, "set" operations, upgrades
that should be safe to replay.

## 4. Bounds as the specification

You may not know the answer, but you know what it must satisfy.

```fe
let n = uint_in(0, 1000000000000).generate(mut src)
let r = isqrt(n)
ensure(r * r <= n && (r + 1) * (r + 1) > n, 1)
```

**Use for** square roots, division and rounding direction, price and share
calculations ("never pays out more than deposited").

## 5. Metamorphic

Relate two runs instead of predicting one.

```fe
let a = uint_in(0, 1000000000000).generate(mut src)
let b = uint_in(0, 1000000000000).generate(mut src)
if a <= b { ensure(isqrt(a) <= isqrt(b), 1) } else { ensure(isqrt(b) <= isqrt(a), 1) }
```

**Use for** monotonicity (more collateral never lowers the borrow limit),
symmetry, scaling.

## 6. Invariant over a sequence

Apply a generated list of operations and check something after each one.

```fe
let cap = uint_in(1, 1000).generate(mut src)
let xs = vec_of(uint_in(0, 2000), max_len: 30).generate(mut src)
var total: u64 = 0
var i: usize = 0
while i < xs.len() {
    let next = add_capped(total, xs[i], cap)
    if next > cap || next < total { return Verdict::Fail { code: 1 } }
    total = next
    i += 1
}
Verdict::Pass
```

When the operations have different kinds and a model is worth keeping, move
up to a `StateMachine` (Demos A and B), or an `EffectfulMachine` for a
deployed contract (Demo C, [vs-hand-written.md](vs-hand-written.md)). Demo E
does this for an ERC-20: balances sum to the total supply after every
transaction.

**Use for** caps, supply conservation, access control, queue and buffer
bounds.

## 7. Preconditions with `assume`

Discard inputs the property does not cover. Discards are counted, and a test
that discards too much gives up instead of passing.

```fe
let a = uint_in(0, 1000).generate(mut src)
let b = uint_in(0, 10).generate(mut src)
let ok = assume(b != 0)
if !ok.is_pass() { return ok }
ensure((a / b) * b + a % b == a, 1)
```

Prefer generating valid inputs directly (`uint_in(1, 10)`) when you can;
`assume` is for conditions that are hard to generate.

## 8. Pin the failure

Once FeCheck finds a bug, replay its shrunk choices in a plain test so the
fix stays fixed.

```fe
var src = Source::replay(choices_from([0x8000000000000000]), 4096)
let x = uint_in(0, MAX).generate(mut src)
assert!(popcount_fast(x) == popcount_slow(x))
```

For state machines, `fecheck run` prints this test for you, with the steps
setting filled in.

## Picking failure codes

`ensure(condition, code)` takes a code. Give each property in a test its own
code. The shrinker only accepts smaller inputs that fail with the same code,
so separate codes stop it from trading one bug for another while shrinking.

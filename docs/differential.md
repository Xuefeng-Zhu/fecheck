# Demo D: differential testing of Fe's own arithmetic

Demos A to C find bugs that were planted for them. Demo D points FeCheck at
code this project did not write: Fe 26.6's core library (`core::num`) and the
compiler's lowering of integer operators, on both backends.

Each property draws inputs and compares the Fe operation with a Fe reference on the same backend. Examples include bit-by-bit long division for u256 division and shift-and-add for multiplication. Each backend compiles both sides. A mismatch within a backend fails the property and FeCheck tries to shrink the input. Shared errors in the operation and reference can go undetected, and these tests do not compare raw outputs across backends.

Inputs are edge-biased: small values, powers of two, one below a power of
two, values near the maximum, and full random words. Shift amounts run past
the type's width (up to 300 bits, or 255 for `u8`), because that is where
EVM (`SHL` yields 0) and native instruction sets (which mask the count)
naturally disagree.

A development mutation of the `u8` reference mask from `0xff` to `0x7f` made `shl_u8_agrees` fail.

## Result

**The tested operations agreed with their references on the sampled inputs.** As of commit `36df3c7` (CI run [45247761227](https://github.com/Xuefeng-Zhu/fecheck/actions/runs/45247761227)):

| Run | Backend | Properties | Configured passing cases |
|---|---|---|---|
| `examples/differential` | Sonatina EVM | 29 | 110,000 |
| `examples/differential` | native (x86-64, CI) | 29 | 110,000 |
| `examples/differential_deep` | native (x86-64, CI) | 29 | 11,000,000 |

The deep run is native only: the `fe test` EVM caps gas at 10^9 per test,
which the 256-step references exceed at those counts. It uses a different
seed (20261124). Logs: `docs/evidence/ci-run-differential.txt`.

A negative result is still a result: Fe 26.6's shift, division, saturation,
narrowing and 512-bit helpers agree with their definitions on both backends
across the cases above. The suite stays in CI as a regression net for the
compiler and the core library.

## The properties (`examples/differential/src/lib.fe`)

| Property | Operation under test | Reference |
|---|---|---|
| `shl_u8`, `shr_u8` | `u8 <<`, `u8 >>`, shift 0 to 255 | u64 shift and mask; 0 once shift >= 8 |
| `shl_u32_matches` | `u32 <<`, shift 0 to 100 | u256 shift masked to 32 bits |
| `shl_u64`, `shr_u64` | `u64 <<`, `u64 >>`, shift 0 to 300 | u256 shift and mask |
| `shift_u128_matches` | `u128 <<` and `>>`, shift 0 to 300 | u256 shift masked to 128 bits |
| `shl_u256` | `u256 <<`, shift 0 to 300 | repeated doubling |
| `sar_i8`, `sar_i64_matches` | arithmetic `>>` on i8 and i64 | repeated floor halving (ends at 0 or -1) |
| `wrapping_u8` | `wrapping_add`, `wrapping_sub`, `wrapping_mul` on u8 | arithmetic mod 256 in u64 |
| `saturating_u64` | `saturating_add`, `_sub`, `_mul` on u64 | exact result in u256, clamped |
| `saturating_i64_matches` | `saturating_add`, `_sub`, `_mul` on i64 | exact result in i256, clamped |
| `pow_u64_matches` | `wrapping_pow` on u64, exponent 0 to 70 | repeated multiplication mod 2^64 in u256 |
| `div_i64_matches` | i64 `/` and `%` | sign-magnitude division on u64 |
| `div_i128_matches` | i128 `/` and `%` | long division of the magnitudes |
| `div_u256_matches` | u256 `/` and `%` | restoring long division (no `/`, no `%`) |
| `mul_u256_matches` | u256 `wrapping_mul` | shift-and-add |
| `addmod_matches` | `core::num::addmod` | reduce, then add without overflow |
| `mulmod_matches` | `core::num::mulmod` | double-and-add over the bits |
| `full_mul_matches` | `core::num::full_mul` (512-bit product) | schoolbook on 128-bit halves |
| `mul_div_matches` | `core::num::checked_mul_div` (Remco Bloemen's muldiv) | 512-bit long division; `None` on zero or overflow |
| `isqrt_matches` | `core::num::isqrt` | z*z <= x < (z+1)^2 |
| `gcd_matches` | `core::num::gcd` (Euclid) | Stein's binary gcd |
| `clz_u256_matches`, `ctz_u256_matches`, `clz_u64_matches` | `leading_zeros`, `trailing_zeros` | bit-scanning loops |
| `swap_u64_matches` | `swap_bytes` | byte loop |
| `downcast_u256_matches`, `downcast_i256_matches` | `downcast`, `downcast_saturate`, `downcast_truncate` to u8 and i8 | range checks on the 256-bit word |

Inputs that would panic by design (division by zero, `MIN / -1`) are
discarded. The runner counts passing cases toward its target, so generated attempts can exceed the configured totals.

## Running it

```sh
fe test examples/differential                         # EVM, 110,000 cases
fe test --backend native examples/differential        # native, 110,000 cases
fe test --backend native examples/differential_deep   # native, 11,000,000 cases
```

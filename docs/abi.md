# Demo F: Fe's Solidity ABI against the specification

Every contract call in Fe goes through `core::abi` and `std::abi`. Demo F
([examples/abi](../examples/abi)) checks the Solidity encoder and decoder
against the layout the ABI specification gives, computed by hand in the test
from plain u256 arithmetic, and checks that each encoding decodes back to the
original values.

| Property | Types | Checks |
|---|---|---|
| `uints` | uint8, 16, 32, 64, 128, 256 | one zero-extended word each; decodes back |
| `ints` | int8, 16, 32, 64 | two's complement over 256 bits; decodes back |
| `wide_ints` | int128, int256 including MIN and MAX | the same, at the extremes |
| `custom_widths` | uint24, uint160, uint248, int24, int72, int136, int248 (`std::abi::sol` wrappers) | canonical word; decodes back |
| `bool_and_address` | bool, address | 0 or 1; the 160 address bits zero-extended |
| `dynamic_bytes` | (uint8, bytes, uint16, string), lengths 0 to 32 | head offsets, length words, left-aligned zero-padded data, total size; decodes back |
| `dynamic_array` | (uint256[], uint256), lengths 0 to 5 | offset 0x40, length, elements, total size; decodes back |
| `fixed_array` | (uint16[3], int32) | the static array inline; decodes back |
| `return_values` | `returns (bytes)` and `returns (uint256)` | the 0x20 offset word for a single dynamic return, none for a static one; `decode_output` back |

Values are edge-biased: 0, 1, the maximum and one below it, the top bit
alone and random words cut to width. Int72, Int136 and Int248 use sign-extended i64 samples, so their own width extrema are outside the sampled range. Several properties compare selected words and round-trip values. The uint tuple, dynamic bytes and array tuples, fixed array and static return also check total encoded length.

## Result

**No bug found.** 2,000 cases per property (18,000 in total) pass on the
Sonatina EVM backend and natively in CI.

During development, changing the negative sign-extension and byte-padding references was reported to make five of the nine properties fail. The checked-in suite runs the original references. There is no automated reproduction of that mutation experiment.

## Not covered

* Rejection of non-canonical input (dirty high bits, a bool word of 2, an
  offset past the end). Fe's decoder reverts on these, and a revert aborts
  the whole test in `fe test`, so it can't be classified per case. Fe's own
  suite covers these with `#[test(should_revert)]`.
* Nested dynamic types (`bytes[]`, `string[2]`, structs holding them) and
  `bytes` longer than 32.
* Packed encoding (`abi.encodePacked`).

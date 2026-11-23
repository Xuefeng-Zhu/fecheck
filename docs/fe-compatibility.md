# Fe 26.6 compatibility findings

Compiler: `fe 26.6.0 (5b3f96a)`, installed with
`feup.sh --version v26.6.0`. Everything below was verified by compiling and
running code, not by reading docs.

## Environment

| Check | Result |
|---|---|
| `fe test` (Sonatina/EVM) on AArch64 Linux | works |
| `fe build --backend native` on AArch64 Linux | **rejected**: "native executable and library output currently require an x86-64 Linux or AArch64 macOS host" |
| Native on x86-64 Linux | works (verified with the official `fe_linux_amd64` binary under qemu-user on the dev machine, and is the CI target on `ubuntu-latest`) |
| Native `fe test` | works; test stdout is shown only for failing tests |

Development note: the authoring machine was AArch64 Linux, so native builds
were produced with the x86-64 release binary under `qemu-user` + binfmt and
an `x86_64-linux-gnu-gcc` linker. Reviewers on x86-64 Linux or Apple Silicon
need none of that.

## Language and library behaviour that shaped the design

| Finding | Consequence |
|---|---|
| Closures implement `Fn` and can be passed to generic functions (`F: Fn(mut Source) -> Verdict`), and generic callers forward the closure's effects with `uses F::E`. | A test is a closure; `check`/`shrink`/`replay` are generic over it and work with `Evm`-using tests. |
| Closures capture by copy or move and cannot mutate captures; capturing a non-`Copy` value by view is rejected. | Machines are small `Copy` structs; the engine threads all state through parameters. |
| Traits with associated types (`type Cmd: Copy + Display`) and generic impls (`impl<S: PermissionApi + Copy> StateMachine for PermissionMachine<S>`) work. | `StateMachine` uses associated types; demos test two implementations through one generic machine. |
| A trait method's effect can be typed by an associated type (`fn run_sut(..) uses (env: mut Self::Env)`), and a generic caller supplies it with `uses (env: mut M::Env)`. In 26.6.0, a generic impl with a bounded parameter (`impl<P: Pure> Tr for Adapt<P>`) of such a trait is rejected with 6-0009 "stricter bounds"; the unbounded form and 26.7.0 (after argotorg/fe#2000) accept it. | `EffectfulMachine` is its own trait with its own executor instead of an adapter over `StateMachine`. |
| `#[arithmetic(unchecked)]` on a function gives wrapping u64 arithmetic. | SplitMix64 is written directly; default checked arithmetic is kept everywhere else. |
| `as` casts must be lossless on every target: `usize -> u64` and `u64 -> usize` are rejected (EVM `usize` is 256-bit, wasm 32-bit). | `len64()` and `downcast_saturate()` helpers. |
| Labelled parameters: an argument must carry the parameter's label unless the parameter is declared `_` (a variable with the same name counts). | Public API uses `_` for positional arguments and labels for config-like ones (`max_len:`). |
| Enum struct-variant fields need `pub` to be matched from another module. | All public enums declare `pub` fields. |
| `MemVec<T>` has no `Clone`; values move. The access checker rejects reading a place while a `mut` access to it is open. | Explicit `copy_choices`; candidates are built before the `mut` call. |
| `String<N>` holds at most 31 bytes; longer literals need `DynString`. | Long test inputs use `DynString`. |
| `format!`, `write!`, `writeln!` and `std::io::Display` work on every target, including the EVM. | Traces and case files are rendered in the pure core and tested on Sonatina. |
| `Option<T>` supports `==`; `MemSpan` has `lines`, `split`, `trim`, `index_of`, `starts_with`; `core::text::parse_uint` returns `Option<u256>`. | The case parser is written with these; it adds its own digit and overflow checks. |
| `Result` is `Result<E, T>` (error first). | Used as such in `decode`. |
| `unwrap()` on a `Result` whose error is not ABI-encodable is rejected on the EVM ("panic value without revert data"). | Tests match and call `panic()`. |
| A native panic cannot be caught. | Properties report failures as `Verdict` values; an uncaught panic in a SUT aborts the run (see limitations). |
| Native `pub fn main() -> i32 uses (out: mut Stdout, args: Args, fs: mut Fs)` works; `target = "native"` in `[ingot]` selects the backend. | The CLI is a native Fe program. |
| `fe test` on the workspace root tries to compile the native CLI ingot for the host; on hosts without native support that member fails. | `scripts/test.sh` tests ingots individually. |
| `evm.create<C>(value:, args:)` deploys a fresh contract each call. | Demo C deploys per case and per shrink candidate. |

## Simplifications made

* No `Gen::shrink` method; all shrinking is on choices.
* Observations are compared with `Eq` and rendered with `Display`; no generic
  serialization of `Model` or `Sut` values.
* The CLI registry is a static `match` over test names (Fe has no dynamic
  loading); library users run FeCheck through `fe test` instead.
* JSON is export-only; the replayable format is the line-based `.case`
  text, which is simpler to parse safely in Fe.

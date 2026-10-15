# Native compiler (`DQ_COMPILER=native`) issues

Measured 2026-10-14 on `tools/native-compiler` (dmb/takeover 6c8827a9b7 merged with origin/master e375b00e38), Windows, 64 GB,
other lanes running (timings are noisy). Logs and outputs are under `E:/dq-cache/native-land-eval/`. Native was run with
`DQ_COMPILER_STRICT=1` throughout, so no DreamMaker fallback hid a failure.

Rule applied: anything DreamMaker accepts, dmbc must accept. Items 1-3 were compiler gaps that master's tree hit; they are fixed in
this branch. Items marked OPEN are not.

## Timings (same tree, `deepquarry.test.dme` unless noted)

| Case | DreamMaker | Native |
|---|---|---|
| Cold compile, test dme | 139-162 s (`Total time` 2:19 / 2:42) | 118 s, 142 s (daemon cold start) |
| Cold compile, production dme (`build.sh dm`) | 166 s | 96 s |
| Unchanged rebuild, test dme (`dm-warm`/`nat-warm`) | 139 s (DreamMaker has no incremental path) | 42 s (input preparation 20.6 s, compilation 12.6 s) |
| After one proc-body edit | n/a (full compile) | 63 s (input preparation 32.6 s, compilation 16.8 s) |
| Peak memory | `dm` 721 MB | `dmbc` daemon 10.1-10.6 GB working set |
| Focused tests (4 ordinary tests) | 4 passed, world 80 s | 4 passed, world 115-121 s |

`doc/testing.md` promises about 1.3 s unchanged and about 20 s after a proc edit. Neither was reached (issue 9).

## Fixed in this branch

1. **`#ifdef` inside macro-call arguments (blocking, fixed).** `code/modules/metrics/metrics_api.dm:69` (`METRICS_EVENT(... list(` with
   `#ifdef UNIT_TESTS` inside) failed with `missing ) in macro call`; DreamMaker accepts it. Repro: that file, or the two tests below.
   Cause: `logical_arena::plan()` finishes the pending logical line at any `#` line, so the call was split and its first half
   never closed. Fix: a line whose macro call is still open is held and joined with the following active lines, on both
   preprocessor paths (`project_context.rs` and `regions/expansion.rs::expand_region`); a call still open at a `#define`/`#undef`/
   `#include`, the end of the segment or 256 lines falls back to the old per-line diagnostic. Tests:
   `directive_inside_open_macro_call_*`, `open_macro_call_never_closed_*` in `lib_tests_1.rs` and `regions/tests.rs`. Cache keys
   bumped (`CACHE_FORMAT_VERSION` 10, `EXPANSION_VERSION` 4). Known limit: all output lines of a joined call carry the first
   line's source line number.
2. **`/mob/living/carbon/human/var/var/pale = 0` (fixed, DM typo).** DreamMaker accepts the stray `var`; dmbc reports
   `body_clock.dm:83 pale: undefined type: /var`. Source corrected to `var/pale`. Compiler mismatch: dmbc should either accept
   it or warn like DreamMaker (OPEN as a mismatch; severity low).
3. **`callee.src` / `callee.usr` unsupported (fixed).** `code/engine/kernel/safe.dm:28` (`frame?.src`) failed with
   `unsupported semantic query: variable storage (owner=/callee, name=src)`. Repro: `E:/dq-cache/native-land-eval/probe/p.dm`.
   Cause: `engine_catalog.rs::names("/callee")` listed only `proc`, `name`, `caller`. Added `src`, `usr`; catalog schema bumped to
   v9. Verified only by compiling the probe and the full tree; there is no runtime test of `safe_call` through a native build.
4. **`build.sh dmbc` fails while a daemon runs (fixed).** `failed to remove file ...\dmbc.exe: Access is denied` (log
   `native-land-eval/dmbc2.log`). The resident daemon is `dmbc.exe` itself. `DmbcTarget` now renames the old binary aside
   (`dmbc.exe.old-<ms>`), which Windows allows, and sweeps older aside copies that are no longer in use.

## Open

5. **Output not equivalent to DreamMaker's (high until triaged).** `dmb-equiv out-dm/deepquarry.dmb out-native/deepquarry.dmb`
   (full production tree, logs `equiv.log`, `equiv-nodebug.log`): NOT EQUIVALENT, 218,558 differences, 144,843 with
   `--ignore-debug`. Categories:
   - Benign or order-only: `proc.debug_info` 73,715 (native always emits debug lines, DreamMaker emitted none here; this is also
     why the native `.dmb` is 75.2 MB against 53.0 MB), `order.proc_table` 69,755, `order.type_table` 37,397,
     `order.var_name_strings` 15,730 (the user's decision of 2026-10-14 treats ordering as non-semantic; the checker still counts
     it, so `--strict-order` should not be the gate).
   - Probably benign, needs a rule in the checker: bytecode where native does not constant-fold (`PushVal 1.0 PushVal 2.0 Bor` vs
     `PushVal 3.0`, `GetVar null-ref` vs `PushVal null` 7,705, `Jz` vs `GetFlag` 1,120), 16,000 procs in `proc.bytecode`;
     `proc.extra` 2,855 and `type.type_meta` 2,800 (per-type `<init>` procs where DreamMaker shares one); `map_objects` 91 (inline
     var sets instead of a shared `<init>`); `type_appearance` 59 (`icon_state`/`name`/`text` `null` vs `""`);
     `proc_locals` 86 (native keeps one more local, e.g. `/atom/vv_edit_var`); `proc_args` 50.
   - Possibly real: `type.type_mob` 9 (`mob sight`: DreamMaker 164 vs native 128 on `/mob/living/simple_mob/mechanical/mecha/combat/
     marauder*`, 132 vs 128 on `xeno_ch*`); `header.header` (native says `min compatibility v515 468`, DreamMaker `v516 516`, so a
     native build admits clients DreamMaker's would refuse); `header.header_flags` (`0x21e0050d` vs `0x21e2050d`);
     `proc.missing` 6 anonymous procs present only in DreamMaker's output.
   Repro: build `build.sh dm` with and without `DQ_COMPILER=native` (delete `deepquarry.dmb/.rsc` between, see issue 8), copy both,
   run `tools/dmb/target/release/dmb-equiv A.dmb B.dmb [--ignore-debug]`. The branch's earlier "dmb-equiv clean" claim was for a
   smaller tree.
6. **dmbc daemon memory (high).** The daemon sits at 9.7-10.6 GB working set after one build (`dmbd` soft private limit 8 GB, hard
   12 GB, `E:/dq-cache/dmb-daemon/lifecycle.log`), and `dmbc` peaked at 9.1-10.6 GB in every cold build. Two such daemons
   (e.g. a rebuilt binary) would not fit beside a normal lane load. The daemon exited by itself after roughly ten idle minutes
   in one observation; after a binary change the old one is not told to exit.
7. **Warm and edit rebuilds far slower than documented (medium).** See the table: 42 s unchanged, 63 s after an edit, dominated by
   `native input preparation` (re-preparing 6,998 paths, 20-33 s) every time. The focused-test flow derives a fresh
   `deepquarry.test.dme` each run, which may be defeating the reuse; not confirmed. Machine load from other lanes inflates all
   numbers.
8. **DreamMaker treats native output as up to date (medium).** After `DQ_COMPILER=native build.sh dm`, a plain `build.sh dm`
   finished in 15 s without compiling and left the native `deepquarry.dmb` in place (same byte size). Lanes that switch
   `DQ_COMPILER` in one worktree get the other compiler's output silently. Workaround used: delete `deepquarry.dmb/.rsc`.
9. **Warnings differ (medium).** `build.sh dm`: DreamMaker 87 warnings, native 70; test dme: DreamMaker 107, native 86. Anything
   gated on warnings-as-errors or `-ignore-warning` behaves differently.
10. **Console noise (low).** About 750 `frontend ...` and `native procedure lowering ...` progress lines per build reach the
    console (58 KB for one build, `native-land-eval/nat-cold2.log`); `--progress` is passed unconditionally.
11. **Failing Rust unit tests on the branch tip (medium).** `cargo test -p dmbc --no-fail-fast`: 32 failed, 972 passed
    (`cargo-test-dmbc2.log`); with the `/callee` change reverted, 32 failed as well (`cargo-test-dmbc-base.log`) and the failing
    sets differ between runs by a few tests, so they are partly flaky. Example: `cli::tests::first_argument_error_and_existing_messages_are_preserved`
    expects `expected analyze or compile` and gets `expected analyze, compile or prepare-query`.
    `cargo test -p dm-codegen-byond`: 11 failed, 364 passed (`cargo-test-dmbc.log`), e.g.
    `simple::tests::control_flow_1::switch_cases_compare_a_single_evaluated_selector`. Not caused by this branch's edits;
    `cargo test -p dm-preprocess`: 146 passed, 0 failed.
12. **Merge hazard (low, tooling).** `git rm` of a crate leaves empty directories (`tools/dmb/crates/dm-compiler/src`); cargo's
    `crates/*` workspace glob then fails with "failed to read .../Cargo.toml". `tools/dmb` must be made exactly the takeover tree
    after a merge with master's old `tools/dmb`.
13. **`unit_test.dm` / `error_handler.dm` coupling (low).** The native build tooling needs the runtime-event and inventory hooks in
    `code/modules/unit_tests/unit_test.dm`; they merge-conflict with every master change to that file. They were re-applied by
    hand onto master's version (E0 tier and `want_e0` kept).
14. **Removed.** The old `dmb-check` target and `DQ_DMB_PRECHECK` (crate `dm-compile` no longer exists in `tools/dmb`) and
    `tools/dmb/precheck_known.txt`.

## Status 2026-10-14 (tools/native-fix)

- **Item 5 header and sight: fixed.** Mob sight: DreamMaker keeps the low seven sight bits in the compact byte beside the `0x80`
  extension marker (SEE_MOBS with see_in_dark is `0x84`); `mob_writer::apply_settings` wrote a bare `0x80` and the fixture tests
  compared only the decoded bits. They now compare the raw byte. Header: dmbc never computed `min compatibility`; it kept the
  engine template's `v514 468` plus two world-setting cases, so DeepQuarry came out `v515 468` against DreamMaker's `v516 516`.
  `dm_ir::header_compat` now prices opcodes (alist, sin/cos/tan, trunc, ...) and built-in variables per procedure and per class
  default; a unit tied to its own version (`a.pixel_z`) makes the build equal the version. Production now prints `v516 516`.
  Of 776 captured fixtures with a DreamMaker header, 625 match and 10 differ (141 do not compile natively); the remaining
  differences are pair interactions among 500-511 features and `src.x` spelling, not modelled. The `/atom` type path literal was
  tagged 9 (317 sites); DreamMaker tags it 10. `dmb-equiv` reports ordering separately (not counted without `--strict-order`),
  masks the debug header bit with `--ignore-debug` and treats `GetVar null` as `PushVal null`. Production residual against a
  same-source DreamMaker build: 218,558 -> 15,091 (bytecode 9,141: constant folding and dead constant branches DreamMaker
  removes, `Jz` against `GetFlag`, fused range iterators, receiver caching; `<init>` sharing 2,855 + 2,800; map objects 91;
  extra temporaries 86; image subtype `name`/`text` and authored `icon_state = ""` null against empty string 59; argument
  value-source owner names 50; anonymous procs 6; verb order 3). Open: the null/empty string defaults and `world.name`
  (DreamMaker uses the project name, native keeps the template's).
- **Item 8 cross-compiler staleness: fixed.** `build.sh dm` records the compiler that wrote the pair in `<project>.dmb.compiler`;
  the byond target only treats the pair as up to date when the stamp says byond.

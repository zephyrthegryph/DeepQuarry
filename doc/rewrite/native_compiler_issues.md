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

## Status 2026-10-15 (tools/native-default: native is the default)

**Default.** `DQ_COMPILER` unset now means native (when a `dmbc` binary exists or cargo can build one, else DreamMaker). `dreammaker`
(alias `byond`) is the fallback, `shadow` compares the two. `build.sh dm`, `dm-test`, `dq_focused_test.sh`, `dq_merge_gates.sh`,
`dq_lane_ready.sh` and `dq_push_master.sh` all go through that selection, so they compile natively. CI's production compile check
(`tools/ci/compile_and_run.sh`) and the benchmark workflow pin `DQ_COMPILER=dreammaker` as the cross-check. `DmbcTarget` now restores
`dmbc`/`dmbd` from a shared content-addressed cache (`E:/dq-cache/dmbc`, `DQ_DMBC_CACHE`, `lib/dmbc_cache.ts`) keyed by the git ids of
`tools/dmb`, so a fresh worktree copies the executables instead of running a 3-5 minute cargo build and keeping its own `target/`.

**Equivalence against DreamMaker** (production dme, same source, `dmb-equiv --ignore-debug`, A = DreamMaker, B = native). Residual
133,256 differences; 123,837 of them order-only and not semantic (proc table 70,694, type table 37,396, var-name strings 15,747, per
the 2026-10-14 decision). The rest: bytecode 9,075, `<init>` sharing 99 + 79 + 70 (anonymous procedures), locals 86, map objects 6,
verb order 3, argument flags 1. Triage:
- **Fixed: `mob/T = null as mob in list` argument flags.** DreamMaker adds the `null` input bit (0x80) when an annotated formal with an
  `in` source defaults to null (`/datum/game_mode/malfunction/verb/unlock_cyborg`: 0x81 against native 0x1). Native now matches
  (`procedure_abi.rs`). Without it the verb prompt would not offer the null choice.
- **Fixed in the checker: verb list order.** Three types (`caught_soul`, `silicon`, `pai`) list the same verbs in another order; the
  client verb panel sorts them, so `dmb-equiv` compares the verb list as a set. Lengths and members still must match.
- **Not behavioural (inspected, left):** bytecode where native does not fold constants or remove dead constant branches (for example
  `(CONST ? expiry_clock_now(...) : world.time)` keeps a `PushVal 0; Test; Jz` where DreamMaker emits one branch), `Jz` against
  `GetFlag`, the `IterLoad` type-filter operand (native emits 0 and keeps the explicit `IsType` test on every iteration, so the loop
  body sees the same values), receiver caching, extra temporaries, and per-type `<init>` procedures where DreamMaker shares one.
Boot gate and smoke set under `DQ_COMPILER=native DQ_COMPILER_STRICT=1`: `FOCUSED RESULT: 47 passed, 0 failed` (smoke set, the
gameplay scenarios, keybinding, admin.txt and client-verb tests; log `E:/dq-cache/nd/smoke-nat.log`), no runtime before the first test.

**Why edits were slow, and the fix.** Instrumenting the input stage (`native input preparation ... prepared inputs: hits= misses=`) showed
that after every build the daemon released its "rich buffers" (prepared sources for 5,800 files, maps, link bindings, initializer
assemblies; `dmbd artifact release tier=2`) because its private memory sits above the 8 GB soft limit, and the next edit then paid
about 11 s to re-prepare every source plus the map and link rebuilds. The release returned no memory (private bytes before and after
differ by under 0.1%), so it was pure cost and fired after every build. Soft pressure now releases nothing (the hard ceiling and the
one-hour idle release are unchanged), which removes the 25-65 s spikes: a body edit after a pressure release went from 54.8 s to 17.8 s
in the same measurement sequence, and a steady patch edit stays at 8-10 s.

**Compile time per edit kind** (production dme, resident daemon, `dmbc compile` wall time, a machine shared with other lanes so single
runs vary by up to 2x; the table is the best of the runs that were not disturbed):

| Edit | Master (default limits) | This branch |
|---|---|---|
| unchanged rebuild | 2.3-5.0 s | 1.9-2.1 s |
| body edit (patch path) | 8.8 s steady, 54.8-65.6 s after a pressure release | 8.1-9.8 s |
| numeric default edit (patch path) | 10.3-11.2 s steady, 22-25 s after a release | 9.6-11.8 s |
| new var | 21.3 s | 19.2 s |
| new proc | 34.6 s | 20.2 s |
| new type | 47.4 s | 35.9 s |
| new `#define` | 37.7 s | 30.1 s |
| cold build (empty daemon) | 98 s | 70-88 s |

The target of at most 2.5 s for a structural edit is **not met**. Where a structural edit spends its 19 s (new var, no pressure): about
1.3 s session validation, 0.2 s input preparation, 3.5 s frontend (directive plan 0.7, tree resolution 0.8), 1.5 s resources and maps,
0.4-0.7 s patch attempt, then the whole-program stages that each re-walk 81,749 procedures with memo hits: startup 0.5, ABI 1.2,
initializers 2.8, lowering 2.5, required types 0.6, link 2.1, composition 2.4, and 1.8 s publication (a third and fourth 9,735-file
validation). Those stages are the design's consumers 3 and 4-7 (`tools/dmb/doc/structural_change_set.md`); until a structural edit can
skip them, 2.5 s is out of reach. A new type that carries members and a `#define` still decline the tree splice (tree resolution 4.9 s
instead of 0.8 s), and a changed `#define` line in a file shifts later declaration rows. Cheap items left: reuse the session
validation's directory proofs for the resource and publication admissions (about 1.5 s per request).

**Memory is not within the approved 8 GB.** Working set of the daemon: cold build peak 10.4 GB, retained after a build 8.7-9.5 GB.
The Rust live heap (counting allocator, `--features allocation-counting`) is 2.7 GB after the frontend, 3.9 GB after startup/ABI,
5.0 GB after initializers, 7.2 GB after lowering and 8.0 GB at publication; the heap census sees about 1 GB of it. A sampled call-site
profile (`--features allocation-sites`, `DMB_ALLOC_SITES_PATH`, new in `dm-profile`) shows a flat distribution with no single
dominant owner: the session artifact stores (incidence index, receipts, leases) hold about 1.2 GB, the directive/region memos 0.7-0.9
GB, declaration parsing and the adapter 0.45 GB, owner shapes and normalization 0.2 GB, classification stores 0.2 GB. Setting
`MIMALLOC_PURGE_DELAY=0` and `MIMALLOC_ABANDONED_PAGE_PURGE=1` changed nothing (the memory is live, not fragmentation). Getting under
8 GB therefore needs the Incidence index interned (its leaves clone every read domain) and the receipt groups compacted, not tuning.
Until then the daemon stays above its soft limit; with soft pressure no longer shedding state, the limit only defers a second
concurrent build.

Rust tests: `cargo test -p dmbc --lib -- service_housekeeping daemon::service::tests` 31 passed, 1 failed
(`pressure::soft_pressure_defers_another_build_but_preserves_single_build_progress`, an admission timing assertion this branch does not
touch).

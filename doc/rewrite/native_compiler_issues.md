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

5. **Output not equivalent to DreamMaker's (medium, was high).** Re-measured 2026-10-21 on origin/master `a6ce3d8f16`, production dme,
   `dmb-equiv dm.dmb native.dmb` (DreamMaker 58.7 MB, native 67.9 MB; DreamMaker build 0 errors, 50 warnings): NOT EQUIVALENT,
   **104,408 differences, identical with `--ignore-debug`** (the checker counts ordering in the total here; `proc.debug_info` no longer
   differs). 2026-10-14 was 218,558 / 144,843 ignoring debug. Without ordering (97,600 of the total): **6,808**, against 15,091 after
   the 2026-10-14 fixes. Categories:
   - Ordering only (non-semantic per the 2026-10-14 decision): `order.proc_table` 79,249, `order.var_name_strings` 16,011,
     `order.type_table` 2,340. The `header`, `header_flags`, `type_mob` (sight) and `type_appearance`/`proc_args` categories are gone.
   - Benign, bytecode shape (`proc.bytecode` 6,476): `Jz` vs `GetFlag` 1,256; `End`/`GetVar`/`PushVal` vs `Jmp` (DreamMaker folds the
     tail) about 850; `JmpOr`/`JmpAnd` target shifts 360; iterator forms (`IterLoad` vs `Range`/`View`/`ORange`/`Viewers`/`Hearers`)
     about 700; `PushCache` vs `GetVar` receiver caching about 270; constant strings not folded (`"</span>"` vs `Add`) 96; `Square` vs
     `PushVal 2.0` 22; `NewImage` vs `NewImageArgs 2` 39.
   - Benign naming: `type.type_meta` 96 (per-type `<init>` anonymous procs hash-named differently), `proc.extra` 76 and `proc.missing` 67
     anonymous procs by hash (`<anon ...>`, `<init>` sharing; the 9 net extra are native-only), `map_objects` 6 (the `vent_pump`
     var-set `<anon>` names), `proc.proc_locals` 87 (native keeps one more local, e.g. `/atom/vv_edit_var`, `/client/verb/who`).
   - Possibly semantic groups, read 2026-10-21 (tools/dmb-equiv `src/normalize.rs`, `EQUIVALENCE.md` "Encoding rules"): (a) the 35
     `infoplain`/`bold` literals are `A + (B + ...)` against `AB + ...`, the same text; (b) the 214 `PushVal null` sites are
     DreamMaker's dead null store for every `var` (native omits it outside loops), a dead `Jmp` after `Ret`, `/T::field` folded to its
     default against a runtime `initial()`, and DreamMaker's `0x1000_0000|id` field-name operands; one real gap fixed: a bare `var/x`
     after a backward `goto` now stores null again; one site unexplained (`/mob/death`, `a?.b?.c = const` pushes the constant before
     the guards); (c) the anonymous procs are type initializers (DreamMaker shares the class and map-instance procedure, store order
     differs): now compared by body under the type. Same-tree counts: `proc.bytecode` 4,779, `proc.extra`/`proc.missing`/
     `type.type_meta`/`map_objects` 0. New finding: `/obj/item/book/tome` `tomedat` keeps `
` from a CRLF source file in a multi-line
     string, DreamMaker has `
` (`type.type_var_default` 1).
   Repro: `build.sh dm` and `DQ_COMPILER=dreammaker build.sh dm` (delete `deepquarry.dmb/.rsc` between), then `dmb-equiv A.dmb B.dmb
   [--ignore-debug] [--max-examples N]`. Kept at `E:/dq-cache/dmb-equiv-20261021/` (dm.dmb, native.dmb, equiv*.log).
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
| cold build (empty daemon) | 98 s | 62-88 s |

The target of at most 2.5 s for a structural edit is **not met**. Where a structural edit spends its 19 s (new var, no pressure): about
1.3 s session validation, 0.2 s input preparation, 3.5 s frontend (directive plan 0.7, tree resolution 0.8), 1.5 s resources and maps,
0.4-0.7 s patch attempt, then the whole-program stages that each re-walk 81,749 procedures with memo hits: startup 0.5, ABI 1.2,
initializers 2.8, lowering 2.5, required types 0.6, link 2.1, composition 2.4, and 1.8 s publication (a third and fourth 9,735-file
validation). Those stages are the design's consumers 3 and 4-7 (`tools/dmb/doc/structural_change_set.md`); until a structural edit can
skip them, 2.5 s is out of reach. A new type that carries members and a `#define` still decline the tree splice (tree resolution 4.9 s
instead of 0.8 s), and a changed `#define` line in a file shifts later declaration rows. Cheap items left: reuse the session
validation's directory proofs for the resource and publication admissions (about 1.5 s per request).

**Memory: 9.5 GB retained and 10.4 GB peak down to 7.75 GB and 8.4 GB (working set), still not under 8 GB private.** Measured on a
cold build in a fresh daemon, working set sampled every second: peak 10,450 MiB and 9.5 GB retained before, peak 8,373 MiB and
7,745 MiB retained after; the daemon's own private-bytes reading after a build went from 9.5-9.9e9 to 8.49e9 against its 8e9 soft
limit. The Rust live heap (counting allocator, `--features allocation-counting`) is 2.7 GB after the frontend, 3.9 GB after
startup/ABI, 5.0 GB after initializers, 7.2 GB after lowering and 8.0 GB at publication (7.6 GB after this change); the heap census
sees about 1 GB of it. A sampled call-site profile (`--features allocation-sites`, `DMB_ALLOC_SITES_PATH`, new in `dm-profile`) put the
session `Incidence` index first at 1.45 GB: every leaf, variant and reverse map held its own clone of each read domain (a resolver
query, tens of bytes). `dm-session` now interns the domains (`DomainId`, one `Arc` per domain) and no longer keeps a domain-to-leaves
reverse index that only `visit_affected` (tests) read, which is where the saving comes from; the 88 `dm-session` tests and the dmbc
`six_session_contract` byte-parity tests still pass. What is left is a flat distribution: session artifact stores and leases about
0.9 GB, receipt groups 0.34 GB (the stored observations themselves), directive/region memos 0.5 GB, declaration parsing and the adapter
0.36 GB, the disk-cache segment indexes 0.3 GB (reopened for the one directive miss of every edit, which is also 0.4-1.0 s of each
request), classification stores 0.2 GB. Setting `MIMALLOC_PURGE_DELAY=0` and `MIMALLOC_ABANDONED_PAGE_PURGE=1` changed nothing (the
memory is live, not fragmentation). The next steps are keeping one opened disk-cache snapshot per daemon (instead of per request) and
compacting the receipt observations (`Observation` is query + answer + domain, about 150-200 bytes each). With soft pressure no
longer shedding state, the soft limit only defers a second concurrent build.

Rust tests: `cargo test -p dmbc --lib -- service_housekeeping daemon::service::tests` 31 passed, 1 failed
(`pressure::soft_pressure_defers_another_build_but_preserves_single_build_progress`, an admission timing assertion this branch does not
touch; it fails the same way on origin/master).

## Status 2026-10-16 (tools/dmb-frontend: per-edit fixed costs)

Goal of the lane: body edit and new var/proc at most 2.5 s, new type and `#define` at most 8 s, memory no higher than before. **Not met**
for the 2.5 s target (body edit 6.5-7 s, new var/proc 9-10 s) and for new types (full compile). Met for a `#define` line (6.3-6.6 s) and
for the memory ceiling. Everything below is measured on the production tree with a resident daemon, baseline = origin/master c3cb037784
and the branch tip run alternately in the same worktree (private daemon namespaces, `DMB_DAEMON_NAMESPACE`), on a machine shared with
other lanes, so single runs vary by up to 1.5x; the ranges are the three runs of each.

| Edit | Master | This branch | Path |
|---|---|---|---|
| unchanged rebuild | 2.0 s | 2.0 s | session hit |
| body edit | 13.9-14.9 s (12.2-13.0 quieter) | 7.2-9.7 s (6.1-7.0 quieter) | patch |
| new var on an existing type (after a body edit) | 17.7-38.8 s (first one declined: stale model) | 9.2-11.3 s | append patch |
| new proc on an existing type | 15.4-17.4 s | 9.3-9.6 s | append patch |
| comment line, blank lines or doc block between declarations | 22.2-24.0 s (full compile) | 6.5-6.6 s | patch (new) |
| `#define` line between declarations | 22.5-22.7 s (full compile) | 6.3-6.6 s | patch (new) |
| new type, removed var or proc, `#define` used outside a body | 21-43 s | unchanged | full compile |

Where a body edit spends its time (quiet runs, seconds; the stage names are the `request_mark` timeline of `DMB_TIMINGS_DETAIL=1`,
which lands in `E:/dq-cache/dmb-daemon/lifecycle.log`). "Before" is the build immediately before that stage's change (master for the
frontend, the later rows were measured one change at a time as the lane proceeded), so the rows do not add up to the table above:

| Stage | Before | This branch | Change |
|---|---|---|---|
| session validation | 0.69-1.0 | 0.38-0.45 | record decode moved to a background thread; `filter_generated` no longer canonicalizes every listing name |
| input preparation | 0.30 | 0.24 | none |
| frontend | 4.4 (directive disk 1.9) | 1.7-1.8 | disk memo skipped for a few resident misses |
| source revision (query capture) | 0.25-0.75 | 0.05-0.1 | digest over fixed chunks on all cores (token v3) |
| resources and maps | 1.0-1.1 | 0.85-0.9 | resource admission reuses the session's directory proofs |
| freshness snapshot merge | 0.48 | 0.24-0.29 | merge compares and inserts instead of re-filtering retained listings |
| startup facts | 0.45-0.5 | 0.40-0.45 | body keys on the workers (the rest is the declaration ledger, 0.2) |
| ABI preparation | 1.5-1.9 | 0.45-0.55 | the batch recipe (0.5-0.8 s) is built only when replay is enabled |
| publication and finalization | 0.9-1.1 | 0.8-1.0 | none |

**Other changes.** A body patch splices code rows into the retained image and left the retained composed model alone, so the next
structural append saw a stale model and ran a full compile; the slot now remembers the spliced rows and the append applies them to a copy
of the model (`Dmb::patch_list_rows`, checked against the patch base hash). Edits that only move code are patched from a token alignment
of the changed files' old and new text (`body_patch_lines.rs`, `structural_change_set.md` addendum). The three failing dm-tree tests were
stale against rules that landed earlier (inherited variable redeclaration is rejected; the chunker is content defined) and are fixed; the
dmbc lib tests did not compile on master (`initializer_disk_tests.rs`) and `session::tests::immutable_session_reuse_validates_inputs_and_rejects_corruption`
asserted corruption of an already decoded record; both are fixed. 24 other dmbc lib tests fail on master and still fail here
(`cargo test -p dmbc --lib`: 993 passed, 24 failed; master with only the compile fix: 984 passed, 25 failed; the failing sets are identical
apart from the session test): header compatibility fixtures, retained-runner-facts catalogs, lazy cache batches, `expansion_memo` staging,
modified-initializer source recipes, among others.

**Equivalence.** `dmb-equiv` of the patched output against a fresh one-shot native compile (`DMB_BODY_PATCH=0 --no-cache --no-daemon`):
EQUIVALENT with `--strict-order` and debug lines for a body edit, a comment line and a `#define` line; for a new var and a new proc the
only difference is the order entry of the new member (`order.var_name_strings`, `order.proc_table`: appended numbering, by design).
Each scenario's differences against a DreamMaker build (`dm.exe`, same source) are identical for the patched and the fresh output in
all categories. `six_session_contract_tests` gained `code_motion_edits_patch_and_match_fresh_bytes` (byte-identical to fresh through
comment, blank-line, doc-block and directive edits and back) and `appends_after_body_patches_edit_the_model_with_those_patches_applied`.

**Memory** (cold build in a fresh daemon, then three body edits, sampled every second; master vs this branch): peak private
10,160 vs 9,877 MiB, peak working set 11,298 vs 11,090 MiB, private after the edits 8,295 vs 8,281 MiB. No regression, and not under 8 GB:
the retained set is unchanged apart from the disk-segment indexes no longer reopened for every edit.

**What the 2.5 s target still needs.** Every remaining stage is a whole-program pass with per-item replay: directive planning (0.56 s,
a serial walk of 5,983 intervals), expansion replay (0.27 s, 12,968 regions), declaration merge (0.5 s, 9,650 chunks), tree resolution
on a structural edit (1.1 s: identity refresh 0.28, dependency graph 0.24, certificate carry 0.52), resource demand (0.24 s, a lex of the
whole expanded text), the ABI scheduler (0.45 s over 86,782 units), startup facts (0.4 s), two 77 MB writes at publication (0.4 s) and the
four directory sweeps of a request (about 1 s in total). Reaching 2.5 s needs one retained frontend revision per daemon that a change set
edits in place (design consumers 1, 2 and 4 of `structural_change_set.md`), not further trimming of these passes. Smaller items measured and left:
per-chunk memoization of resource literal discovery and of `source_checks` (0.1-0.25 s each), a persistent filesystem watcher for the
sweeps, and patching removed members and new types (tombstones; class order).

**Default daemon namespace hazard.** All worktrees share one daemon endpoint per user unless `DMB_DAEMON_NAMESPACE` is set, and a client
whose compiler build differs retires the other build's daemon ("dmbd retiring"). With several lanes building, a resident daemon is
often replaced between two requests, which shows up as three or four consecutive full compiles ("no patch base retained"). Benchmarks
should set a private namespace.

## Status 2026-10-21 (tools/dmb-behaviour: behaviour against DreamMaker)

**Method.** Master did not compile with DreamMaker (105 errors, now fixed; the merge gates and the push compile the production dme with
`DQ_COMPILER=dreammaker` too, `agent_workflow.md` section 28). Two tools measure behaviour rather than bytes:
`tools/dmb/scripts/diagnostics_corpus.py` (DreamMaker's diagnostics against dmbc's, 121 cases; 118 match, the three that do not are
`bad_operator`, `string_embed_unterminated` and `tab_space_mix`, older gaps), and the unit test `dq_compiler_behaviour`
(`code/modules/unit_tests/dq_compiler_behaviour_probe.dm`, generated by `tools/dmb/scripts/gen_behaviour_probe.py`), which runs the same
world under both compilers and dumps 104,550 observable rows to `data/compiler_behaviour.txt`: folded constants (8,000 operand pairs over
20 operators plus unary, ternary, builtin math), iterator type filters, `typesof()` of 14 roots, proc and verb lists of 11 types, `vars` of
five datums, `world.vars` and `global.vars`, and exception positions. The pin `snapshots/compiler_behaviour.txt` is built from a DreamMaker run
(`tools/dmb/scripts/pin_behaviour.py`) and both compilers pass it.

| Item | Result |
|---|---|
| 1. Constant folding | **Fixed.** `fold_number` now follows DreamMaker: `& \| ^ ~ ! ** << >>` (24-bit, negative shifts are 0, counts mod 32, 32-bit saturation), `&&`, `\|\|`, `?:` with a constant condition (the dead side is still checked, not emitted), `if`/`while`/`do..while` on a constant (the dead branch is dropped, `while(1)` loops without a test), and `round floor ceil abs sqrt sin cos tan arcsin arccos arctan log clamp` on literals (`round(x)` is a floor, `min` and `max` are not folded). DreamMaker's own folder disagrees with its runtime in 74 grid cells (`-1 << 2` folds to 0, the VM gives 16777212): native reproduces the folded values, which is what the DreamMaker world does. Same-tree production `dmb-equiv --ignore-debug`: numeric `PushVal` against `PushVal` differences 1,701 to 0; `proc.bytecode` 9,039 to 6,493; total 139,989 to 137,460. |
| 2. IterLoad type filters | **Behaviour-equivalent, left as is.** Native emits filter operand 0 and an explicit `IsType` test per iteration. The probe (`for(var/obj/x in L)` over a mixed list, nested, `as anything`, `break`, subtypes, no matches) gives identical counts and visited types in both worlds, and the filter works (`obj` 4 of 9 entries, `mob` 1, `turf` 0). 254 signature differences remain in the checker. |
| 3. typesof, vars, proc order | **Identical at runtime.** The dumps are byte-identical: `typesof(/datum)` 51,865 entries, `/atom` 22,854, `/obj/item` 13,559, procs, verbs, `vars` of datum, obj, mob, movable, world and global. `dmb-equiv` still counts table numbering (77,228 proc table, 37,478 type table, 15,929 var names) because it cannot tell which renumberings the runtime shows. `header_compat::fixture_tests::null_and_empty_text_defaults_match_dreammaker` fails the same way on master: its reference numbers the class table in DreamMaker's small-program order, which commit `ee888aa61c` (class table order) carries and master does not yet. |
| 4. Debug line numbers | **Not observable.** The DreamMaker that builds the live server is the same `dm.exe` command line: it writes no debug lines with or without `-DDEBUG` (0 `DbgLine` in a small program and in the production dme), and the native production output carries none either. In the test world neither build gives an exception a file or line (`e.file`, `e.line` are empty in both dumps). Native does emit `DbgLine` in fixture and test-oriented builds, following each statement's source line; there is nothing to compare it with until a DreamMaker build with debug information (the IDE) exists. |
| 5. `--warning=error`, `--no-warning` | **Already working.** `build.sh` maps them to `--warnings-as-errors` and `--ignore-warning CODE`; `var/x = 5` prints `warning (unused_var)` natively as DreamMaker does, and an ignored code no longer counts toward `--warnings-as-errors`. |

**Accepts-but-DreamMaker-rejects classes now rejected by dmbc** (`source_checks.rs`, `member_normalization.rs`, corpus cases): a keyword as a
named argument, formal or local (`to`, `in`; `if set while ...` as formals), a `proc/` or `verb/` keyword on a subtype's override
(`duplicate definition`), `nameof` of a call or index, a plain `"text"` literal over a line break (`unterminated text`), `% 0.5`, and builtin
math outside its domain (`sqrt(-1)`, `arcsin(2)`, `log(0)`). Found and fixed in the tree: 105 errors in the production dme and, in the test
dme, a string with a raw newline in three files and a local named `to`. Still open: `typesof(/datum/verb)` (an undefined type path) and
`typesof(/world)` are accepted; DreamMaker reports the unused variable of a statement it rejects.

**Follow-up 2026-10-21.** `header_compat::fixture_tests::null_and_empty_text_defaults_match_dreammaker` passes on master since `ee888aa61c` (class
table order) landed. `typesof(/T/verb)` is now rejected unless `/T` itself declares a verb (an inherited one does not count: `undefined type path`),
and `typesof(/world)` is `not a prototype` (`source_checks.rs::typesof_errors`; corpus `typesof_*`, test `typesof_paths_follow_dreammaker`).
`typesof(/T/proc)` is not checked: the engine's own procs are not in the tree.

**To do when the engine catalog allows it:** `typesof(/T/proc)` is not rejected for a type that declares no procs of its own (DreamMaker:
`undefined type path`), because the engine's built-in procs are not in the semantic catalog and a user type may inherit them. Add the check
beside `typesof_errors` once built-in procs are catalogued.

# Native compiler integration status

Updated September 30, 2026. This describes the native Rust frontend, separately
from the earlier OpenDream-output translator.

## Full continuous-suite comparison

Fresh BYOND 516.1687 and native Rust builds of the same frozen source snapshot
each completed all 1,089 runnable tests. BYOND: 985 passed, 46 failed, 58 skipped.
Rust: 997 passed, 34 failed, 58 skipped. There are 33 shared failures, 13
BYOND-only failures, and one Rust-only failure (`dq_damage_flavour_bands`).
Another 24 types are intentionally excluded by the framework. Neither run is
clean: both record extensive game runtime errors. These counts establish full
coverage, not exact semantic parity or a clean integration gate.
The Rust-only damage-band test passes in a fresh focused run on both outputs,
so its full-suite divergence remains context-dependent and unresolved.

See [full comparison](FULL_SUITE_COMPARISON.md) for reproducible inputs, failure
differences, runtime counts, and diagnostic follow-up.

## Final checkpoint (Build50)

- Test generation: `571c8f32e5a6da45f963d365ae6d8f3b859cda1845527819e3fe4b4e6cd6d979`.
- Server generation: `cd169d554dfa2c2ebec4d49dedbf90260a07ba7d2a13285ae522f04263afe427`.
- All 48,681 test procedures and 47,192 server procedures emit successfully.
- Compiler phases take 130.942 seconds (tests) and 126.696 seconds (server).
- All 1,134 Rust workspace tests pass.
- Procedure-only subtype headers now inherit final parent flags, layer, plane,
  and visibility defaults; all 737 storage class flags match native output.
- Original, unpatched 28-test run preserves all 14 compiler regression passes.
  The remaining 14 failures have the exact same assertions as the prior native
  comparison. Runtime errors prevent a clean full-game-suite claim.
- Comparison: `target/final-selected-regressions50-comparison.csv`.

## Verified

- Final workspace gate: 1,134 Rust tests pass (`cargo test --workspace --lib --bins --tests -j1`).
  This includes binary-format validation, native macro semantics, compiler/codegen,
  daemon, resources, output patching, and disk-cache tests.

- The project's `CBT`, `CIBUILDING`, `CITESTING` configuration preprocesses
  without diagnostics. Build50 emitted all 48,681 procedures and published
  a validated DMB/RSC pair.
- Declaration and initializer audits passed for that expansion.
- 212 focused codegen tests and 173 compiler tests pass, including native
  bytecode and metadata comparisons.
- A trusted BYOND 516.1687 smoke world passes construction, initializer order,
  inheritance, static state, argument forwarding, comparisons, exceptions,
  switch ranges, nested iterator exits, namespaces, verb references, and
  indexed logical assignment.
- Persistent procedure and preprocessing caches survive process restarts.
  Worktree sharing, selective invalidation, artifact corruption recovery,
  and journaled output patching have focused regression coverage.
- An unchanged full-project build in a fresh process reused all 48,646
  procedures with no lowering. Measured phases total about 14 seconds,
  dominated by dependency hashing and output verification/publication.
- Persisted procedure parsing packs relocate spans across worktrees and
  use bounded immutable segments for concurrent writers. Corruption fallback
  and concurrent publication pass focused tests. Full-project speed impact
  remains to be measured.
- Daemon builds retain verified project inputs under a combined 64 MiB budget.
  Unchanged builds skip preprocessing and resource scanning after exact
  dependency checks. Source, map, asset, and resource-shadow invalidation,
  idle eviction, and output-corruption recovery pass all 29 daemon tests.
- Procedure-body edits use per-procedure Salsa lowering and persisted linked
  checkpoints, preserving unchanged procedure IDs. Four incremental emission
  tests and three checkpoint capture tests pass. Cold restarts, appended local
  and string tables, declaration fallback, corrupted checkpoint recovery, and
  same-size binary patching have focused coverage. Full-project body edits
  lower exactly one procedure and preserve every other authored procedure;
  current measured timings are below.
- Preprocessing cache format 8 with larger individual leaf limits reused
  5,557 include requests in a measured 2.21-second replay, down from
  30.58 seconds with the smaller limits. Expanded output was identical;
  the total cache budget remains 64 MiB. All 46 preprocessing tests and both native semantics integration tests pass.
- All three active unit-test TGM maps have their dictionaries and assignments
  parsed and lowered. Nineteen map tests cover multiline dictionaries, native
  float/null/escaped text, mob descriptors, tagged type references, and bounds.

Build49 successfully emits both complete configurations: 48,681 test procedures
and 47,192 regular-server procedures. Its test DMB is byte-identical to Build48,
so the 28-test native comparison applies to the final compiler. The regular
server generation is `ec166a490521cfd5ec89abcaf1223c24e9833a857d471816cefea86234ba7592`.
A fresh non-daemon process reuses the final test build from disk in 14.962 seconds:
output cache hit, zero procedures lowered, all 48,681 procedures reused.
Actual trusted runtime execution verifies compact `set name="..."` inherited
verb calls against native output without runtime errors.

Final tail validation executes the five previously unfinished eligible tests.
Native/Rust equipment (1,713,624 cells) and holster (13,923 cells) decisions agree;
both fail lifecycle cleanup errors. Suit storage shares seven removed-type
assertions across 861,588 cells; the DCS argument test passes without runtimes.
Storage sweep creation counts differ (Rust 158/474,201 versus native
154/477,477). Targeted tracing identifies the existing lifecycle timing bug
inside `qdel()` of temporary storage-cost probes. Pill initialization and
cost calculation succeed; diagnostic-only timing suppression lets all six
differing holders construct. This is diagnostic evidence, not a normal test pass.
Evidence: `target/storage-creation-cause49.txt`.

## Measured incremental performance

The matching compiler/daemon build 39 was measured on the full project with
`CBT`, `CIBUILDING`, and `CITESTING`, a 2 GiB process limit, and 48,647 authored
procedures. An isolated mirror copied only the edited DM file; untouched files
were hardlinked or reached through read-only directory junctions. The original
game sources remained unchanged. A trusted runtime check was running separately
on the same computer during this measurement.

| Daemon request | Total elapsed | Procedures lowered |
|---|---:|---:|
| First request, existing disk artifact | 12.709 s | 0 |
| One literal-return body edit | 20.002 s | 1 |
| Unchanged request after that edit | 4.238 s | 0 |

The body-edit compiler stage took 5.002 seconds, versus 131.085 seconds for
the full build (about 26 times faster). It preserved 48,646 procedures and
published a valid pair through the ordinary output publisher. Dependency
discovery, resource checks, serialization, and publication account for the
remaining total time.

The unchanged shortcut verifies the published output first, then performs one
exact source/map/resource/shadow check immediately before returning. Its
4.238-second elapsed time is down from 8.333 seconds before removing the second
identical validation. Exact input validation remains the dominant cost.

Peak daemon working set was 671 MiB; the idle working set after all requests
was 118 MiB. The persisted linked checkpoint was 44,728,619 bytes, below its
64 MiB limit. The daemon was stopped after measurement. The reproducible runner
is `scripts/measure-body-edit.ps1` with optional `-DaemonAddress`; logs are
retained beneath `target/body-edit-*` and `target/daemon-body39.stderr.log`.

## Integration still required

The full project emits a validated native DMB/RSC pair with all 48,646 authored
procedures. The latest build completed compilation and map assembly in 140
seconds in the previous checkpoint; the next full compilation took 120.846
seconds. Included map stacking now matches native BYOND.

Missing builtins, stream operators, native predefined macros, nested macro
expansion, method-name validation, and static callee aliases are corrected.
The stricter full-source lowering audit passes all 48,646 procedures.

Trusted full-project runtime validation remains incomplete. A stale Verdigris
DLL was rebuilt and independently passed its native ABI handshake. Crash dumps
then identified an empty-stack access in a datum constructor during global
initialization: bare `return` incorrectly emitted opcode 0x08 (FTP output).
Both lowering paths now emit the native return instruction. A minimal native
and Rust constructor world agrees and exits cleanly; full-project runtime
verification passed that crash point but exposed missing early initialization:
the preprocessor discarded executable DM lines in included `.dme` files,
including the project's `Genesis()` call. The corrected expansion includes
48,647 authored procedures. Further native comparisons corrected null typed
global/static member access, literal-list initialization phases, initializer
wait flags, and local-variable resets inside loops. The next full build emits
a validated pair and a 44.7 MB incremental checkpoint. Runtime validation
remains in progress; the project unit-test suite has not passed yet.

Construction of verb references, argument-source candidate slots and procedure
context, and coexistence of `global.vars` with an ordinary static named `vars`
now pass focused native comparisons. A trusted smoke world also verifies the
combined `vars` case, arithmetic folding, and mob construction/type identity.
Typed static constructors preserve arguments and dimensions. Generated
initializer assembly, map assembly, and output serialization pass. Full
runtime tests remain required to establish project correctness.

`dev-scripts/run_project_tests.ps1` runs an already compiled test world in
trusted mode, with separate result files, a timeout, and a memory watchdog.
Compiler processes also enforce a 2 GiB memory ceiling by default.

## Latest native comparison fixes

Build42 fixes numeric range counter semantics: empty ranges preserve the
binding, and completed ranges retain the last iteration value. The previous
lowering made the timer subsystem abort on an empty client-timer list before
delivering callbacks, including normal test startup. A minimal timer-loop
runtime now matches native output without errors. Normal project test startup
is verified: the focused nine-test run completed in 32.2 seconds and wrote fresh
results without a launcher patch. Four previous failures pass; five atmosphere
and airlock failures remain. Runtime errors prevent a clean-run result. The
full 1,113-test suite is running through its normal startup path.
Savefile version compatibility also passes actual DMB serialization/readback.
The next checkpoint also fixes high-ID compound defaults, inheritance through
native-template intermediary classes, and default atom text. All three have
focused native regressions; project runtime validation is still required.

Build45 emits both configurations: 48,681 test-world procedures and 47,192
regular server procedures. Global map descriptor interning fixes duplicate area
objects and the station map instance-table overflow. All five previously failing
power-dependent assertions now pass in a normal selected test run. That run
recorded six assertion passes and thirteen failures among nineteen tests;
runtime errors still prevent a clean-run result. The next checkpoint corrects
same-type reopened procedure ordering, including inherited child lookup, verified
against native output. The complete normal suite reached test 1,072/1,113 before
its 900-second timeout: 953 PASS lines, 38 FAIL lines, and 58 explicit SKIPPED
lines. These are partial logs, not final result JSON or a passing full suite.

Build46 verifies the corrected reopened-procedure chain and fixes equipment
constraints, auxiliary-machine hibernation, and repeated shuttle movement
assertions. Build47 corrects current/inherited member precedence over global
procedure names: the actual sheet-stock test passes, and smartfridge now reaches
the same later failure as native output. All seven reference-count failures and
both latent-light failures also reproduce natively. Build48 fixes null-safe member/index continuation during state serialization and
verb selectors in phase-shift calls. A normal, unpatched 28-test selection
completed in 83.4 seconds: 14 passes and 14 failures. All remaining assertion
failures also occur in native output, including the later power and skill
assertions. Runtime errors still prevent a clean integration result.
Evidence: `target/final-selected-regressions48-comparison.csv`.

Native probes also establish that ordinary DM statements inside included `.dme`
files execute after ordinary `.dm` expansion, while macros expand when encountered.
Procedure emission preserves that source order. Parent procedure metadata is
resolved independently of emission order, including forward parent declarations.
Static initializers retain their authored `__TYPE__` and `__PROC__` context.
A `break` inside a switch exits the enclosing loop. Trusted executable probes
match native BYOND for these corrected semantics.

The current native game reference also reports lifecycle and power list-index
errors and cannot populate the isolated unit-test block pool. These are reproduced
with native BYOND output and prevent treating the full project suite as a passing
compiler gate. The Rust startup is being checked separately for additional failures.

The next integration build corrected implicit subtype filtering for atom
iterators. Trusted native/Rust comparisons now agree on typed turf contents;
false duplicate-firedoor reports are gone. Build40 emitted all 48,647 procedures
in 112.781 seconds. The actual Rust project still blocks during map initialization
on repeated invalid numeric deletion calls, before the first unit test. The
full game suite remains unverified. Native error descriptions are suppressed
after 100 errors, so a private diagnostic copy skips the already-reproduced
lifecycle timing error to capture the next caller. Diagnostic workarounds are
not used as evidence of a passing game suite.
Build41 fixes explicit `locate(type) in list` object/null results and legacy
`prob(weight)` pick syntax. Focused trusted native/Rust runtime checks agree.
The original game source now completes initialization and starts the game.
The normal round-start test callback still fails to start the suite. A separate
artifact-only direct-launch harness schedules the original compiled RunUnitTests
procedure after initialization, preserving all test bodies. This harness reached
all 1,113 test types and recorded passes for the first five tests; clothing validation
is running. These partial results do not establish a passing full suite or a fixed
normal test-start path. No diagnostic lifecycle suppression is present in this run.
The direct-launch harness run reached test 640/1,113 before its 360-second watchdog,
with 537 PASS lines, 27 FAIL lines, and 56 explicitly SKIPPED lines. It did not produce
final result JSON or a clean-run marker, so this is a partial run rather than a
passing suite. The runtime was stopped and cleaned up. Logs are retained under
`target/runtime-tests/native-compiler-b02fc7d9e2f64e50a24f65602180302b/`.

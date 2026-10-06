# Preserved compiler sampling harness

External sampling is stopped at the user's request because the recorder repeatedly
opened administrator permission prompts. The harness now defaults to ordinary
compiler execution with built-in stage traces and an independent timing receipt.
It does not launch samply or xperf unless a sampler path is explicitly supplied.
The historical sampling instructions below preserve reproduction evidence;
agents must not resume external sampling without renewed user authorization.
Ten named sampled frames remain a deferred gate, not a claimed result.

Root owns executable jobs. The sampler has passed a separate smoke check; that
check is not a compiler measurement. Use release binaries from frozen ac1af55d1a
and keep their hashes. Historical PERFORMANCE.md 3.240s used optimized prototype
builds and warm OS caches, not a release empty-cache run.

Run profile_base.py separately with --scenario cold or --scenario daemon-body, --compiler <dm-compile.exe>, --daemon <dm-compiled.exe> for daemon mode, --builtins <builtin.dmb>, and --output <new directory>. Manifest defaults to the captured comparison.dme. Source defaults to D:/dmb-native-v2-phase0/frozen/source. Sampling defaults to D:/dmb-native-v2-phase0/profiler/samply.exe. Defines default CBT/CIBUILDING/CITESTING; pin them explicitly with --define=-DCBT etc. Verify frozen compatibility edits and input hashes against the baseline before attributing performance.

The driver creates a private source mirror with the edited file copied and other immutable inputs hardlinked. It excludes Git/cache/target directories and old DMB/RSC files. A new private Git common directory isolates compiler caches; daemon cache is also new. This is application-cold, not OS-cold. Frozen hardlinked inputs must stay immutable. Body mode completes a baseline, changes only tool_skill_factor return1 to return2 like measure-body-edit.ps1, then calls the existing build-project-daemon client. An unfinished baseline yields no body measurement.

Input preparation and each compiler/capture command have separate budgets of at
most 300 seconds. The watchdog stops owned process trees at 285 seconds within
the active budget, reserving 15 seconds for cleanup/receipts. A daemon spans its
baseline and edit requests, each separately bounded; its lifetime is not a single
compilation. Final sampling conversion has its own bounded budget. Receipts record
every budget transition and the total scenario wall time, including preparation.
No new compiler memory cap is imposed. Hard termination may require cache recovery;
failed or timed-out runs remain partial receipts. `cold-2` used the earlier combined
budget: 44.64 seconds of preparation left 240.1 seconds for sampled execution. Its
timeout is preserved and is not a completed cold-build measurement.

Prepared sampler invocation: samply record --save-only --no-open --unstable-presymbolicate --symbol-dir <release directory> --output profile.json -- <command>. A separate sampler smoke check passed; it is not a compiler profile or evidence of Rust symbol coverage. Daemon sampling includes startup+baseline+body. Stop attempts CTRL_BREAK then bounded hard cleanup; missing profile after termination is reported. Samply's Windows backend requires the installed xperf utility; the driver verifies its path and does not silently substitute another profiler.

receipt.json records wall intervals, PIDs/commands, hashes, timeout/error, and outputs. Raw stdout/stderr are retained; stages.log streams existing DM_BUILD_TRACE lines. profile_frames.py profile.json --output top10.json extracts observed inclusive/leaf sample weights from processed Firefox JSON. --receipt receipt.json filters the daemon body interval using Unix timestamps; absent interval/alignment fails explicitly. Null stacks or schema errors are coverage gaps. Weights are not exact CPU seconds; module and debug identity distinguish same-named symbols. Inspect the original profile before explaining costs.

Cold sampling launches `timed_command.py`, which records the actual unchanged
compiler command's PID, start/end timestamps, execution seconds and exit code in
`compiler-timing.json`. Compiler stdout/stderr are separate from sampler logs.
Samply's pinned Windows implementation samples descendants, then processes ETL
and symbolizes after the child exits; it can return zero after a failed child.
Therefore `cold_capture` is profiling overhead plus execution, never compiler
latency. Successful compilation requires the independent child receipt. Body
client intervals are measured directly. Source: samply-v0.13.1
`samply/src/windows/profiler.rs` and `profile_context.rs`.

A completed profile still requires captured-input incremental-versus-cold output/diagnostic equality and the preserved game parity comparison. This harness does not declare either passed.

`check_build_oracle.py --profile <completed run> --output <new oracle directory>`
builds the same captured source paths using independent Git/cache and output roots.
It compares complete DMB/RSC bytes and ordered stderr diagnostics (excluding named
build-trace records), retaining hashes, raw logs and mismatch/timeout evidence.
Each fresh command has its own five-minute bound. Oracle time is separate from
the measured iteration interval. An oracle mismatch leaves performance unqualified.

The coordinator verified sampler record/save-only/no-open/duration in a separate smoke. Presymbolication uses the release directory; keep matching PDBs. Tool hashes and bounded --version probe outputs are recorded; unsupported compiler version switches are recorded as such. Windows SetErrorMode3 suppresses native fault dialogs and child startup requests hidden windows. Optional output hashing/stage enrichment failures are recorded instead of preventing receipt.json.

## Storage fairness

Run directory may be on another drive, e.g. C:/Users/bmene/.codex/cache/native-v2-phase0-profiles while captured inputs remain D:. Immutable inputs use hardlinks when possible; EXDEV/WindowsERROR_NOT_SAME_DEVICE alone triggers byte copying. Other link errors fail visibly. The edited body remains a private copy. Required icons/sounds/maps/interface/source assets remain included. Root-level data and code-live-reference are excluded as copied runtime/duplicate reference trees, not compile-input asset folders. If a captured manifest actually references those roots, prepare a dedicated complete snapshot rather than using that exclusion.

Receipt records source/run/cache/output paths and drives, linked/copied file+byte totals, and input_preparation_seconds separately. Compiler phase events begin after setup, with a fresh bounded command budget. Compare compile latency separately from preparation and disclose differing disk locations/OS cache state. No existing run or frozen hardlink is removed or rewritten by this change.

Symbol coverage is separate from stack parsing. Address-only profiles never pass coverage_complete or the ten-named-hot-frames gate. Analysis uses embedded frameTable.nativeSymbol/nativeSymbols names when present. --symbols accepts an explicit JSON symbols address-to-name mapping; it rejects unknown sampler sidecar schemas rather than silently claiming symbolication. Keep actual *.syms.json sampler sidecars with profiles and verify their schema before conversion. Presymbolication requires matching PDBs and may still fail; profiler success alone does not satisfy Phase0 hot-frame attribution.

### Symbol sidecars

`profile_frames.py --symbols profile.syms.json` accepts samply's official
`PrecogSymbolInfo` schema: shared `string_table`, per-library `data` with
`debug_name`, `debug_id`, `symbol_table`, and exact RVA/index `known_addresses`.
Resolution joins Firefox `resourceTable.lib` to profile `libs`, then matches
`debugName` plus `breakpadId` and the frame's library-relative `address`. It never
uses a cross-library address map or guesses nearest symbols. The schema and exact
address lookup follow [samply symbol_precog.rs](https://github.com/mstange/samply/blob/main/samply/src/shared/symbol_precog.rs).
Embedded native symbols remain supported. Sidecar inlining/source locations are
not expanded; rankings show the recorded physical frame's outer symbol.

Stack coverage, global symbol coverage, and the named top-ten gate are separate.
The top-ten gate requires ten observed named hot frames, including a named
`dm-compiled`/`compiler-integration` frame; unresolved colder OS frames do not
fail that gate. Global complete symbol coverage still requires no unresolved
frame observations. A gate pass does not imply complete Rust PDB coverage.

## Timing and offline Windows ETL recovery

Keep three intervals distinct: input preparation, actual compiler child execution
from `compiler-timing.json`, and sampler capture/ETL processing/symbolication.
The current overall 300-second bound includes all three; it is not a full
300-second compiler allowance. A timeout during profile processing does not
retroactively make a completed child compile a timeout. Conversely sampler exit0
cannot prove the child succeeded. Preserve both outcomes separately.

Pinned samply0.13.1 `import --help` supports a kernel ETL followed by optional user
ETLs, process filtering, save-only and offline presymbolication. After an orderly
recording stop has produced valid ETLs, the coordinator can recover to a new
output path without relaunching the compiler:

```powershell
& 'D:/dmb-native-v2-phase0/profiler/samply.exe' import --save-only --no-open --unstable-presymbolicate --symbol-dir 'D:/dmb-native-v2-phase0/reference-release' --windows-symbol-cache 'RUN/symbol-cache' --pid COMPILER_PID --output 'RECOVERY/profile.json' 'RUN/kernel.etl' 'RUN/user.etl'
```

Replace `COMPILER_PID` with the exact child PID in its timing receipt, and replace
ETL paths with actual recorded paths; omit the user argument when absent. Keep
raw traces, original timeout receipts, tool hashes, recovery command/status and
matching PDBs. Offline conversion and symbolication are separate analysis time,
not compiler execution. An incomplete recording remains a partial profile even
when import succeeds; sample coverage must be assessed explicitly.

For future recording, `record --keep-etl` preserves exported ETLs. The default
Windows implementation deletes them after conversion and before saving JSON and
presymbolication, so a late failure may leave only JSON. Hard-killing the sampler
before its normal xperf stop/export does not guarantee valid ETLs or stop its
recording helper/session. Recover only after exact owned-session cleanup and
trace finalization; do not stop unrelated system recording sessions. This document
does not claim the current run retained valid ETLs or authorize an extra compiler
run. The coordinator owns any bounded recovery job.

### Pinned recorder session ownership and volume

Pinned Windows `xperf.rs` starts the default `NT Kernel Logger` with
`PROC_THREAD+LOADER+PROFILE+CSWITCH`, stackwalks `PROFILE+CSWITCH`, writes
`profile.kernel.etl`, and requests 1024KiB buffers. If optional user providers are
requested, their session is exactly `SamplySession` and its output is
`profile.user.etl`. These fixed names are not unique ownership tokens.

After an interrupted run, the coordinator must first inspect current logger
configuration and verify its output file equals the exact interrupted run path.
Only then is explicit `xperf -stop "NT Kernel Logger"` appropriate; separately
stop `SamplySession` only when its output path is verified to that run too.
An absent/mismatched logger is not permission to stop another session. Avoid
unnamed `-stop`, implicit `-d`, or `-cancel`: the pinned recorder normally uses an
unnamed stop internally, but recovery must retain evidence and prove ownership.
The installed `xperf -help stop` confirms explicit logger-name stopping.

Lower sampling rate reduces PROFILE sample events, not context-switch event
volume. This backend always captures systemwide CSWITCH stacks and filters
processes during conversion. `--cswitch-markers` and `--main-thread-only` affect
conversion/representation, not the kernel provider flags; neither promises a
smaller raw trace. Pinned samply exposes no context-switch disable option.
`--vm-hack` removes PROFILE and adds unrelated syscall/allocation/handle events,
so it is not a suitable CPU-profile volume remedy. A custom sampling-only xperf
recording would be a separately documented experiment requiring its own process
launch/timing/finalization ownership, not an unrecorded change to this harness.

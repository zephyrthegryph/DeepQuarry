# Preserved compiler sampling harness

Root owns executable jobs. The sampler has passed a separate smoke check; that
check is not a compiler measurement. Use release binaries from frozen ac1af55d1a
and keep their hashes. Historical PERFORMANCE.md 3.240s used optimized prototype
builds and warm OS caches, not a release empty-cache run.

Run profile_base.py separately with --scenario cold or --scenario daemon-body, --compiler <dm-compile.exe>, --daemon <dm-compiled.exe> for daemon mode, --builtins <builtin.dmb>, and --output <new directory>. Manifest defaults to the captured comparison.dme. Source defaults to D:/dmb-native-v2-phase0/frozen/source. Sampling defaults to D:/dmb-native-v2-phase0/profiler/samply.exe. Defines default CBT/CIBUILDING/CITESTING; pin them explicitly with --define=-DCBT etc. Verify frozen compatibility edits and input hashes against the baseline before attributing performance.

The driver creates a private source mirror with the edited file copied and other immutable inputs hardlinked. It excludes Git/cache/target directories and old DMB/RSC files. A new private Git common directory isolates compiler caches; daemon cache is also new. This is application-cold, not OS-cold. Frozen hardlinked inputs must stay immutable. Body mode completes a baseline, changes only tool_skill_factor return1 to return2 like measure-body-edit.ps1, then calls the existing build-project-daemon client. An unfinished baseline yields no body measurement.

Default and maximum overall deadline is300seconds including preparation. Watchdog stops process trees at285seconds, leaving15seconds for cleanup/receipts. Receipt hashing and stage summaries stop before the overall deadline and disclose missing hashes/truncation. No new memory cap is imposed. There is no promise of graceful compiler cancellation: hard termination may require cache recovery. Failed or timed-out runs remain partial receipts.

Prepared sampler invocation: samply record --save-only --no-open --unstable-presymbolicate --symbol-dir <release directory> --output profile.json -- <command>. A separate sampler smoke check passed; it is not a compiler profile or evidence of Rust symbol coverage. Daemon sampling includes startup+baseline+body. Stop attempts CTRL_BREAK then bounded hard cleanup; missing profile after termination is reported. Samply's Windows backend requires the installed xperf utility; the driver verifies its path and does not silently substitute another profiler.

receipt.json records wall intervals, PIDs/commands, hashes, timeout/error, and outputs. Raw stdout/stderr are retained; stages.log streams existing DM_BUILD_TRACE lines. profile_frames.py profile.json --output top10.json extracts observed inclusive/leaf sample weights from processed Firefox JSON. --receipt receipt.json filters the daemon body interval using Unix timestamps; absent interval/alignment fails explicitly. Null stacks or schema errors are coverage gaps. Weights are not exact CPU seconds; module and debug identity distinguish same-named symbols. Inspect the original profile before explaining costs.

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

Receipt records source/run/cache/output paths and drives, linked/copied file+byte totals, and input_preparation_seconds separately. Compiler phase events begin after setup; overall300-second watchdog still includes copying. Compare compile latency separately from preparation and disclose differing disk locations/OS cache state. No existing run or frozen hardlink is removed or rewritten by this change.

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

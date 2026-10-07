# dmb-bench — revision 5 protocol

The benchmark harness is scaffolding for root-run traces. It has not been run on the full project. No new acceptance result is claimed. Historical rows imported from A–K remain context only.

## Protocol

`dmb-bench.py` runs three repetitions at **8 workers**, then three at **2 workers** as a regression series. It appends individual runs and medians to `results.jsonl`. Each measured compilation runs with `--trace`. A separate, unmeasured `--verify` invocation compares a captured snapshot against its fresh cold oracle, including diagnostics. The harness also checks that its measured DMB/RSC hashes equal the verified installed pair. A failed oracle, moved frozen input or watchdog expiry cannot count as a performance result.

Every compiler invocation has a **285-second maximum watchdog**, including the oracle. A timeout stops only that invocation's process tree. Competing processes are observed, never stopped. The harness records visible process count and Cargo/rustc/DreamDaemon counts before and after compilation. The process-list scope excludes the harness; it is context, not a measure of runnable CPU contention.

Acceptance uses CPU, never wall time. `cpu_acceptance` checks critical-path CPU, total process CPU, stage CPU budgets, private memory and allocation measurement; median CPU must meet the scenario target and not regress more than 20% against the last three acceptance medians. Three repeats also cover the revision-5 rerun requirement for results within 10% of a budget. Two-worker rows cannot be acceptance rows.

`io_acceptance` is separate. Process-wide byte totals are compared to scenario budgets; overlapping per-stage process windows are never added. Missing blocked-I/O measurements remain `not_evaluable`, even when byte budgets pass. Missing critical-path CPU, stage CPU or allocation data likewise blocks CPU acceptance. No time or byte count is invented from another metric.

## Prepare isolated inputs

Use a **private frozen source mirror** prepared by the root coordinator. Files to edit must be private copies: the harness rejects symlinks and hardlinks for edited files. It never edits the main source tree by discovery. The supplied snapshot JSON names the captured inputs and their SHA256 hashes:

```json
{"commit":"ACTUAL_COMMIT","files":{"deepquarry.dme":"ACTUAL_SHA256","code/bench_probe.dm":"ACTUAL_SHA256"}}
```

Include every captured positive source/asset input, not just these example files. This manifest supplements the compiler's snapshot oracle; it does not replace its negative searches, directory facts or moved-input checks. Input hashes are checked before and after measured and oracle compilations, outside measured compilation time.

An ordered scenario file supplies compiler flags and exact edit replacements. `project` is inserted separately; `arguments` must not contain `--workers`, `--trace`, `--verify`, `--no-cache` or internal capture/replay flags. For example, use a dedicated isolated probe whose body is an exact unique replacement:

```json
[
  {"name":"cold","project":"deepquarry.dme","no_cache":true,
   "arguments":["--no-daemon","--engine-template","PINNED_TEMPLATE","--bootstrap-catalog"]},
  {"name":"body-edit","project":"deepquarry.dme",
   "arguments":["--no-daemon","--engine-template","PINNED_TEMPLATE","--bootstrap-catalog"],
   "edits":[{"path":"code/bench_probe.dm","before":"return 101","after":"return 102"}]},
  {"name":"unchanged","project":"deepquarry.dme",
   "arguments":["--no-daemon","--engine-template","PINNED_TEMPLATE","--bootstrap-catalog"]}
]
```

Each repetition restores the original private edit files, then performs the ordered scenarios. Edits require exactly one byte match. Original bytes are restored on exit, including failure. Output logs and traces are retained in a new evidence directory; it must not already exist.

## Run after profiler integration

```text
python tools/dmb/bench/dmb-bench.py --compiler FROZEN_DMBC_EXE --project-root PRIVATE_MIRROR --snapshot captured.json --scenarios scenarios.json --output NEW_EVIDENCE_DIRECTORY --stage-map stage-map.json
```

Replace the example compiler token with the actual frozen executable path. `--cache` defaults to `DMB_CACHE_DIR`, otherwise `E:/.dmbd/cache`. The harness checks at least 4 GiB free before population; `--min-free-bytes` is explicit. Compiler publication independently checks space. The harness does not evict files or stop processes to obtain space.

The profiler contract is schema 1. For trace `run.trace.json`, it reads `run.trace.report.json`, retaining `critical_path_cpu_s`, `total_cpu_s`, stages, I/O bytes, allocation availability and private memory. Chrome trace and sibling CPU/wall folded stacks and SVGs remain raw evidence.

`stage-map.json` must explicitly map nonoverlapping, sequential trace stage names to every revision-5 budget domain: `input`, `frontend`, `tree`, `resources_maps`, `abi_initializers`, `lowering`, `link`, `composition_publication`. Names must come from actual trace output. Do not map nested spans twice or guess names before instrumentation is wired. Critical-path totals must be issued by the profiler's explicit sequential top-stage configuration. Missing domains or metrics block acceptance.

The current harness supports cold, body-edit and unchanged scenarios. The broader edit corpus, history replay, daemon and six-worktree benchmark remain open. An eight-worker cold CPU baseline and ten-heaviest-span write-up are still required.

## Historical import

```text
python tools/dmb/bench/import-receipts.py E:/dmb-native-v2-phase0
```

The importer preserves raw small receipts byte-for-byte in `receipts/`, records their SHA256, and extracts available CPU/wall/memory fields plus scalar stage wall timings from hash-bound stats. It preserves later benchmark rows. Full stats files remain at their original evidence paths; their hashes are recorded. Existing historical output equality statements are in the archived narrative, not upgraded to a diagnostic oracle pass by the importer.

## Measurement-quality gate

CPU acceptance requires finite, nonnegative metrics (positive CPU totals), an identified thread clock, and a usable startup calibration. Windows must report positive cycle rate, calibration CPU and calibration wall duration. Native Linux thread CPU uses its nanosecond clock and does not need a cycle rate.

Covered exclusive thread CPU must agree with process CPU within **5%**. This is a measurement-quality tolerance, not permission to exceed an acceptance budget. The reported crosscheck must match its recorded totals; exclusive stage sums must match covered CPU. Missing clock samples, invalid stage names/counts, duplicate stages or inconsistent CPU sums decline acceptance. Allocation counting must be explicitly enabled and show observed allocations, not just a build-feature flag.

The report must include the exact unique `critical_path_stages` supplied to profiler completion. The harness checks their measured maxima against the reported critical-path total; the budget mapping must cover exactly those names. Missing coverage or calibration is `not_evaluable`, never a zero-cost stage.

Raw profiler reports are hash-bound in run rows. Nonfinite JSON measurements are retained in that raw report; ledger values become unknown with an explicit `profile_error`. The results ledger uses strict JSON (no NaN/Infinity).

Stage `read_bytes`/`write_bytes` remain **overlapping process windows**. Separate `attributed_io` rows retain explicit operation bytes and blocked durations; these are partial measurements, not complete stage coverage. I/O acceptance requires an explicit `io_coverage: "complete"` report plus measured blocked time. The current profiler does not issue that completeness claim, so I/O acceptance remains open even if process byte budgets pass. No stage-window or partial-operation sum is represented as full-process I/O.

### Authenticated unchanged shortcut

Unchanged acceptance requires the exact declared critical sequence `engine_input`, then `session_validation`. Both names must occur exactly once in the global eight-domain mapping. Only domains executed by that short sequence receive stage-budget checks. This exception does not apply to cold or body-edit traces: they still require every mapped stage and the complete eight-domain sequence. CPU quality, calibration, coverage, allocation and oracle checks remain mandatory.

Scenario total-CPU limits are 2.0 seconds for a body edit and 0.2 seconds unchanged, alongside critical-path limits of 1.5 and 0.25 seconds respectively.

# Runtime comparison inputs

`normalize_runtime.py --run byond:preserved=DIR --run byond:1=DIR --run byond:2=DIR --run byond:3=DIR --run native:preserved=DIR --run native:1=DIR --run native:2=DIR --run native:3=DIR --output report.json`

Each dedicated directory contains its own `unit_tests.json`, stdout/stderr, and copied `runtime.log.json` and `runtime-errors.log` where available. Do not combine global runtime-errors.log with a specific run's log. Structured JSONL is the selected detailed channel. Raw logs are independently streamed and counted, never summed with it. They are not assumed to be mirrors: historical raw logs can contain far more events. Reports include raw normalized counts and unmatched location/message counts; these heuristic multisets do not prove event correspondence. Complete cross-channel coverage is never asserted. When structured logs are absent, one raw source is selected in order: runtime-errors.log, stderr.log, stderr, stdout.log, stdout. Unrecognized lines are counted as parse coverage gaps; raw fallback cannot establish procedure coverage.

Logs are streamed. Per-test objects (including exact status/messages) are preserved unchanged in the report. Runtime identities retain procedure, source and line; first-line message numbers/references/timestamps are replaced heuristically. At most sixteen original first-line examples per identity/run are kept, each bounded to4096 characters; complete event text remains in the untouched input files. Numeric normalization can coalesce distinct errors: inspect raw records before assigning a semantic cause. Do not use these normalized identities as compiler correctness proofs.

`:1`, `:2`, `:3` are repetitions. Other labels are preserved comparison inputs, not a substitute for three replays. Presence/count variability is reported separately from deterministic differences. Observed distribution differences from three runs are evidence to investigate, not statistical proof. Missing logs, malformed records, missing procedures/locations or missing test entries prevent complete comparison coverage. Equality is never automatically declared.

The existing game structured recorder has no reliable per-event active test field. Such events are ownership-unavailable, not non-test-owned. Only explicit test/test_path fields establish ownership. Per-test runtimes are reported independently and never added to log event counts. This also retains errors belonging to passing tests and startup/other unowned periods.

Baseline format inspected read-only: E:/projects/CHOMPStation2/tools/dmb/target/full-suite-comparison-dcd1b1f39fe14bd6a3ad65fd8d2bc1da/byond-runtime-final/data/logs/native-compiler-6475a3d057ca4f5eabab43addc3dae04/runtime.log.json and runtime-errors.log. JSONL contains a header followed by runtime events with msg/proc/source embedded text. Raw log has time source.dm:line message records. No replay or normalization job was executed while preparing this tool.

## Finalization eligibility and provenance

Use `finalize_baseline.py` after all six corrected receipts prove normal completion.
It checks pinned external-fixture identity and rejects an explicitly ineligible
runtime overlay. Earlier complete-but-missing-fixture observations stay separate
audit evidence, not one of the three eligible repetitions. Source snapshot, pair
and engine identities are recorded in evidence.json with complete raw inputs.

Engine closure is an independent coverage dimension: pre-launch, post-run or
missing. The first corrected run predates the runner's closure preflight field;
a matching later check cannot be relabelled pre-launch. The pinned twelve hashes
without a check timestamp establish expected identity, not the timing of a live
check. No audit is silently invented. Observed mismatches fail finalization;
missing or post-run checks remain explicit limitations.

Preserved-vs-current comparison normalizes every line of complete failure messages
and retains their originals. It reports absent preserved signatures/counts, stable
deviations and variable observations separately. New/dropped cross-compiler
divergences are identified only from fully present stable observations, not treated
as proof of semantic improvement. An observation outside a three-run count range
is descriptive, not a statistical significance test. Unknown event ownership stays
unknown even when a test's result message contains a background runtime.

## Complete observations with abnormal terminal exits

A complete-results-abnormal-exit observation retains exact selection coverage,
results, suite-finished and shutdown evidence, an observed terminal exit code,
and no watchdog/runner stop. It is eligible as one of three observations, and
resume skips it after the same pinned-input checks. It is **not** a healthy run:
normal_exit_gate_passed remains false, and finalization reports all three exit
codes per producer plus stable/variable exit outcomes. A crash after complete
results is not erased by a zero-failure marker or excluded to manufacture a
healthy-only baseline. Truncated, timeout, memory-limited, unknown-exit and
clean-marker-grace forced-stop runs remain incomplete. Existing receipts are
reclassified only by coordinator append-only proof/audit, preserving originals.
This explicit contract supersedes earlier text requiring normal exit for result
observation completeness; the normal-exit/reproduction gate remains separate.

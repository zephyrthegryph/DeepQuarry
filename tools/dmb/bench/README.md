# dmb-bench — revision 6 protocol

This harness does not build compilers or launch DreamDaemon. Historical revision 5 receipts retain their original interpretation; they are not upgraded to revision 6 acceptance evidence.

## Frozen cold cohorts

The initial revision 6 implementation accepts `cold` scenarios only. Cached body-edit and unchanged cohorts are rejected until their authenticated warm-up/session-isolation protocol is implemented. This avoids presenting a cold recomputation as an incremental measurement.

Each configured worker count runs **ABABAB**: three previous-binary and three new-binary invocations in alternating order. `--self-comparison` uses the same frozen binary for both labels to measure the current noise floor. Eight workers supply acceptance rows; one and two workers are diagnostic series. Every invocation has a maximum **600-second** watchdog and owned-process cleanup. At least **25 GiB** free on E: is required before measured runs. Competing processes are recorded and never stopped.

Before measurement, the harness reads every captured input. With `--input-journal`, it reads the pinned journal index, index hash, and every unique captured payload, without copying the source tree per repetition. Warm-up time is recorded separately. Compiler, metadata, inspector, diagnostic policy, source manifest and BYOND comparison receipts are pinned. Compiler flags and input journals remain identical between A and B.

Measured cold invocations bypass disk memos and session hits with `--no-cache`. An unmeasured fresh invocation must produce identical DMB/RSC hashes and identical normalized diagnostics. Unknown diagnostic-shaped messages are not discarded by the shared normalization policy.

## Structural gate

The inspector interface is:

```text
dmb-inspect structural-diff EXPECTED.dmb ACTUAL.dmb REPORT.json SNAPSHOT_ID
```

The BYOND sidecar must pin `snapshot_id`, `dmb_sha256`, and `semantic_configuration`:

```json
{"project":"comparison.dme","defines":{"CIBUILDING":"1","CITESTING":"1","DM_VERSION":"516","DM_BUILD":"1687"},"byond_version":{"version":516,"build":1687},"native_engine_template_sha256":"EXACT_SHA","bootstrap_catalog":true}
```

`configuration_evidence` lists `{path,sha256}` receipts containing the successful BYOND command/output hash and native explicit engine/bootstrap command. `byond_version_evidence` pins a metadata JSON `{compiler_sha256,file_version:"5.0.516.1687"}` tied to the successful BYOND receipt. Both definition forms follow the compiler's exact validation and last-write-wins order. Unknown semantic flags and implicit engine paths fail closed. File-only `snapshot_id` remains compatible, but rows/cohort receipts separately record `semantic_configuration_sha256`; neither identity silently substitutes for the other. Structural traversal and tool ownership/decoding coverage must be complete for measurement admission. Semantic interpretation coverage is reported separately and may remain incomplete when every unknown site has an exact wire fingerprint. Full semantic coverage plus zero unexplained differences is reported separately as strict parity; it is not inferred from a successful compiler exit or a deterministic fresh oracle.

`--self-comparison --establish-structural-baseline` records complete existing divergence counts without claiming zero parity. Later `--structural-baseline structural-admission.json` admission requires sorted exact case fingerprints from the inspector (`signature_algorithm: md5-length-framed-v1`, `category_signatures: {category: [case_hash, ...]}`). Every current case must exist in the baseline and category counts may not grow; removing old differences is allowed. Bounded examples and counts alone cannot prove that the same cases differ. Unknown cases have separate `uncovered_signatures` and occurrence counts; their current cases must also be a subset with no count growth. Missing exact unknown evidence blocks structural no-regression, while explicitly incomplete semantic interpretation alone does not block valid measurements. A same-snapshot pinned native pair sidecar (`--native-baseline`) can alternatively prove DMB/RSC byte identity when it also pins the same semantic configuration digest. Missing tool ownership/decoding, invalid branches or a mismatched source snapshot block measurement admission.

## Binary metadata

`--profile-metadata` and `--previous-profile-metadata` pin the exact executable SHA256 and these build facts:

```json
{"compiler_sha256":"EXACT_BINARY_HASH","measurement_revision":6,"profile":"release","lto":"thin","debug":"line-tables-only","codegen_units":16,"allocator":"mimalloc","allocation_counting":false,"compiler_commit":"EXACT_COMMIT","source_archive_sha256":"EXACT_SOURCE_HASH"}
```

`--binary-mode acceptance` requires counting disabled. A separately frozen `--binary-mode counting` executable records allocation diagnostics; its CPU is never accepted as the performance baseline. The build coordinator supplies trusted metadata; the harness verifies identity, not executable build flags by inspection.

Windows CPU comes directly from GetThreadTimes at natural stage boundaries, with quantization bounds and an independent process-CPU crosscheck within 5%. Item rows report wall/allocation data only and are excluded from CPU sums. Budget mapping must cover exactly the declared critical chain without nested double counting. Measurement admission and Phase0 structural baseline admission are separate from performance target acceptance and full semantic parity. Missing CPU/tool coverage blocks admission. Unavailable I/O blocking measurements or missed throughput/memory targets remain explicit failures/not-evaluable budget results; an unmet optimization target does not discard otherwise valid baseline measurements.

## Invocation

```text
python tools/dmb/bench/dmb-bench.py --compiler FROZEN_DMBC --profile-metadata FROZEN_METADATA --self-comparison --establish-structural-baseline --project-root PINNED_ROOT --snapshot SOURCE_MANIFEST --input-journal PINNED_JOURNAL --scenarios COLD_SCENARIOS --output NEW_EVIDENCE_DIR --inspector FROZEN_INSPECTOR --byond-dmb PINNED_BYOND_DMB --byond-snapshot PINNED_BYOND_RECEIPT --stage-map STAGE_MAP
```

Scenario JSON uses `name`, `project`, and `arguments`; harness-owned options cannot be overridden. Per-scenario `input_journal`, `byond_dmb`, `byond_snapshot` and `structural_baseline` can pin an alternate exact fixture.

## Retention and safety

Completed rounds remove their owned compiler cache before the post-round free-space check. Incomplete rounds stay available for diagnosis. Retention retries leftover artifacts and records each cleanup attempt.

Only marker-authenticated E: artifact directories created by this harness are eligible for recursive cleanup. All protected paths are checked first; reparse points are refused. Bulky output stores and compiler artifacts are disposed immediately after the native-fresh output/diagnostic oracle passes and the structural invocation finishes. Structural coverage or parity may still fail; their small reports and output hashes remain, and cleanup does not upgrade those gates. Receipts, profiler reports, folded stacks, raw diagnostic logs and output hashes remain. Failed runs remain intact. Across sibling owned revision 6 cohorts, at most the three newest completed oracle-valid runs retain full Chrome traces. Older eligible traces are removed while their small evidence remains. This retention eligibility does not mean semantic coverage is complete. Outputs with a failed/missing native-fresh oracle remain intact. Cleanup failures are explicitly reported rather than counted as successful pruning.

Read-only Windows output links are preserved rather than changing shared inode attributes, which could affect pinned or global RSC hardlinks. Cleanup limitations are written to the receipt, and the free-space gate still applies. Pinned sources, BYOND output, compiler references and unrelated directories are never pruned.

## Captured source body-edit trace

wall_s and child_wall_s measure process launch through process reap. profile_wall_s covers only the profiler window, ending before report serialization. Older receipts without child_wall_s cannot recover end-to-end time; summaries leave it unavailable.

The `cold-body-edit` scenario runs an authenticated, separately pinned captured
journal with one exact same-length procedure-body literal replacement. This is
an edited-source cold trace; it makes no claim about daemon or warm incremental
latency and receives `diagnostic_only` performance admission. CPU quality,
complete structural traversal/no-regression, and fresh-output equality remain
mandatory for Phase0 measurement admission. Both measured and fresh compiles use
`--no-cache`, distinct output stores and artifact directories, and the same
edited journal. Both normalized stdout and stderr must agree.

Keep `--input-journal` pinned to the immutable parent journal. In the scenario,
provide `name: cold-body-edit`, `input_journal` for the derivative, and
`variant_receipt` plus its explicit `variant_receipt_sha256`. The receipt uses the
existing schema1 derivative format: original/edited journal index and checksum
SHA256 pins, `original_snapshot`, `snapshot`, `physical_source_changed: false`,
and `overlay_sha256` for sibling `overlay.json`. The overlay pins its canonical
source path, old/new xxh3_128 payload identities and SHA256s, equal byte length,
and one uniquely matching before/after text. Capture closure paths, directory
entries and negative inputs must be identical. Rust replay independently checks
its native index checksum and every requested payload. No frozen source is edited.

An edited scenario must also supply `byond_dmb`, `byond_snapshot` and (when
comparing a previous baseline) `structural_baseline` for that derivative. The
BYOND pin must contain the edited index SHA256 as `snapshot_id`, the exact
`variant_receipt_sha256` as `source_variant_sha256`, the BYOND DMB hash, and the
normal authenticated semantic configuration/defines and BYOND tool evidence.
An original-source BYOND pin is rejected. Preparing that reference requires a
private BYOND source derivative containing the identical single edit, compiled
with the same semantic configuration; preserve its source/provenance receipt.
The original journal, source closure, and BYOND pair remain immutable.

Captured no-cache replay authenticates the journal index and checksum before/after each run, and pins its exact BYOND snapshot/configuration. It does not hash unrelated live physical source files; replay verifies every requested payload and refuses uncaptured reads. Live scenarios retain full physical SHA256 validation. This change affects unmeasured preparation only. Receipts name the closure-validation mode and pin benchmark methodology files. Oracle-valid private output bundles may clear readonly attributes only after all NTFS links are proved internal to the jointly owned output roots; outside or pinned links remain untouched.


### Asymmetric retained-session isolation

The existing native-iteration runner accepts an optional zero-based `sessions`
array on an edit row. For example, assign a body edit to `[0]` and a new-proc
edit to `[1]`; sessions 2 through 5 remain unchanged. Omit the array to preserve
the existing all-session edit behavior. Every session is still requested from
the same owned daemon and compared independently against a fresh native build.

A partial assignment is labeled `six-session-isolation-probe`, not full
acceptance. Full six-worktree byte acceptance requires body, new-var, new-proc
and default edits in every root, plus all fresh byte oracles and existing
worktree/source/process proofs. An isolation probe requires distinct body and
structural sessions and at least one entirely unchanged session. Existing
worker and memory bounds apply. Scenario labels alone never certify outputs.

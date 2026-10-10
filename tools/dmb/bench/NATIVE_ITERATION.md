# Real-project iteration checks

`native-iteration.py` runs initial population, unchanged, body edit and structural
edit requests through one owned daemon, followed by an independent fresh native
byte oracle after each revision. It records client launch-to-reap wall time,
compiler stats/last-run telemetry, output SHA256 and total end-to-end time. This
is functional/iteration evidence, not runtime parity or r6 CPU/memory admission.

Example (explicit binary must already exist):

```powershell
python tools/dmb/bench/native-iteration.py --compiler E:/path/dmbc.exe --inspector E:/path/dmb-inspect.exe --edits E:/dq-cache/dmb-native-v2/iteration-609/edits.json --workers 2
```

For six real worktree sources, provide `--worktree-sources E:/path/roots.json`,
an array of exactly six distinct E: Git checkout/worktree roots, and
`--project deepquarry.dme` when those sources use the production manifest.
Each worktree is independently isolated under a unique E:/dq-cache run root.
Cold population is limited by the worker budget. After population, six retained
clients are submitted concurrently per revision; the owned daemon enforces
`DMB_DAEMON_MAX_WORKERS` from `--total-workers` (default two). The runner checks
its startup observation and rejects old binaries that ignore the requested
limit. Concurrent clients queue without increasing the active worker budget.
Fresh native oracles run sequentially
after the entire retained burst. Stable per-session publication destinations
exercise unchanged-output reuse. All daemon and client requests inherit a new
run-specific `DMB_CACHE_DIR`; historical cache population is excluded.

`--one-shot-requests` switches requests to cache-enabled `--no-daemon` builds
for the six-concurrent-one-shot contract. This mode does not demonstrate daemon
reuse and its six independent pools have no daemon-wide worker ceiling. Use two
workers and explicitly review concurrent memory availability before running it.
This does not test compaction under load or same-session publication races.

The captured BYOND structural comparison is mandatory (`--inspector`). Defaults
pin `frozen/pairs/byond/world.dmb`, `byond-structural-pin.json`, the source
snapshot and authenticated input closure under `review-power-focus`.
The pin authenticates BYOND output/configuration evidence. Before any build,
the source snapshot must exactly match the pin's authenticated source-closure
roster; each isolated initial source is checked against that roster and bytes.
Configuration equality is reported separately. Source-identical initial and
unchanged comparisons can establish baseline admission only with complete
tool/semantic coverage and zero differences. Existing differences leave that
gate explicitly open without invalidating a passing native/fresh byte oracle.

Edited rows compare against the original captured BYOND output and are labeled
cross-revision diagnostics only; they cannot establish edited-input BYOND
parity. Every report exposes coverage and category/uncovered counts and retains
the full raw evidence by path/SHA. Identical inspector/input/output/configuration
contexts may reuse authenticated raw report evidence within this invocation;
fresh native byte oracles are never reused. Inspector failures fail the run.
Successful invocation alone never establishes structural or runtime parity.

Each edit JSON entry contains `kind` (`body` or `structural`), relative `path`,
`before` and `after`. Each anchor must occur exactly once. Edited files are
private copies from the outset and replaced atomically. Other inputs use
hardlinks. Git state, compiler state, Cargo targets, node_modules and generated
DMB/RSC outputs are excluded. Reparse paths are rejected; no readonly attributes
are changed. Inputs, old receipts and output artifacts are never deleted.

The runner refuses any pre-existing daemon and verifies the server process ID
before and after each child. `--require-owned-daemon` is an explicit capability
opt-in for binaries implementing `DMB_DAEMON_AUTOSTART=0`; older binaries must
omit it. Without that policy, a disappearance/auto-start race fails the run and
leaves any replacement untouched. Every compiler child has a 300-second
watchdog; the overall deadline defaults to 1800 seconds. Workers are 2 or 8.

## Integration audit

Current `tools/build/lib/compiler_selection.ts` implements:

- `DQ_COMPILER=byond` by default; native success avoids DreamMaker.
- Native DM source-error status 2 and cancellation status 75 never fall back.
- Internal statuses 1/70 and launch/infrastructure exceptions fall back with a
  named reason. Other unexpected statuses do not silently fall back.
- Shadow native output uses an isolated artifact directory/store and named
  structural comparison, preserving the conventional BYOND output location.

Shadow now validates schema, snapshot label, all nine mandatory categories and
count consistency. Inspector failure, malformed evidence, incomplete traversal,
incomplete tool/semantic coverage, and any discrepancy fail with distinct
classification in `structural-admission.json`. Only complete zero-discrepancy
reports with an authenticated shared input closure can establish structural
parity. This is stricter than admitting a known
historical burn-down baseline; shadow has no such baseline input.

Remaining acceptance gaps in that adapter:

- The shadow context records configuration and output evidence, but the
  compiler-issued shared BYOND input-closure capability is not yet available.
  Even a complete zero-discrepancy report remains incomplete without it;
  manifest identity or native positive reads cannot substitute for that proof.
- Native integration requires explicit compiler/template paths. The direct
  runner verifies `--artifact-directory` output hashes; it does not exercise
  `build.ts`, nightly scheduling, diagnostic corpus parity, or test-slot pair-ID
  acquisition. Those require separate integration gates.
- The six-source option tests independently isolated copies of real worktrees,
  not mutation of existing user worktrees. It supplies concurrency/output
  correctness evidence, not the six-session retained-memory budget proof.

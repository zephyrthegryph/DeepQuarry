# Preserved runtime replay

Coordinator invocation (do not run concurrently with another runtime job):

```powershell
powershell.exe -NoProfile -File tools/dmb/phase0/replay-runtime.ps1 -FrozenRoot D:/dmb-native-v2-phase0/frozen -OutputRoot D:/dmb-native-v2-phase0/runtime-replays
```

Requires the pinned `pairs/byond/world.{dmb,rsc}`, `pairs/native/world.{dmb,rsc}`
and the complete frozen runtime overlay. The default reference engine is BYOND
516.1687 console dd.exe.
The frozen `expected-runnable-tests.txt` is required and supplied as `test-select`:
the original comparison ran its 1,089-test intersection, rather than every type
present in either output. Its hash is recorded for each replay.
The runner makes six serial launches, alternating BYOND
and native for each of three repetitions. It copies the entire preserved runtime
for each run (no writable shared links), then copies its pinned pair into that
runtime. No source is recompiled, no bytecode patched, no Procmon launched.

Original baseline controls remain a 2 GiB private-memory ceiling and 3600-second
watchdog, port0, trusted headless mode, error mode3, normal test tier. Runtime
setup/copy duration is recorded separately. Raw logs, full unit_tests.json,
clean marker and runtime files stay under each run. A run containing failed tests
is still complete evidence; incomplete runs are labelled, never silently omitted.

The preserved binaries govern seeds. The runner supplies no new RNG parameter;
seed values emitted in raw results/logs must be recorded by the normalizer.
Do not assert that a source file's current seed is necessarily compiled into a
preserved binary. Pair/engine hashes, engine file version, PID, command parameters,
control limits, timing and completion receipts accompany every run. Frozen source
identity and compatibility-overlay manifest should be attached from the root
coordinator's frozen-snapshot receipt, not inferred by this runner.

The `clean-marker-shutdown-grace` label means results plus clean marker were present
but the child required stopping after the original three-second grace. Timeout,
memory-limit and runner-error cases remain incomplete even if partial JSON exists.
Only the launched child PID and descendants are stopped. Every runtime directory is
unique; existing frozen files and original outputs are untouched.

## Finalization after all six runs

Do not run this while replays are active. Example (replace snapshot/preserved paths
with the coordinator's actual receipts and raw run directories):

```powershell
python tools/dmb/phase0/finalize_baseline.py --replay-root D:/dmb-native-v2-phase0/runtime-replays/replay-7c646... --output-root D:/dmb-native-v2-phase0/parity-final --snapshot-receipt D:/dmb-native-v2-phase0/frozen/snapshot.json --preserved byond:preserved=<raw-byond-run> --preserved native:preserved=<raw-native-run>
```

The tool refuses fewer than six complete clean-marked receipts. It copies each
unit_tests.json plus its nested structured/runtime-error logs into a separate
normalizer input directory, hashes evidence, then invokes normalize_runtime.py
with explicit --run arguments. An ambiguous nested log is an error, not guessed.
`--run LABEL=DIRECTORY` can point to a coordinator-prepared unambiguous view.
It never changes preserved runs. REPORT.md is a compact observation summary;
normalized.json retains every test's status/message/runtime-count distributions,
original result objects, coverage and stable-versus-variable runtime identities.
Even complete coverage does not establish equality from finite observations.

## Pause and resume

Future invocations accept `-PauseBetweenRuns D:/.../pause.marker`. Create that marker
while a run is active: the current run finishes, and the runner returns before
launching the next unfinished run. Remove it to resume with the same limits and
`-ResumeSession <exact replay-ID directory>` plus its parent `-OutputRoot`.
A session OS file lock prevents two updated coordinators running together.

Complete receipts are skipped only after validating engine SHA256, both frozen
pair hashes, frozen runtime path, required selection-file SHA256 and control limits.
Incomplete/running directories are NEVER overwritten or automatically moved.
The coordinator must stop its own remaining child and explicitly preserve/move that
single directory before retrying. This also protects sessions started by older
runners that do not hold the new coordinator lock. No existing runner can acquire
pause support merely because its source file changed; it has already loaded its script.

## Corrected completion contract

Frozen world.dm FinishTestRun writes clean_run.lk ONLY when no runtime or test
failures exist. Its absence is expected for the preserved failing baseline. Suite
completion instead requires exact selected-test JSON coverage, the matching
`Unit-test suite finished: N test types,` log line, `Shutdown complete`, normal
exit0 and no watchdog/runner stop. The runner records these independently; clean
marker remains a pass-quality observation. Earlier receipts are not rewritten
by these tools: the coordinator may append proof-backed corrected classification.
An interrupted native setup with only copy.log is not a completed runtime run.

Future replay launches authenticate all twelve pinned engine EXE/DLL files against
frozen-engine.json immediately before each unfinished run. Engine preflight JSON
records check time, manifest hash, every actual file hash/length and mismatches.
A mismatch refuses launch. This is a provenance check, not proof of future immutable
DLL contents. Finalization records missing engine audits as coverage limitations;
a post-run audit is explicitly not relabelled a prelaunch check. An observed audit
that disagrees with pinned hashes prevents finalization.

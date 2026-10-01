# Native compiler build integration

The normal build entry points select their compiler with `DQ_COMPILER`:

| Selector | Produces the conventional `.dmb` / `.rsc` | Checks |
|---|---|---|
| `byond` (default) | BYOND | Existing build checks |
| `native` | Rust compiler | Immutable generation and detached conventional pair |
| `shadow` | BYOND | Cached Rust versus an isolated fresh Rust build; informational BYOND structural/map/resource differences |

The adapter is in `tools/build/lib/byond.ts`, used by the build and test targets.
`DQ_NATIVE_COMPILER` selects the executable; otherwise release then debug binaries
under `tools/dmb/target` are searched. `DQ_NATIVE_DAEMON=127.0.0.1:47616` selects an
already running compiler daemon. Unset it to use a standalone process. This
integration never launches DreamDaemon.

```powershell
$env:DQ_COMPILER = 'native'
$env:DQ_COMPILER_STRICT = '1'
bin/build.cmd
```

The Rust entry point can also be used directly:

```powershell
tools/dmb/target/debug/dm-compile.exe integrated-build deepquarry.dme --mode native --strict --builtins tools/dmb/fixtures/native_template.bin -DCITESTING
tools/dmb/target/debug/dm-compile.exe integrated-build deepquarry.dme --mode shadow --byond 'C:/Program Files/BYOND/bin/dm.exe'
```

## Target and failure contract

The native target is **BYOND 516.1687**. `DQ_NATIVE_TARGET` / `--target` must name
this supported target. Adding another patch release requires updating the target
catalog and running its compiler fixture gates; an installed newer BYOND does not
silently select another native target. Shadow mode probes the reference BYOND
version and requires an exact match.

The checked-in `native_template.bin` is identified by its SHA-256 digest and
decoded header. `DQ_NATIVE_BUILTINS` / `--builtins` selects another builtin schema;
custom schemas require a sibling `NAME.target.json` (for `NAME.bin`) containing
`{"target":"516.1687","sha256":"lowercase digest of the schema"}`. That is the
custom schema producer's compatibility declaration, not evidence that new native
targets have passed fixture gates.

Errors use `file:line:error: message`. Source errors, unsupported source constructs,
configuration errors and comparison failures fail the build. Automatic fallback
is allowed only after a proven internal failure, such as a panic, missing native
executable, transport failure or publication I/O failure. The reason is printed
as a visible warning and saved in the report. `DQ_COMPILER_STRICT=1` / `--strict`
disables fallback for native acceptance and CI. Legacy compiler errors represented
only by strings are conservatively classified as source failures.

`.dm-native/PROJECT.dme/integration.json` records `producing_compiler`,
`native_gate_passed`, failure/fallback classification, target, builtin/source
digest, generation and timings. BYOND fallback is never a native pass. Shadow
success currently proves cached/fresh native byte equality at the same expanded
source revision; BYOND differences are reported, and bytecode/runtime equivalence
is not claimed. Comparisons cap structural and map discrepancies at 200.

## Publication and persistence

Native output generations live under `.dm-native/PROJECT.dme/native/generations`.
Generation v2 identity depends only on the DMB/RSC byte digests and lengths; every
publication route uses that identity. Legacy v1 generations remain readable.
An unchanged immutable RSC can be reused by a verified archive token.

Conventional `PROJECT.dmb` and `PROJECT.rsc` are detached copies. Editing them
cannot mutate a generation or a shared cache. A locked recovery journal under
`.dm-native/publication/PROJECT.dme` recovers an interrupted pair installation;
an unchanged conventional RSC is preserved. Conventional consumers must be stopped
before publication. Immutable generation readers remain independent of this
compatibility installation. There is no cross-file atomic view for readers that
ignore the journal/lock; those consumers should use immutable generation paths.

Ordinary CLI and daemon builds use `SessionKey.build_mode = canonical`, producing
the same bytes after an edit/revert regardless of cache/history. The explicit
`build-project-patch` and `build-project-patch-daemon` commands select
`legacy-history`, require exclusive ownership, and are excluded from build/test
integration. `build-project-json` exposes the canonical structured response.

`DM_COMPILER_CACHE_ROOT` overrides every stage's project cache root. Shadow mode
spawns a fresh child with an empty private cache root; it does not mutate the
daemon environment or reuse persistent frontend/lowering artifacts for its
reference build. Fresh reference directories are retained beside native output
for inspection. Normal caches remain shared through Git's common directory.

## Focused gates

```powershell
cd tools/dmb
cargo test -j1 -p dm-output --lib -- --test-threads=1
cargo test -j1 -p dm-compile --bin dm-compile --test integration -- --test-threads=1
cd ../..
bun test tools/dmb/integration/policy.test.ts
```

For a small six-worktree acceptance gate, build the two binaries once, then run:

```powershell
pwsh -File tools/dmb/integration/accept-six-worktrees.ps1 -Compiler tools/dmb/target/debug/dm-compile.exe -Daemon tools/dmb/target/debug/dm-compiled.exe
```

The driver creates six actual linked worktrees in an owned temporary fixture
repository. It checks initial/unchanged builds, six independent procedure edits,
revert identity, daemon restart with disk caches, and exact DMB/RSC equality
against sequential fresh builds with isolated caches. Native acceptance requires
zero fallback. It runs at most two clients together, limits the daemon and client
process memory, samples aggregate private memory and stops its own processes if
the aggregate budget is exceeded. Sampling is an additional guard, not an atomic
OS-wide memory reservation. Logs and `acceptance.json` are retained; it never
starts a world or runs a DM suite.

`-Worktrees` can supply six existing worktree roots with `-ProjectFile` and
`-Defines`. Their source is left alone, so edit/revert phases are skipped for this
mode. Conventional output publication still updates their generated DMB/RSC.
The large-project mode is opt-in; the default gate remains the tiny fixture.

### Commit replay

`replay-commits.ps1` creates one actual detached Git worktree inside a new owned
result directory. `-Commits` selects explicit commits in the supplied order;
otherwise `-Last N` selects the last N first-parent commits, oldest first. It
never checks out or edits the original repository, refuses unexpected source
changes, and uses checkout without overwriting ignored-file collisions.

```powershell
pwsh -File tools/dmb/integration/replay-commits.ps1 -Compiler tools/dmb/target/debug/dm-compile.exe -Daemon tools/dmb/target/debug/dm-compiled.exe -Last 3
```

The daemon remains alive across revisions. Each revision's canonical build is
compared with a fresh standalone child using an empty all-stage cache. The gate
requires successful native production, zero fallback, the same expanded source
digest and exact full DMB/RSC SHA-256 equality. `replay.json` retains commit IDs,
binary/builtin digests, timings, lowering reuse and output digests. Fresh artifacts
are removed only after a successful comparison to bound disk use;
`-KeepFreshArtifacts` retains them. Failed output and the linked worktree remain
available for review.

Large historical projects may need generated ignored art. `-AssetOverlayRoot`
copies only untracked assets from `-AssetDirectories` (default `icons/gen`) once;
it never replaces tracked files. The overlay manifest digest is recorded, so
results are described as commits plus that asset snapshot. A missing or invalid
historical source revision fails visibly; it is not counted as native parity.
The live daemon plus fresh reference share the sampled aggregate budget and
their separate process ceilings. An overrun stops owned processes and preserves
the report; the driver does not raise its memory limit automatically.

### Small compiler-error captures

`check-errors.ps1` runs six small probes with native and reference BYOND 516.1687:
a valid procedure, explicit preprocessing error, missing include, unterminated
string, unknown procedure and unknown type. It requires zero native fallback and
records both raw logs and located diagnostics in `errors.json`.

```powershell
pwsh -File tools/dmb/integration/check-errors.ps1 -Compiler tools/dmb/target/debug/dm-compile.exe -Byond 'C:/Program Files/BYOND/bin/dm.exe'
```

This gate compares success/failure and whether both failures are proven source
errors. It does not rewrite messages or claim that differing diagnostics mean
the same thing. Unlocated nonzero BYOND exits remain unclassified (or internal
for abnormal negative process codes), not source parity. The existing
`dev-scripts/correctness_reports.py` can compare the captured diagnostic logs
for exact message differences independently. The three drivers share hidden,
owned-process, bounded log/memory handling in `process.psm1`.

## Reusable compiler facts

`dm-compile analysis-jsonl PROJECT.dme [-DNAME]` exports the `dm-analysis` versioned
JSONL snapshot: declarations, exact authored signature headers, inheritance,
expanded-to-source line origins and diagnostics. Each header states coverage.
Resolved references remain explicitly unavailable until semantic resolution
supplies them. This export is a detached snapshot suitable for documentation and
linting; it does not pin a live daemon database.

# Archived compiler usage

These instructions describe commit ac1af55d1a. The commands below require that reference checkout or its frozen executable; the prototype command/daemon crates are removed from native-v2. They do not describe the new compiler's implementation or performance.

## Preserved original incremental prototype

The following commands and performance documents describe the older compiler
retained for baseline comparison, rather than completion of the native v2 design.

See [implementation status](IMPLEMENTATION_STATUS.md) for verified native
frontend coverage, measured cache performance, and remaining integration work.
See [iteration performance](PERFORMANCE.md) for cache validation and timings,
and [parallel workers](PARALLEL.md) for bounded daemon concurrency.

The `crates/` workspace contains a DM preprocessor, parser, semantic model,
BYOND code generator, daemon coordinator, and output publisher. For a small
project containing supported global procedures, run:

```powershell
cargo run --manifest-path tools/dmb/Cargo.toml -p dm-compile -- build-project tools/dmb/fixtures/native_compiler/simple.dme tools/dmb/fixtures/native_template.bin tools/dmb/target/project-output
```

This writes an immutable validated `world.dmb` / `world.rsc` pair under
`project-output/generations/` and appends its content ID to `HEAD`. An identical
rebuild reuses the files. A torn final `HEAD` line is ignored by readers and
repaired by the next publication. `dm-output` also has a fixed-layout in-place
patch API for exclusive ownership of an existing pair.
`build-project` uses a persistent content store even without a daemon. For a
long-lived process, `dm-compiled` accepts `BuildProject` requests through the
`dm-compile build-project-daemon` command.
For an output pair owned exclusively by the compiler, `build-project-patch`
updates fixed-layout changes in place with an undo journal. It rejects layout
changes; use `build-project` to publish a new immutable generation then.
`build-project-patch-daemon` performs the same operation through the daemon.
The `--exclusive` flag asserts that the server is stopped and no other process
is reading or writing either output file. Both live output paths must exist.
An interrupted patch is rolled back from its journal before the next request.

```powershell
cargo run --manifest-path tools/dmb/Cargo.toml -p dm-compiled -- 47616
cargo run --manifest-path tools/dmb/Cargo.toml -p dm-compile -- build-project-daemon 127.0.0.1:47616 tools/dmb/fixtures/native_compiler/simple.dme tools/dmb/fixtures/native_template.bin tools/dmb/target/project-output
cargo run --manifest-path tools/dmb/Cargo.toml -p dm-compile -- build-project-patch tools/dmb/fixtures/native_compiler/simple.dme tools/dmb/fixtures/native_template.bin C:/path/to/live.dmb C:/path/to/live.rsc --exclusive
cargo run --manifest-path tools/dmb/Cargo.toml -p dm-compile -- build-project-patch-daemon 127.0.0.1:47616 tools/dmb/fixtures/native_compiler/simple.dme tools/dmb/fixtures/native_template.bin C:/path/to/live.dmb C:/path/to/live.rsc --exclusive
```

The daemon patch command writes only changed spans to the live DMB/RSC pair;
it does not publish a second complete output generation. The shared disk cache
stores DMB and RSC as separate content-addressed blobs, linked by a small
manifest. A code-only edit writes a new DMB blob and reuses an identical RSC
blob across builds and worktrees. Verification of published output can reuse a
persisted proof of unchanged files; missing or invalid proofs require digest
verification. Patch builds verify their exclusively owned live output pair.
Set `DM_BUILD_TRACE=1` on the daemon process to print timing for discovery,
hashing, resource fingerprinting, cache lookup, compilation, and output work.

Safe procedure-body edits reuse a persisted linked checkpoint and lower only
changed procedures through per-procedure Salsa inputs. Unchanged procedures
keep their IDs; new strings and locals append to existing tables. Checkpoints
live under the shared cache root, survive non-daemon builds and cold starts,
and are versioned and checksummed, with a 64 MiB record limit and 32 retained
records per compilation context. Signature, declaration, static initializer,
procedure metadata, map, resource, or compiler-context changes fall back to a
full build. Corrupt checkpoint records also fall back to compilation.

The direct compiler emits type inheritance, class/global/static variables,
dynamic initializers, procedures and verbs, world settings, DMM templates,
resources, and active skins. Procedure lowering includes structured control
flow, exceptions, arrays, named arguments, safe access, constructors, and a
growing native-verified builtin catalog. Full-game output generation passes;
runtime integration and complete language/metadata coverage remain in progress.
The daemon verifies source, map, and asset contents and resource search-path
shadowing before reusing retained project inputs.
Project builds hash source, map, and asset bytes before using a cached output. The
preprocessor separately caches leaf includes against their source and incoming
macro state, so a changed include can reuse unaffected siblings. The leaf
cache has bounded path, macro, and byte budgets; large macro environments
are preprocessed without retaining a snapshot for every include.
Its versioned cache is saved at
`<git-common-dir>/dm-compiled-cache/preprocess-v3/` as per-project indexes and
content-addressed expansion shards, and loaded by new CLI
processes. The project ID comes from the Git-relative DME path: matching worktrees
share a cache, while separate project manifests keep separate entries.
Standalone projects use `.dm-cache/` beside the DME. Macro fingerprints and
changed definitions replace full macro snapshots; retained preprocessing cache
data is capped at 160 MiB. Cached inputs retain a SHA-256 digest and byte length;
source origins retain compact line offsets and share their path allocations.
Procedure cache records are closed and atomically renamed without a disk
barrier per procedure. Missing or damaged records are rebuilt after validation;
published output and patch journals use their own durability rules.
The one-shot `dm-compile check PROJECT.dme` diagnostic caps expanded source
at 16 MiB before building a whole-project AST; set `DM_CHECK_MAX_SOURCE_BYTES`
to an explicit byte limit when testing a larger parser input. This cap does
not apply to project builds. Project builds have a separate 64 MiB default
limit, configurable with `DM_BUILD_MAX_SOURCE_BYTES`. They parse procedure bodies
individually. Daemon build-input snapshots have a separate aggregate 96 MiB
budget that includes dependency tables and strong metadata proofs, so projects
near the expanded-source limit can still retain their input snapshots.
Both CLI and daemon additionally use a
Windows process memory ceiling of 2 GiB; `DM_MEMORY_LIMIT_MB` changes it
(`0` explicitly disables the ceiling). `dm-compile preprocess PROJECT.dme`
checks preprocessing without constructing the full-project AST.
Compiler work runs on a dedicated thread with a 16 MiB stack; the process
memory ceiling also applies to that thread.
`dm-compile audit-project PROJECT.dme` also inventories parser gaps in
256 KiB chunks, retaining at most 50 diagnostic samples. It reports skipped
oversized declarations explicitly. Saved expansions automatically invalidate
when the preprocessor or lexer changes. Active DMF skins are tracked as assets,
and mixed UTF-8/Windows-1252 source text is decoded before preprocessing.
Project builds retain compact declarations and parse one procedure body at a
time. The default declaration chunk budget is 1 MiB, configurable with
`DM_BUILD_MAX_PARSE_CHUNK_BYTES`; oversized declarations are reported.

The whole-project audits work without producing a DMB or starting a server:

```powershell
$env:DM_PREPROCESS_DUMP = 'tools/dmb/target/expanded.dm'
dm-compile preprocess deepquarry.dme -DCITESTING
dm-compile audit-source tools/dmb/target/expanded.dm
dm-compile audit-declarations tools/dmb/target/expanded.dm
dm-compile audit-initializers tools/dmb/target/expanded.dm tools/dmb/fixtures/native_template.bin
dm-compile audit-lowering tools/dmb/target/expanded.dm tools/dmb/fixtures/native_template.bin
```

The lowering audit reports grouped failures and source spans. Passing it means
the procedures can be lowered independently; it does not establish linking,
metadata, resource, or runtime correctness.
The `dm-resources` crate provides deterministic RSC entries and content
fingerprints for asset inputs. Literal resource expressions and constant
declarations now produce paired DMB/RSC entries; the build cache invalidates
when an asset changes. Positional `file(...)` and `icon(...)` calls, plus named
`icon(...)` arguments, are lowered; some resource-bearing metadata remains
unsupported.

Build configurations can pass `-DNAME`, `-DNAME=VALUE`, or `--define NAME=VALUE`
after the normal arguments to `check`, `check-project-daemon`, `build-project`,
`build-project-daemon`, and `build-project-patch`. For example, append
`-DCITESTING` to select the unit-test build. Defines participate in session
identity, preprocessing, active map selection, and output cache keys.

Project builds also persist symbolic procedure code before linking it to DMB
table IDs. Editing one procedure reuses unchanged procedures on the next build,
including a new CLI process or daemon restart. The portable keys cover the body,
resolved names/types, and a fingerprint of the Rust compiler sources. Keys track
the names used by each procedure, so adding unrelated declarations in another
worktree preserves reuse. Member-type and inheritance changes invalidate affected
lookups. These
artifacts live in `<git-common-dir>/dm-compiled-cache/proc-lowering-v1/`, shared
by worktrees; standalone projects use `.dm-cache/proc-lowering-v1/` beside the
DME. Corrupt entries are rebuilt. The in-process procedure cache is capped at
16 MiB. The daemon retains up to eight diagnostic sessions and bounded syntax
summaries, while the disk artifacts remain available after eviction.

Parsed procedures are persisted separately under
`<cache-root>/proc-parse-v1/<compiler-fingerprint>/`. Their spans are stored
relative to the procedure and relocated for the current source. Immutable
packs let concurrent worktrees publish independently and reuse open readers
without opening one file per procedure. Active packs have a combined 256 MiB
budget, at most 32 segments and 100,000 indexed records; individual records
are capped at 2 MiB. Checksums and structural validation reject damaged
records and fall back to parsing. Parsed trees are consumed individually.

The small server integration fixture can be built and executed in trusted mode:

```powershell
./tools/dmb/dev-scripts/native_runtime_smoke.ps1 -ByondDirectory 'C:/path/to/BYOND516/bin'
```

It checks dynamic class/global initializers, static locals, method and field
access, renamed methods, inherited dispatch, nested labeled loops, comparison
values, list iteration, try/catch, switch, output, and shutdown. The run must
print `RUST_COMPILER_SMOKE 23` without a runtime error and exit within its
15-second watchdog. This fixture passes on BYOND 516.1687; it does not certify
the full game.

For integration, build the actual unit-test configuration with
`-DCBT -DCIBUILDING -DCITESTING`, then run the resulting generation with:

```powershell
./tools/dmb/dev-scripts/run_project_tests.ps1 -DmbFile C:/path/to/generation/world.dmb -ByondDirectory 'C:/path/to/BYOND516/bin'
```

This uses trusted mode, a six-minute watchdog, and a 2 GiB runtime memory
limit. Results are isolated under `tools/dmb/target/runtime-tests/`; the runner
requires nonempty test results and the game's clean-run marker. Its working
directory is the repository root so runtime configuration and FFI libraries
resolve normally. `-RuntimeDirectory` selects an isolated runtime asset tree.
`-TestNamesFile` selects existing compiled tests using the game's `test-select`
parameter. Supply one absolute `/datum/unit_test/...` path per line; no
recompilation or bytecode patch is needed for this selection. The runner
requires fresh result JSON and a clean shutdown marker before reporting success.
Child native crash dialogs are suppressed while crash exits remain failures.

The current game test-room template contains two missing type paths. For a
comparison against the current native compiler, prepare a disposable overlay:

```powershell
$overlay = ./tools/dmb/dev-scripts/prepare_test_asset_overlay.ps1 | ConvertFrom-Json
./tools/dmb/dev-scripts/run_project_tests.ps1 -DmbFile C:/path/to/generation/world.dmb -ByondDirectory 'C:/path/to/BYOND516/bin' -RuntimeDirectory $overlay.RuntimeDirectory
```

This replaces those paths only in a copied template. Use the same overlay for
native and Rust outputs; it does not change the source worktree or imply that
unrelated game failures are compiler defects.

`byond-dmb` is a standalone Rust package for reading and writing Dream
Maker's compiled files. It parses the BYOND 516 DMB container into typed
tables and its RSC companion archive. Procedure bytecode is split into
instructions with exact operand boundaries. All opcodes observed in both
DeepQuarry builds have identified operations; value tags and variable access
modifiers have typed decoders in `src/operands.rs`.
`Instruction::typed_operands()` also exposes nested variable accesses, tagged
constants, and switch case tables; every instruction in both compiled builds
passes typed operand decoding and word-for-word reassembly.


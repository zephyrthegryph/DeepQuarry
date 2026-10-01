# BYOND compiled format tooling

## Incremental compiler prototype

See [implementation status](IMPLEMENTATION_STATUS.md) for verified native
frontend coverage, measured cache performance, and remaining integration work.
See [iteration performance](PERFORMANCE.md) for cache validation and timings,
and [parallel workers](PARALLEL.md) for bounded daemon concurrency.

See [persistent compiler architecture](ARCHITECTURE.md) for the proposed complete
incremental query graph, reusable analysis APIs, shared disk caches, parallel
scheduler, linker and binary patch design. It includes the measured bottlenecks,
implementation stages, and explicit correctness and reuse contracts.
The accepted [revised architecture](REVISED_ARCHITECTURE.md) supersedes its output
and persistence policies. [Correctness gates](CORRECTNESS.md) distinguish verified
fixture parity from pending real-project runtime and performance checks.

Canonical output is the default: recorded semantic dependencies validate cached
symbolic procedures, and linking uses a fixed source order. Every publication is
an immutable generation. Unchanged assets reuse the verified RSC by identity.
Transactional redb metadata and batched procedure caches survive daemon restarts
and share a Git-common cache across worktrees. `DM_COMPILER_CACHE_ROOT` overrides
all native cache stages for an isolated fresh reference.

The build adapter supports `DQ_COMPILER=byond|native|shadow`. Internal failures
may fall back visibly to BYOND; source errors do not. Set `DQ_COMPILER_STRICT=1`
to forbid fallback. Shadow produces BYOND output and checks native output against
an independent fresh native build. `analysis-jsonl` exports versioned declaration,
signature, inheritance and origin facts with explicit reference coverage.

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
The following patch commands are explicit legacy experiments, excluded from the
canonical integrated build and test path. For an output pair owned exclusively
by the compiler, `build-project-patch`
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

Explicit legacy-history procedure-body edits reuse a persisted linked checkpoint and lower only
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
growing native-verified builtin catalog. Earlier game snapshots produced full-game
output. Current game compilation, runtime parity and real structural-edit latency
remain active integration gates; unsupported source constructs are diagnosed.
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
Procedure syntax and semantic records use bounded transactional snapshots and
batched writes, without a database operation per procedure. Legacy packs are
read-only migration inputs. Missing or damaged records are rebuilt after validation;
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

## Resource archive

An RSC file is a concatenation of entries. Each entry starts with a
little-endian `u32` payload length and a one-byte validity flag. Valid entries
(`1`) have a 17-byte metadata header, a NUL-terminated filename, and resource
data:

| Field | Size |
| --- | ---: |
| resource kind | 1 byte |
| resource ID | 4 bytes |
| record timestamp | 4 bytes |
| imported source timestamp | 4 bytes |
| declared size | 4 bytes |
| filename | variable bytes plus NUL |
| data | rest of entry |

Invalid entries (`0`) are kept as opaque bytes. The declared size is the length
of the current asset data. Some RAD slots have unused trailing bytes.
The resource ID is NQCRC of exactly the declared-size prefix, initialized to
`0xffffffff`. All 3,911 main-build and 3,852 test-build named resources match
this rule. `NamedResource::from_data()` creates new entries with matching IDs;
`Dmb::attach_resource()` adds them to the paired files.
Native BYOND 516.1687 paired probes verify UTF-8 resource names for Latin,
Greek and CJK filenames. Filenames remain byte strings to preserve other
archives without assuming their encoding. Writing parsed entries preserves
all bytes. See [RESOURCE_FILENAME_ENCODING.md](RESOURCE_FILENAME_ENCODING.md).
`Entry::deleted_named_resource()` can inspect former named metadata in a deleted
slot when its bounds and content CRC still validate. Incremental native probes
show that other deleted slots can contain split asset fragments and unused
capacity; the writer preserves those bytes and their deleted status.
The observed kind codes for text/skins, MIDI, sound, DMI, BMP, PNG, ZIP, RSC,
JPEG, GIF, and fonts have
typed `ResourceKind` values; other byte codes remain available as `Other`.

From the repository root:

```powershell
cargo test --manifest-path tools/dmb/Cargo.toml
cargo run --manifest-path tools/dmb/Cargo.toml -- rsc-info deepquarry.rsc
cargo run --manifest-path tools/dmb/Cargo.toml -- rsc-copy deepquarry.rsc copied.rsc
cargo run --manifest-path tools/dmb/Cargo.toml -- dmb-info deepquarry.dmb
cargo run --manifest-path tools/dmb/Cargo.toml -- dmb-copy deepquarry.dmb copied.dmb
cargo run --manifest-path tools/dmb/Cargo.toml -- pair-info deepquarry.dmb deepquarry.rsc
cargo run --manifest-path tools/dmb/Cargo.toml -- opcode-audit deepquarry.dmb
cargo run --manifest-path tools/dmb/Cargo.toml -- rsc-id-audit deepquarry.rsc
```

The source fixture in `fixtures/v516_builtins.dme` can be compiled with
Dream Maker 516 and inspected with `opcode-audit`. It exercises the
new arithmetic, associative-list, vector, and pixloc operations whose
opcode names and operand shapes were derived from compiler output.
`fixtures/proc_flags.dme` isolates verb flag and invisibility encodings.
`fixtures/arguments.dme` isolates argument type and `in` encodings.
`fixtures/proc_source.dme` isolates verb source selectors;
`fixtures/mob_sight.dme` isolates sight settings;
`fixtures/hidden_initializer.dme` shows runtime initialized variable markers;
and `fixtures/movement_mode.dme` exercises the optional header word.

The original local BYOND 516 `deepquarry.rsc` sample has 3,911 named entries and 347 opaque
entries. The `rsc-copy` output was SHA-256 identical to the 247,868,564-byte
input. This verifies lossless parsing and serialization of the outer archive,
including preservation of invalid entries. The BYOND 516 DMB also rewrites
byte-for-byte identically, including strings, map, classes, procedures, and
resource references. All 3,835 DMB resource references are present in the RSC.
These counts describe the original investigation samples; the fresh native
comparison and translated artifacts are tracked in `doc/audits/PARITY_REPORT.md`.
The corresponding test-build DMB and RSC also rewrite byte-for-byte
identically.
The bytecode decoder and encoder cover every procedure in both builds. The
world record exposes client script text and its file-reference list separately.
The variable-table footer resolves to global declaration flags.
Class accessors decode initial opacity, density, visibility, luminosity,
gender, mouse opacity, animation movement, appearance flags, and compiled
mouse-event handler bits. These encodings were checked against small Dream Maker
fixtures, including isolated mouse and luminosity variants.
Class initializer assignments and procedure argument records are available as
typed Rust records. The `0x3e` hidden initializer marker is kept distinct from
the generic list table.
`Dmb::replace_proc_code()` installs an edited instruction stream into a fresh
list slot, so shared lists stay intact. It validates instruction boundaries;
callers must still supply correct jump targets and stack behavior.

The supported DMB dialect is `world bin v516` with 16-bit or 32-bit
object IDs, as selected by header flag `0x40000000`. Several small
Dream Maker 516 fixtures with 16-bit IDs and compatibility settings
from v514 through v516 round-trip byte for byte, including the optional
extended header word. See [FORMAT.md](FORMAT.md) for the table layout,
verified counts, and remaining semantic gaps. The package preserves every
observed byte. Native probes identify the feature bits observed in the matched
game header. The byte following `client.control_freak` records authored
client Import-handler presence, with paired zero/nonzero native specimens. Unobserved encodings and runtime equivalence remain
separate from lossless file round trips.

## OpenDream JSON translation (experimental)

`dmb-inspect od-to-dmb` accepts OpenDream's compiled JSON, an OpenDream
baseline JSON, a Dream Maker native scaffold DMB, a resource root, and output
paths. It builds DMB/RSC tables, remaps IDs, and lowers the OpenDream
instructions currently understood by `src/od_lower.rs`. Unsupported
instructions and values produce errors with the procedure and byte offset.
This is a **partial translator**: a successful write confirms container and
reference validity. Runtime behavior must be checked for the translated
constructs a program uses.

The native scaffold supplies Dream Maker's built-in classes and procedures.
The OpenDream baseline identifies OpenDream's built-ins so they are not
mistaken for authored game code. Generate both from the same minimal source,
using the same BYOND target version as the game being translated. The source
is [`fixtures/native_template.dme`](fixtures/native_template.dme), which
includes only `/world`. Keep compiled outputs in a temporary directory:

```powershell
$stage = Join-Path $env:TEMP 'dmb-scaffold-v516'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item tools/dmb/fixtures/native_template.dm,tools/dmb/fixtures/native_template.dme $stage
Push-Location $stage
try {
    & 'D:\Program Files (x86)\BYOND516\bin\dm.exe' native_template.dme
    & 'C:\path\to\DMCompiler.exe' --version=516.1687 native_template.dme
} finally {
    Pop-Location
}
```

For a program compiled by that OpenDream build, run from the repository root:

```powershell
cargo run --manifest-path tools/dmb/Cargo.toml -- od-to-dmb `
    C:\path\to\program.json `
    "$stage\native_template.json" `
    "$stage\native_template.dmb" `
    C:\path\to\project-root `
    C:\path\to\output.dmb `
    C:\path\to\output.rsc
```

The resource root is the source project's directory; paths in OpenDream JSON
are resolved relative to it. Keep the output `.dmb` and `.rsc` together and
use the same base name. The scaffold must be a BYOND v516 world with no game
map or resources. The CLI validates typed cross-table references before it
writes either output. The CLI uses the input JSON filename stem as Dream
Maker's default world name; an explicit `/world.name` in the program wins.
Add `--debug-lines` after the output RSC path to emit Dream Maker's source
file/line markers from OpenDream `SourceInfo`. Optimized OpenDream JSON can omit
some line events; compile with `--no-opts` when exact debug-line coverage is
needed.

### Validation and present limits

The independent source fixtures in
[`fixtures/translation/`](fixtures/translation/README.md) cover variables,
lists, branches, calls, inheritance, a map with an object override, and a file
asset. All seven translated DMB/RSC pairs produced the expected startup log
lines in bounded DreamDaemon 516.1687 checks on 2026-09-26. The OpenDream JSON
loader parses real compiler output, and the DMB/RSC reader/writer round-trips
the two DeepQuarry builds byte for byte. These checks cover the constructs in
the fixtures; they do not prove general semantic equivalence. The translator
retains explicit errors for unproved OpenDream bytecode and constant forms.
Native probes identify the header fields observed in these builds. The current
DeepQuarry export passes lowering for all 59,982 procedures. Its complete
DMB/RSC emission passes reference, instruction and branch audits. The latest
completed package gate passes 564 tests (453 core), including the
wide-string-ID regression. Resource registration order matches all 3,856
native entries. Paired trusted full-game servers complete initialization;
shared baseline runtime errors remain. The translated-only lighting null turf
error is traced to map numeric constants and repaired. The repaired full-game
trusted boot completes initialization with zero translated-only runtime errors
in the captured log comparison. Playable-round parity is unverified.
The full translated DM suite completes with 982 passed, 34 failed, and 58 skipped;
14 native-passing tests fail translated. See [`doc/audits/DM_TEST_REPORT.md`](doc/audits/DM_TEST_REPORT.md).
Remaining structural bytecode differences are under review. The exporter
preserves the original length mutations and native extension instructions.
See [`doc/audits/PARITY_REPORT.md`](doc/audits/PARITY_REPORT.md) for the current integration results
and [`TRANSLATION_GAPS.md`](TRANSLATION_GAPS.md) for historical snapshots and
remaining limits.

Compare captured native and translated server errors with
`python scripts/compare-runtime-logs.py native.log translated.log`. The script
reports shared and unique errors with counts and source lines, and exits 1 for
translated-only errors. It checks reported errors; reaching initialization or
matching logs does not establish gameplay equivalence. Runtime validation uses
trusted mode.

The pinned OpenDream exporter can write optional metadata needed for Dream Maker
parity: `ExplicitAnything` and `TypePath` for arguments,
`ExplicitInvisibility` for verbs, and provenance-filtered `ExplicitTypeFields`
and `ExplicitWorldFields` for authored assignments that equal defaults. The
exporter additionally records `DynamicDeclarationFields` and ordered
`DynamicInitializerAssignments` for native dynamic value markers; paired
fixtures cover list declarations and overrides, object creation, and particle
generators. `Globals.DynamicInitializerGlobalIds` records authored global and
static declarations whose runtime initializer needs a marker; diagnostic
`InitializerValueKinds` fields describe expression classes. Argument
`PossibleValuesProc` points to an isolated companion proc for `arg in expression`
sources. Type records preserve `VariableDeclarationOrder` and
`VariableOverrideOrder`, and map objects record `OverrideOrder`;
`ConstantInitializerFields` plus
assignment counts identify constant values left in OpenDream initializer
procedures. `ResourceAliases` preserves source spelling when case-insensitive
file lookup resolves to another spelling. `ResourceArchiveNames` separately
preserves decoded authored archive names while `Resources` identifies physical
files. This retains case, dot segments, and slash/backslash aliases without
using an external physical path as the archive name. Identical payloads share
one DMB resource reference while the RSC retains every authored name. Native runtime resource identity is the content CRC alone: even aliases with different file extensions share the first resource reference and its kind, while each RSC entry retains its own extension kind.
The preprocessor honors `#pragma multiple`, which restores the nine
DeepQuarry turfpack classes absent from stock OpenDream JSON; absolute argument
paths also create implicit class entries, including `/datum/disease/advance/A`.
The
exporter also writes the interface path with `/` separators so its resource
path remains project-relative on Windows. The
[`combined compiler patch`](patches/opendream-combined-1362abc.patch) and
[`multiple include patch`](patches/opendream-multiple-include-1362abc.patch) target
OpenDream commit `1362abc5accbc2037df9b45efa1de13fb1bb677f`. The Rust
loader accepts JSON with or without these optional fields. The build requires
the .NET 10 SDK and initialized RobustToolbox submodule.

```powershell
git -C C:\path\to\OpenDream submodule update --init --recursive
& tools/dmb/scripts/build-patched-opendream.ps1 `
    -SourceRoot C:\path\to\OpenDream -Dotnet C:\path\to\dotnet.exe
```

The patched exporter records optimized `ImplicitLocateOffsets` per procedure:
implicit `locate(value)` emits native unary `LocateRef`, while an explicit
`in world` or list container emits binary `LocateType`. Old JSON without the
annotation remains readable, but cannot recover that lost distinction.
Declaration namespaces (`var`, `proc`, and `verb` blocks) do not create phantom
types; root global verbs retain `/verb/name` and the native `/verb` namespace.
Class and world method memberships preserve native override precedence:
overrides precede declarations, with newest definitions first within each phase.
Ordered paired tests check procedure bodies and argument metadata as well as paths.
Constant `file()` and `icon()` declaration initializers receive native hidden
markers; constructors depending on runtime globals retain null defaults.
The Rust loader accepts both old and extended JSON. See
[`TRANSLATION_GAPS.md`](TRANSLATION_GAPS.md) for exact coverage and
remaining limitations.

The earlier full static diagnostic snapshot emitted 189 warnings; this count is historical. Modified type
constants now retain their overrides, while verb source metadata survives
OpenDream's warnings and is translated by the DMB writer. The counted warning
families are in [`doc/audits/OPENDREAM_WARNING_AUDIT.md`](doc/audits/OPENDREAM_WARNING_AUDIT.md).

With generated icons available, a temporary diagnostic manifest can produce
full DeepQuarry JSON without changing game source:

```powershell
& tools/dmb/scripts/compile-deepquarry-opendream.ps1 `
    -Compiler C:\path\to\OpenDream\bin\DMCompiler\DMCompiler.exe `
    -OutputJson D:\opendream-diagnostic\deepquarry-diagnostic.json `
    -ScratchRoot D:\opendream-diagnostic
```

The patched compiler accepts the original `length()` mutations and recognizes
`load_ext` as an intrinsic. This probe supplies a bare test-only type required
by both compilers and adapts the build manifest for static comparison.
Add `-NativeConditionalBranches` for a static comparison with a Dream Maker
build. The temporary overlay undefines OpenDream's `OPENDREAM` macro before
project includes, so native-only branches such as `lootpanel/open` are present
without modifying tracked game source. Leave it off for an OpenDream runtime
build.

For a fresh paired reference, add `-NativeCompiler C:\path\to\dm.exe`
and `-NativeOutputBase C:\path\to\reference` together with
`-NativeConditionalBranches`. This compiles both outputs from the same temporary
manifest and copies native `.dmb`, `.rsc`, and `.log` files to that base path.
The compatibility type is declared after the game includes. In this source
snapshot, the generated gas-holder temperature getter incorrectly redeclares an
inherited procedure; the diagnostic manifest supplies a temporary copy using
override syntax for both compilers. Its body is unchanged. Original game files
are not edited.

The validation script checks paths only by default and does not start
DreamDaemon:

```powershell
& tools/dmb/scripts/validate.ps1 -OpenDreamJson C:\path\to\program.json `
    -DmbPath C:\path\to\output.dmb
```

For paired Dream Maker and translated DMBs, compare compiled classes,
procedures, arguments, locals, and normalized bytecode without starting
DreamDaemon. Optional path prefixes restrict the report to authored code:

```powershell
cargo run --manifest-path tools/dmb/Cargo.toml -- dmb-compare `
    C:\path\to\reference.dmb C:\path\to\output.dmb /world/New /obj/my_type
```

The comparison reports differences and exits with an error when it finds any.
It also errors when a supplied path filter matches no class or procedure; use
the full compiled path (for example `/proc/my_proc` rather than `my_proc`).
It normalizes symbol IDs through their table records and branch targets to
instruction positions, but keeps opcode choices and other numeric operands
visible. Compiler optimizations can still appear as differences even when
behavior is equivalent.

For a large OpenDream JSON, `od-diagnostic` checks table construction,
bytecode lowering, and cross-table references without reading or compressing
resource payloads. It writes no DMB/RSC files:

```powershell
cargo run --release --manifest-path tools/dmb/Cargo.toml -- od-diagnostic `
    C:\path\to\program.json C:\path\to\baseline.json `
    C:\path\to\native_template.dmb C:\path\to\resource-root
```

The diagnostic uses placeholder resource IDs; its in-memory result is not a
runnable world. Run `od-to-dmb` after the diagnostic passes.

When the full diagnostic stops at the first unsupported procedure,
`od-lowering-audit` attempts every procedure independently and groups its
first lowering error. It writes no output files:

```powershell
cargo run --release --manifest-path tools/dmb/Cargo.toml -- od-lowering-audit `
    C:\path\to\program.json C:\path\to\baseline.json `
    C:\path\to\native_template.dmb C:\path\to\resource-root --examples=10
```

`--examples=N` shows up to N procedure names and byte offsets per error
family (default 1, maximum 100). Add --debug-lines to audit the same source-marker path used by debug DMB emission.

`od-map-audit` compares the emitted map tables directly with a native DMB
before bytecode lowering is complete. For two completed DMBs, use
`dmb-map-compare REFERENCE.dmb OUTPUT.dmb` instead.
`od-class-audit` performs the same early check for class paths, parents,
declarations, defaults, and initializer presence. It takes the same five
arguments as `od-map-audit` and hashes asset bytes so resource values can be
compared with the native DMB. Add `--grouped` to count every mismatched class
field across the program and show the largest families.
Add `--paths` to list every differing field path without large value dumps.
`od-proc-audit` takes the same five arguments and compares procedure metadata,
arguments, locals, class membership, and initializer presence before bytecode
lowering is complete. Use `--grouped` to count differences by field or
`--field=proc.count` to list one field's affected paths.
Add `--semantic-values` to either command to compare objects within each map
cell regardless of their storage order and to compare straight-line constant
instance overrides by final field value. Initializers with calls, branches, or
reads still require exact bytecode parity.
With the pinned exporter patch, the full DeepQuarry map passes this semantic
comparison against its native BYOND 516 DMB.

```powershell
cargo run --release --manifest-path tools/dmb/Cargo.toml -- od-map-audit `
    C:\path\to\program.json C:\path\to\baseline.json `
    C:\path\to\native_template.dmb C:\path\to\resource-root `
    C:\path\to\reference.dmb
```

Runtime checking is an explicit opt-in. Use it only for a fixture you intend
to execute; it starts DreamDaemon in trusted mode, hidden on a random port, captures the log,
and stops the process it started:

```powershell
& tools/dmb/scripts/validate.ps1 -OpenDreamJson C:\path\to\program.json `
    -DmbPath C:\path\to\output.dmb -RunDreamDaemon `
    -DreamDaemon 'D:\Program Files (x86)\BYOND516\bin\dd.exe' `
    -ExpectedLog 'CALLS 8 8'
```

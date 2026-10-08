# BYOND compiled format tooling

## Native v2 (Phase 0/1 integration)

[DESIGN.md](DESIGN.md) defines the replacement architecture;
[STATUS.md](STATUS.md) records current evidence and unfinished gates.
The new uncached command uses captured semantic inputs and publishes an
immutable DMB/RSC pair before installing the conventional manifest output paths:

```powershell
cargo run -j1 --manifest-path tools/dmb/Cargo.toml -p dmbc -- compile deepquarry.dme --workers 2 -DCITESTING=1 --progress
```

This path is experimental and does not yet admit the complete project. Unsupported
semantics fail before output publication. No daemon or incremental reuse is
implemented in this path yet. The pinned target is BYOND 516.1687; the driver
supplies its default version macros and accepts explicit source defines.

On Windows, pairs share `%LOCALAPPDATA%/dmbd/pairs` on that drive and
`<drive>:\.dmbd\pairs` on other drives.
`--output-store PATH` selects an alternative store and is required for network
volumes. Other platforms currently use `.dmbc/outputs` beside the project.
One worktree's complete capture/compile/install
sequence holds an OS lock; different worktrees have independent build locks.
Conventional output files are compatibility copies; run consumers should acquire
the authenticated pair through `publish::PairStore`.

## Preserved compiler reference

The original prototype's usage and measurements are archived in
[REFERENCE_COMPILER_README.md](phase0/REFERENCE_COMPILER_README.md).
Its command, daemon, compiled-artifact and output-host crates are removed from
this workspace. Frozen reference outputs and executables remain the Phase 0
baseline; the new command above is the supported experimental path.

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
python tools/dmb/check_source_shape.py
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

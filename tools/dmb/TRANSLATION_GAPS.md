# OpenDream translation coverage and gaps

The translator targets BYOND 516 DMB/RSC and requires a Dream Maker native
scaffold plus an OpenDream baseline made from the same minimal source. It does
not infer either baseline from a game binary. `od-to-dmb` uses the input JSON
file stem as Dream Maker's default world name; callers translating another
project name must pass that name through `translate_named`.

## Current integration

Full DM-suite execution now exposes 14 native-passing/translated-failing tests.
The complete translated result is 982 passed, 34 failed, and 58 skipped. Native
records 991 passed, 25 failed, and 58 skipped. No test result key is missing.
See [`doc/audits/DM_TEST_REPORT.md`](doc/audits/DM_TEST_REPORT.md); the translation is not fully passing.

See [`doc/audits/PARITY_REPORT.md`](doc/audits/PARITY_REPORT.md) for current static gates and residual
classification. The latest completed package passes 564 tests (453 core),
including the wide-string-ID regression; all 59,982 game
procedures lower, emitted instructions and typed references validate, and no
checked branch destination is invalid. Archive registration order matches all
3,856 native entries. Paired trusted full-game servers complete initialization,
with shared baseline errors. A translated-only null turf error in lighting is
traced to map numeric constants and repaired; the full repaired trusted boot
completes initialization with zero translated-only errors in captured logs.
Playable-round parity and unresolved mixed bytecode
differences remain under investigation. DEBUG versus release initializer-token
sharing now has native proofs; the full-game audit pairs 19,617 marker records
without missing, split, or merged groups. Historical
hashes below identify their own snapshots and must not be used for the current
artifacts.

## Historical DeepQuarry audit (2026-09-27)

The patched OpenDream export contains 59,982 procedures. The full grouped
lowering pass of `deepquarry-nativemethods.json` reports **zero errors**.
Its matching baseline is `native_template_nativemethods_5161687.json`, with
metadata version `FDA1F9ED59C3ADD83FECC57BA6F3C157`.
Field assignment and modification ordering, conditional indexed destinations,
safe-expression joins, and native method display-name bindings have paired
native regressions. All 341 Rust tests, all targets, and Clippy with warnings
denied pass. Complete file emission and structural validation are recorded
separately below; procedure acceptance does not establish whole-game runtime
equivalence. The export for this historical snapshot had 189
warnings. Modified type expressions and verb source declarations retain the
information needed for native emission; remaining warning families still need
paired validation for runtime parity.

### Complete emitted files

The same export successfully produced a 55,456,121-byte DMB and a
217,619,930-byte RSC. Reading the generated DMB resolves all typed table
references. All 62,318 emitted procedures decode and reassemble with zero
failures and zero unknown instructions. Its 3,835 resource references resolve
against 3,856 RSC entries, with zero missing resources. Both generated files
round-trip byte for byte through the Rust reader/writer.

SHA-256:

- DMB: `2CB8ADA339B781A53C45D4897062EB61A100CCE26B0B7E4292CD5C6FF6A33BE6`
- RSC: `F9A93967BEC9711F019585BABD28F4F999D98749D29B13954C7B25FD75FD23AC`

These checks describe the earlier diagnostic snapshot and are static. No full
translated game was run in DreamDaemon for this validation. The current export
script no longer rewrites length mutations or supplies an extension stub.

The native DMB and OpenDream export agree on all 70,739 placed map-object paths
and their order across 32,209 occupied cells. With zero-argument `newlist()`
preserved as an empty list in the patched export, `od-map-audit --semantic-values`
reports no decoded map discrepancies against the native DMB. Class-table
auditing now reports zero differences across 40,479 classes with the annotated
exporter. The global footer now also has zero decoded differences. Modified type
paths, proc references, mob paths, and `/client` header values now match.
The independent procedure-table audit of `deepquarry-nativemethods.json`
reports zero differences: argument and local lists, class procedure membership,
counts, flags, and verb metadata match. `Arguments.HasDefault` preserves the
native nullable flag on authored verb arguments with a default value. Array
arguments omitted by the earlier exporter are restored.
These are point-in-time findings, not a claim of
complete compatibility.

### Wide table follow-up (2026-09-28)

Native static probes now cover 65,631 classes, 65,609 procedures and 65,717
variables. Class and procedure allocation preserves the nullable ID `0xffff`
as a canonical reserved record; variable ID `0xffff` is a real variable.
IDs above that boundary retain their high tag bits. The reference validator
accepts only the exact reserved procedure record at its specified index.
Instruction and branch audits skip that record and decode all 65,608 real
procedures in the native wide fixture, with zero invalid destinations.

The native compiler successfully writes 65,535 instance records, whose last
ID is 65,534; attempting 65,536 records crashes the native compiler during
saving. The translator rejects allocation of the reserved instance ID rather
than emitting an invalid file. This is static format evidence, without
DreamDaemon execution.

For a static comparison against a Dream Maker build, run
`compile-deepquarry-opendream.ps1 -NativeConditionalBranches`. This adds
`#undef OPENDREAM` to the temporary diagnostic overlay before project includes,
so native branches of `#if OPENDREAM` compile without modifying game source.
The paired full export includes native-only `lootpanel/open` locals `build` and
`version`, which the default OpenDream branch omits. The other affected source
families are rust-g library selection, lootpanel image handling, TGS engine and
topic-port values, and compiler-version gating. `UNIT_TESTS` remains undefined
in this mode. It is for native parity analysis; a normal OpenDream runtime build
should retain its standard conditional branches.

## Subsequent paired input and metadata fixes (2026-09-28)

- `ImplicitLocateOffsets` preserves the distinction between native unary
  `locate(value)` and explicit binary container lookup after OD optimization.
  The lowering hook removes only an annotated synthesized world getter;
  explicit `in world` remains binary, including debug builds.
- Declaration namespace blocks no longer materialize phantom `/var`, `/proc`,
  or nested declaration types. Root verbs retain `/verb/name` and the native
  `/verb` namespace rather than becoming global proc paths.
- Resource runtime IDs are shared by content CRC across extension kinds.
  RSC entries retain each authored name and its own kind. Constant `file()`
  and `icon()` initializer marker provenance is distinguished from constructors
  depending on runtime globals.
- Class/world procedure membership order now follows paired native override
  precedence. Tests compare ordered body identities, argument metadata, and
  parent overrides; a sorted path multiset is insufficient evidence.

- Absolute `/var/name` parameter syntax creates a global declaration, rather
  than phantom types or an argument slot; paired reads retain the native value.
- Procedure constants distinguish an original `/type/proc/name` body from an
  override `/type/name` body. Native world callback paths retain `/world/name`.
  Unqualified root bodies are retained because `/name` constants can reference
  them even when named global calls remain bound to the `/proc/name` definition.
These additions are covered by portable native/OD fixtures. The historical
counts and hashes above describe their original snapshot. Current full-project
and corpus checks must use the current patched exporter and matching baseline;
loader compatibility with older JSON does not restore omitted provenance.
Static tests and successful lowering do not establish runtime behavior for
unobserved BYOND features or complete whole-game runtime equivalence.
## OpenDream JSON field audit

| JSON fields | Translation or validation |
| --- | --- |
| `Metadata.Version`, `OptionalErrors` | Matched to the OpenDream baseline; changed optional errors are rejected. |
| `Strings`, `Resources`, `Interface` | IDs remapped; resources packed into RSC; DMF interface sets the world skin ResourceID. Unrecognized extensions use verified generic kind 0; authored archive spellings and physical paths are separate. |
| `GlobalProcs`, `Globals`, `GlobalInitProc` | Procedure ownership and global indexes validated; static/global declarations emitted; initializer bytecode lowered unless it contains only literal assignments already represented by variable defaults. Unsupported global initializer metadata errors. |
| `Types.Path`, `Parent`, `InitProc`, `Procs`, `Verbs` | Classes and procedure tables emitted; actual parent ancestry determines type categories; initializer ownership and verb membership are validated. |
| `Types.Variables`, `GlobalVariables`, `ConstVariables`, `TmpVariables` | Literal fields, inherited values, static declarations, const/tmp flags, and initializer markers emitted. Changed native const/tmp sets and changed native global defaults error. |
| `Procs.Name`, `OwningTypeId`, `Attributes`, `Arguments`, `Locals`, `Bytecode` | Paths, typed arguments, local name lists, and bytecode emitted. The lowerer uses `MaxVariableId` plus local `Offset`/`Remove` events to resolve reused slots. Missing authored bytecode and unsupported attribute bits error. |
| `Procs.IsVerb`, `VerbSrc`, `VerbRange`, `VerbName`, `VerbCategory`, `VerbDesc`, `Invisibility` | Verb metadata emitted; out-of-range source/range and negative invisibility error. |
| `Procs.ExplicitVerbFields`, `ExplicitVerbFieldValues`, `ExplicitVerbTextValues`, `ExplicitVerbSource/Range/SourceWasIn`, `NestedBackground` | Patched exporter records authored `set` statements, including values lost to later inheritance and nested `set background` in OpenDream's effective fields. Optional for older JSON. |
| `Procs.LexicalLocalAddIndices` | Patched exporter lists successful local Add-event indices in source order. This matched ten paired full-project native local lists, including repeated names; the lowerer must apply the same slot remap before the emitter can reorder local metadata. |
| `Procs.Arguments.DeclaredPath`, `NativeOmit` | Preserves list element type paths (`list/turf/x`, etc.) lost by `TypePath=/list`; marks leading-absolute parameter paths that Dream Maker treats as implicit type declarations rather than formal arguments. Paired `list_arg_path` and `absolute_arg` fixtures cover these cases. |
| `Procs.Arguments.HasDefault`, `DefaultIsNull` | Preserves authored default expression provenance. The paired `null_default` fixture shows that effective verb arguments with any default gain the native nullable type flag; ordinary procedure arguments do not. `DefaultIsNull` is diagnostic and does not substitute for `HasDefault`. |
| `Maps.MaxX/Y/Z`, `CellDefinitions`, `Blocks`, map objects and overrides | Grid, instances, contents, and override initializers emitted. Cell names must match their keys; bad dimensions, overlaps, and unresolved definitions error. |

`Procs.MaxStackSize` is compiler bookkeeping without an observed DMB field.
`SourceInfo` can emit native file and line markers with `--debug-lines`;
optimized OpenDream output may omit some events, so use `--no-opts` when
comparing debug symbols. A baseline is required whenever
native definitions or procedures appear, because otherwise the emitter cannot
distinguish authored overrides from OpenDream's built-ins.

## Verified in paired Dream Maker and OpenDream fixtures

- Native and authored type/procedure binding, inherited class order, globals,
  literal fields, local and argument variable IDs, and type path values.
- A paired type-path fixture establishes that native tag 8 payloads index the
  `MobType` table for `/mob` paths; tags 9 (`/atom/movable` and `/obj`), 10
  (`/atom` and `/turf`), 11 (`/area`), and 32 (`/datum`) index the class table.
  The tag follows the value's target path, including subtype overrides, rather
  than the declared variable type. Tag 41 instead indexes an `Instance` record
  for a modified path such as `/obj/item{amount = 20}`; that record stores its
  base class and a procedure that applies the modified fields.
- Multiple map sections, skipped z-levels filled with world turf/area defaults,
  atom prototypes, map object variable overrides, resource references, and
  DMM row orientation.
- A custom `.dmf` skin: OpenDream's `Interface` path also appears in `Resources`;
  the emitter writes the resource and sets the world skin ResourceID.
- Paired RSC kinds for `.dmi`, `.png`, `.ogg`, `.ttf`, `.txt`, `.html`,
  `.css`, `.js`, and `.json` resources.
- Numeric/string/null/resource/type constants, global and class initializer
  procedures, hidden initializer markers, inherited class initialization,
  proc-reference defaults, and positive/negative infinity values.
- Positional and associative list constants in map object variable overrides,
  emitted as native initializer constructor bytecode. Proc-reference constants
  in class defaults, inherited overrides, and map overrides use native value
  tag 38 and remapped ProcIDs. Mixed map lists get positional numeric keys.
- Default procedure and verb display names replace underscores with spaces.
- Authored class static globals use declaration flag 1 (flag 3 for static
  constants); literal-only OpenDream global initializers become DMB variable
  defaults without a world initializer.
- Basic verbs: source selector/range, display name, category, description,
  and positive invisibility. Proc slots 2 and 3 hold description and category.
- Inherited `set hidden`, `popup_menu`, `waitfor`, `background`, and `instant`
  metadata, including explicit false/true resets on child definitions; paired
  fixtures distinguish authored values from inherited OpenDream attribute bits.
- Typed arguments for the paired `mob`, `obj`, `turf`, `area`, `file`, `sound`,
  `null`, `icon`, `message`, `num`, and `text` type bits. Type combinations use
  the corresponding bitwise union.
- All 16 text-format markers observed in the full OpenDream export, paired
  against Dream Maker output (including interpolation, articles, pronouns,
  `\proper`, `\improper`, Roman, ordinal, and plural forms).
- Exact-first switches interleaved with numeric range cases become one native
  `SwitchRange` table; range and exact destinations retain their branch targets.
- Weighted picks with forty candidates and computed candidate values. Native
  `PickSwitch` thresholds sum individually truncated weights scaled by 65,535;
  `PickProb` evaluates dynamic weights before branching to the selected value.
- `initial()` and `issaved()` retain wide string IDs and cache computed owners.
- `json_encode(data, flags)` uses native opcode `0x167` with its argument-count
  operand; the decoder preserves that boundary rather than treating the count
  as another instruction.
- Indexed savefile reads use `Index`/`Read`, followed by direct or field
  assignment or an ordinary destination `ListSet`. Indexed output constructs
  its receiver before evaluating the output value.
- The opcode translations listed in [OPENDREAM_OPCODE_MATRIX.md](OPENDREAM_OPCODE_MATRIX.md).

## Explicitly rejected or still unverified

- DMB versions other than v516, or an OpenDream compiler metadata version that
  differs from the supplied OpenDream baseline. The baseline and input must
  also have equal `/world.byond_version` and `/world.byond_build` values;
  the translator reports a target mismatch before table emission.
- Changed OpenDream optional error tables.
- Authored `/world` fields beyond `name`, `tick_lag`, `view`, `map_format`,
  `icon_size`, `turf`, `area`, `mob`, `loop_checks`, and `visibility`.
- The stock OpenDream JSON loses whether a `/world` field was explicitly set
  to its default value. Optional `ExplicitWorldFields` from
  `patches/opendream-combined-1362abc.patch` restores that
  information using source provenance. A paired world-settings fixture then
  matches native header flags and minimum compatibility metadata.
- Stock JSON also loses authored type overrides equal to OpenDream defaults.
  The same combined patch exports `ExplicitTypeFields` from non-standard source
  assignments. A paired `/area.luminosity = TRUE` fixture matches Dream Maker;
  the OpenDream standard `/area.layer` default is excluded.
- Dynamic list/object declarations and type override initializers require
  native value marker tag 62. The combined exporter patch records final
  `DynamicDeclarationFields`, ordered `DynamicInitializerAssignments` (including
  repeats), and diagnostic `InitializerValueKinds`. A paired fixture checks
  list declarations, two overrides of the same field, object creation, null
  and scalar overrides, and a particle `generator(...)`. The full annotated
  DeepQuarry JSON exports 17,455 class initializer assignments across 17,249
  unique path/field pairs, matching the native DMB counts; per-path equality
  and declaration-marker counts are being audited separately.
- The pinned exporter also preserves global/static marker IDs, `arg in`
  source expressions as companion procs, repeated `#pragma multiple` includes,
  implicit classes from absolute argument paths, map override order,
  case-preserving resource aliases, original global declaration constants by
  ID (`Globals.DeclarationValues`), proc-local constants
  (`Globals.CompileTimeConstDeclarations`), and constant values left in runtime
  initializer procs. Paired fixtures verify
  these source forms; full-project emission parity is still being audited.
- The earlier patched OpenDream diagnostic snapshot reported 189 warnings; this is a historical count.
  Modified type constants are exported as type 7 values and opcode 0x9F,
  preserving their source overrides; native tag 41 instances are allocated
  by the translator. The 117 `set src=view()` warnings do not erase `VerbSrc`
  and `VerbRange` JSON metadata, which the translator maps to native verb
  source fields. See
  [`doc/audits/OPENDREAM_WARNING_AUDIT.md`](doc/audits/OPENDREAM_WARNING_AUDIT.md) for all counts.
  The remaining warnings are assessed separately for source-data loss.
- List constant objects in variable tables have not appeared in paired output:
  ordinary `var/list = list(...)` becomes an initializer procedure. Map
  overrides support positional, associative, and mixed lists. List construction in
  initializer bytecode is supported separately. Unsupported constants error.
- Explicit `as anything` arguments: stock OpenDream emits Type=0 for both explicit
  `as anything` and an untyped argument, while Dream Maker uses distinct DMB
  flags. The Rust parser accepts an optional `ExplicitAnything: true` field
  per argument and emits Dream Maker's 0x1000 flag. The combined pinned compiler
  patch exports this field. In stock OpenDream's
  [`DMProc.GetJsonRepresentation`](https://github.com/OpenDreamProject/OpenDream/blob/master/DMCompiler/DM/DMProc.cs),
  `parameter.ExplicitValueType` still distinguishes the two cases before the
  conversion to [`ProcArgumentJson.Type`](https://github.com/OpenDreamProject/OpenDream/blob/master/DMCompiler/Json/DreamProcJson.cs); a compatible upstream patch can add
  `ExplicitAnything = parameter.ExplicitValueType?.IsAnything == true` to the
  JSON record. Existing JSON remains valid because the new field defaults to
  false. OpenDream also loses the `/atom/movable` parameter path when it emits
  coarse `Type=0`, although Dream Maker records argument flags `0x0003`.
  An optional `TypePath: "/atom/movable"` field restores those flags; see
  `patches/archive/opendream-argument-type-path-1362abc.patch`. A paired animate fixture
  compares cleanly when this field is present. Unknown argument type bits and
  OpenDream procedure attributes beyond
  the explicitly supported attribute mapping are rejected. Negative verb invisibility
  values are rejected.
- OpenDream's stock JSON drops whether a procedure explicitly set
  `invisibility = 0`. Optional `ExplicitInvisibility` from
  `patches/opendream-combined-1362abc.patch` restores Dream
  Maker's extended proc flag; paired default, zero, and seven settings match.
- Map dimensions beyond DMB limits, overlapping map sections, and map object
  offsets beyond the DMB field width.
- Resource extensions outside the verified kind mapping use Dream Maker's
  generic resource kind. Ordered authored archive names are retained separately
  from normalized physical paths.
- OpenDream bytecodes without a paired Dream Maker lowering; the translator
  reports the procedure and byte offset rather than emitting a placeholder.

## Full DeepQuarry compilation input

The stock OpenDream compiler cannot compile the unmodified DeepQuarry manifest.
The generated `icons/gen` assets must exist first. A temporary manifest quotes
`FILE_DIR`, omits OpenDream lint pragmas that reject Dream Maker accepted
syntax, and supplies the test-only `/obj/item/dq_rule_test` type. The paired
native diagnostic contains that bare type too; an unbound type constant is
invalid in both compilers, so this remains a build configuration requirement.
The patched compiler accepts the original `length()` mutation expressions and
declares `load_ext` as an intrinsic. No expression replacements or placeholder
extension procedure are needed by the current export script.

Build the pinned OpenDream compiler with the call_ext opcode and combined
exporter annotations, then compile the diagnostic JSON:

```powershell
git -C C:\path\to\OpenDream submodule update --init --recursive
& tools/dmb/scripts/build-patched-opendream.ps1 `
    -SourceRoot C:\path\to\OpenDream -Dotnet C:\path\to\dotnet.exe
& tools/dmb/scripts/compile-deepquarry-opendream.ps1 `
    -Compiler C:\path\to\OpenDream\bin\DMCompiler\DMCompiler.exe `
    -OutputJson D:\path\to\deepquarry-annotated.json `
    -ScratchRoot D:\path\to\scratch
```

The successful annotated output was 56,767,278 bytes: 40,473 types, 59,836
procs, 3,854 relative resource paths, and four maps. The matching patched
516.1687 baseline has the same compiler metadata version. The probe links asset
directories into its scratch directory and removes scratch on completion. Its
`load_ext` intrinsic retains native extension-loading instructions; external
libraries are not exercised by these static checks. Source filenames are absolute because
the temporary manifest uses absolute DM includes. The patched exporter writes
the skin interface and matching resource as `interface/skin.dmf`, with no
absolute resource paths. Native extension semantics and remaining
OpenDream-to-DMB coverage still need validation.

Read/write parity of an existing DMB/RSC is separate from OpenDream translation:
the package round-trips observed compiled files without losing bytes, while
translation coverage grows through paired compiler fixtures and explicit errors.

Upward proc searches and inferred `nameof` references preserve inherited proc resolution. Direct absolute proc literals retain the native restriction to an actual declaration on the named owner. The portable inherited_proc_refs fixture checks both forms against native procedure targets and bodies with debug output enabled and disabled.

### Native arglist legality sweep

A compile-only sweep tested `builtin(arglist(L))` separately for all 173
exported OpenDream global builtins against DreamMaker 516.1687. Twelve forms
were accepted: animate, file, filter, generator, gradient, image, min, max,
sound, icon, _dm_db_new_con, and _dm_db_new_query. Rejected forms are not
translation requirements merely because OpenDream accepts them.

The sweep exposed native arglist constructor/call mappings for sound, image,
file, and self calls. Root parent calls also exposed an OpenDream compiler
null dereference; the patched exporter now emits its no-parent warning and
retains the call. Native database constructors ignore their entire argument
expressions, including side effects. The patched compiler omits their arguments rather
than a stack-only lowering shortcut. Portable paired fixtures retain these
observations; integration status is tracked by the regression tests.


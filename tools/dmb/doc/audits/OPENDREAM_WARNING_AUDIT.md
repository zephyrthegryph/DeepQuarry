# Full DeepQuarry OpenDream warning audit

Pinned OpenDream commit `1362abc5accbc2037df9b45efa1de13fb1bb677f`,
BYOND target 516.1687, combined exporter and `#pragma multiple` patches.
Historical source: `D:\opendream-diagnostic\deepquarry-modifiedtype.log`, paired with
`deepquarry-modifiedtype.json` and the matching
`native_template_modifiedtype_5161687.json` baseline. The temporary
diagnostic manifest also stubs `load_ext` and rewrites four unsupported
`length()` lvalues; these changes do not provide runtime semantics.

| Count | Code | Compiler message | Translation effect |
|---:|---|---|---|
| 117 | OD2800 | `set src = view()` becomes `src = range()` | Warning persists, but patched `ExplicitVerbSource`/`ExplicitVerbRange` preserve authored values even when later inheritance overwrites `VerbSrc`/`VerbRange`. |
| 21 | OD2800 | `set src = usr.loc` unimplemented | `VerbSrc=12` preserves this category for native DMB emission. |
| 17 | OD2800 | `set instant` unimplemented | `ProcAttributes.Instant` preserves the native extended flag. |
| 8 | OD2800 | `/icon.Crop()` unimplemented | Paired native output uses a generic method call; OD retains the call target for DMB lowering. |
| 6 | OD2800 | `/world.OpenPort()` unimplemented | Paired native output uses a generic method call; OD retains the call target. |
| 4 | OD2800 | `walk_away()` unimplemented | Native uses opcode `0x125`; lowering from OD's stub call needs paired validation. |
| 2 | OD2800 | `shell()` unimplemented | Native uses opcode `0x98`; lowering from OD's stub call needs paired validation. |
| 2 | OD2800 | `/client.MeasureText()` unimplemented | Paired native output uses a generic method call; OD retains the call target. |
| 1 each | OD2800 | `regex.Replace_char()`, `run()`, `operator""` unimplemented | Regex uses a generic method call. `run()` in output context needs native `0x09`. A paired `operator""` fixture retains the proc definition and native-style string Format operation. |
| 6 | OD3204 | `in` order of operations ambiguous | Paired native/OD expressions use the same unusual precedence; bytecode lowering must preserve it. |
| 2 | OD2305 | Redundant `usr` | Diagnostic only. |
| 1 | OD2000 | Parameter named `usr` | Reserved-name compatibility warning. |

The native-field-operations export was checked again on 2026-09-27 and retains
the same warning counts. An effectful membership/ternary fixture matches native
instruction order, as do membership/OR and explicitly parenthesized ternaries.
Native constant folding of a truthy literal list can change instruction shape
without changing that precedence. Argument/local lookup takes priority over
the built-in `usr` reference for the named-parameter case.

Total: **189** warnings: 180 OD2800, 6 OD3204, 2 OD2305, 1 OD2000.
The previous 377 modified-type warnings are gone: patched OpenDream preserves
source overrides in JSON type-7 constants and opcode `0x9F`. Paired native
fixtures confirm the source forms; full-project translated table/bytecode audits
remain necessary. Some remaining OD2800 warnings describe limitations of
OpenDream's own runtime but preserve enough metadata for native DMB emission,
as indicated above. Counts may change with source or compiler patches.

## Current compile check (2026-09-28)

`deepquarry-current-semantics.log` from the latest Del exporter contains the
same **189 warnings** in the table above (0 errors). Its JSON SHA256 is
`3FB8012F544B5C7D8479175236371C20773B02A178C31E0BD3703D5AB718ED7D`.
These messages alone do not establish that translated native behavior is lost.

Fresh native/current-exporter static pairs under `D:/opendream-diagnostic/warnings-current`
checked the highest-count families without starting a runtime:

- `warning_verbs`: `set src=view(3)`, `set src=usr.loc`, and `set instant=TRUE`
  produce the three warnings, but decoded native metadata and bodies match.
  The comparison selected the full `/mob` subtree, so it includes the authored verbs.
- `warning_context`: six authored global procedures cover effectful unparenthesized
  membership/OR and membership/ternary, their explicit-parenthesis counterparts,
  and a parameter named `usr`. All decoded bodies match native output.
- `runtime_stubs`: Crop, OpenPort, MeasureText, walk_away, and shell bodies match.
  Replace_char differs only in StaticProc versus DynamicProc descriptor form;
  dispatch evidence is documented in `STATIC_SELECTOR_EVIDENCE.md`.

The existing literal-list membership/ternary fixture has a native compile-time
truthy-list fold while OpenDream retains the list/branch instructions. The
separate effectful fixture verifies the grouping and evaluation order without
that fold. This is not evidence for globally normalizing different expression bodies.

Portable `warning_context` and `warning_verbs` DM/DME/JSON/native fixtures retain
these checks. No new source-export defect was established by this warning triage.
The probes are compile-only evidence; they do not claim a runtime execution test.
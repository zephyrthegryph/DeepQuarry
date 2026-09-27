# BYOND DMB format research (Dream Maker 516)

This note concerns the compiled `*.dmb` loaded by DreamDaemon, **not** the
text `*.dme` project manifest. The companion `*.rsc` contains resources. The
eventual objective is to emit a BYOND-compatible DMB/RSC pair from OpenDream's
compiled representation. A valid DMB writer needs a verified reader first.

## Evidence and scope

- Local specimen: `deepquarry.dmb` (45,917,853 bytes), built September 23, 2026.
  Its companion `deepquarry.rsc` is 247,868,564 bytes. These are build artifacts,
  not fixtures to commit.
- Existing Rust tools in `tools/` do not parse DMB. `tools/dm-health` consumes an
  AST JSONL export from `tools/dm-health/opendream-bridge/Program.cs`; `mapcore`
  handles maps. The bridge runs OpenDream's preprocessor and parser *before*
  producing its export. This export is distinct from OpenDream's compiled JSON.
- The most detailed public draft is
  [20kdc's DMB format document](https://github.com/20kdc/byond-data-docs/blob/master/formats/DMB.md).
  It calls itself structurally complete through v512, with unverified use on
  v514. Its [bytecode document](https://github.com/20kdc/byond-data-docs/blob/master/formats/DMB.Bytecode.md)
  is incomplete. The [dmasm loader](https://github.com/willox/dmasm/blob/dmb/src/dmb/loader.rs)
  is another Rust implementation to compare against. None of these establishes
  v516 compatibility by itself.

## Independently checked against the local v516 DMB

Offsets are zero-based. Integers below are little-endian. `ObjectID` is 32-bit
in this specimen because the `LARGE_OBJECT_IDS` flag is set.

| Offset | Size | Interpretation | Observed value |
| --- | ---: | --- | --- |
| 0 | 15 | ASCII header line | `world bin v516\n` |
| 15 | 27 | ASCII compatibility line | `min compatibility v516 516\n` |
| 42 | 4 | game flags | `0x61e2050d` |
| 46 | 6 | `u16` grid width, height, z levels | `100, 100, 3` |
| 52 | 27,846 | grid run groups | 2,142 groups covering exactly 30,000 cells |
| 27,898 | 4 | total string bytes, including terminators | 10,521,632 |
| 27,902 | 4 | probable class-table entry count | 40,117 |

Grid groups in this specimen are 13 bytes each: `u32 turf_instance_id`, `u32
area_instance_id`, `u32 additional_instances_list_id`, `u8 run_length`. The
first group is `(21823, 21543, 65535, 255)`. The sum of all run lengths is
exactly `100 * 100 * 3`, which strongly supports this interpretation. `65535`
is the observed nullable-ID sentinel even with 32-bit IDs, consistent with the
public draft. The class count is a candidate because parsing of the class
records has not yet reached the string table to verify the next boundary.

## Reported table order requiring v516 verification

The public draft describes a header and grid followed by: class table, mob
type table, encrypted string table, generic list table, procedure table, var
table, a procedure-reference table, instance table, map object placements,
standard object IDs/world settings, and cache-file references into RSC.
Version gates change record layouts. The string table uses position-dependent
XOR encoding and an NQCRC footer. Resource records live in the RSC companion.
These are useful hypotheses, **not** a fully decoded v516 layout.

## Gaps before an OpenDream-to-DMB writer

1. Parse every v516 table with exact byte boundaries, counts, and referential
   integrity. Record unknown fields as raw bytes; do not silently default them.
2. Decode and validate all DM value tags, string formatting escapes, list
   payloads, procedure argument/local metadata, initializers, map instances,
   world settings, and resource references.
3. Decode the complete BYOND instruction set and operands for v516. The public
   bytecode documentation does not supply this. A table reader without bytecode
   support cannot produce runnable output.
4. Decode RSC records and the identifiers joining DMB references to them.
5. Compare small Dream Maker fixtures against equivalent OpenDream compiled
   JSON, then compile generated DMB/RSC pairs and load them in DreamDaemon.
   Full validation needs differential runtime tests, not just parse/write
   round trips.

OpenDream's AST JSONL export is not sufficient for this translation: it omits
the resolved bytecode, compiled map/interface/resource content, and several
semantic tables. Its compiled JSON is the relevant starting point, together
with the resources OpenDream emits. The mapping from OpenDream's instruction
model to BYOND's VM instructions remains a separate compiler backend project.

In the checked-out OpenDream compiler source, `DreamCompiledJson` exposes
`Strings`, `Resources`, `GlobalProcs`, `Globals`, `GlobalInitProc`, `Maps`,
`Interface`, `Types`, and `Procs`. `DreamTypeJson` includes path, parent,
initializer, procs, verbs, and variable dictionaries. Those are plausible
inputs for the corresponding DMB tables, but the records and IDs are not
byte-for-byte equivalent. In particular, OpenDream's procedure bytecode uses
its own opcode model, and BYOND's DMB procedure bytecode is still the main
unresolved translation step.

# Phase 0 preprocessing inputs

These are isolated input cases, not an executed test suite. `manifest.json` records
all preserved-producer executions and DreamMaker comparisons as **pending**.
`source_support: base-supported` means that the relevant directive/API path exists
in `ac1af55d1a`; it does not assert that this exact case compiles successfully or that
its result agrees with DreamMaker. `pending-probe` also lacks that source evidence.

Do not add station includes to these wrappers. Run preprocessing observations first;
duplicate declarations and deliberately invalid non-text files may make a whole-world
compile inappropriate. The non-text fixture establishes only item routing and inactive
input handling, not map/skin validity. The diagnostic fixture intentionally has an error.
Each execution receipt must state the observation layer and exact binary/inputs.

Additional Phase 0 paired probes must cover:

- A parent conditional opened before an include and closed afterward; a child trying
  to close its parent's conditional; unmatched `#else` and duplicated `#else`.
- Comment, escaped-newline, string, and indentation state at include boundaries.
- Empty, function-like, command-line and repeated FILE_DIR definitions; empty pops.
- Identical FILE_DIR tops with distinct predecessors, followed by `#undef FILE_DIR`.
- A resource initially found in a later directory, then shadowed by a new file in an
  earlier directory without changing DM bytes or declaration skeletons.
- Missing active versus inactive DM/DMM/DMF includes; repeated non-text items.
- External paths, unresolved leading `..`, Windows drive/UNC spellings, case aliases,
  and symlink/junction aliases. Do not assume their canonicalization from lexical code.
- Identical region bytes in separate files without location macros: shared expansion
  values must still report each consuming occurrence's diagnostic origin.

Root ran the original inputs with pinned DreamMaker 516.1687. Five ordinary cases
compiled without errors; `diagnostics` produced the intended `#error`. Three cases
had unintended fixture errors and have been repaired, awaiting rerun:

- FILE_DIR is not consumed as an unquoted DM expression. The case now resolves
  `marker.txt` before/after the pop, exposing resource-search stack behavior.
- Equal path-origin bodies now belong to distinct `/datum/a` and `/datum/b` blocks,
  avoiding duplicate global variables while retaining identical included bytes.
- Non-text conditional directives now live in an included DM file and use `#ifdef`.
  The default case is inactive and should compile; an enabled run intentionally
  contains invalid map/skin data and is a routing/error probe, not a valid world.

These compile observations do not establish runtime values, parity, or repaired
case results. Raw compile logs and generated DMB/RSC files are ignored here and
must be copied separately into the evidence directory if retained as receipts.

The pending list is part of the human review contract. A runner must record results,
not silently replace pending outcomes with predictions.

## Runtime observation wrappers

Eight supported textual cases have optional `runtime_manifest` entries. Each
wrapper includes the unchanged original DME, then a shared JSON recorder and a
case-specific World.New observer. `phase0-preprocess.json` and PHASE0 log records
retain actual value, explicit source-derived expected value, and equality flag.
The expectations are predictions, not captured DreamMaker receipts. The runner
must retain mismatches rather than treating a successful compile/exit as parity.
Original compile roots and source hashes remain applicable to their unchanged
inputs; wrapper input closures require new hashes at capture.

File/line checks intentionally normalize only separators and final source suffix,
not full provenance. Repeated inclusion checks the final global value only.
Diagnostics and selected/nonselected map/skin cases remain compile-only here.

Eight BYOND516.1687 runtime captures are now retained in
`evidence/byond-runtime-observations.json`. Original mismatches remain visible:
repeated result1 versus predicted2; during resource text earl versus predictedlate.
Current wrapper expectations reflect these finite observations, with FILE_DIR
during expanded to five characters for future captures. See PREPROCESS.md §8
for duplicate-include/declaration and resource archive/search ambiguities.

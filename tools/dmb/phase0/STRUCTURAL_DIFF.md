# Whole-program structural comparison

Run `dmb-inspect structural-diff EXPECTED.dmb ACTUAL.dmb REPORT.json SNAPSHOT_ID`.
The expected producer is pinned BYOND; both producers must consume the same
authenticated captured-input snapshot. The caller supplies its verified receipt
identity. The comparator records that identity; a DMB cannot prove its source inputs.

Exit zero means a report was written, **not** that parity passed. Schema version 1
requires `traversal_complete`, `complete`, and `unexplained_discrepancies == 0` for a
passing strict semantic-parity projection gate. Parse or I/O errors exit nonzero. `complete` is false if
`uncovered` is nonempty, even when no differences were observed. The tool compares
the whole program, without path filters or a discrepancy cap. Each category keeps
five examples, truncated at 4096 bytes per displayed value; counters remain uncapped.

Measurement and structural regression gates distinguish `tool_complete` from
`semantic_coverage`. `tool_complete` requires traversal/decoding of required
categories and rooted procedure ownership, and remains false for unpaired procedures,
missing tables, unresolved required references or decode failures. A fully recorded
local unknown operand/value meaning can leave it true while `semantic_coverage` is
`incomplete`. The original `complete` field retains strict full semantic coverage;
neither tool completeness nor a no-regression result claims full semantic parity.

Categories cover the type set, headers, typed declarations/defaults, physical proc
names, class proc/verb ordered bindings, procedure metadata/flags, global declarations,
strings at established use sites, and decoded procedure bytecode. Counts mean
individual field discrepancies, not failing procedures. String-use discrepancies are
an additional projection: a changed literal can also count in bytecode/defaults.
Duplicate named procedures pair using established owning-class binding ranks.
Physical `/proc/` and override paths are separately checked and are not conflated.

Bytecode uses the existing decoder and semantic operand resolver. Debug file/line
instructions are excluded and branch destinations are normalized to remaining
instruction indices. PushInt and equivalent numeric PushVal compare identically.
Known type, string, proc, variable and resource references resolve using the existing
format reader. Unknown value forms, opaque instance initializers, unresolved typed
references, unpaired anonymous procedures and uncertified fixed-word operand roles
are explicitly uncovered. Equal raw IDs cannot establish semantic equality.

The strings-by-use projection covers named procedure display/description/category,
decoded literals/format strings, class appearance strings/default literals, and global
literal defaults. It does not compare unused table entries. Missing semantic coverage
of other strings is represented by the corresponding uncovered operand/value/proc.
Resources currently resolve to established kind/resource identity, not to arbitrary
RSC table positions. This command does not compare RSC payloads, map cells, or opaque
header bits and makes no runtime correctness claim.

`explained_divergences` is currently empty. There are no category exemptions or
wildcard admissions. Adding an explanation requires a separately reviewed exact
semantic case; the current normalizations are listed once in `normalization`.
Preserve failed/incomplete reports and producer receipts for investigation.

`category_signatures` contains sorted, deduplicated exact-case fingerprints for
every category, including empty arrays. `signature_algorithm` is
`md5-length-framed-v1`: append each full path, field, expected value and actual value
as UTF-8 with its preceding little-endian u64 byte length; compute lowercase MD5.
Fingerprinting happens before example truncation. These are reproducibility case
identifiers, not adversarial authentication. A no-new-divergence gate requires the
candidate case set to be a subset of a complete authenticated baseline's set in
every category; strict zero-difference parity remains a separate gate. Removing an
old case is an improvement; changing its actual value is a new case. Repeated
instances of a case are separately counted even though fingerprints deduplicate.

`bytecode_procedures` records decoded instruction counts, positionally compared
lengths, unmatched tails and differing fields per named/owned procedure. An unequal
instruction count is explicitly labeled provisional positional alignment. One
inserted instruction may cause many following mismatches; these field counts are
not counts of independent compiler bugs, nor an edit-distance alignment claim.

Anonymous procedure ownership follows explicit class/world initializer references,
argument source slots, modified-type default/use references and map coordinate
references. It follows nested references with a cycle guard. Procedure IDs and
body similarity never choose pairings. Anonymous procedures lacking a rooted use
remain uncovered. Pinned BYOND 516.1687 client-path payloads are singleton zero:
a nonzero payload is reported as a known invalid encoding discrepancy, rather
than classified as unsupported meaning or silently accepted when both inputs
contain the same malformed payload.

`uncovered_signatures` supplies sorted/deduplicated fingerprints by uncovered kind.
The same framing algorithm hashes kind, full consumer site, and full evidence as
three framed strings. Local unsupported scalar words include opcode and all raw
operand words; opaque values include their original encoded words; opaque instance
initializers include type/path and full initializer words without using its ProcID
as an owner. Sites resolve to class/field names, global names or rooted procedure
names and opcode occurrence/operand slots, rather than procedure table IDs or debug
word offsets. Examples may be truncated; fingerprints are not. Infrastructure gaps
remain tool-incomplete regardless of their diagnostic fingerprints.

A structural no-regression gate requires both known-case and unknown-case subsets
of its same-snapshot baseline and no growing category/unknown occurrence counts.
Identical unsupported counts are insufficient: changing unknown wire evidence is a
new case. A valid native fresh-output oracle and measurement protocol establish
timing admissibility separately; strict BYOND semantic parity still requires the
original complete flag and no unexplained differences.

Unmatched named or rooted anonymous procedures include their complete resolved
metadata, arguments, locals and debug-normalized code in `proc.unmatched_payload`,
plus nested owned procedure payloads. Presence/count alone cannot baseline-admit
later body changes. The shared instruction decoder and branch normalizer provide
these payloads; no independent opcode grammar is maintained.

Switch cases and range endpoints have explicit ordinal consumer slots. Repeated
unknown values therefore remain distinct cases by position: changing their
multiplicity or moving a value to another slot introduces a new signature even
when the total unknown count stays constant. Global duplicate declarations likewise
include their occurrence rank; code operands include their operand slot.

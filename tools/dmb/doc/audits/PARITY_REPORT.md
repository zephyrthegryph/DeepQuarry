# Native Dream Maker versus translated output

## Full DM test suite — 2026-09-28

The full unfiltered translated suite completes in trusted mode: **982 passed,
34 failed, 58 skipped**, versus native **991 passed, 25 failed, 58 skipped**.
Both enumerate 1,098 types and record the same 1,074 non-abstract/non-focus-only
results. Fourteen native-passing tests fail translated; five native failures
pass translated. There are zero translated-only runtime-error identities, but
the assertion differences prevent a test-parity claim. See
[`DM_TEST_REPORT.md`](DM_TEST_REPORT.md) for the complete issue list and evidence.

## Live server investigation — 2026-09-28

The lighting discrepancy below is traced to negative map constants encoded
as unsigned 16-bit `PushInt`: `-26` becomes `65510`, and pixel setters clamp it
to `32767`. The emitter now uses floating `PushVal` outside `0..65535`; the
comparator now applies native unsigned-word semantics. Earlier zero map
difference results used the incorrect signed normalization and are superseded.
Paired trusted minimal worlds agree for negative offsets and values at 65535
and 65536. The new map regression checks both debug modes and rejects an
intentionally corrupted negative initializer. The repaired `final12` comparison
reports zero expanded metadata differences and zero semantic map differences
with the corrected numeric rules. All 19,617 initializer records preserve their
identity partition. Procedure comparison remains 29,227 normalized matches and
30,238 structural differences; no procedure is unmatched. All 3,856 resource
entries retain payloads, identities, source timestamps, and order; creation
timestamps differ. All 62,318 emitted procedures decode without failures or
reserved instructions, and DMB/RSC round-trip byte for byte.

The full package gate now passes **564 tests (453 core)**, with strict Clippy
clean. Final12 DMB SHA256:
`84BBA39159FD7A58603C51EC2C91B4ABE3E83E302D55B3B64A927B9CD9EC0A03`.
Input hashes and exact runtime options are recorded in
`D:/opendream-diagnostic/final12-provenance.json`. The trusted full-game boot
completes initialization in **101.625 seconds** and remains alive afterward at
about 1.43 GB private memory. The server is stopped after capture. Runtime log
comparison reports **zero translated-only errors**: lighting errors are gone,
and shared power error counts match. This is a startup check, not evidence of
client-interaction or playable-round parity. Captures are under
`D:/opendream-diagnostic/server-boot-20260928/translated-final12-server.log`
and `final12-runtime-counts.json`.

Trusted native and translated full-game boots now have captured runtime
evidence; see [`SERVER_BOOT_REPORT.md`](SERVER_BOOT_REPORT.md). Both load
the world and matching Verdigris library, listen on a network port, and reach
full initialization on the latest trusted paired checks. Both still report
shared baseline errors; neither establishes error-free or playable-round parity.

Live checks exposed reserved-field-ID collisions, invalid readonly
intrinsic deletion, and lost inherited builtin class defaults, now repaired.
The completed package gate passes **562 tests (452 core)**, including the
wide-string-ID regression after the final automatic-name repair.
Native fixtures cover reserved IDs, twelve deletion cases, twenty-two
appearance classes, seventeen header boundaries, and twenty-eight name/text
classes in both bytecode debug-line settings.
The repaired trusted server no longer reports the cable `power_edit` null
conversion or readonly-write failures. Its first attempt aborts with a memory
allocation failure; a retry of the identical artifact completes initialization
in 95.9625 seconds. The paired native server completes in 100.575 seconds.
Both remain alive afterward, although shared baseline errors remain.
Earlier zero metadata-difference counts must not be treated as proof of
effective inherited builtin values or runtime parity.

The expanded class-header comparison initially found **42,439 metadata differences**:
22,066 flags, 10,401 text, 9,130 names, 821 layers, 19 directions, and two
ordinary name defaults. Header inheritance, callback flags, zero direction,
ordinary datum defaults, raw text bytes, and image defaults repaired those
families. The `final11` artifact also repairs automatic-name/text truncation
on `/obj/compass_holder`; a native-paired regression covers string IDs above
65,535. Its expanded metadata comparison reports **zero differences**.
The current artifact
pairs all **59,465 procedures**, with **29,227 normalized matches** and
**30,238 differences**. The refreshed comparison completes, with zero semantic map
differences and exact payloads, identities, and source timestamps for all
3,856 resource entries and identical entry order; archive creation timestamps differ.

Initializer identity coverage is complete for observed source keys: **17,456
class assignments and 814 globals**, with zero unclassified keys. Final DEBUG
macro state controls native token sharing independently of debug-line emission.
The full `final11` partition audit pairs **19,617 marker records**, with zero
missing records, split groups, or merged groups. Class-owned footer entries are
paired by their declaration owners; duplicate source names must not be matched
by footer order. The reusable `initializer_identity_audit` example rejects the
release-versus-DEBUG negative control.

The repaired `final10` trusted server completes initialization in **106.713
seconds**, remains alive afterward, and is stopped after capture. Shared power
errors remain. Playable-round and client-interaction parity are still unverified.

Final artifact: `D:/opendream-diagnostic/deepquarry-final11.dmb`, SHA256
`2DEF9A99D2B702907B0A88422060184C893DBD5AB2E5073AD57D41B998D38AB4`.
All **62,318 emitted procedures** decode, with zero failures or reserved
instructions. Both DMB and RSC round-trip byte for byte. Its final trusted
startup check completes initialization in **213.75 seconds** and remains alive
afterward, using about 1.43 GB of private memory. It is stopped after capture.
Log comparison exposes a translated-only `Cannot read null.x` during lighting
initialization, also present in earlier translated boots. The bytecode location
points to `pixel_turf.x`; the typed corner iterators reject null before their
bodies. The cause remains under investigation. Successful initialization does
not establish clean runtime parity.

## Previous static integration — 2026-09-28

The latest completed package gate passes **539 tests (447 core)**.
The current `deepquarry-iteration3` checkpoint pairs all **59,465 procedures**:
**24,327 normalized matches**, **35,138 structural differences**, and no unmatched
procedures. Maps match. One newly exposed metadata difference is under repair:
the exporter's builtin list/client `.type` declarations must remain runtime
fields instead of creating two readonly globals.

All **62,318 emitted procedures** decode and reassemble; typed references resolve;
**237,892 branch targets** are valid. DMB/RSC round-trip hashes match byte for
byte. The archive matches all **3,856 ordered native entries**, payloads and
source timestamps; creation timestamps differ. Checkpoint SHA-256:

- DMB: `8A64937947262ECE9FD7A1EED5E4DA641F606696FBF18FF18BABA75BC1B2720A`
- RSC: `BC266FBB212B10B07EC5060653D1C6A89DE29B54C45033225D7BFA7CA3B41B00`

The bounded branch-route audit verifies all **93 branch-only candidates**.
Across **62,318 paired records**, reachable F8/F9/FA/Catch/TryJmp counts agree;
85 raw count differences are unreachable F8 tails. All **352** previously
observed adjacent retained-result selector hazards are eliminated. These checks
do not establish general runtime equivalence. Constant-condition cleanup and
skipped-declaration metadata are being integrated; spatial iterator contracts
and unresolved cache/mixed bodies remain under review.

The refreshed compiler corpus has **557 accepted translations**, 113 native
rejections and one documented OpenDream rejection across all 671 cases, with no
translation or instruction-validation failures. This sweep predates the latest
constant-condition changes and must be refreshed after those changes stabilize.

## Previous 522-test checkpoint

The previous completed package gate passes **522 tests (447 core, 64 targets)**,
strict Clippy with warnings denied, and formatting checks. This includes authored goto
and continue budget checks, frozen receivers used by `initial`/`issaved`, lazy
multi-argument `pick`, and weighted Pick compilation-context regressions.

The current `deepquarry-final` classified comparison against a fresh native
compile pairs all **59,465 procedures**: **23,564 normalized matches** and
**35,901 structural differences**, with no unmatched procedures. Metadata and
maps have zero compared differences. All **62,318 emitted procedures** decode
and reassemble, typed references resolve, and **243,393 branch targets** land on
valid instruction boundaries. Whole-game lowering covers **59,982 procedures
with zero errors**. These are static gates, not universal runtime-equivalence
claims.

All 3,856 named resource payloads, source timestamps, kinds, CRCs and sizes
match. Creation timestamps differ between independent builds. Archive order
now matches the native metadata sequence at all **3,856 positions**, with no
missing or extra names. The 132-case native resource matrix and 30 portable
fixtures pass. The complete emitted archive comparison also confirms all
3,856 ordered entries, payloads, kinds, CRCs, declared sizes and source timestamps
match exactly; only creation timestamps differ between builds.

Current difference candidates are 89 branch/switch-only, 9,543 cache/reference-only,
181 other-operand-only, and 26,088 mixed bodies. A bounded whole-body audit
classifies 3,021 mixed bodies through local store/reload and unused flag
materialization rules. Remaining receiver and branch audits are being refreshed;
these candidate categories do not establish semantic parity. A bounded class-static
binding audit checks 1,625 aligned references with no differing owner identities;
six different-name candidates belong to reordered meteor switch cases. It leaves
2,121 references and 12,389 procedure layouts unresolved. The compiler corpus
has been refreshed after the exporter ordering repair: all 671 cases finish
with 554 accepted translations, 113 native rejections and four OpenDream
rejections; no translation or metadata errors. The subsequent fixes cover nested receiver association, field-write boundaries,
indexed/output expression entries, skipped safe RHS cleanup, builtin-named
static bindings, implicit null provenance, literal Unicode/control separation
and Usr retained-result ownership. The current archive is 217,619,930 bytes;
the DMB is 43,170,786 bytes. Both round-trip byte for byte. Current SHA-256:

- DMB: `DFAAE85A7B2124B1A6F0064C1B195894ED70A65AD18E997AAEEE224C629DC33D`
- RSC: `92A947AC15E9F65116BE4032A28AD1CB682F105AE68005C21896A3D1BB584577`

The residual review found another constructor expression entry defect in
`/proc/log_research`: a conditional branch skips the inserted constructor type
operand. Its repair is in progress. Two corpus rejections are premature
OpenDream `log` constant validation; `initial(issaved(local))` also needs a
paired wrapper contract. Native accepts the fourth rejected source, a bare
`global` iterator destination, but emits an invalid null-field write. These
limits prevent a claim of complete semantic equivalence.

## Previous completed static validation — 2026-09-28

This section records an earlier snapshot. Artifact filenames have subsequently
been reused; the active integration section above identifies current bytes.

The `deepquarry-final` artifacts under `D:/opendream-diagnostic/` use the
original game expressions and the current patched OpenDream exporter.
All 59,982 exported procedures pass lowering. All 62,318 emitted procedure
records decode and reassemble, every checked branch lands on an instruction
boundary, and all typed table references resolve. The completed package gate
passes 444 core tests and every integration test, including native deletion,
null ownership, client settings and warning-context regressions. There are
231,381 checked branch targets and zero invalid targets. Static validation
does not establish universal runtime equivalence.

The refreshed pinned compiler corpus contains 671 cases: 554 pass lowering,
emission and instruction validation; Dream Maker rejects 113 sources and
OpenDream rejects four. There are zero translation failures and zero compared
metadata differences among accepted cases. Native rejections include 100
explicitly authored compile-error tests. Diagnostic pragmas are removed
identically for both compilers; source incompatibilities remain recorded.

The matched game comparison pairs 59,465 named/initializer procedures, with no
unmatched pairs: 20,224 normalized matches and 39,241 structural differences.
These are comparison counts, not a semantic coverage percentage. All compared
table/world/header metadata and map semantic differences are zero. The prior
client callback aggregation, computed receiver call-mode, and equality-to-null
categories are absent from this refreshed difference report. Duplicate paths
are paired by ordered class bindings, with regression checks that corrupted
bound bodies and argument lists still surface. Both DMBs reference the same
3,835 resource identities; all 3,856 named RSC payloads match byte for byte.
Archive order and timestamps differ. Current DMB and RSC both survive a
byte-identical read/write round trip.

The refreshed conservative cache audit considers 27,360 procedure pairs and
skips 16,686 unsupported layouts. It establishes 39,386 equal full references
and 4,847 equal method receivers, retaining 802 unknown accesses. Eleven
candidates are the previously inspected independent initializer store
reorderings. Paired native probes establish cache persistence for procedure
Src and World roots across calls; derived receivers and unproved roots stay
unknown. Mixed layouts still require analysis. No DreamDaemon execution was
used, and these checks do not establish universal runtime equivalence.

The generated DMB is 43,098,689 bytes, SHA-256
`9CE9BE9F6486580AA4F36CE37AF4754844D33F8C0691B117F794FA9DA35BB635`.
The RSC is 217,619,930 bytes, SHA-256
`D27638E32960C30BBBD3DF47E9B17779415E19496B7BF83746E4CE423BCB0DCA`.
Both hashes are unchanged by read/write copying. The input export SHA-256 is
`3FB8012F544B5C7D8479175236371C20773B02A178C31E0BD3703D5AB718ED7D`.
These identify the completed snapshot; remaining bytecode differences are
still being reviewed and must not be counted as proven semantic matches.

The residual review has since established further behavioral defects:
repeated method calls through a mutable derived receiver reload its replacement
instead of preserving native Cache, and a continue targeting the first protected
instruction lacks native exception-frame cleanup. Native probes and interpreter
dispatch tracing establish both. Repairs and refreshed gates are in progress;
the snapshot above must not be described as complete semantic parity.
Resource archive order is also runtime-visible for duplicate-content filenames:
native CRC-tree insertion and resource formatting depend on that order. Six
alias groups have reversed ordering in this snapshot. Reconstruction of native
resource ordering is in progress; matching all named payloads does not prove
filename identity.

The 75 branch/switch-only pairs in this snapshot have a bounded classification:
67 differ by conditional/unconditional jump chains and eight by switch-table
entry order. Following only the same short-circuit test or unconditional jump
with cycle bounds preserves the destinations in all 67 cases. The eight tables
preserve every key's logical target and the default target (six string tables,
two numeric). This evidence applies only to these pairs, not arbitrary mixed
control flow, and does not change the strict comparison output.

Evidence: `final-emission.txt`, `final-opcodes.txt`,
`final-references.txt`, `final-parity.txt`/`.ndjson`,
`final-dmb-copy.txt`/`final-rsc-copy.txt`, `final-cache-owner.ndjson`, and
`conformance-verified/sweep.ndjson`. The older results below are historical.

Follow-up numeric probes found 18 binary logarithm constant mismatches from
rounding each logarithm before division. The compiler patch now rounds the
double-precision quotient once. A portable fixture verifies 168 logarithm,
square-root and power constants against native float bits. Separate fixtures
cover cardinal and very large trigonometric inputs and 673 RGB/HSV/HSL
constants, including signed hues, named arguments and explicit null alpha.

Further native probes verify 1,073 arithmetic and bitwise constants across
five portable fixtures. Corrections include 24-bit bitwise results, native
shift-count clamping, signed integer conversion for modulo, floating remainder,
and positive-zero normalization. A fractional modulo divisor that truncates to
zero now produces a compiler diagnostic instead of crashing the compiler.

The cache audit also independently matches 11,516 constant-initializer
signatures. The bounded pattern audit proves 892 additional complete bodies
with local/argument store-reload fusion or discarded flag materialization.
The remaining mixed layouts still require proof. Static VM disassembly now
establishes that StaticProc resolves the referenced procedure's actual display
name and enters the same receiver-based resolver as DynamicProc. The comparer
uses that exact name only; the paired static-selector integration passes in
both debug modes. StaticVerb is excluded. Call29 followed by Pop and the
native CallStatement form differ in managed-result lifetime; this difference
is preserved by lowering rather than hidden by comparison normalization;
the refreshed game report has no call-mode-only differences.

Native incremental archive fixtures now establish how deleted RSC slots split
and retain old payload fragments. The reader exposes validated former named
metadata without turning deleted slots into live assets, and preserves every
free-block byte on write.

Static comparison performed 2026-09-27 against the matched Dream Maker
516.1687 diagnostic build. Both builds use the native conditional branches
and the documented diagnostic source overlay, rather than an unrelated game
build. No DreamDaemon execution was used.

## After correctness fixes

The latest translated artifact is D:/opendream-diagnostic/deepquarry-fixed-debug.dmb with its matching RSC. The full debug lowering audit passes all 59,982 exported procedures. All 373 package tests, Clippy with warnings denied, and the formatting check pass. All 62,318 emitted procedure records decode and reassemble without word changes.

| Area | Latest result |
| --- | --- |
| Named/initializer pairing | 59,465 pairs, zero unmatched |
| Strict normalized bytecode | 13,280 match; 46,185 differ |
| Maps | Zero semantic differences |
| DMB resource identities | 3,835 each, zero missing/extra |
| RSC payloads | All 3,856 named assets byte-identical |
| RSC metadata | Only timestamp/source_timestamp differ; entry order differs |
| Mob/world metadata | Earlier darkness, savefile-version and world-membership discrepancies resolved |
| Procedure totals | Seven fewer equivalent duplicate constant initializer records |
| Variable records | 37,991 translated versus 38,111 native; 119 duplicate null/name records and one unused intrinsic account for the gap |
| Lists | 122,519 translated versus 125,539 native |
| DMB size with debug info | 47,498,375 translated versus 45,526,112 native bytes |

Every emitted Teq precedes Pop, and conditional Tne uses Test. Iterator saves are present and nested/labelled/range exit fixtures match native behavior. Strict differences still include alternate cache, result-discard, filtering and control-flow encodings. Those require further equivalence analysis; these results do not certify full runtime parity.

Latest evidence: fixed-parity-summary.txt, fixed-parity.ndjson, and fixed-opcode-audit.txt under D:/opendream-diagnostic/. The earlier comparison-context census is fixed-equality-contexts.txt. The sections below preserve the initial audit.

The follow-up fixes native `global.vars` access through a kind-82 variable record,
formatted output fusion across debug markers, and method receiver analysis across
debug markers. Native receiver-mutation fixtures also confirm argument timing in
ordinary, safe and computed field calls. Of the earlier 121-variable record gap,
119 are duplicate null/name entries, one is an unused native intrinsic entry, and
the live intrinsic entry is now emitted.

## Original results

The follow-up classification and prioritized fixes are in
[BYTECODE_ISSUES.md](../../BYTECODE_ISSUES.md). Improved alias/duplicate matching pairs
59,465 records with zero unmatched named/initializer records: 10,704 normalized
matches and 48,761 differences. The original raw-path comparison below remains
as a record of the initial audit. The follow-up identifies distinct equality,
inequality and iterator correctness bugs; strict matching is not runtime parity.

| Area | Result |
| --- | --- |
| Classes | 40,479 in both files; no class declaration/default discrepancies reported |
| Maps | Zero semantic discrepancies, including constant override initializers |
| DMB resource identities | 3,835 in each; zero missing or additional identities |
| RSC assets | All 3,856 named payloads byte-identical; no missing filenames |
| RSC encoding | Entry order differs; metadata differs in all 3,856 named entries |
| Procedure metadata | Earlier owner-aware procedure-table audit reports zero discrepancies; the simple path/table-order comparison reports ten argument/local differences from reversed override pairs |
| Other metadata | 829 mob records, one world numeric setting, one world procedure-membership comparison differ |
| Strict normalized bytecode | 10,696 of 59,435 paired path/initializer records match; 48,739 differ |

The bytecode comparison resolves typed IDs, equates integer/float pushes, removes
debug file/line instructions, and normalizes supported branch destinations.
It does **not** prove equivalent stack/cache execution, align alternative
control-flow graphs, normalize every switch table, or match reordered overrides
by their ownership chains. The 18.0% strict match rate is not a runtime parity
percentage. Thirty records on each side remain unmatched under raw path spelling;
their names show native callback aliases such as `/atom/Click` versus
`/atom/proc/Click`, plus differing duplicate-chain grouping.

## Concrete differences to investigate

1. **Mob `see_in_dark`: native 2, translated 0 in 829 records.** Sight bits,
   key values, and `see_invisible` agree in those records. Examples include
   `/mob/living` and its descendants. This is a value discrepancy, not an ID change.
2. **World savefile BYOND version: native 516, translated 0.** Other numeric
   world settings in the compared tuple agree. The effect of the zero value
   needs native validation.
3. **Procedure binding/chain representation.** Native callback paths and
   translated `/proc/` paths differ. The simple comparator also pairs opposite
   override entries for `power_change`, `forceMove`, `rejuvenate`, `get_bodytype`,
   and `set_viewsize`; these ten metadata reports require chain-aware matching,
   rather than treating them as ten established compiler bugs.
4. **Bytecode/cache/optimization differences.** Frequent first differences
   include native CallStatement versus Call, SetVar versus SetVarExpr, cached
   field references versus explicit SetCache references, and alternate handling
   of unused or null values. These require instruction/control-flow inspection;
   a positional mismatch alone does not establish changed behavior.

## Container sizes and counts

| Table | Native | Translated |
| --- | ---: | ---: |
| DMB bytes | 45,526,112 | 55,456,121 |
| Procedures | 62,325 | 62,318 |
| Variables | 38,111 | 37,990 |
| Strings | 298,380 | 299,834 |
| Lists | 125,539 | 360,414 |
| Instances | 26,236 | 26,227 |
| RSC bytes | 217,619,930 | 217,619,930 |

The DMB is 9,930,009 bytes larger (21.8%). Different allocation/sharing and
generated records can explain count differences; the count alone does not
establish a missing runtime object. The large list-table increase deserves
deduplication analysis after semantic differences are resolved.

## Reproduce

Run `cargo run --manifest-path tools/dmb/Cargo.toml --example output_parity --`
followed by native DMB, translated DMB, output NDJSON, native RSC, and translated
RSC paths. The summary is written to stdout; the NDJSON contains all metadata
differences and up to three differences for each differing bytecode pair.

Artifacts from this run:

- Native: `D:\dmb-matched-reference-0996c651\deepquarry-static-ref.dmb`
- Translated: `D:\opendream-diagnostic\deepquarry-translated.dmb`
- Summary: `D:\opendream-diagnostic\output-parity-summary.txt`
- Detailed differences: `D:\opendream-diagnostic\output-parity.ndjson`

Passing the lowering check means every input procedure has an accepted
translation. This comparison demonstrates that native semantic/runtime parity
still needs work.

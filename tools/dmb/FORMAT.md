# BYOND 516 compiled format notes

This describes the dialect checked against DeepQuarry's Dream Maker 516 output.
All binary integer fields are little-endian. The normal body starts with two ASCII lines terminated with LF. An optional
executor prefix precedes them: `#!` plus executor bytes and LF. Native executor
text may contain UTF-8, formatting controls or additional LF characters, so the
reader preserves the entire prefix up to the body version/compatibility pair.
Position-based string length/data ciphers count from the body start, excluding
this prefix. Four native executor fixtures verify exact read/write round trips. Header flag `0x40000000` selects 32-bit object IDs;
otherwise object IDs are 16-bit. The nullable ID sentinel is `0x0000ffff`.

The original public research is [20kdc's DMB document](https://github.com/20kdc/byond-data-docs/blob/master/formats/DMB.md)
and [RSC document](https://github.com/20kdc/byond-data-docs/blob/master/formats/RSC.md).
The `dmasm` parser by Willox informed version-gated field investigation. The
package validates v516 behavior independently against two local compiled
worlds and reproduces their bytes exactly.

## DMB section order

The counts in this table describe the original investigation sample, not the
latest translated build. Current comparison counts are in `doc/audits/PARITY_REPORT.md`.

| Section | Encoding | Main-world count |
| --- | --- | ---: |
| Header | two text lines, `u32` flags | 42 header bytes |
| Grid | three `u16` dimensions; run groups of three object IDs and `u8` run length | 2,142 groups for 30,000 cells |
| String total | `u32`, includes one virtual NUL per string | 10,521,632 |
| Classes | object ID count and variable-length records | 40,117 |
| Mob types | object ID count and variable-length records | 1,279 |
| Strings | object ID count, position-XOR lengths, XOR-jump-9 data, NQCRC footer | 300,084 |
| Lists | object ID count; each has `u16` word count and that many `u32` words | 122,572 |
| Procedures | object ID count and variable-length records | 59,624 |
| Variables | object ID count, fixed records, then one `u32` footer | 39,383 |
| Procedure references | object ID count and IDs | 110 |
| Instances | object ID count and fixed records | 22,569 |
| Map objects | `u32` count, `u16` cell delta and instance ID | 4,296 |
| World | v516 fields including savefile target version, script text ID, counted script-file IDs, and view dimensions | 101 bytes with zero script files |
| Resource references | object ID count, `u32` ID and `u8` kind | 3,835 |

The final resource record ends exactly at EOF. The string byte total and
checksum verify. Every DMB resource-reference pair `(id, kind)` resolves to
a valid named RSC entry. DMB strings are raw bytes because DM string formatting
uses non-text control codes.

The header's 32-bit flags contain compiler settings. Isolated v516 builds
identify `0x2` as disabled `world.loop_checks`, `0x20` as enabled
`world.sleep_offline`, `0x400` as disabled `client.show_verb_panel`, `0x800`
and `0x1000` as `client.preload_rsc` modes 0 and 2 (neither means mode 1),
`0x2000` as hidden `world.visibility`, `0x8000` as disabled
`client.authenticate`, `0x100000` as disabled `client.show_map`,
`0x20000` as Dream Maker debug source markers (`DbgFile`/`DbgLine`),
`0x10000000` as disabled `client.show_popup_menus`, and `0x20000000`
as use of external-library calls or `load_ext` (ordinary object `call()` does
not set it). `0x40000000` selects 32-bit IDs.
Bit `0x80000000` adds a second 32-bit flag word. Isolated
`world.movement_mode = 1` and `= 2` builds put `0x4` and `0x8` in that
second word, respectively. The reader and writer preserve that word.
The main and test builds have identical header flags, `0x61e2050d`.
Native callback probes identify `0x4`/`0x8` as authored `Click`/`DblClick`,
`0x200000`/`0x400000` as `MouseUp`/`MouseDown`, and
`0x800000`/`0x1000000` as `MouseDrop`/`MouseDrag`. These arise for atom
and client owners, not unrelated datum/global procedures with the same names.
For client owners only, `0x2000000` marks `MouseEntered`/`MouseExited`; `MouseMove` also sets it
and extension-word bit `1`, while `MouseWheel` sets extension-word bit `2`.
`client.Command` sets `0x4000`, and `client.IsByondMember` sets `0x40000`. `client.macro_mode = 1` sets `0x80`, and
`client.perspective` modes 1/3 set `0x8000000` (modes 0/2 clear it).
`0x100`/`0x200` are cleared by explicit `client.lazy_eye`/`world.view`
assignments, even assignments of their default values. Native `filter()`
use clears the default `0x40` bit. Bit `0x1` marks resolved CPU access;
plain discarded CPU reads do not set it, but used/computed/nameof/issaved
mentions and dead-branch resolved accesses do. Source metadata preserves
these distinctions. Header
comparison checks verified semantic bits, excluding opaque bits, ID width,
and debug markers. See `CLIENT_HEADER_PROBES.md` for portable evidence.

Small 16-bit-ID fixtures compiled with a v516 banner also round-trip exactly.
The `min compatibility v514` variant omits the four-byte
`savefile_byond_version` world field; v515 and v516 include it.

## RSC entries

Each entry is `u32 payload_length`, `u8 validity`, then exactly that many
payload bytes. Validity `1` contains resource kind, ID, two timestamps,
declared size, a NUL-terminated path, then data. Validity `0` marks an invalid
or obsolete entry; its payload must be kept opaque. The declared size is the
current asset length. The ID is NQCRC of the first `declared_size`
data bytes, starting at `0xffffffff`; this was verified for every named entry
in both builds. Remaining bytes are unused capacity retained by RAD after
asset updates: replacing a 100-byte `probe.txt` with `SHORT` left the old slot
length and bytes `SHORTAAAA...` in a Dream Maker fixture. The writer retains
all of it. The named resources in the main archive use these kinds:

| Kind | Resource type | Count |
| --- | --- | ---: |
| 0 | Generic resource (including DMF skins and text) | 28 |
| 1 | MIDI and tracker modules | 4 |
| 2 | Sound (including OGG) | 1,936 |
| 3 | DMI | 1,853 |
| 6 | PNG | 43 |
| 13 | GIF | 43 |
| 14 | Font | 4 |

The DMB resource table stores ID before kind, matching the RSC fields.
Runtime resource identity is the NQCRC content ID, independent of extension
kind. A paired archive containing identical bytes under tracker, sound, image,
and generic filenames has one DMB resource reference using the first kind;
its named RSC records retain their individual kinds and exact authored spellings.
Physical source paths are separate from archive names, including assets found
through `FILE_DIR` outside the project directory.

## Remaining semantic decoding

The container and every table are parsed and writable. Procedure code is
available through `Dmb::proc_code_words()` as exact `u32` words and through
`bytecode::decode()` as instructions with operand boundaries. The decoder
parses and reassembles all 59,624 main-build procedures and all 62,391
test-build procedures. All opcodes used in the two local builds now have
operation names, including newer v516 opcodes identified by matching DM source
with compiled code. Value tags and nested variable accessors decode to typed
forms; their raw words remain available for exact writes.
`od_lower.rs` translates a verified subset of OpenDream bytecode into BYOND
instructions. Paired Dream Maker/OpenDream fixtures cover object creation,
variables, lists, branches, calls, inheritance, maps, resources, and selected
built-ins. Unsupported instructions return a procedure and byte offset rather
than an approximate instruction. General opcode and game-wide semantic parity
remain open work.

Paired fixtures establish frame-reference operands `0xfff0` for `caller` and
`0xfff1` for `callee`. Receiver Cache is `0xffd8`. These operands do not index
the string table. Native reader `10131055` bounds intrinsic dispatch to
`0xffcd..=0xfff1`; `0xfff8` is an ordinary field string ID, not an Eval operand.
The interpreter's Eval scratch has no observed variable-reference encoding.
Native
value tag `0x59` represents builtin class paths such as `/alist`, `/vector`,
and `/callee`; its payload is a class ID. Type categories follow the actual
`parent_type` ancestry, including types whose written path is under a different
builtin root. The intrinsic builtin roots retain their own categories.

`CmpText` and `Teq` retain an operand and expose their boolean through the
comparison flag. A value consumer needs `Pop; GetFlag`; a conditional can read
the flag directly after `Pop`. Variadic text comparison short-circuits before
evaluating later arguments. Native `0x16a` and `0x16b` are `Trunc` and `Fract`.
The variable-table footer is a list of global variable ID/flag pairs
(`1` global, `2` const). Dream Maker comparison fixtures identified the world
record's `savefile_byond_version` field and the packed `world.view` width and
height. Variable kind `0x3e` marks values built by initializer bytecode rather
than literal constants. `fixtures/hidden_initializer.dme` emits this kind for
a global list, a static local list, and an object member list; the ordinary
local list and numeric member do not have it. The `value` word contains a
compiler-assigned initializer token (`0`, `1`, `2` in that fixture). With DEBUG
undefined, native reuses tokens for identical initializer expressions across
independent globals, class declarations, and static declarations. Final,
case-sensitive DEBUG macro presence disables that sharing, even for DEBUG=0.
Constructor argument count, order, and named/positional mode affect identity.
These words therefore do not establish runtime object identity. Initializer
procedures construct the lists and assign them by VarID. The runtime use of
the marker is confirmed: `initial(field)` copies its tag and token, and native
equality compares both. See [`INITIALIZER_TOKEN_EVIDENCE.md`](INITIALIZER_TOKEN_EVIDENCE.md).

Class flag bits 21 and above encode `appearance_flags`: the root
`/atom/movable` value is `0x321` for `TILE_BOUND | PIXEL_SCALE |
KEEP_TOGETHER | LONG_GLIDE`, while the gas overlay override is `0x100` for
`TILE_BOUND`. Dream Maker comparison fixtures also established these low
class flag encodings: MouseEntered/MouseExited set `0x800`, MouseMove sets
`0x80000`, and MouseWheel sets `0x100000`; MouseDown/MouseDrop do not set
these callback bits. Authored ancestor layer/appearance defaults propagate
through builtin class headers. Direction zero serializes SOUTH (`2`).
Dedicated name/text defaults use actual ancestry: atoms derive names from
their leaf paths, while images and mutable appearances retain absent defaults.
Derived atom text preserves the first raw name byte after native formatting
prefixes; it must not decode and re-encode a Unicode character.

Procedure argument lists consist of four `u32` words per argument: `as` type
flags, a packed `in` value-source code and parameter, parameter VarID, and a
reserved word. Both local builds have lengths divisible by four, valid variable
IDs, and zero reserved words for every argument (50,334 main, 55,006
test). The fifth class list slot stores variable-ID/declaration-flag pairs;
all observed IDs resolve to variable records, and all list lengths are even.
Its observed flag values are 0, 1, 3, 4, and 5. Bits `1`, `2`, and `4`
represent `global`, `const`, and `tmp` declarations respectively, as in the
global-variable footer.

Wire declaration pairs retain compiler order and need not be sorted by VarID
or by the variable's name StringID. The native loader resolves and merges
parent/child declaration vectors at `1011a352` through `10117e90`, sorts the
runtime pairs by `variable_name[VarID]` (comparisons at `10117f15` and
`10117f37`), and stores the resulting list in the runtime class's `+0x70`
slot. Field lookup `10213370` binary-searches that runtime list by name
StringID; it does not search the original wire order. Both fresh native and
translated `/obj/structure/cable` declaration lists are unsorted on wire,
and both contain identical numeric defaults for `d1` and `d2` (0 and 1).
Remapping strings therefore does not require sorting serialized declaration
pairs; the loader reconstructs its search order from the remapped names.
The argument `as` mask observed in the main build is `0x1daf` and uses
`MOB=1`, `OBJ=2`, `TEXT=4`, `NUM=8`, `FILE=16`, `TURF=32`,
`NULL=128`, `AREA=256`, `SOUND=1024`, `MESSAGE=2048`, and
`ANYTHING=4096` as independent bits. The package exports these constants.
The argument source field's low byte selects the source kind and the
next byte holds a radius or a reference-table index. `0x01` is `in view`,
`0x02` is `in oview`, and `0x10` is `in world`; `0x7d` in the next byte
is the default radius sentinel and `0x7f10` represents `in world`.
Kind `0x40` means `in` a generated expression. Its next byte indexes
the DMB procedure-reference table. In an isolated fixture,
`a in list(1,2,3)` produced `0x40` and reference 0 to a generated proc
that constructs the list; `a in /obj` produced `0x140` and reference 1
to a generated proc that returns the type path. Both full builds have
exactly one reference for each kind-`0x40` argument, with every index
resolving. The package exposes `Dmb::argument_source_proc_id()`.

The fourth class list slot is a sequence of `VarID, tagged value` records.
The tagged value has two words, or three for a numeric constant. All 132,189
main-build and 137,980 test-build assignments parse to the end of their lists
and resolve valid VarIDs. Tag `0x3e` is a hidden initializer placeholder for a
non-constant value, as [BYOND's developer explains](https://www.byond.com/forum/post/2975205?hla=LummoxJR).
For example, `/datum/controller/subsystem/aifast` stores one for
`dependencies`, while its class initializer procedure executes
`PushVal /datum/controller/subsystem/ai`, `NewList 1`, then assigns
`dependencies`. The stored number is not a List Table ID.
The class's final override list stores `StringID, tagged value` records for
builtin properties without dedicated fields. All 81,971 main-build and
82,311 test-build overrides parse cleanly and resolve valid property names;
for example, the projectile bullet type overrides `glide_size` and `plane`.

The class interface discriminator is `1` for ordinary classes in this build.
Value `15` adds a `u32` native interface code: observed roots include `/image`
(`65`), `/sound` (`545`), `/icon` (`769`), `/matrix` (`1025`), `/regex`
(`8193`), `/mutable_appearance` (`16449`), `/generator` (`32769`), and
`/database/query` (`36865`).

Procedure flag bit `0x1` is `set hidden`, `0x4` is `set waitfor`, `0x100`
is `set background`, and `0x200` is `set instant`. With compact flag bit
`0x80` set, a `u32` extended flag word and one byte follow; the extended
word carries the same low bits. The settings were cross-checked with
`/obj/machinery/feeder/process` (`background = 1`) and
`/client/verb/moveKeyDown` (`instant = 1`, `hidden = 1`). Bit `0x2` marks
an explicit `set src = ...`; `0x20` means `set category = null` and `0x40`
means `set popup_menu = 0`. Bits `0x8` and `0x10` encode an explicit
`set invisibility`. Level zero uses byte `255` and bit `0x8`; positive
levels use both bits and the level byte, capped at `127`.

The procedure source kind is `0` for default, `1` for `src in view`,
`2` for `src in oview`, `3` for `src = usr.loc`, `5` for `src in range`,
`8` for `src in usr`, and `32` for `src = usr`. The companion byte is the
view/range radius when given; `125` appears for `view()` with no explicit
radius, `127` for `in usr`, and `255` where no numeric radius applies.
Isolated `set src` fixtures reproduce every source kind in DeepQuarry.

Mob records store the `sight` mask in one byte until bit `0x80` signals
an extended `u32` mask plus `see_in_dark` and `see_invisible` bytes.
The observed mask bits `BLIND`, `SEE_MOBS`, `SEE_OBJS`, `SEE_TURFS`,
`SEE_SELF`, `SEE_INFRA`, `SEE_PIXELS`, `SEE_THRU`, and `SEE_BLACKNESS`
match isolated assignments. `see_infrared = 1` emits extended bit
`0x10000`.

| Bits | Initial property | Encoding |
| --- | --- | --- |
| `0x1` | `opacity` | Boolean |
| `0x2` | `density` | Boolean |
| `0x4` | normal visibility | Cleared by nonzero `invisibility` |
| `0x38` | `luminosity` | Three-bit unsigned value; `luminosity = 7` produced `0x38` |
| `0xc0` | `gender` | 0 neuter, 1 male, 2 female, 3 plural |
| `0x100` | `mouse_drop_zone` | Boolean; isolated fixture with value 1 added this bit |
| `0x400` | disabled `animate_movement` | Set when `animate_movement = 0` |
| `0x800` | mouse event handler | Set by `MouseEntered` and `MouseExited` |
| `0x3000` | `mouse_opacity` | `(value - 1) & 3` |
| `0xc000` | `animate_movement` | `(value - 1) & 3`; zero also sets `0x400` |
| `0x80000` | `MouseMove` handler | Set when the type defines `MouseMove` |
| `0x100000` | `MouseWheel` handler | Set when the type defines `MouseWheel` or `MouseMove` |

All low class flag bits present in the two DeepQuarry builds now have identified
purposes. Other bit positions have not been emitted by these builds. The byte
between `client.control_freak` and `client.script` is zero in both builds and
in isolated client settings fixtures for `show_popup_menus`, `macro_mode`,
`perspective`, `pixel_step_size`, `lazy_eye`, `control_freak`, `dir`, `view`,
`fps`, `default_verb_category`, `screen`, `command_text`, and
`command_prompt`. The byte is authored client Import-handler presence: /client/Import and client subtype Import bodies set it to1; Export or unrelated datum/global Import bodies leave it0. The public unknown_byte field is retained for compatibility with semantic accessor methods.
Byte parity proves the parser has the correct boundaries and wire encoding for
the two specimens; unobserved flag positions and noncanonical field values
remain outside the native evidence.

## BYOND 516 opcode identifications

The compiler produced these operations in procedures whose DM source contains
the matching expression. `v` is a nested variable operand; `u` is one raw word.
[BYOND's 516 feature summary](https://www.byond.com/forum/post/2966223)
documents the new arithmetic and associative-list built-ins used in the
isolated fixtures.

| Opcode | Operation | Shape | Source witness |
| --- | --- | --- | --- |
| `0x15e` | generator initialization | `v` | built-in `/generator/New` |
| `0x167` | `json_encode` with flags | stack | `/proc/save_admin_backup` |
| `0x169` | `ceil` | stack | vote threshold calculation |
| `0x16c`, `0x16d` | `isnan`, `isinf` | stack | `isnum_safe` in `/proc/deep_copy_list_alt` |
| `0x16e` | `trimtext` | stack | `/proc/parse_github_changelog` |
| `0x170` | coordinate `block` | stack | `RANGE_TURFS` in `/proc/urange` |
| `0x173` | square | stack | `b*b` in `/proc/SolveQuadratic` |
| `0x178` | `refcount` | stack | `/proc/prune_list` |
| `0x179` | `load_ext` | stack | generated Verdigris bindings |
| `0x17a`, `0x17b` | `call_ext` positional, arglist | `u`, stack | generated Verdigris bindings |
| `0x17c` | construct `alist` | `u` | kitchen recipe registration |
| `0x17e` | associative pair value iterator | `v` | `/proc/_debug_variable_value` |
| `0x17f`, `0x180`, `0x181` | `pixloc`, `vector`, `bound_pixloc` | `u`, `u`, stack | isolated spatial built-in fixture |
| `0x182`, `0x183`, `0x184` | `sin`, `cos`, `tan` | stack | trajectory and tangent circuit procs |
| `0x187` | `lerp` | stack | isolated `lerp(a,b,c)` fixture |
| `0x188`, `0x189`, `0x18a` | `values_sum`, `values_product`, `values_dot` | stack | isolated built-in fixture |
| `0x186` | `sign` | stack | isolated `sign(b)` fixture |
| `0x18b`, `0x18c` | `values_cut_under`, `values_cut_over` | stack | isolated built-in fixture |

The opcode table in `src/opcodes.txt` covers the instructions observed in the
main and test builds. Unobserved BYOND instructions still require fixtures.

## Additional native emission contracts

### Compact numeric literals

`PushInt` (`0x50`) reads its operand as an **unsigned 16-bit word**, even
though the DMB code table stores 32-bit words. Native 516.1687 handler
`10145d86` zero-extends the word and constructs numeric tag 42. `PushVal`
(`0x60`) tag 42 reconstructs float32 bits from its high/low operands.
Compact literals are therefore safe for integral values in `0..65535` only;
negative and wider values need the floating encoding. Treating a raw compact
operand as signed 32-bit incorrectly hides errors: encoded `-26` is read as
65510 and can clamp atom pixel offsets to 32767. Native map fixtures and trusted
paired execution confirm the corrected negative and wide-number handling.

Implicit `locate(value)` uses unary `LocateRef` (`0x5b`). Explicit
`locate(value) in world` and `in list` use binary `LocateType` (`0x97`);
the adjacent world getter alone cannot distinguish these source forms.
The patched exporter supplies optimized byte offsets for the implicit form.

Procedure membership lists carry native definition precedence. Paired class
and world reopen fixtures place override bodies before ordinary declarations,
newest first within each phase. Comparing only sorted procedure paths loses
this distinction; the regression also compares ordered bodies and arguments.

Hidden initializer kind `62` occurs for constant `file()` and `icon()`
declaration constructors, including static declarations. Static constructors
whose arguments depend on another runtime global retain kind `0` instead.
The resource-initializer fixture verifies both cases; this does not establish
all unobserved constructor marker rules.
Procedure-path constants can identify different bodies with the same method
name: `/type/proc/name` references the original declaration, while
`/type/name` references an own override. An unqualified root `/name` body may
be absent from named global dispatch but remains reachable by a proc-path value.
Canonicalizing both paths or omitting that body loses this distinction.
Native world callbacks use `/world/name`, not `/world/proc/name`.
### Deleted RSC capacity

The historical primary archive contains 347 validity-zero slots. A bounded
inspection recovered 96 nonempty former filenames with complete named headers
and matching content CRCs; the other 251 slots did not satisfy that evidence.
For example, deleted `icons/obj/closets/decals/closet.dmi` retains kind3, a3084-byte
asset prefix, and a matching saved resource ID. Some deleted records retain
unused trailing capacity. Arbitrary remaining bytes are not proven named records
or zero-filled space. The controlled probe below identifies free asset remnants;
the exact history of each older slot remains unknown.

`Entry::deleted_named_resource()` exposes borrowed former metadata only when
header/name/declared-size bounds and content CRC validate. It never turns the slot
into a live entry. Reader/writer round trips preserve validity0 and every byte.
The portable `deleted_slots.rsc` fixture covers a recoverable record and opaque
free-block remnants, with corruption and truncation negative cases.
A native incremental compile probe establishes why deleted payloads need not
contain a header. Growing `a.txt` from120 to500 bytes invalidates its old143-byte
payload intact. Importing a new50-byte `c.txt` reuses that capacity: a73-byte live
payload replaces the prefix, followed by a new5-byte deleted-slot header and65
bytes copied exactly from the former asset interior. These residual asset bytes
are free capacity, not another named-resource structure. Shrinking in place keeps
unused old asset bytes after the new declared-size prefix. Removing a source
reference alone leaves its prior cached live entry in this probe.

The347 historical deleted slots group structurally as245 declared-size fields
out of bounds,5 empty names,1 non-filename-shaped name, and96 bounded printable
former names with matching CRCs. The controlled split probe proves allocator
remnants can produce the first categories; it does not identify the exact history
of each old slot. Five portable incremental archive snapshots preserve this proof.
### Resource archive insertion order

Optional compiler JSON field `NativeResourceArchiveOrder` contains native archive
filenames in compiler import order. A present empty array is an annotated export;
an absent field retains the legacy materialization order. Interface tokens expand
to their imported skin icons followed by the interface resource. Resource aliases
retain separate named archive entries even when their NQCRC content IDs match.
Resource table IDs remain mapped by content ID; their kind follows the first
ordered archive entry for that ID.

This order is observable. The native loader inserts every named archive record
into a tree keyed by content ID, and resource-to-text conversion returns the
filename of the tree's matching record. Equal-content aliases are separate nodes;
tree rotations make archive-wide insertion order relevant. Sorting aliases alone
does not establish filename parity. The emitter rejects annotated names that do
not resolve to an imported archive record.

### Client script include metadata

Patched compiler JSON preserves native DMS includes in optional
`NativeClientScriptFiles`, an ordered list of Resource paths. Duplicate exact
includes are ignored. Native world `client_script_files` resolves these includes
first, then appends a resource-valued effective `/client.script`; this final value
can repeat an included ResourceID. Inline script text instead populates the
separate client-script StringID while retaining included files. The nested paired
fixture preserves resource/archive spelling `scripts/a.dms` and `b.dms` directly.
This compiler/exporter support belongs to the separate preprocessor patch plus
combined JSON patch; the build script applies both.
### Authored input selection filters

The patched OpenDream Prompt type operand reserves bit 29 for an omitted
`as` clause, bit 30 for an authored choice expression, and bit 31 for an explicitly
authored `anything` token, including unions. The translator removes these
provenance bits before decoding OpenDream type flags. Explicit anything adds
native mask `0x1000`; omitted types write mask zero with or without choices;
explicit `as anything in L` uses mask `0x1000`. The two forms previously
collapsed to the same OpenDream operand. This annotation adds no instruction
bytes or new opcode, and does not change the compiler metadata version.

### Native hub-password assignment history

Optional program field `NativeHubPassword` stores the last authored constant
text assignment to `world.hub_password` by source ordinal. Native compilation
updates the hashed header only for text assignments: a later null override
changes the variable but retains the earlier password hash. Empty text is a
real assignment and uses its own hash. Standard definitions do not populate
this annotation. Older JSON falls back to the effective world variable.


## Hub password text

The world header's hub-password StringID stores `X` followed by lowercase
MD5 of `hub + password + lowercase_hex(MD5(password))`, using native password
bytes. Native compilation retains the last authored text assignment even if
later assignments are null. See [HUB_PASSWORD_FORMAT.md](HUB_PASSWORD_FORMAT.md)
for source-order export requirements and paired evidence.

### World text, version, and executor header fields

`world.status` is the nullable StringID stored in `World.server_name`;
`world.name` is the separate nullable `World.ids[6]` StringID. Authored null
clears either field. `world.version` truncates a float32 to a signed integer
then stores its bits in a u32; values beyond the exact signed bounds clamp to
plus/minus 2147483647, while exactly 2147483648 stores 0x80000000.

A nonempty `world.executor` adds an optional `#!executor\n` line before
`world bin v516\n`. `Header.executor_line` preserves those bytes separately
from the version and compatibility lines. Empty text and null remove it;
this is a prefix on the normal DMB format, not a different world version.

### Source-resolved graphics compatibility flag

`NativeGraphicsAccess` records authored declarations or resolved references
to intrinsic icon/overlays/underlays fields on actual atom, image, or
mutable_appearance descendants. The native graphics compatibility header bit
0x40 clears for these constructs, including nameof(icon), initial(icon), and
references in a constant-false branch. Same-named custom datum fields and
untyped colon access do not clear it. The exporter checks real parent ancestry
and source origin, and excludes standard library implementation mentions.
Native filter construction is independently identified from lowered code.

### Authored world dimensions and generated cells

Authored positive `world.maxx`, `maxy`, or `maxz` generates a default world grid.
Values truncate to integers; an omitted or zero remaining axis becomes one when
another axis is positive. With no positive axis, the generated grid is empty.
Included maps follow the generated levels: their Z coordinates shift by the
generated depth, and their X/Y extent supplies the resulting map width/height.
The emitter builds those cells from the world turf/area prototype before adding
included maps. Nine paired cases in `fixtures/translation/world_dimensions`
cover empty and fractional dimensions, size changes, and included-map offsets.
The `world_dimensions` integration test compares dimensions, map semantics,
world metadata and reference validity.

`NativeCpuAccess` records authored evaluation of the intrinsic world CPU field
or an unresolved dynamic `cpu` field. Resolution occurs before constant-false
branches are optimized away. Discarded pure field expressions are excluded;
computed receivers, `nameof`, `initial`, and `issaved` retain the native flag.
Custom resolved fields named `cpu` and string-based `vars` indexing do not set
this annotation. The Rust input defaults the optional boolean to false.

The optional per-type `NativeClientSettings` map retains authored client header
settings, including script/preload values in the usual JSON constant encoding.
Settings apply from descendant types toward ancestors; siblings retain first
creation order. Later assignments win within each reopened type, rather than
across all source globally. The old top-level numeric map remains a fallback
for root show_map/macro_mode. These two compile-only settings accept only
numeric 0 or 1 and do not create synthetic class variable records. Missing
settings use native defaults (show_map 1, macro_mode 0).

Native executor formatting keeps the first ASCII space and removes subsequent
ASCII spaces across the entire value; tabs and newlines remain. For example,
`alpha beta gamma` becomes `#!alpha betagamma\n`. This transformation belongs
only to the executor prefix, not ordinary strings. Seven paired whitespace
cases verify prefix bytes and native/emitted read-write parity.

### Additional client setting encodings

Text-valued client.preload_rsc is stored as a class builtin String override and sets preload mode0 (0x800). Numeric preload values must be within [0,2]; exact0 and2 set their respective flags, while other legal values set neither. Native accepts fractions0.5 and1.5. client.control_freak validates [0,7] before truncating to the world.control integer. Both rules apply to client subtype settings in the class-order aggregate described above.

`NativeNullOffsets` on each procedure records optimized byte offsets of authored
runtime null loads. These lower to the intrinsic Null reader, which clears the
owned evaluation temporary before pushing null. Synthetic padding nulls remain
unmarked; switch-case null descriptors are excluded because they are table data.
The compiler preserves marked loads through null-assignment optimization, since
native global/local/field assignments retain the Null read before their setter.
This metadata preserves bytecode opcode IDs and operand widths, and is optional
for older JSON inputs. Historical unannotated inputs cannot establish the full
cleanup timing of arbitrary null expressions.

Perspective accepts numeric values in [0,3]. Both the client builtin override
and header use the truncated integer; the header stores its low bit.
Boolean settings accept numeric zero or one, including JSON floating-point
representations of those exact values; fractional values are rejected.

### Const-null binding provenance

Native runtime reads of `var/const/name = null` retain a named Global reference,
including proc-local declarations. The patched exporter preserves these bindings
in `Globals.ConstGlobalIds`; proc-local const-null declarations allocate no local
slot and emit no runtime declaration initialization. Class declarations reuse their
existing constant Variable record via `Globals.ConstFieldGlobalIds` rather than
creating a duplicate declaration. Other constant values retain their existing folding.

A statically known class const-null field preserves effectful receiver evaluation
and safe-access guards. The patched bytecode uses reference discriminator **17**
with no operand bytes for the native receiver Cache destination (`0xffd8`); it is
distinct from the interpreter's Eval scratch and DM `.`.
This extension does not change opcode widths or the metadata opcode hash.
Unknown field-name resolution selects the last owner in first type-creation order,
including reopened owners. When that winning declaration is const-null, its Global
binding is preserved; a winning ordinary declaration retains dynamic field lookup.
Pure typed dot receivers preserve their known owner binding; computed receivers,
including typed constructors, use the name winner. Pure typed colon access
permits known-owner constant folding; safe colon access uses the name winner.
The paired `const_null_bindings` fixtures cover direct/inherited/typed/computed/safe
reads, distinct same-name proc-local bindings, and an ordinary-field collision.

Prompt type operand bit 29 records an omitted `as` clause. Native mask zero is
preserved instead of replacing omitted input types with explicit `as text` mask 4.
Bits 30/31 continue to record explicit choices/explicit `anything` respectively.

### World view word

The world view u16 supports compact radius and packed axes. Native loader516.1687 (`1024c6d1..1024c723`) tests the word as signed16-bit against255: signed values<=255 are radii; larger positive values are width/highbyte and height/lowbyte. Radius axes are2*r+1 with16-bit wrapping;FFFF is radius-1. This signed test also covers highbit-set words produced by large accepted textual widths. `WorldViewEncoding`, `World::view_encoding`, and `native_view_size` expose this interpretation. The original `view_dimensions` field and raw-byte `view_size` accessor preserve compatibility and exact wire roundtrip.

Compile-time numeric limits are[-1,35] before truncation. Text axes use decimal prefixes with native strtol rules, negative axes clamp0, each axis<=255 and area<=5041. The serializer writes packed axes when width!=0; width0 writes floor(max(width,height)/2) instead. Paired proof and parser/validator/writer addresses are recorded in `fixtures/translation/world_view_shapes/README.md`.



### Authored try control flow provenance

Patched OpenDream procedures optionally export `NativeTryContinueOffsets`,
`NativeTryBreakOffsets`, and `NativeTryGotoOffsets` as optimized byte offsets
of authored Jump instructions inside protected try bodies. Catch bodies are
excluded unless they are themselves protected by an enclosing try. Natural
loop backedges are unmarked. Optimizer passes preserve these marked jumps;
the native lowering uses the source distinction to preserve exception-frame
cleanup at a target equal to the first protected instruction. These fields
add no opcode or payload bytes and do not change the opcode metadata hash.
The native compile-only `try_loop_provenance` fixture covers protected-head,
prefixed, nested, indexed, natural-tail, break, and goto boundaries.

### Authored goto and continue budget checks

`NativeGotoOffsets` identifies authored gotos in either direction. Native
unprotected goto uses JmpLoop (`F8`) even for a forward or adjacent-label jump;
ordinary Jmp (`0F`) omits its CPU-budget check. Protected goto retains TryJmp.

`NativeContinueOffsets` identifies authored continues. A present empty array
proves there are no such branches; missing metadata is legacy output. Synthetic
if/else joins near the final loop backedge remain ordinary Jmp. The natural
backedge and authored continue preserve their native budget dispatch. Paired
`goto_budget` and `continue_budget` fixtures check counts, direction and targets
in ordinary and debug translations.

`NativeDoWhileConditionOffsets` identifies optimized conditional branches at
authored `do/while` tails. The condition is followed by its natural backward
jump, and the false target must follow that jump. Lowering validates this
shape and emits native JnzLoop (`F9`), whose budget check runs on both true
and false outcomes. Constant-false tails emit neither a condition value nor
a jump; constant-true authored continues target the body directly. Native
background procedure attributes govern scheduling without inserted sleeps.

## Authored escaped ellipsis

The patched exporter uses U+FF21 for the authored `\...` escape; emission writes native bytes `FF 12`. This is distinct from literal `...` and from exporter Roman format markers U+FF12/U+FF13. A fourth period remains ordinary text after the control. The native-paired `escaped_ellipsis` regression covers class defaults, direct returns, comparison, length and JSON encoding without running a world.

### Literal format-range Unicode

New exporter strings prefix authored Unicode characters U+FF00 through U+FF5E with U+FF5E before interning. The prefix itself is doubled when authored literally. Native emission consumes this escape and writes the following character as UTF-8, without treating it as a format control. Normal strings, raw strings and Unicode escapes use the same encoding; actual format macros remain unescaped. The `literal_format_unicode` native pair checks defaults, concatenation, returns, length, copytext, MD5, JSON encoding and interpolation separately from ellipsis/Roman controls. Legacy input lacks this source provenance, so existing unescaped control interpretation remains its fallback.

### Initial and issaved reference provenance

Optional per-procedure NativeInitialReferenceOffsets and NativeIsSavedReferenceOffsets identify optimized PushReferenceValue byte offsets. They preserve the authored outer reference modifier for locals, arguments, and readonly constant globals; nested initial/issaved wrappers select the outer modifier on the original reference. Marked globals must belong to Globals.ConstGlobalIds. Invalid offsets, conflicting modifiers, and other reference kinds are rejected. Absent fields retain legacy lowering.

Native local constants retain separate readonly global bindings (footer flags 3), including unused and fold-only declarations. Direct constant reads and modifier queries use these bindings; enclosing compile-time arithmetic and concatenation may still fold. The native-accepted global_reference corpus case assigns a field through a null receiver and remains an unsupported invalid-runtime source case.

Direct global and class constant reads retain native readonly variable references, including numeric, text, and type constants. Pure typed receivers are omitted; computed receivers and safe guards remain evaluated. Unknown computed field names use the native field-name winner, and nonconstant collisions retain dynamic field access. Enclosing constant arithmetic can still fold. Runtime local lifetime removal excludes constant bindings, which have no local slot.

NativeStoreReloadOffsets optionally records optimized Assign byte offsets produced by fusing statement AssignNoPush plus the subsequent read of the same local or argument. Lowering restores SetVar followed by GetVar; unmarked authored assignment expressions keep SetVarExpr. The distinction preserves RHS ownership while a displaced object's synchronous Del callback runs. Marked instructions are retained through later optimizer passes; invalid/nonlocal/nonargument markers are rejected. Global/field stores are outside this fusion optimizer and retain their separate source paths.

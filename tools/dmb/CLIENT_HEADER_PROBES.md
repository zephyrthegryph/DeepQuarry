# Client header probe evidence

Native DreamMaker 516.1687 compile-only probes extend the earlier investigation
of the byte between `client.control_freak` and `client.script`.

## Proven translation fixes

- `client.preload_rsc = 0`, `1`, and `2` produce header mask `0x800`, `0`, and
  `0x1000`, respectively. Changing modes replaces **both** mask bits. The emitter
  previously rejected mode 2 and could retain its bit when changing modes.
- Inline `client.script` uses a StringID; a `.dms` resource uses a ResourceID in
  `world.client_script_files` and leaves the text StringID absent.
- Included `.dms` files precede the direct resource-valued `client.script`. A
  direct script equal to an already included file is appended again. Repeated
  identical `#include` directives are ignored.
- Inline text, including quoted UTF-8 Latin/CJK macro text, is preserved as UTF-8
  bytes. It can coexist with included script files.
- Script-file vector elements are mandatory ResourceIDs. A preceding unrelated
  `.txt` resource makes the direct script's native index **1**; StringID1 is
  unrelated. Archive payloads are the original `.dms` bytes, with resource kind0.

`fixtures/translation/client_header_probe/` contains native and OpenDream output
for preload modes, no-script/inline/file forms, duplicate/nested includes, UTF-8
inline text, and additional client settings. `tests/client_header.rs` checks
all nine resource-free preload baseline transitions and sixteen script source
checks in forward/reverse order using the standard resource-free scaffold. It
compares ordered resource identities and raw script assets, and rejects invalid
vector indices. Resource-bearing outputs cannot be reused as native scaffolds
under the emitter API. The no-script case has an effective null OpenDream value;
native explicitly assigning `client.script = null` is rejected.

## Unknown byte: still zero

The following legal isolated settings leave this byte zero:

- Preload modes0/1/2.
- Text `edge_limit`, pixel_x/y/w/z, glide_size, mouse_pointer_icon, show_map0/1.
- Client New/Del/Click overrides.
- Inline STYLE and macro scripts, empty script text, `.dms` resource scripts,
  multiple included scripts, PASSWORD_TRIGGER and URL directives.
- UTF-8 characters inside a quoted macro command string.

Other settings affect existing header flags, class data, or the script text/file
fields. None of these probes gives a nonzero specimen of the unknown byte.
Its meaning remains unassigned, and its reader/writer representation is preserved.

## Native-rejected probe forms

Numeric edge_limit, static mob/eye assignment, undefined mouse_drag_pointer,
script lists (file/file and inline/file), and explicit null script are rejected.
Client scripts use DM Script, not JavaScript: invalid script source can print a
script diagnostic while the compiler's final error count misleadingly says zero;
the rejected probes produced no DMB. An unquoted non-ASCII STYLE identifier is
also rejected, while quoted Unicode macro text is accepted.

Outside-package raw probe logs and record dumps are in
`D:/opendream-diagnostic/client-unknown-probe/`.
DM Script syntax is documented in the [official client script reference](https://www.byond.com/docs/ref/info.html#/client/var/script).

## Additional header flags

Native isolated callback bodies identify Click `0x4`, DblClick `0x8`,
MouseUp `0x200000`, MouseDown `0x400000`, MouseDrop `0x800000`,
MouseDrag `0x1000000`, MouseEntered/MouseExited `0x2000000`, and client
Command `0x4000` and IsByondMember `0x40000`. Atom/client ancestry matters: unrelated datum/global
procedures with identical names leave these bits unchanged. MouseEntered, MouseExited, MouseMove, and MouseWheel require client ancestry. MouseMove also
sets `0x2000000` and extension-word bit 1; MouseWheel sets extension-word bit 2.

Client perspective modes 1/3 set `0x8000000`; modes 0/2 clear it. The authored
class variable remains present as well. Client macro_mode 1 sets `0x80`;
authenticate/show_map/show_popup_menus 0 set `0x8000`/`0x100000`/`0x10000000`.
World sleep_offline 1 sets `0x20`. Explicit lazy_eye assignments clear `0x100`,
even an assignment of zero; explicit world.view assignments clear `0x200`.

Native external-library call, load_ext, and call_ext instructions set
`0x20000000`; ordinary dynamic object calls do not. Native filter construction
clears the default `0x40`. Translation derives these instruction features from
actual decoded opcode boundaries after lowering. Semantic header comparison
uses mask `0x3bf4ffef` and extension mask `0xf`, excluding ID width, debug
marker presence, and opaque bits.

The expanded portable test covers sixteen perspective baseline transitions,
fourteen callback owner cases, twenty-four boolean setting transitions, five
native instruction-feature pairs, and positive/negative semantic header
comparison. No runtime execution was used.

Earlier negative bit-0 probes included real/minimal/macro skins, map size,
world callbacks, and mob Login. The bit was subsequently identified as CPU
access below. Compiler-only raw logs are under
`D:/opendream-diagnostic/header-flag-probe/`.

Typed builtin icon/overlays/underlays references and declarations also clear
`0x40`, including atom/image ancestry, initial(), nameof(), and dead if(0)
branches. Custom datum fields and untyped colon access do not. Their native
instructions can be identical, so resolved source metadata is necessary.
`NativeGraphicsAccess` exports this aggregate and supplements the decoded
filter instruction scan. The sixteen-case `graphics_access` fixture matrix
checks both exact compiler annotation and translated header bits.

Native boolean range probes reject 2, -1, 0.5, and null for authenticate,
show_map, show_popup_menus, macro_mode, and sleep_offline: strict 0/1 checks
are intentional. Lazy_eye accepts 2, -1, and 0.5, each clearing the explicit-
assignment bit. The truncated numeric value is stored in world.eye as a byte: 2 becomes 2, -1 becomes 255, and 0.5 becomes 0. No client variable declaration is emitted; null is rejected.
Three additional native paired lazy_eye fixtures cover these legal values.

## Header bit 0: CPU access

Native CPU-access probes identify `0x1`: used/computed CPU references and
nameof/issaved/initial mentions set it, including resolved dead-branch use.
Plain discarded world.cpu or untyped W:cpu reads do not. NativeCpuAccess
exports this source distinction; translation replaces the bit from it rather
than scanning identical native field operands. Sixteen portable cases under
`fixtures/translation/cpu_access/` check source annotation and translated bits.
Custom/local fields and string-only mentions leave the bit clear; typed,
untyped-used, and safe world receivers set it. All flag bits observed in the original full-game header now have native probe
meanings. The formerly unknown world byte now has positive client Import-handler specimens, described below.

World view has a separate explicit-assignment distinction: removing an authored
view override restores `0x200`, even when both explicit/default values are 5.
Nine native baseline transitions cover omitted, explicit-default, and changed
view values, checking the bit and actual view dimensions.

Native lazy_eye range probes accept35 and reject -1.5,35.5,36,256, and very large values: the legal numeric interval is [-1,35], with truncation only after validation.

Legacy two-target call with a syntactic String literal first target uses CallLib (0x116), or CallLibArgList (0x117) for arglist. Resource, numeric, and dynamic variable first targets use CallName (0xb5), so source export classifies only the original String literal AST case as external. Parentheses preserve this classification; folded string concatenation and local/global const references remain ordinary calls. Paired fixtures assert call opcodes as well as the external-library header bit.

Native callback ownership matrix distinguishes client-only MouseEntered, MouseExited, MouseMove, and MouseWheel feature flags from Click, DblClick, MouseUp, MouseDown, MouseDrop, and MouseDrag which also apply on atoms. Atom callbacks remain valid procedures but do not set the former client negotiation flags. Eight subtype fixtures cover all four client-only callbacks on /obj/test and /client/test.

Client subtype header settings are native-legal and are folded in native class table order: descendants before ancestors, first-created sibling order, preserving the last assignment within each type. Reopening a type does not move it. Native parent_type reparenting of client subtypes and world subtypes are rejected. Client subtype scripts accept valid inline script text or resource files; an explicitly authored null script is rejected. Per-type NativeClientSettings metadata preserves these authored constants; legacy optional metadata remains supported.

Native preload_rsc also accepts constant text (including empty text). It retains a client builtin String override and sets disabled preload mode0, for URL and filename forms alike. Numeric values in [0,2] are legal: exact0 sets0x800, exact2 sets0x1000, and fractions0.5/1.5 setneither bit. Resource, list, and null forms are rejected. Control_freak accepts numeric values in [0,7], truncating fractions into world.control, and rejects null/text/out-of-range values. Eight additional portable pairs cover these legal forms plus text/numeric baseline transitions.

Perspective accepts numeric values in [0,3], including0.5/1.5/2.5; it truncates the class builtin value and derives its header bit from the same truncated integer. Boolean settings show_verb_panel/authenticate/show_popup_menus/show_map/macro_mode accept exact numeric0/1 (including float1.0), and reject fractions/null/out-of-range values. Three new native perspective pairs and legacyfloat/rejection tests cover this distinction.

The former unknown world byte is client Import-handler presence. The native world writer at0x1024cd40 writes world+0x4a after control+0x4c and before script+0x50; compiler callback classification at0x10105c64 sets world+0x4a=1 and returns reserved StringID0x20 (Import). Seven native pairs independently prove client/subtype/parent/override Import bodies set1, while Export and unrelated datum/global Import bodies leave0. This identifies the encoded presence marker, without claiming runtime invocation behavior. Translation recomputes it from actual client proc implementations, including empty authored bodies and baseline removal. Stock abstract/native stubs have Attributes4 and must be excluded even though their JSON Bytecode is an empty string; the reader/writer retain the public unknown_byte field and expose semantic accessors.

World view's value encoding is separate from its explicit-assignment flag.
Numeric radius limits are [-1,35] before truncation. Text accepts native decimal
prefix parsing, clamped negative axes, dimensions up to255, and area up to5041.
A zero first axis serializes radius floor(max(axes)/2), rather than packed axes.
The loader tests the raw word as signed16-bit against255; compact radii and
negative signed words expand with16-bit wrapping. Thirty native compile-only
pairs and four baseline transitions are specified in the new Rust regression;
the parent gate is pending. See `fixtures/translation/world_view_shapes/README.md`
for exact parser/validator/writer/loader addresses and accepted/rejected shapes.

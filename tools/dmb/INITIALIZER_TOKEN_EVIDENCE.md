# Native initializer-token identity

Static evidence is from installed BYOND516.1687 byondcore.dll. No DreamDaemon execution was used.

## Loader and Initial getter

The variable loader at10119eb0 reads kind/value/name. Its call at10119f6a to1024c940 converts a wire kind/value into the eight-byte runtime value stored at10430c9c. The converter's kind62 table entry selects1024c96d: it preserves the kind and payload, except the ordinary FFFF sentinel normalization. It does not allocate or resolve a list.

The intrinsic reference switch at10131064 uses the table10131918. FFE7 (Initial) selects101310ac. A plain field operand follows10131167 →1015c410 →1020ab40. Declaration lookup finds the VarID and declaration flags. A global declaration reads10430c9c directly. An instance declaration first searches the class initialized-value list through10213470; the matching record's tag/payload are copied at10213531/10213537. If no class override exists,1020abd0 reads the variable default record at10430c9c. The result is copied into Eval by102247b0, without evaluating an initializer expression.

Consequently a hidden Initial(field) result is the tagged expression identity62/token, rather than a ListID or constructed object. Nested Initial(Global) takes the global getter at101312f2 and returns the current global value; it does not recover the original initializer expression.

## Observable identity

Teq opcode37 dispatches to1013ea69. Its nonnumber path1013eafa calls1024ccd0, which compares the tag byte and32-bit payload exactly. Therefore equal initializer tokens compare equal and unequal tokens compare unequal. Token numbers may be reassigned only if their equality partition is preserved. The generic retain/release tables map kind62 to their return-only epilogues1022542e/10224d3d: the token owns no reference-counted object.

## Fresh compile-only probes

Portable fixture: fixtures/translation/initializer_token_identity/probe.dme and probe.native.bin. Native compile: zero errors/warnings.

Identical list(1,2) declaration defaults, explicit subtype overrides, globals, and statics share token0. list(1,3) gets1; identical new /datum/token_target() defaults/override share2. A distinct list(1,4) override gets3. Identical sound(null,1) defaults/override share4; sound(null,0) gets5. Identical six-argument matrix constructors share6; changed first argument gets7. A global custom procedure-call initializer is legal but has kind0; class custom-call and image() initializers in this matrix are native rejected.

Additional fresh folding probe: list(1+1), list(2), list(const2) share identity. Named list(a=1) and list("a"=1) share identity. Folded and literal New arguments share identity. Sound(), sound(null), sound(null,0), explicit five-argument defaults, and named arguments have distinct tokens: argument count/mode remains part of expression identity.

## Whole-game bounded audit

On deepquarry-iteration4.dmb versus fresh native:18,594 class-qualified marker default/override keys are paired. No native token group is split and no translated token group merges distinct native tokens. This proves that artifact's equality partition for those keys, not general initializer execution parity. The fallback allocator still requires a portable regression when future exports introduce new class marker records.

## Expression identity repair

The patched compiler now exports versioned structured expression keys for
declarations, globals/statics, and each authored dynamic assignment. The Rust
emitter normalizes constant leaves through its native value codec and interns
keys across those scopes. This preserves native f32 folding, resource aliases,
argument order/count/mode, and repeated assignments before a later clear.

Four expression-sharing regression tests pass in both debug-line settings: 22 class/global/static defaults,
14 folded construction defaults, and six declaration/override marker records
including two same-field assignments followed by null, plus thirteen additional
constructor-family marker records. A separate DEBUG regression requires all
22 native marker identities to remain distinct. Equality and inequality
partitions are compared against fresh native output; executable initialization
order remains independently checked by the bytecode comparisons.

The current full-game export reports 17,456 recognized class assignment keys
and 814 recognized global keys, with zero unclassified keys. These counts are
source-key coverage, not proof that every listed expression uses native kind 62.
All 19,617 native/emitted marker records pair with identical equality partitions.
The full game defines DEBUG, so expression interning must be disabled; release
sharing rules would merge thousands of native marker groups incorrectly.
Metadata.NativeInitializerInterningMode records the final macro state explicitly.

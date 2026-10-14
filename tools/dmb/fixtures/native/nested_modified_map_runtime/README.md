# Nested modified map initializer runtime control

The one-cell DMM places `/obj/parent{child=/obj/item{amount=7};scalar=11}`
with a turf and area. A local variable receives the modified child typepath and
`new child_type()` must produce an item with amount7; the ordinary scalar map
attribute is11. Type checks must both be1, and the independent body marker13.
Actual pinned BYOND516.1687 and native64b8c56d3370a264c1580e47fb62c7f235a6920e
both compiled and executed this fixture successfully. All six markers match,
including nested amount7 and leaf scalar11, with zero runtimes.
Receipt: `E:/dq-cache/dmb-nested-modified-map-runtime/06cde4a0c4f14edcab9b8730f388f7c8/receipt.json`.
Native SHA256: `25bdfe426cced51ad959be5f3be5150678ea1a6fb02fe714793639c44db339b0`.
Four fixture Python checks and six existing common-runner checks passed.
This is paired correctness evidence, not compiler throughput evidence.

`run.py` uses the same explicit compiler/template/DM/DD pins as the callable
runtime fixture, with an owned E:/dq-cache output root. Both map and resource are
explicit hash-checked assets. No new executor or cache is introduced.

`run_retained.py` uses the existing common retained contract with explicit
immutable map/resource assets. Initial, unchanged, body13ÃƒÂ¢Ã¢â‚¬Â Ã¢â‚¬â„¢17 and unrelated field
insertion revisions require exact retained/fresh DMB/RSC equality and all BYOND
runtime values. The map stays constant; no file-specific map edit is claimed.

Actual retained validation passed all four revisions with source
`853e1dddeb0a2e6cb2aa63b544df40115e2de1c6`, compiler SHA256
`55720ef6559d943413fd952cd2a1118bf71b29fd1dd996a81d5802535e5493d8`.
Each revision matched all six BYOND/retained/fresh markers, with zero runtime
errors and exact fresh/retained DMB and RSC SHA256 equality. The owned daemon
was reaped with no cleanup errors.
Receipt: `E:/dq-cache/dmb-nested-modified-map-retained/77a5547638ae4a98a50ebb753dd1b8fe/receipt.json`.
This is focused runtime correctness evidence, not full-suite or performance
acceptance.
This is focused execution evidence when run, not full-suite parity or historical
initializer root-cause proof.

## Additional map-edit scenarios (not yet executed)

The same scenario descriptor now adds `map_nested` (amount7→19) and
`map_scalar` (scalar11→23), with unchanged body marker17. `asset_edit` names an
explicit transported asset and one exact before/after text site. Only private
native/BYOND copies are atomically replaced; original fixture hashes remain
immutable. Every revision records and rechecks current map bytes in both source
roots. The earlier853 receipt proves the original four revisions only, not these
new map-edit steps. No second runtime runner or cache is introduced.

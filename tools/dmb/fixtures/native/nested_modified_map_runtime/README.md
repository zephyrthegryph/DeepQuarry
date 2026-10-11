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
immutable map/resource assets. Initial, unchanged, body13â†’17 and unrelated field
insertion revisions require exact retained/fresh DMB/RSC equality and all BYOND
runtime values. The map stays constant; no file-specific map edit is claimed. Retained revisions
remain unrun and await the newer853 executable; the paired64b8 result does not
admit retained behavior.
This is focused execution evidence when run, not full-suite parity or historical
initializer root-cause proof.

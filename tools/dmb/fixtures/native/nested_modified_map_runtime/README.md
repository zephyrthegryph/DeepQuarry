# Nested modified map initializer runtime control

The one-cell DMM places `/obj/parent{child=/obj/item{amount=7};scalar=11}`
with a turf and area. A local variable receives the modified child typepath and
`new child_type()` must produce an item with amount7; the ordinary scalar map
attribute is11. Type checks must both be1, and the independent body marker13.
Pinned BYOND compiles and runs first through the existing shared paired launcher;
map syntax and expected values await that actual reference admission. No runtime
has been run while authoring this fixture.

`run.py` uses the same explicit compiler/template/DM/DD pins as the callable
runtime fixture, with an owned E:/dq-cache output root. Both map and resource are
explicit hash-checked assets. No new executor or cache is introduced.

`run_retained.py` uses the existing common retained contract with explicit
immutable map/resource assets. Initial, unchanged, body13→17 and unrelated field
insertion revisions require exact retained/fresh DMB/RSC equality and all BYOND
runtime values. The map stays constant; no file-specific map edit is claimed.
This is focused execution evidence when run, not full-suite parity or historical
initializer root-cause proof.

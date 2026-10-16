# Object initializer burn-down

Branch: `codex/init-burndown-objects`.

The analyzer has reduced the init baseline from 4,111 to 3,844 rows,
including `code/game/objects` from 571 to 304. Exactly 267 rows were
removed and none added. Source declarations and regression fixtures are
committed; compilation, DreamChecker and focused lane-ready proof are pending.

The leaf setup, ownership, constructor and ordering changes and retained
contracts are listed in `init_objects_nonitems_1016_handoff.md` and
`init_objects_items_handoff.md`. Retained initializers need their original
pre-parent, mapload, constructor-argument or lifetime boundary; they were not
moved into wrappers to silence the lint. No new ALLOW was added.

## Additional leaf cohort (verification pending)

Three further baseline rows have source conversions prepared, not yet counted by
the analyzer: the two permanent candles light through native completion-phase
setup, and the integrated-circuit implant links its declared assembly there.
These types have no retained descendant Initialize tail to reorder. The candle
message, glow, fuel exemption and snuff/re-light behavior remain unchanged; the
assembly remains owned by its implant, with the same non-owning reverse link.

`dq_init_objects_permanent_candles` checks both real candle constructors, actual
lit appearances, unchanged fuel, snuff and re-light behavior, plus an ordinary
unlit control. `dq_init_objects_circuit_implant` checks actual child identity,
location, reverse link and destruction ownership. Both are in the already-wired
`dq_init_objects_weapons_tests.dm`. No compile, generation, baseline update or
test was run for this supplemental cohort.

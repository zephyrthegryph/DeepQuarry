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

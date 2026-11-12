# Static window data: `ui_static_data(A)`

Status: landed (refactor/ui-windows-new-style-2). Extends `final_api.html` §13 (`interface()` + `ui_data(A)` outputs).

## Form

A window's rarely changing data is the standard output `ui_static_data(datum/act/eval/A)`, beside `ui_data(A)`:

```dm
/obj/machinery/autolathe/ui_static_data(datum/act/eval/A)
	var/mob/user = A.actor
	return list("designs" = designs_for(user))
```

- `A.actor` is the viewer, `A.holder` the window host, `A.observer` a read-only ghost view: the same context `ui_data(A)` gets
  (`present_eval_context()`).
- The base `/datum/proc/ui_static_data` returns an empty list (an override extends `..()`). The engine reads it through `present_tgui_static_data(holder, user)`
  (`code/engine/present/outputs.dm`), which the window's payload uses when it carries static data (open, ready, full update).
  Code that wants another holder's static block (a lathe embedding its material container's) calls the same proc.
- It is an output: it writes nothing (a per-payload cache is a local, as the R&D console's id cache now is).

## Invalidation: read-driven, like `ui_data`

The reads generator finds the holder vars `ui_static_data()` reads and writes them as `ui_static_from(...)` rows in
`code/_generated/reads.dm` (kind `ui_static`, `tools/analyze` `derived_reads` / `gens/reads.rs`); `gens/deps.rs` counts them as window
reads, so they are tracked and published like any `ui_data` read. A publish of one of them marks `DEP_UI_STATIC` (bit 19); the refresh
engine's pass sends each open window a full update (static and dynamic data) instead of a data push (`refresh_ui_static()` ->
`presentation_refresh_static()` in `code/library/present/ui_transport.dm`, logged through `log_tgui`). A window opening or closing marks
neither bit.

The hand invalidations whose state is a tracked holder var are gone (the dirty-items flags of the circuit printer and the mining vendor,
the ban panel, the log viewer, the lathes' design and coefficient refreshes). `update_tgui_static_data()` and
`update_static_data_for_all_viewers()` stay for state that is not one var of the holder: a player's refresh button over global state (the
character directory), an async result landing outside the holder (a portrait), another entity's state (a robot's window over its module),
preferences middleware. That is the same split as `PUBLISH_CHANGE()` for a key that is not one var.

## Ban

`tgui_static_data` is in `[lint.legacy_forms.lists] banned` (`tools/ci/lint_scopes.toml`).

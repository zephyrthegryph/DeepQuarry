# Draw on change

Status: **landed** (lane `perf/draw-on-change`). Replaces the lazy-draw "interest" system of
[proposals/demand_driven_refresh.md](proposals/demand_driven_refresh.md) section 3 (that section is history now). The look builder and the naming
convention are unchanged: see [look.md](look.md).

## 1. The model

An atom is drawn when its look changes, not when someone looks at it. A look change marks the atom (`refresh_mark()`), and the mark files it where
the work will be found:

| What the atom owes | Where it waits | Drained |
|---|---|---|
| its look alone (most atoms: a wall, a pipe, a light, an item) | the **draw queue** (`code/engine/change/draw_queue.dm`): a bucket per 16 x 16 turf chunk per z-level | after the refresh queue, nearest a client's eye first, then every other bucket, under the presentation lane's budget |
| any output besides its look (values, a Rust push, a window, a mob's verbs, a plain datum) | the **refresh queue** (`refresh.dm`), as before | first, in order, under the same budget |

Nothing is parked, nothing waits for a viewer, and nothing is covered. Every dirty atom is drawn, in an order that favours what a player can see.
`refresh_run()` is the one place that runs an atom's pending outputs; both drains call it.

Rules that hold:

- A change files the atom once (`GLOB.draw_filed`, slot to chunk key): a second change before the drain adds nothing, and the one draw shows the latest state.
- A filed atom that gains an output besides its look is queued in the refresh queue as well, which runs everything it owes; its bucket entry is then a
  stale one the drain counts (`draw_stale`) and skips.
- A deleted atom leaves its bucket (`engine_forget()` calls `draw_unfile()`), so no bucket pins one.
- The drain does nothing while no bucket is filled (one `length()` read). A walking client changes the order of the work that exists and creates none:
  the order is computed from the turf each client looks from (`GLOB.gaze_at`) when a drain pass starts.
- The order is rings of chunks around the eyes (`draw_order()`): the chunks that hold an eye, then the ring round them, outward; the nearest of several
  eyes decides; a level with no client and the atoms that stand nowhere come last. Within a bucket the order is the order of the changes.
- A drain pass stops when the lane is out of budget; the rest stays filed. Under a sustained overload the far buckets wait, and drain when the load drops.

## 2. The appearance cache

A look is finished work. `code/engine/present/look_cache.dm` keys a finished look by the inputs its draw reads: the type, the values of the vars the
generated plan (`analyze gen plans`) names for its draw, and the base vars no look has set (`icon`, `icon_state`, `color`, `alpha`, `dir`, `plane`,
`layer`, `invisibility`, the pixel offset). A draw computes the key, looks it up and applies the held look; on a hit `draw()`, the builder and
`change_key()` do not run.

A type is cacheable only when that is provable from declarations: the plan names vars of the holder itself (no hop to a turf, area or container), every one
of them holds text, a number, a path, a file or null (a datum, a list or a runtime icon is state the key cannot see), the holder is no mob or area and has
no capability engine state (a watched atom or a flash), and the finished look is plain data (text overlays; no effect, flick, underlay, vis_contents or
watched atom). Anything else draws as before and is counted as a bypass. Test builds verify every hit against a fresh draw (`look_cache_verify()`); a
mismatch is a draw that reads something its plan does not name, and fails the test that drew it. The strict staleness checker keeps checking served draws
against a fresh draw as well.

The cache is bounded (40000 looks) and in memory: it is rebuilt by use each boot.

## 3. Default looks are not drawn

An atom whose look equals its type's default is what the map loader or `new` already gave it: drawing it does nothing. Three rules, none of which reads a file:

1. A type the generated declarations say derives nothing (no `draw()`, verbs, capabilities or values) is never queued (`caps_init()`).
2. The first fresh instance of any other type is drawn once per boot (the sample). If its draw is empty (`type_look_default_empty()`), the type is
   stamped (`GLOB.type_look_stamp`) and its fresh instances owe no first draw. For a type the cache can key, the stamp records the sample's key, and an
   instance is stamped only while its own key is the sample's (`type_look_stamped()`): a fresh instance a map var edit changed is drawn.
3. The look-verdict file (`data/look_verdicts.json` and its journal) is gone. Nothing is written for the next boot; the boot samples again (about a
   hundred and fifty types, once each).

The default skip count (`default looks skipped`) is in the look log line.

## 4. Boot

The map loader creates every atom before any drain runs.

- A fresh atom of a type with no verdict, while the boot map load runs, is **held** (`DF_BOOT_HELD`, `boot_created_hold()`): in no queue, in its type's
  bucket. The first fresh instance of the type is queued as its sample. A mark of a held atom does nothing (a write during setup never wakes one atom at
  a time); the settle decides the whole bucket from the sample's verdict: an empty default look is dropped without a draw, the rest are marked once.
- Before the settle everything queues in the refresh queue (it samples by type). `refresh_settle_created()` then files each remaining look-only atom in
  the draw queue and leaves the rest where they are.
- A server leaves the remaining boot draws to the presentation lane: they are drawn over the ticks that follow, nearest a client first and then all the
  rest, and no player enters the map until the refresh queue (everything with an output besides its look) is empty (`boot_draws_pending()`); the filed look draws drain nearest a client first and are not waited for. A test world draws them all before init completes
  (`refresh_boot_drain()`).
- The writes an atom's own setup makes (`DF_INIT_OPEN`, `DF_CONSTRUCTING`) are its construction: one first draw, with what it was written.

## 5. The gaze registry

`code/engine/change/gaze.dm` keeps who is looking where, set by events (never polled): a client's eye moving or changing, its view size, a container
that carries it, open space around it. It holds a count per chunk (`gaze_covers(turf)`: is a viewer near here, used by footsteps and the lighting
queues) and the turf each client looks from (`GLOB.gaze_at`, which orders the draw queue). It draws nothing and scans nothing.

## 6. Tracing

The look log line (`REFRESH LOOKS`, at boot and every five minutes) carries: look changes, draws and drain ms per second since the last line; the draw
queue (filed, buckets, refresh queue depth, dirtied, filed, drawn and how many of them within a chunk of an eye, stale entries skipped, drain passes,
their ms and the longest, passes the budget cut); the default looks skipped; the appearance cache (hits, misses, hit rate, bypassed, held, looks
built); and the draw cost (mean and p95 ms over all draws, and by type for the five types that cost the most).

## 7. Tests

`code/tests/unit_tests/dq_draw_on_change.dm` and `dq_look_cache.dm`: a change is filed and drawn by the drain and is current after it; nothing is stale
after a budgeted drain over many chunks; a walking client causes no draw work; a change near the eye is drawn before a far change; the order is rings
around the eyes; a deleted atom leaves its bucket; an atom with another output runs in the refresh queue and is not drawn twice; the boot hold marks
nothing and draws once; boot leaves nothing undrawn; a cache hit builds no look; the cache serves what a fresh draw makes. `dq_look_cache_draw_cost`
logs the draw cost by type with the cache off and on.

## 8. What went

`interest.dm` (the observer holds and the owed index, the prefetch ring and edge scans, the cover over a view while it is drawn, the walker budgets,
perceivability), `DEP_PARKED`, the lazy verdict (`type_look_lazy`, `refresh_park_backlog()`), the verdict file, `look_verdict_fits()`, the sampled audit
of seen chunks, and their tests.

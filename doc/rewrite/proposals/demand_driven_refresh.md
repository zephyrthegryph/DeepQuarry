# Demand-driven refresh: one mechanism for every derived output

Status: phases 1 to 3 landed (3: `code/engine/change/interest.dm`, section 3a below). Lane `engine/demand-refresh`. Supersedes `E:/projects/dq-lazy-draw.md`: the lazy first draw
(`DEP_PARKED`, `refresh_park_backlog()`, `refresh_drain_near()`) is a policy inside this mechanism, to be absorbed by it, not extended.

## 1. The problem, in numbers

One full-map boot (120,830 first refreshes queued by `caps_init()` / `state_changed()`):

| What | Count | Why it is there |
|---|---|---|
| dropped as an empty look (`type_look_stamp`) | 14,570 | works, and stays |
| parked (`DEP_PARKED`) | 8,029 | works, and is absorbed below |
| still queued | 97,317 | |
| ... not atoms: rx_state 15,193, vending products 9,224, reagents 3,020, others | 45,118 | a datum type no refresh has probed yet is `TYPE_DERIVES_PENDING`; `refresh_wanted()` says yes to PENDING; boot runs no drain until `refresh_settle_created()`, so every instance written before the first drain is queued, for a type that derives nothing |
| ... atoms "marked during init" (pipes ~7k, cables ~5.7k, lattice ~2.7k, windows, lights) | 51,006 | `refresh_mark()` clears `DEP_CREATED` on any real mark; `refresh_park_backlog()` parks only entries that still carry it; the mark was look-only, the atom is unobserved, and it is drawn eagerly anyway |
| ... excluded by type rules | ~1,200 | correct |

Beyond boot, the same shape repeats at run time and is just less visible: an explosion marks 10k atoms and all 10k redraw this frame
though few are on any screen; `refresh_drain_near()` polls `range(view+2)` around every client turf every 0.5 s (plus up to 8 levels of
open space), and `refresh_has_parked` is set TRUE once and never reset, so the poll runs all round after anything ever parked.

All of it is one mistake: **work is scheduled by what the holder is, not by who needs the result.** The fix is one rule stated once.

## 2. The model: derived outputs are nodes, consumers decide when they run

Every derived output is a node. Its inputs are the tracked keys it read (read-driven tracking already records them: `plan.dm`,
`derived.dm`, `auto_tracked`). A write only marks the node's dependents dirty with a per-kind bit: cheap, O(readers). That is exactly
what `state_changed()` + `refresh_queued` (DEP_* bits) already is. What is missing is the second half: **when a dirty node is run.**

| Kind | Nodes | DEP bits | Runs when | With no consumer |
|---|---|---|---|---|
| presentation | `draw()` and `hidden_verbs()` (look), `tgui_data()` (UI) | `DEP_DRAW`, `DEP_UI` | something observes it: a client's interest covers the atom (look), an open window (UI) | stays dirty, zero cost |
| value | `derive()` values, STAT effective values, caches | `DEP_VALUES` (and the stat layer's own marks) | on read, memoized until invalidated; eager only if an effect subscriber exists (on_change, notice, a held requirement) | stays dirty, computed by the first read |
| effect | `push_to_rust()`, `should_run()`, `on_state_changed()`, notices | `DEP_PUSH`, `DEP_RUN`, `DEP_LEGACY` | eager, coalesced once per frame, as today | n/a: an effect is its own consumer |

The decision is made from **declarations, never from the holder's type name**:

- whether an output exists at all for an entity: its type derives it (`derived_table_of`, an override of `draw`, `push_to_rust`, ...)
  or the instance has it (open windows, periodic cadence, granted verbs). Call this the entity's **live outputs**.
- who consumes it: an effect subscriber (the reader plan: `plan_reader_bits`, `rx_readers`), a viewer (interest set), an open window.

### 2.1 Live outputs

`refresh_live_outputs(D)` returns the DEP bits that would do anything for D now:

- atom: `DEP_DRAW` if its type draws or has capabilities (type flags LOOK/CAPS/PENDING, or a look key), `DEP_VALUES` if it has a derived table,
  `DEP_PUSH | DEP_LEGACY` if it overrides the side effects (`TYPE_DERIVES_SIDE`), `DEP_RUN` if periodic, `DEP_UI` if a window is open.
- datum that is not an atom: no look. `DEP_VALUES` if it has a derived table, `DEP_PUSH | DEP_LEGACY` if its type overrides `push_to_rust`
  or `on_state_changed`, `DEP_RUN`/`DEP_UI` per instance. Everything else is dead: **a datum with no live output never enters the queue.**

`refresh_wanted()` is then simply `live != 0`, and a pending mask is only ever judged as `pending & live`.

### 2.2 Pending kinds

The queue entry already is a bitmask of kinds. Phase 2 adds the rule that was missing: an entry is **deferrable** when its live pending
bits contain only presentation kinds (`pending & live` is within `DEP_DRAW`). It is then parked (out of the queue, owing the draw), whether
or not the mark that queued it was the creation mark. Parked is not a separate state machine: it is "dirty presentation node with no
observer yet". Its eventual run draws from the *current* state, so a mark made during init changes nothing about what is drawn, only when.

Any pending bit that is a value with a subscriber, or an effect, keeps the entry eager. A value bit with no subscriber is phase 4.

### 2.3 Where the datum verdict comes from

Today the verdict for a datum type is learned by running a refresh on one instance (the probe). Instances written before that wait in the
queue. The static facts are all declarations, so the generator provides them: `analyze gen plans` emits `generated_side_overrides`, the
types that define `push_to_rust()` or `on_state_changed()` with a body (their subtypes inherit). `datum_derive_flags()` combines it with
`derived_table_of()` at first sight, with no probe and no `PENDING`. This kills the 45k datum entries at the cause.

(Atoms keep the probe for their look/verb facts for now: a draw may read what a subtype's `Initialize()` sets, so the draw is not decided
statically. The atom's look is presentation, so being unprobed costs a queue entry, not correctness.)

## 3. Interest replaces the near-client scan (phase 3)

Presentation work is scheduled by observers, so the observer set must be a first-class, event-driven structure instead of a poll.

- **Chunks.** Dirty presentation nodes are bucketed per 16x16 chunk per z (`GLOB.refresh_dirty_chunks`: chunk key -> list of atoms).
  A mark of an unobserved presentation node adds the atom to its chunk's bucket; a mark of an observed one queues it as today.
- **Interest set per client.** The chunks the client's *eye* covers: its eye atom's turf (`client.eye`, which also covers camera consoles, AI
  eye, holopad projections and mech/vehicle eyes), the view radius (`world.view` / `client.view`, zoom, meson/xray changes), then down
  through open space (`seen_through()` per tile, as `refresh_drain_near()` follows today) and the levels above where a viewer looks up.
  It is recomputed **only on an event**: the eye crossed a chunk boundary, the view changed, the z changed. Not polled.
- **Entering interest** drains the chunk's bucket nearest-first under the lane budget; a chunk already in interest at the time of a mark is
  not bucketed, the atom is queued directly. So an atom inside interest is never stale after the frame it entered it.
- **Prefetch.** While the lane has idle budget, the chunks adjacent to each client's interest are drained, so first sight is already drawn.
- **Appearances shown away from the viewer's turf** are observers too: `vis_contents` viewers (camera screens, holograms, mirrors, monitor
  displays), `look.watch_look()` consumers, and a screen object showing another atom. A node whose appearance is read by a drawn node is
  observed through that node (the existing hop/watch graph forces the neighbour first). Phase 3 audits and covers these before the poll goes.
- `refresh_has_parked` disappears: the structure is the bucket count, which is exact.
- A **mass change** (an explosion marking 10k atoms) puts them in buckets; only those in interest draw now.

### 3a. What landed (phase 3)

- **Grid of hold counts**, not per-chunk datums: `GLOB.interest_grid[z][cx+1][cy+1]` counts the observers holding a 16x16 chunk. An observer is a key (a client's
  `ref_token()`, a vis_contents holder's) with a list of chunk keys; `interest_hold_set()` diffs it against what it held.
- **Visible set and ring.** A client's hold is the chunks its view window (half + 2 turfs round the eye and round its mob) covers, the chunk of every turf the
  window shows through open space (`seen_through()`, up to 8 layers), and a ring of one chunk round the window. Entering the ring queues the chunk's owed
  draws in the presentation queue (FIFO, under the lane budget). A chunk that becomes *visible* to an observer has everything it owes drawn at once, outside the
  budget (`interest_scan(now = TRUE)`): the lane being behind, a teleport or a zoom never shows an undrawn atom. A parked atom that moves into a held chunk is
  settled by `Moved()`.
- **Events, no polling.** `interest_eye_update()` runs from mob `Moved()`, `client.set_eye()`, login/logout, `set_viewsize()`, a moving container that carries the
  eye or the mob (`interest_anchor_moved()`, anchors keyed by handle), and `z_transparency` changes. It compares the chunk rectangle of the view window with the one
  held and returns when equal. The vis_* verbs (`vis_add`, `vis_set`, `vis_clear`, ...) register a non-turf holder that shows turfs (camera screens, picture in
  picture, portals) as an observer of them while it does; `on_destroy` releases it. A camera console's screen keeps its turfs held until the next camera pick:
  conservative, never undrawn.
- **Deferral.** `refresh_mark()` parks (`DEP_PARKED`) an idle atom of a lazy type standing on a turf nobody holds, instead of queuing it; further marks of a parked
  atom are absorbed. Items carried, atoms in containers and mobs always queue. Test builds default `interest_defer_marks` off (the suite marks atoms nobody watches
  and reads their looks); the deferral tests turn it on.
- **Atoms still being set up are not drawn from a hold.** `init_open` (slot -> open init frames) is open while an atom's `setup()` hooks run and while its map-load
  `after_init()` entries wait and run; it holds no atom and `slot_free()` drops a deleted atom's entry. `interest_ready()` is per atom: a map load running elsewhere
  holds back only the atoms it is still creating. **Known gap:** an outer atom partway through its own `Initialize()` while a child's init runs is not marked
  (only the innermost initializing atom is skipped).
- **Counters** (REFRESH LOOKS log line): marks deferred, absorbed while deferred, chunks scanned/left, owed draws run at once, parked draws queued by a client.
- Removed: `refresh_drain_near()`, `refresh_has_parked`, `refresh_near_next`, `refresh_draw_seen()`. Not done: nearest-first order inside a chunk's queue, idle-budget
  prefetch beyond the one-chunk ring.

## 4. One budgeted scheduler (phase 3)

The presentation lane drains in this order, each under the shared budget: (1) effects (pushes, `should_run`, side effects), (2) visible
presentation nearest-first, (3) values with eager subscribers, (4) idle prefetch. Nothing in a later class starves an earlier one; nothing
waits forever because a bucket is always drained when its chunk enters interest, and a debug sweep reports a dirty node that stayed
unobserved past its deadline while a client was within range (a falsifier, not a repair).

## 5. Values and stats on read (phase 4, measure first)

Stat recompute is inline today and correct. Counters `stat_read_computes` and `stat_evals` exist; first read how many recomputes are never read
before the next invalidation. Switch a family to compute-on-read only if that count shows a win; correctness is the same invariant as for
`derived()` values: a read always sees a current value.

## 6. Invariants (each has a test)

1. **A read is never stale.** A derived value read after any write sees the written state; the staleness checker keeps passing.
2. **A viewer never sees an undrawn atom.** An atom inside a client's interest is drawn by the end of the frame after it entered interest or
   was marked while inside.
3. **Effects and notices are unchanged.** Pushes, `should_run`, `on_state_changed`, notices and on_change fire exactly as before for every mask
   that contains an effect bit; deferral only ever touches presentation bits.
4. **Nothing waits forever.** Every deferred kind has a counter (deferred, drawn-on-demand, never-needed) and a test that the deferred node
   runs when its consumer appears.
5. **A node with no live output costs nothing.** A datum with no live output is never queued; a test per kind of dead output.

## 7. Counters (deterministic; read in focused tests and the one `--boot` log, not benches)

Queue size by kind at boot end (`refresh queue by kind`: look-only, values, effects, UI, other), `eager / deferred / never-needed`,
`datum entries refused (no live output)`, `parked drawn on demand`, and in phase 4 `first-read computes`.

## 8. Phases (each lands alone)

1. This document.
2. Boot-queue causes: the datum verdict from declarations (generator + `datum_derive_flags()`), `refresh_live_outputs()`, park by pending kind
   so look-only init marks stay lazy, the by-kind boot census.
3. Chunk interest replacing `refresh_drain_near()` and `refresh_has_parked`; lazy redraw of later off-screen changes; unit test that a
   mass mark off-screen defers its redraws and an on-screen one does not.
4. Stats and derived values on compute-on-read, only where measured to win.

No benchmarks until the end of the rewrite (user, 2026-11-04): proof is behavioural tests and the counters above.

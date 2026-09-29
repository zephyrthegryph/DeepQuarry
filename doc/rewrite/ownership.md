# Ownership: own, shared, proto, relations

Status: **authoritative**. This replaced the 20 `REFKIND_*` kinds and `DECLARE_REF()`
(`lifecycle.md` §4, `object_model.md` §4–5). There is no compatibility layer: the old kinds,
their macros, `WEAK_LIST_*`, `OM_STATIC_TYPE`, `link_set()`, `DuplicateObject()` and the lints that
enforced them are gone.

Every object-typed var, and every list that holds objects, is exactly one of four things:

| Concept | The var holds | Cleared by | Declared |
|---|---|---|---|
| **Own** | the one owner's child(ren) | the owner's teardown, by policy | implicit (`own_*` writes); `OWN(...)` for other policies |
| **Shared** | an immortal registered singleton or DEF | nobody: it never dies | implicit for registry-typed vars; `SHARED(...)` for untyped ones |
| **Proto** | a shared prototype, or an owner-stamped private copy of it | teardown deletes private copies only | `PROTO(...)` |
| **Relation** | a non-owning reference to an entity | the framework, when either end dies | implicit (`rel_*` writes); `REL_PAIR(...)` etc. for two-sided, keyed or symmetric shapes |

Locals inside a running proc are the only unowned references.

Code: `code/__defines/ownership.dm` (declarations), `code/datums/ownership/` (own.dm, views.dm,
proto.dm, shared.dm, registry_types.dm, clone.dm, audit.dm, table.dm), the rich-relation engine in
`code/datums/om/relation.dm`, handles and callables in `code/datums/om/timer.dm`. Static half:
`tools/ci/ownership_lint.py`.

## 1. Own

### 1.1 Invariants (checked in every build)

- **O1 One owner.** An owned entity records its owner on itself: `own_holder_ref` (the owner's weak key,
  `own_key()`, so owner and child never form a reference cycle) and `own_slot` (the var). Read with
  `owner_of(D)` / `owner_slot_of(D)`; both re-check that the owner still names D. Movables in
  contents are owned by their ledger slot (`containment.md`); an `OWN(..., OWN_CONTAINED)` var
  names one of them.
- **O2 Writes only through accessors.** `ownership_lint.py` (`raw_write`) rejects assignment, `+=`,
  `-=`, `|=`, `[k] =`, `Cut/Add/Remove/Insert` and the `QDEL_*` / `LAZY*` list macros on an owned
  or relation var anywhere but the accessors.
- **O3 No double ownership.** Adopting a value another holder owns is refused and reported
  (`OWN: ... already owned by ...`). Moves are explicit: `own_transfer` / `own_move`, or a
  one-call transfer (§1.3a), which takes a movable out of the holder that has it.
- **O4 No orphans.** `own_set` disposes of the value it replaces by policy; `own_take` hands the
  value to the caller, who adopts or destroys it. The orphan audit (§1.5) reports anything that
  slipped out (a raw drop, an owner that died without disposing of it).
- **O5 Teardown.** Phase 2: a dying owned entity leaves its owner's var. Phase 3: `OWN_SPILL`
  movables drop out. Phase 4: every owned var is disposed of by policy, then relation views clear
  on both ends. The phases are one declared sequence, `GLOB.destroy_step_sequence`
  (`DESTROY_STEP_*`, `code/datums/lifecycle/transaction.dm`); each step sets the datum's
  `destroy_phase`, and the contents release check is its own step right after the contents steps.
- **O5a One teardown guard.** Every accessor that gives an entity something new (`own_set`,
  `own_add`, `own_put`, `own_transfer`, `own_move`, `rel_set`, `rel_add`, `om_link`, `proto_set`,
  `proto_private`, `shared_set`, `om_after` and `OWN_TIMER` slots, `om_hook`, `om_task`, and the
  ledger's contents adoption) asks `own_guard()` (`code/datums/ownership/guard.dm`) and nothing
  else: when the holder or the target is at or past `LIFECYCLE_REFUSE_PHASE` (or marked for
  deletion) the write is refused. Inside a destroy transaction the refusal is silent (a teardown
  cascade: a dying holder's `on_destroy`, a spilled item's `Moved()`, a light re-reading its
  holder); outside one it is a stack trace (`OWN: refused ...`). Releases are never refused. Call
  sites carry no `QDELETED()` guards of their own for this. Contents adoption refuses a dying
  holder only from its links phase, since its own contents step materializes latent entries
  into its slots. `ownership_teardown_guard` tries every accessor on a dying holder and target.
- **O6 Phase 8.** An owned var that holds a value again after phase 4 was re-set during teardown:
  phase 8 deletes the value and reports it. Nothing is nulled silently.

### 1.2 Declaring

Most owned vars need no declaration: the first `own_set()` / `own_add()` / `own_put()` on a var
records it in its type's table as an implicit `OWN(..., OWN_DELETE)`. A var that is never written
through an accessor holds nothing owned. Declare only the exceptions:

```dm
OWN(/obj/machinery/sleeper, beaker, OWN_SPILL)          // drops to the floor with the holder
OWN(/obj/item/device/radio, keyslot, OWN_CONTAINED)     // in contents: the ledger slot decides
OWN_POLICY(/obj/item/modular_computer, hard_drive, /obj/item/modular_computer/proc/part_policy)
OWN_IF(/obj/mecha, cell, OWN_SPILL, salvageable, OWN_DELETE)
```

- The var is written bare; `nameof(PATH::VAR)` makes the compiler check it.
- **Shape comes from the value**: one value, a list of members, or an assoc list of values.
- **Policies.** `OWN_DELETE` destroys. `OWN_SPILL` moves a movable still inside the holder to its
  drop location (anything else is destroyed). `OWN_CONTAINED` leaves a movable in the holder's
  contents to the ledger slot policy; `own_set` moves the value into the holder's contents itself
  (§1.3a), wherever it was.
- **Conditional policy**: `OWN_POLICY` names a holder proc returning the policy at teardown;
  `OWN_IF` picks between two by a flag var.
- **Gas mixtures and other arena resources** are owned by the holder that makes them (deleting a
  mixture frees its arena slot); a pipe network's shared mixture is the network's, and components
  hold it as a relation or `PROTO`, never as a second owner (lint `matrix`).

### 1.3 Accessors (`code/datums/ownership/own.dm`)

| Proc | Meaning |
|---|---|
| `own_set(holder, "var", value, user =, into =, slot =, force =, log =)` | adopt `value`, transferring a movable in from wherever it is (§1.3a); the previous value is disposed of by policy. Returns `value` (null when refused). |
| `own_take(holder, "var")` | detach and return the value, now unowned |
| `own_add` / `own_remove(holder, "var", value)` | list shape; `own_remove` disposes |
| `own_put(holder, "var", key, value)` | assoc values; disposes of the value it replaces |
| `own_take_member(holder, "var", value_or_key)` / `own_take_all(holder, "var")` | detach members |
| `own_transfer(from, "var", to, "var", member, key)` | move one value between owners |
| `own_move(value, to, "var", key)` | move a value from whatever owns it now (or adopt it) |
| `own_clear(holder, "var", policy)` | dispose of everything the var owns, now (`OWN_DELETE` for the old `QDEL_NULL`/`QDEL_LIST`) |
| `own_values(holder, "var")` | the owned values as a list |
| `/datum/proc/on_owned_release(var, child)` | hook: a child is leaving (disposed, taken or moved), still intact |

### 1.3a One-call transfers (`code/datums/ownership/transfer.dm`)

`own_set`, `own_add` and `own_put` on an atom holder, given a movable that is somewhere else, are
the whole transfer:

```dm
own_set(src, nameof(src.beaker), W, user = user)
```

replaces `user.drop_item(); W.forceMove(src); own_set(src, nameof(src.beaker), W)`. In one call:

1. **Checks** (requirements; a refusal changes nothing, returns null and, with `user`, tells the user
   why through `refuse()`): the item can leave its current place, asked through
   `place.release_refusal(thing, user)` (a mob: NODROP and `mob_can_unequip()`; any ledger holder,
   storage included: its slot's `removal_refusal()` and the pre-remove event), and it can enter the
   holder (`dq_ledger_refusal()` on the holder's slot when it has slots: acceptance, capacity, a
   full storage).
2. **Release**: the current place lets it go through `place.release_to(thing, holder, slot, user)`.
   A mob goes through `remove_from_mob()` (the slot clears, the HUD drops it, the slot redraws,
   `dropped()` runs); a storage item through `storage_exit()` (HUD, `on_exit_storage()`); anything
   else is a ledger commit into the holder's `slot` (null: its default slot). Nothing sleeps between
   the checks and the commit.
3. **Adoption**: another holder's owned var naming it lets it go (its `on_owned_release()` runs), and
   the holder adopts it.
4. **With `user`** the transfer is a dispatched call: `changed(holder)` and
   `dispatch_record(user, holder, "insert", log)` (the fingerprint, and the `log =` line).

When it moves the value: never with `into = FALSE` (`own_transfer` / `own_move` re-own in place);
never when the value is already in the holder or anywhere inside it; always with `into = TRUE`, a
`user`, or an `OWN_CONTAINED` var (off a turf too); otherwise only when the value is inside
something else (a mob, a storage, a machine), so an owned effect or item left on a turf on purpose
(a beam, a field, a pAI cable) stays where it is. `slot =` picks the holder's ledger slot; `force =
TRUE` skips the checks (a worn item swallowing the one under it). The old sequences are flagged by
`tools/ci/sys_rules/dx_manual_transfer.py` (empty baseline).

The accessors are generic procs keyed by the var name rather than generated `set_x()` procs: a
generated setter per var collided with the domain setters many types already have (`set_species`,
`set_cell`, ...), and the lint enforces the single write path either way.

`DECLARE_DEFAULT_CHILD(PATH, var, default)` adopts through `own_set`/`own_add`; a var declared as
another kind is refused at boot. A child type naming its maker in a relation view returns that
var from `default_child_backref()`, and the declaration wires it.

### 1.4 Clone

`entity_clone(D, new_owner, slot, loc)` serialises `D` with the declared codecs (§6) and
re-materialises it: owned children become new owned children, shared and proto references are
copied by id, relation views inside the subtree re-link to the clones and views leaving it are
dropped. A mob stays real (the serializer refuses mobs) and clones as a fresh instance of its type.
`DuplicateObject()` is deleted; the holodeck's `copy_contents_to()` uses `entity_clone`.

### 1.5 Orphan audit (`audit.dm`)

`own_audit()` reports and fixes two things:

- **orphan**: an entity stamped as owned whose owner no longer names it, or whose owner is gone;
- **dropped with a rec**: an unowned, unrooted entity whose `refcount()` is fully accounted for by
  its own OM record (the `rec.owner` cycle kept it alive with live timers or hooks). The audit tears
  the record down.

The audit walks every live datum (no index: an index cost a weak key per entity at boot). Test
builds audit every 5 minutes and at the end of the run (a finding fails the run). Servers audit on
demand (admin verb "Ownership Audit").

### 1.6 Owned timers (`code/datums/om/timer.dm`)

A timer an entity keeps by name is owned, like a child. It is declared in the same ownership table:
`OWN_TIMER(/type/path, name)` (a keyed family `"name:key"` is declared once by `name`). The API:

- `om_after_slot(E, "name", delay, proc_ref, args...)` schedules into the slot, replacing whatever
  was pending there (at most one timer per entity and name);
- `om_timer_slot_pending(E, "name")` / `om_timer_slot_left(E, "name")` read it. Pending is derived
  from the entity's live timers, never a stored flag, so firing and cancelling empty it by
  construction;
- `om_cancel_timer_slot(E, "name")` cancels it;
- `own_teardown()` releases every pending slot with the entity's other owned things
  (`om_release_timer_slots()`), and phase 0 of the destroy transaction already refuses new timers.

Test builds refuse a slot name missing from the table (a typo would otherwise be a silent second
slot). Expiry hooks (`EXPIRY_ON_LAPSE`) arm their lapse timer in the keyed `expiry_lapse` slot.
A timer id is never stored in a var or list; check_grep's "stored timer handles" rule enforces it.

## 2. Shared

- `REGISTRY_TYPE(path, getter)` declares that `path` and its subtypes are registry types; the getter
  returns the registered instance D stands for, so `is_registered(D)` is `getter(D) == D`. It
  replaced the fiat `OM_STATIC_TYPE` list; the declarations are in `registry_types.dm`.
- A per-holder copy of a registry type is **not** registered: it is owned or `PROTO`.
- A var typed as a registry type is implicitly shared. `SHARED(PATH, var)` declares an untyped one;
  `shared_set()` asserts the value is registered.
- A registered instance refuses an unforced `qdel()` (core `lifecycle_keep()`), is never tracked by
  relation views, and is skipped by the leak check only when proven registered.
- **Kind × type matrix** (lint `matrix` and `kinds`, and `own_validate_table()` when a type's table
  is built; `own_validate_boot()` builds the table of every mapped type at boot): one kind per var
  across the hierarchy; no `OWN`/`REL` of a registry type; no `SHARED` of a non-registry type;
  `SPILL`/`CONTAINED` only on movable var types; gas mixtures never written as relations.
- **DEF freeze** (test builds): `def_freeze_snapshot()` digests every enumerable registry instance at
  the start of the run and `def_freeze_verify()` reports any that changed by its end.

## 3. Proto (copy-on-write)

`PROTO(PATH, var)`: the var holds a registered prototype or a private copy stamped with the holder.

| Proc | Meaning |
|---|---|
| `proto_private(holder, "var")` | a private copy the holder may mutate, made (`D.proto_copy()`) and owned on first call |
| `proto_set(holder, "var", value)` | point at a prototype or adopt an unowned private value; deletes the private copy it replaces |
| `proto_replace(holder, "var", value)` | as `proto_set`, but hands the replaced private copy back detached, for a caller still reading it |
| `proto_is_private(holder, "var")` | TRUE when the holder owns the value |

Teardown deletes private copies only. The serializer saves a prototype by registry id and a private
copy as an owned blob. Users: species (the mob's `species`; `produceCopy()` makes the private copy),
seeds, contagions (cleanables, infected rooms), network gas, robot and AI sprite datums.

## 4. Relations

### 4.1 Light edges: relation views (`views.dm`)

A view var holds a direct reference (reads are free). The target keeps a lazy weak reverse index,
`om_refs_in` (an alist: source key → var names). When either end dies the framework clears its side.

Weak keys (`own_key()` / `own_locate()` in `own.dm`) name entities in every weak index: owner
stamps, reverse indexes, keyed links, OM handle slots. A key is the ref spelled in decimal behind a
fast-varying prefix, cached on the datum; a turf's is its position. Never keep raw ref text alive
in bulk: BYOND 516's string table degrades on many strings sharing a prefix, and one retained ref
per entity made boot quadratic. For the same reason big indexes are `alist`s (a plain list inserts
a new key in linear time), `rel_names()` answers "does this list view name X" from the index, and
an index prunes stale entries at each doubling rather than every 48 additions.

```dm
REL_PAIR(/obj/machinery/sleeper, console, sleeper)             // two-sided, single on this end
REL_PAIR(/obj/machinery/sleeper_console, sleeper, console)
REL_PAIR(/obj/effect/directional_shield, projector, active_shields)
REL_PAIR_LIST(/obj/item/shield_projector, active_shields, projector)   // the "many" side
REL_SET(/obj/machinery/atmospherics, nodes)                    // symmetric membership
REL_KEYED(/obj/machinery/button/remote/blast_door, door, id, /obj/machinery/door/blast)
KEYED_TARGET(/obj/machinery/door/blast, id_tag)
```

- **Writes**: `rel_set`, `rel_clear`, `rel_add`, `rel_remove`. An undeclared var written with them is
  an implicit one-sided `REL` (single for `rel_set`, list for `rel_add`). A pair write sets both
  sides; a single end is exclusive, so linking a new partner unlinks the old one on both sides. A
  link to an entity being destroyed is refused.
- **Reads**: the var itself; `rel_targets(src, "var")`, `rel_sources(target)`.
- **Keyed auto-linking** replaces init-time scans and id matching: when a `KEYED_TARGET` or a
  `REL_KEYED` source materializes, sources and targets with matching keys link.
- **Turfs** can be targets (indexed per z-level, since `ChangeTurf` resets a turf's vars).
  `om_drop_z(z)` clears every view naming a turf on a released level and bumps the level's
  generation. Areas are plain vars.

### 4.2 Rich edges: `/datum/om/relation`

Edges with state, hooks or conditions (grab, pull, buckle, orbit, grants, tgui sessions) are DEF
types used with `om_link` / `om_unlink` (`code/datums/om/relation.dm`):

| Field / proc | Meaning |
|---|---|
| `shape` | `REL_ONE_TO_ONE`, `REL_ONE_TO_MANY`, `REL_MANY_TO_MANY`, `REL_SYMMETRIC` |
| `conflict` | a new link replaces (`OM_REL_REPLACE`, exclusivity) or is refused |
| `holds_while` | a check spec; the edge breaks (`RELATION_BROKEN`) the moment it fails |
| `source_view` / `target_view` | framework-maintained 1:1 view vars on each end |
| `undo_list` | list-undo: the source joins a list on the target while linked |
| `derived_view` | a source proc re-deriving a view from `linked()` after each change |
| `on_link`, `on_unlink` (`edge.unlink_reason`), `on_end_changed` | hooks |
| `on_member_leave` + `om_leave(member, rel)` | a member leaving through its own domain proc |
| `clone_follows` | re-link to the clone in `entity_clone` |

Reads: `linked(E, rel)`, `linked_to(E, rel)`, `link_of(E, rel)`, `link_source_of(E, rel)`, and the
typed accessors in `ref_relations.dm`.

### 4.3 Handles and deferred calls

`om_handle()` / `om_resolve()` are core-internal: deferred arguments, latent identity, the
serializer. A content var naming an entity is a relation view (lint `handle`).

`CALLBACK` and `/datum/callback` are gone from content (lint `callback`). A stored call is
`om_callable(target_or_null, PROC_REF(x), args...)`, a plain list holding every datum argument as a
handle; `om_run(spec, extra...)` / `om_run_async` run it, and drop it when the target or an
argument is gone. Timers are `om_after()`. `om_capture_args()` captures deeply (nested lists and
assoc values) and refuses a datum used as an assoc key.

### 4.4 Identity

- **Latent collapse** parks the thing's handle slot (`om_handle_park()`) and puts the views naming it
  to sleep under that slot; re-materializing into the entry unparks it into the same slot, so old
  handles resolve again and the views re-link (`om_handle_unpark()`, `rel_wake()`). Views count as
  accounted references in the collapse refcount check.
- **`replace_with()`** hands the original's `FORWARD_STATE(PATH, var)` vars to its successor
  (`om_handle_forward()`), and its handle slot and relation views too when the successor is the
  same kind of thing: inside the original's type cut to three path elements
  (`om_forward_family()`, e.g. `/obj/machinery/door`). A successor outside it (an airlock torn
  down into a `door_assembly` or a steel stack) is a new thing: the original's handle and views
  end with it, as in any destroy, and the successor registers itself.
- **Turf handles** carry their z-level's generation, so a handle to a recycled level's turf stops
  resolving.

## 5. Annotations that are not kinds

- `KEEP_AFTER_DESTROY(PATH, var)`: diagnostics; the leak check skips it.
- `POOL_RESET(PATH, var)`: pooling; `pool_release()` resets it.
- `FORWARD_STATE(PATH, var)`: carried to a `replace_with()` successor.
- `declared_cache_vars()` rules are unchanged.

## 6. Serialisation

A saved var with no codec of its own gets one from its ownership kind (`state_ownership_codec()`,
`code/datums/state/codecs.dm`): owned values nest as blobs, and on load the owned codec reuses an
existing child of the same type (applying the blob onto it) or disposes of it and adopts the new
one; proto vars save a registry id or a private blob; relation views save child ids inside the
subtree and re-link on load, and views leaving the subtree are dropped. `state_schema_lint.py`
accepts a saved reference var with an ownership kind; `ALLOW(state_ref)` is gone.

## 7. Kind inference and the lint

`tools/ci/ownership_lint.py` builds a codebase-wide index of declarations and accessor writes, and
fails on:

| Check | What |
|---|---|
| `raw_write` | an entity var (typed as an entity, or a list of them, or known owned/relation) written outside the accessors |
| `contradiction` | one var written both as owned and as a relation, or against its declaration |
| `kinds` | related types declaring different kinds for one var |
| `matrix` | the kind × type rules of §2 |
| `callback` | `CALLBACK(` outside the core |
| `handle` | `om_handle`/`om_resolve` or a `*_handle` var in content |
| `removed` | a deleted form (`DECLARE_REF`, `OM_STATIC_TYPE`, `REFKIND_*`, `link_set`, `WEAK_LIST_*`, `DuplicateObject`) |

A site kept on purpose carries `// ALLOW(ownership): <reason>`.

## 8. Checks, in one place

| Check | Where |
|---|---|
| raw writes, contradictions, kinds, matrix, callbacks, handles | `ownership_lint.py` |
| `GLOB.x[key] = src` self-registration | `registry_lint.py` |
| double ownership, orphaned replacement, phase 8 re-sets, refused work on dying entities (`own_guard()`) | runtime, every build |
| one kind per var, policy procs, matrix | `own_validate_table()` (first instance of a type), `own_validate_boot()` |
| orphans and rec cycles | `own_audit()` (test builds, admin verb) |
| DEF freeze | test builds |
| undeclared timer slot names | `om_timer_slot_check()` (test builds) |
| stored timer ids | `check_grep.sh` "stored timer handles" |
| framework behaviour | `code/modules/unit_tests/dq_ownership_tests.dm` |

## 9. The refs audit (items 1-13): where each is fixed

| # | Finding | Fix | Commits |
|---|---|---|---|
| 1 | STATIC escape hatch: non-static types under STATIC, techweb disk leak, robot `sprite_datum`, AI `selected_sprite`, `cleanable.viruses`, leak check skipping STATIC, `om_static_type` never checked | STATIC is gone. Registry membership is proven by `REGISTRY_TYPE(path, getter)` (`registry_types.dm`); `shared_set` asserts it; the kind x type matrix runs in the lint and at boot. Only round webs are registered (`register_techweb`); disk webs are PROTO. `sprite_datum`/`selected_sprite` are PROTO; cleanable contagions are owned per decal. The leak check skips a held value only when it is proven registered. | 24d6e46889, bc274d88e9, 92666fa6bf, 68aac387dc, 3fd948e33c |
| 2 | handle_kinds_lint forcing STATIC; geosample shared by turf and ores; plant analyzer `last_seed`; owned kinds on static types | The lint is deleted (ownership_lint replaces it). Each ore gets its own `geosample.copy()` (`own_set`); `last_seed` is PROTO (an analyzer snapshot); owned declarations on registry types are matrix errors. | dac8f82da8, f2479957ca, 68aac387dc |
| 3 | Proto cases: species, seeds, contagions, gas mixtures, robot/AI sprites | `PROTO` with `proto_private`/`proto_set`/`proto_replace`. Species: the mob holds the registered species until a trait or per-mob change calls `proto_private`; the limb table is resolved before interning, so spawning never writes a registered species. Seeds diverge through `register_line`. Machine gas ports are PROTO and network air is owned by the network, with an arena slot leak test. | 8917247920, 14d56e5ae8, fd9a38d649, f2479957ca, 2201fe6a4b, 9fe498d6d0 |
| 4 | Replace without qdel (243 sites), phase 8 silent nulling, `rec.owner` cycle | `own_set` disposes of the value it replaces by policy; the scripted conversion moved every owned write onto the accessors, and the lint fails on raw writes. Phase 8 (`own_scrub`) reports and deletes re-set values. `own_audit` finds entities kept alive only by their own rec and tears the rec down. | c374ee7dac, 77ef714568, 21c8e14995, f1cb158574, b9c945e4c9 |
| 5 | HELD misuse; gas mixtures made by the holder; owned things deleted by hand in destroy hooks; foreign refs blocking GC | HELD is split: 179 relations, 192 `OWN_CONTAINED`, 41 `OWN`. `OWN_IF`/`OWN_POLICY` give conditional policy; gas mixtures follow the resource rule (PROTO or network-owned). Teardown disposes of owned values, so hand deletes in destroy hooks were removed. Foreign refs are relation views, cleared when their target dies. | 24d6e46889, a99bb2230b, 2201fe6a4b, 7da08b961e, b680fc5053 |
| 6 | Two-sided kinds written directly; vars carrying two kinds | `REL_PAIR` keeps both sides through `rel_set`. `own_validate_table` reports a var declared with two kinds across the hierarchy, and the lint's `contradiction`/`kinds` checks do the same statically (modular computer hardware, mecha minihud, morgue tray, nif comm, fusion field fixed). | 24d6e46889, a99bb2230b, 68aac387dc, d824161a3f |
| 7 | Invisible refs: shallow `om_capture_args`, CALLBACK in content, expedition mission held by a CALLBACK, blood `data["viruses"]` aliasing, `GLOB.x[key] = src` | Deferred arguments are captured deeply and a datum used as an assoc key is refused. `om_callable`/`om_run` replace CALLBACK in content (the lint bans it outside the core); the expedition descriptor owns its mission while the callable runs. Reagent data has a declared codec. Keyed registries replace the self-registrations, and `registry_lint` catches new ones. | bf5a4a00d3, 4f26485fc8, 22244825e7, 4a021ac94b, 88193384da |
| 8 | Serializer duplicating ownership | Codecs derive from the ownership kind (`state_ownership_codec`); the owned codec reuses or disposes of the existing child; relation views re-link inside the subtree. `ALLOW(state_ref)` is gone (the master merge's new ones were stripped too). | 24d6e46889, 5928775320, this merge |
| 9 | Identity: latent collapse, replace_with, turf handles, STATIC turf/area refs | Collapse parks the handle slot and re-materialization unparks into it; `om_handle_forward()` carries the handle and `FORWARD_STATE` vars; turf handles carry a z generation and `om_drop_z` releases per-z relation indexes. Turf and area refs are relation views. | a02c27e735, 47a587135b, 64431fd2e0 |
| 10 | DuplicateObject shallow copy; manual ownership moves | `entity_clone()` serialises and re-materialises the owned subtree (the holodeck uses it); `DuplicateObject` is deleted. `own_transfer`/`own_move` do explicit moves (expedition mission, gifts, event drafts). | 24d6e46889, ceac183451, b9c945e4c9 |
| 11 | Missing relation primitives | Views with reverse indexes, `linked()`, the shapes (`REL`, `REL_LIST`, `REL_PAIR[_LIST]`, `REL_SET`), exclusivity, `holds_while`, keyed auto-linking (`REL_KEYED`, `KEYED_TARGET`), list-undo hooks, derived views, owned-child release hooks, `om_drop_z`, typed views instead of `om_resolve`. | 24d6e46889, ceac183451, 47a587135b, 1216e81f58 |
| 12 | DECLARE_DEFAULT_CHILD without an owning kind | The declaration requires an owning kind on the var (it reports and drops otherwise), adopts through `own_set`/`own_add`, and wires the child's back relation (`default_child_backref()`). | 24d6e46889, 5928775320 |
| 13 | Kind inference | `ownership_lint.py` indexes every declaration and accessor write and fails on contradictions. Undeclared vars learn their kind from the first `own_*`/`rel_*` write, so declarations are needed only for exceptions (policy, relation shape, SHARED/PROTO). | dac8f82da8, a4af88a051, this merge |

Gaps closed while writing this table (in the master merge commit):

- master's new code (admin topic split, event panel, machine first-wake queue, dartgun, topic tests) brought handle vars and raw writes back; all of it now uses views and accessors;
- the lint's fallbacks now honour SHARED, and it no longer counts a proc call's arguments as the written value (`EXPIRY_AT(src, ...)` writes a number).

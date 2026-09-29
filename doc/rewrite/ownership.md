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

- **O1 One owner.** An owned entity records its owner on itself: `own_holder_ref` (the owner's ref
  text, weak, so owner and child never form a reference cycle) and `own_slot` (the var). Read with
  `owner_of(D)` / `owner_slot_of(D)`; both re-check that the owner still names D. Movables in
  contents are owned by their ledger slot (`containment.md`); an `OWN(..., OWN_CONTAINED)` var
  names one of them.
- **O2 Writes only through accessors.** `ownership_lint.py` (`raw_write`) rejects assignment, `+=`,
  `-=`, `|=`, `[k] =`, `Cut/Add/Remove/Insert` and the `QDEL_*` / `LAZY*` list macros on an owned
  or relation var anywhere but the accessors.
- **O3 No double ownership.** Adopting a value another holder owns is refused and reported
  (`OWN: ... already owned by ...`). Moves are explicit: `own_transfer` / `own_move`.
- **O4 No orphans.** `own_set` disposes of the value it replaces by policy; `own_take` hands the
  value to the caller, who adopts or destroys it. The orphan audit (§1.5) reports anything that
  slipped out (a raw drop, an owner that died without disposing of it).
- **O5 Teardown.** Phase 2: a dying owned entity leaves its owner's var. Phase 3: `OWN_SPILL`
  movables drop out. Phase 4: every owned var is disposed of by policy, then relation views clear
  on both ends. From phase 0 the dying entity refuses new timers, hooks, tasks and relation links
  (`OWN: refused ...`).
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
  contents to the ledger slot policy; `own_set` asserts `loc == holder`.
- **Conditional policy**: `OWN_POLICY` names a holder proc returning the policy at teardown;
  `OWN_IF` picks between two by a flag var.
- **Gas mixtures and other arena resources** are owned by the holder that makes them (deleting a
  mixture frees its arena slot); a pipe network's shared mixture is the network's, and components
  hold it as a relation or `PROTO`, never as a second owner (lint `matrix`).

### 1.3 Accessors (`code/datums/ownership/own.dm`)

| Proc | Meaning |
|---|---|
| `own_set(holder, "var", value)` | adopt `value`; the previous value is disposed of by policy. Returns `value` (null when refused). |
| `own_take(holder, "var")` | detach and return the value, now unowned |
| `own_add` / `own_remove(holder, "var", value)` | list shape; `own_remove` disposes |
| `own_put(holder, "var", key, value)` | assoc values; disposes of the value it replaces |
| `own_take_member(holder, "var", value_or_key)` / `own_take_all(holder, "var")` | detach members |
| `own_transfer(from, "var", to, "var", member, key)` | move one value between owners |
| `own_move(value, to, "var", key)` | move a value from whatever owns it now (or adopt it) |
| `own_clear(holder, "var", policy)` | dispose of everything the var owns, now (`OWN_DELETE` for the old `QDEL_NULL`/`QDEL_LIST`) |
| `own_values(holder, "var")` | the owned values as a list |
| `/datum/proc/on_owned_release(var, child)` | hook: a child is leaving (disposed, taken or moved), still intact |

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

Test builds keep an index of every stamped entity and every rec, audit every 5 minutes and at the
end of the run (a finding fails the run). Servers audit on demand (admin verb "Ownership Audit").

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
`om_refs_in` (source ref text → var names). When either end dies the framework clears its side.

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
- **`replace_with()`** hands the original's handle slot, relation views and `FORWARD_STATE(PATH,
  var)` vars to its successor (`om_handle_forward()`).
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
| double ownership, orphaned replacement, phase 8 re-sets, refused work on dying entities | runtime, every build |
| one kind per var, policy procs, matrix | `own_validate_table()` (first instance of a type), `own_validate_boot()` |
| orphans and rec cycles | `own_audit()` (test builds, admin verb) |
| DEF freeze | test builds |
| framework behaviour | `code/modules/unit_tests/dq_ownership_tests.dm` |

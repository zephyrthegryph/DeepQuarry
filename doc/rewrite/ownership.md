# Ownership: own, shared, proto, relations

Status: **authoritative**. This replaces the 20 `REFKIND_*` kinds and
`DECLARE_REF()` (`lifecycle.md` §4, `object_model.md` §4–5 where they
disagree). There is no compatibility layer. The old kinds, macros and lint
exemptions are gone.

Every object-typed var, and every list that holds objects, is exactly one of
four things:

| Concept | What the var holds | Who clears it | Declaration |
|---|---|---|---|
| **Own** | the one owner's child | the owner's teardown, by policy | `OWN(PATH, var, POLICY)` |
| **Shared** | an immortal registered singleton or DEF | nobody, since it never dies | `SHARED(PATH, var)`, or implicit via `REGISTRY_TYPE` |
| **Proto** | a shared prototype, or an owner-stamped private copy of one | teardown deletes private copies only | `PROTO(PATH, var)` |
| **Relation** | a non-owning reference to an entity | the framework, when either end dies | `REF(PATH, var)`, `REF_PAIR(...)`, `/datum/om/relation/*` |

Locals inside a running proc are the only unowned references.

## 1. Own

### 1.1 Invariants (checked in every build)

- **O1 One owner.** An owned entity records its owner on itself:
  `own_holder` (the owning datum) and `own_slot` (the var name). Both are
  `tmp` and cost nothing while null. Movables in contents are owned by their
  ledger slot (`containment.md`). For them `own_holder` is their holder
  and `own_slot` is the slot id.
- **O2 Writes only through accessors.** An owned var is written only by
  `own_set`, `own_take`, `own_add`, `own_remove`, `own_put` and
  `own_transfer`. `ownership_lint.py` bans raw assignment, `+=`, `-=`, `Cut`,
  `[k] =` and `Remove` on a declared owned var.
- **O3 No double ownership.** Adopting a value that already has an owner is
  an error: `OWN: <type> already owned by <holder>.<slot>`. The only
  exception is `own_transfer`, which is an explicit move.
- **O4 No orphans.** Overwriting or dropping an owned value is an error
  (`OWN: orphaned owned value`) unless the old value is destroyed by the
  accessor (`own_set` destroys it by policy) or moved out (`own_take` /
  `own_transfer`). `own_take` hands the value to the caller, who must adopt it
  or destroy it before the proc returns. The orphan audit (§1.5) catches the
  ones that don't.
- **O5 Teardown.** Owned values resolve in lifecycle phase 3 (contained) and
  phase 4 (everything else), by policy. From phase 0 the dying entity's rec
  refuses new timers, hooks, tasks and relation links (`OM: refused <what> on
  destroying <type>`).
- **O6 Phase 8 re-set check.** After core `Destroy()`, any owned var that
  holds a value again was re-set during teardown. Phase 8 deletes that value
  and reports it (`OWN: <type>.<var> re-set during teardown`). Nothing is
  nulled silently.

### 1.2 Declaring

```dm
OWN(/obj/machinery/sleeper, beaker, SPILL)        // one child
OWN(/datum/body, afflictions, DELETE)             // list of children
OWN(/datum/reagents, by_id, DELETE)               // assoc: values are children
OWN(/obj/item/storage, contents, CONTAINED)       // movables in contents
OWN_POLICY(/obj/machinery/computer, circuit, /obj/machinery/computer/proc/circuit_policy)
```

- The var is written bare. The macro stringifies it and validates it with
  `PATH::var` at compile time.
- **Shape comes from the value.** A non-list is *one*. A list whose members
  are datums is *list*. A list with datum assoc values is *values*. At boot,
  `ownership_lint.py` checks the declared var type against the shape.
- **Policies:**
  - `DELETE`: destroyed with the owner.
  - `SPILL`: a movable goes to the owner's drop location. A non-movable is
    deleted, and the lint forbids `SPILL` on non-movable var types.
  - `CONTAINED`: a movable that is in the owner's contents. It is left to the
    ledger slot policy. `own_set` asserts `value.loc == holder`, and teardown
    asserts it again.
- **Conditional policy.** `OWN_POLICY(PATH, var, proc)` names a proc on the
  holder that returns a policy per call. It replaces the old
  `OWNED`-plus-`HELD` double declarations: modular computer hardware,
  mecha minihud, morgue tray, NIF comm, fusion `owned_field`. `OWN_IF(PATH,
  var, POLICY, flag)` is a shorthand for "POLICY while `flag` is set, else a
  relation-only drop".
- **Resources.** `OWN_RESOURCE(PATH, var)` marks a var holding a
  `/datum/gas_mixture` (or another arena-backed handle). It is `DELETE`, and
  deleting it releases the arena slot. Gas mixtures are never `HELD`.
  Machines own their mixtures, and pipe networks own `air1/air2/air3` (§3).

### 1.3 Accessors (`code/datums/ownership/own.dm`)

| Proc | Meaning |
|---|---|
| `own_set(holder, "var", value)` | adopt `value` into a one-shape var. Destroys the previous value by policy. Returns `value`. |
| `own_take(holder, "var")` | detach and return the value, now unowned (the caller must adopt or destroy it) |
| `own_add(holder, "var", value)` / `own_remove(holder, "var", value)` | list shape. `own_remove` destroys. |
| `own_put(holder, "var", key, value)` | values shape. Destroys the value it replaces. |
| `own_take_member(holder, "var", value_or_key)` | list or values: detach one and return it |
| `own_transfer(from, "var", to, "var")` | move one value between owners. It is never destroyed or orphaned. |
| `own_clear(holder, "var")` | destroy everything the var owns, now |
| `owner_of(D)` / `owner_slot_of(D)` | read `own_holder` / `own_slot` |

`DECLARE_DEFAULT_CHILD(PATH, var, default)` adopts through `own_set`. On a
non-movable, the var must be declared `OWN`, and boot validation refuses it
otherwise. The child's back relation (a `REF` named in the child's
`owner_ref_var`) is wired automatically.

### 1.4 Clone

`entity_clone(D, new_owner, slot)` serialises `D`'s owned subtree with the
declared codecs (`state.md`) and re-materialises it under `new_owner`.

- Shared and proto references are copied by id.
- Relations *inside* the subtree are rewired to the clones. Relations leaving
  it are re-linked only if the relation kind says `clone_follows = TRUE`.

`DuplicateObject` is deleted. The holodeck and `replace_with` use
`entity_clone`.

### 1.5 Orphan audit

`own_audit()` runs every 5 minutes in test builds and on demand
(`Debug → Ownership audit`). It visits every entity in the handle table and
every live rec:

- **orphan:** owned (`own_holder` set), but its holder no longer names it in
  `own_slot`, or the holder is QDELETED;
- **dropped with a rec:** a live rec whose owner is unowned and unrooted.
  `refcount(owner)` equals the rec's own references (rec.owner, the
  scheduler rings), so only the rec cycle keeps it alive. The audit
  force-tears the rec down (timers and hooks with it) and reports
  `OWN AUDIT: dropped entity kept alive by its rec`.

Roots are services, locations, `GLOB`, registries and clients.

## 2. Shared

- `REGISTRY_TYPE(path, getter)` declares that `path` and its subtypes are
  registry singletons, and names the getter proc. The getter takes an
  instance and returns TRUE if that exact instance is the registered one (for
  example `species_registered(S)` is TRUE if `GLOB.all_species[S.name] == S`).
  It replaces `OM_STATIC_TYPE`, which asserted membership by fiat.
- A var whose declared type is a registry type is **implicitly SHARED**, and
  needs no declaration. `SHARED(PATH, var)` exists for untyped vars.
- `shared_set(holder, "var", value)` asserts `getter(value)`. A raw write to
  an implicit-shared var is allowed, but in test builds the kind matrix check
  verifies it at teardown and in audits.
- **Kind × declared-type matrix.** At boot (`own_validate_tables()`) and in
  `ownership_lint.py`:
  - one kind per var across the whole type hierarchy;
  - `OWN` of a registry type is an error, unless it is a `PROTO`;
  - `SHARED` of a non-registry type is an error;
  - `REF` of a registry, DEF or location type is an error, because it needs
    no tracking.
- **DEF freeze** (test builds). `def_freeze_snapshot()` at boot records a
  hash of every registry instance's vars. `def_freeze_verify()` at test end
  diffs them and fails on any write.

## 3. Proto (copy-on-write)

A proto var holds either the registered prototype (shared) or a private copy
stamped with the holder as its owner.

| Proc | Meaning |
|---|---|
| `proto_get(holder, "var")` | read. The same as reading the var. |
| `proto_private(holder, "var")` | return a private copy, making one first (`D.proto_copy()`) if the var still holds the prototype. The copy is owned by `holder`. |
| `proto_set(holder, "var", value)` | point at a prototype or adopt a private value. Deletes the private copy it replaces. |
| `proto_is_private(holder, "var")` | TRUE when the value is owned by the holder |

- Teardown deletes private copies only.
- The serializer saves a prototype by registry id and a private copy as an
  owned blob.

**Users:**

- Species: per-mob changes go through `proto_private`, not `produceCopy()`
  into the shared var.
- Seeds: `diverge()` returns a private copy.
- Contagions: `cleanable.viruses`, and `infectedroom`'s shared
  `chosen_disease`.
- Gas mixtures: a machine owns its mixture, and a network's `air1/2/3` is the
  proto.
- Robot and AI sprite datums.

## 4. Relations

Every non-owning reference to an entity is a relation edge. There are two
weights.

### 4.1 Light edges: `REF` views

```dm
REF(/mob/living/bot, target)                      // 1:1 view var
REF(/obj/machinery/camera, viewers)               // list view (1:N)
REF_PAIR(/obj/machinery/sleeper, console, /obj/machinery/sleeper_console, sleeper)
REF_MEMBER(/obj/item/organ, owner, /mob/living/carbon/human, internal_organs)
REF_KEYED(/obj/machinery/door/blast, id_tag, /obj/machinery/button/remote/blast_door, id)
```

- The view var holds a direct reference, so reads are free. The target keeps
  a lazy reverse index `om_refs_in` (an alist: source → var names).
- When either end dies, the framework clears its side:
  - the target's death nulls every source view, or removes it from list views;
  - the source's death drops its entries from each target's index.
- There is no manual bookkeeping.
- **Writes:** `ref_set(src, "var", target)`, `ref_add`, `ref_remove`,
  `ref_clear`. `REF_PAIR` / `REF_MEMBER` writes set both sides (`ref_set` on
  either side sets the partner's view too). Exclusivity is implied for 1:1
  views, so linking a new partner unlinks the old one.
- `ownership_lint.py` bans raw writes to a view var (framework write only).
- **Keyed auto-linking.** `REF_KEYED(PATH, var, TARGET_PATH, key_var)` links
  by matching id when either end materializes, through the registry id index.
  It replaces init-time machine scans and id matching.
- **Symmetric membership:** `REF_SET(PATH, var)`, a many-to-many where both
  ends list each other (atmos node topology).
- **Identity across collapse.** An edge to an entity that collapses to latent
  (`containment.md` §4) goes dormant, keyed by the target's handle id. When
  the entry re-materializes into the same handle slot, dormant edges
  re-link. When the owner of a dormant edge dies, it drops its entries.
- **z-level release.** `ref_drop_z(z)` bulk-unlinks every edge whose end is on
  the z-level (turf handles carry the z generation, `loc_gen`).

### 4.2 Rich edges: `/datum/om/relation`

These are for edges with state, hooks or conditions. Grab, pull, buckle, tgui
sessions and grants are examples. They use the existing
`om_link`/`om_unlink`. Completed per `object_model.md` §5:

| Field / hook | Meaning |
|---|---|
| `shape` | `REL_1_1`, `REL_1_N`, `REL_N_N`, `REL_SYMMETRIC` (sets `source_single`/`target_single`) |
| `exclusive` | a new link replaces (`OM_REL_REPLACE`) or refuses |
| `holds_while` | a check spec. When it fails, the edge breaks with a reason (was `break_if`). |
| `source_view` / `target_view` | framework-maintained 1:1 view var names on each end |
| `on_link`, `on_unlink(reason)`, `on_end_changed` | hooks |
| `on_member_leave(member)` | a member unlinking itself through a domain proc (cloning pod, jukebox, resleever, conveyor) |
| `undo_list` | list-undo: on unlink, remove from a declared list on the target (alternate_appearance, lg_imageholder, song, multicam) |
| `derived_view` | a proc recomputing a view var from `linked()` (omni filter/mixer) |
| `on_owned_release(child)` | runs when an owned child is released (media, tooltip, overmap) |
| `clone_follows` | re-link to the clone in `entity_clone` |

Reads:

- `linked(E, rel)` returns the targets (a shared empty list when there are none);
- `linked_to(E, rel)` returns the sources;
- `link_of(E, rel)` returns the single target, typed by accessor procs
  (`relation_accessors.dm`).

Hand-cast `om_resolve` is gone from content.

### 4.3 Handles

`om_handle()` is internal to the core:

- deferred arguments (timers, I/O, tasks): `om_capture_args` captures deeply
  (nested lists and assoc values) and refuses anything else;
- the latent identity slot;
- the serializer.

A content var holding a handle is a relation. `CALLBACK` is banned outside
`code/datums/om`, `code/controllers` and the core helpers. A deferred call is
`om_after()`, which holds its arguments as handles.

## 5. Annotations that are not kinds

- `KEEP_AFTER_DESTROY(PATH, var)`: diagnostic. The leak check skips it (an id
  the GC report reads).
- `POOL_RESET(PATH, var)`: pooling. `pool_release()` resets it.
- `CACHE_VAR` rules (`declared_cache_vars()`) are unchanged.

## 6. Serialisation

State codecs derive from the declarations:

- an owned var saves as an owned blob, and the owned codec reuses the
  existing child when the type matches, or deletes it and adopts the new one;
- a shared var saves its registry id;
- a proto var saves a prototype id or a private blob;
- a relation saves its target's handle id and re-links on load.

`ALLOW(state_ref)` is gone. Reagent `data` has a declared codec
(`reagent_data_codec()`), so `data["viruses"]` is copied, not aliased.

## 7. Kind inference

`tools/ci/ownership_infer.py` builds a codebase-wide assignment index. For
each object var it records who creates the value (`new`), who assigns a
foreign value, and who deletes it. It infers:

| Evidence | Inferred kind |
|---|---|
| created by the holder and never assigned a foreign value | Own/DELETE |
| typed as a registry type | Shared |
| foreign assignment and never created by the holder | Ref |

It fails on contradictions: a declaration that disagrees with the evidence,
or a var both created and assigned foreign without an `OWN_POLICY` or
`PROTO`. Declarations are required only where inference can't decide:
teardown policy other than DELETE, pairs, keyed links, protos.

## 8. Checks

| Check | Where |
|---|---|
| one kind per var across the hierarchy, and the kind × type matrix | `own_validate_tables()` at boot, `ownership_lint.py` |
| raw writes to owned or view vars | `ownership_lint.py` |
| `CALLBACK` outside core, `GLOB.x[key] = src` | `ownership_lint.py`, `registry_lint.py` |
| double ownership, orphans, phase 8 re-sets, refused links on dying | runtime (all builds) |
| orphan and rec-cycle audit | `own_audit()` (test builds and verb) |
| DEF freeze | test builds |
| arena slot leak | `gas_retain_mixtures` test |

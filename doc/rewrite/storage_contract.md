# Storage contract: lazy owned state

The design is in `E:/projects/dq-design-review/` (migration plan S3, `lazy_and_variables.md`). This file is the repo-side record of the form and of the grouping of the old `sparse()` slots into state datums.

## The form

Rarely used state is the vars of a small datum the holder owns, made on the first write:

```dm
/datum/omen_state
	var/damage = 1

CAPABILITIES(/mob/living)
	owns_one(nameof(omen), /datum/omen_state, lazy = TRUE)
```

- Read: `STATE_GET(A, omen, damage)`, the field, or the state type's own default (`/datum/omen_state::damage`) while no state exists. It allocates nothing. `A` is a var or `src` (it is evaluated twice).
- Write: `omen_of(A).set_damage(2)`. `omen_of()` is a generated global proc that makes the datum on its first call. The state's vars are tracked; a write publishes the var on the state and the holder's `omen` key, so draws, stats and `on_change()` that read it follow.
- End: `omen_clear(A)` deletes the datum when a feature clearly ends. Otherwise it lives until the holder dies; a write back to the default frees nothing.
- The state type is `/datum/<var>_state` (the generator refuses another name). No proc is added to `/mob`, `/atom` or `/datum`.

## Holders and features

A mob holder owns its state in a var (`owns_one(nameof(feature), /datum/feature_state, lazy = TRUE)`). Every other holder (`/atom`, `/atom/movable`, `/obj`, `/obj/item`, `/obj/machinery`: types with millions of instances) gets no var: the state is a row of an engine table keyed by the holder's slot (`lazy_state(feature, /datum/feature_state)`, state type `parent_type = /datum/lazy_state`). `x_of()` makes the row, `STATE_PEEK` looks it up, `engine_forget()` drops it with its holder.

One state per declaring feature; a field with no obvious feature goes to its holder's `*_misc` state (`mob_misc`, `living_misc`, `carbon_misc`, `human_misc`, `atom_misc`, `movable_misc`, `obj_misc`, `item_misc`, `machinery_misc`). The state types are in `code/library/mob/states/` and `code/library/atom/states/`; `cooldowns` holds the cooldown and stamp fields of every atom.

- A write of a field's default makes no state, and a state goes when its last non-default field returns to the default (`STATE_SET`).
- A list field is a plain field (null until held). A weak reference is `ref_one(nameof(f), /type, weak = TRUE)` in the state type's CAPABILITIES block, read with `STATE_REF` and written with `STATE_REF_SET`.
- A field whose default is per instance or per type (integrity, surface germs) holds null for "the default" and its reader substitutes it.
- View Variables, mass edit and SDQL reach every field as `@slot.name` or by the bare name (`code/engine/declare/lazy_vv.dm`); the object state serializer keeps the plain fields of a row as `lazy.feature.field` (`code/content/state/lazy_state_saved.dm`).
- The old `sparse()` slots, `sparse_get`/`sparse_set` and the `cooldown_table` are deleted and banned.

## Copy on write: `per_type`

Copy-on-write used to be four schemes with four "has this instance copied yet" tests. There is one form: a value the type builds once, shared by every instance until one of them writes.

| Shared value | Form | The copied-yet test | Freed |
|---|---|---|---|
| A starting list | `per_type(nameof(v), PROC_REF(build), copy_on_write = TRUE)` | the var is not the type's table (`cow_table()`) while `v_version` is 0 | with the holder: the private list is the holder's own var |
| A type's own constant list | `per_type(nameof(v), TYPE_PROC_REF(/datum, per_type_own))` | never written (read-only; `analyze` rejects a write) | never |
| A type's trait block | `type_trait_of()` reads, `type_trait_own()` writes | a row of `per_type_copies[kind]` at the holder's slot | `engine_forget()` -> `per_type_forget()` |

- **Read.** A list var holds the type's one table from preinit (`per_type_bind()`), so a read is a var read and allocates nothing. A trait read finds no row and answers the type's shared datum.
- **First write.** A list's generated mutator (`add_v`, `remove_v`, ...) unshares first and counts `v_version`, so later writes edit the private list in place. `type_trait_own()` copies the shared trait, and `per_type_copy_make()` records the copy as the holder's row. Other instances, and instances made later, still read the shared value.
- **Tracking.** A copy-on-write list is a tracked list: the setter and mutators publish the var, and reads are generated as for any tracked var. A trait write publishes the kind's key (`tracked_changed(holder, key)`), as before. No instance holds a shadow of the shared value.
- **Free.** A private list dies with its holder. A trait row is dropped in `engine_forget()` (idempotent), after `Destroy()`, so a dying holder's teardown still reads its own values.
- **Not copy on write.** An owned child that a holder may replace with a private clone (`owns_one(copy_on_write = TRUE)` + `proto_private()`: a species, a robot sprite) is a relation: the clone is owned, stamped, and deleted by its holder, which a built-once shared table is not. It stays an ownership form (`code/engine/refs/prototypes.dm`).
- **Gone and banned.** `shared_type_list()` (use `per_type_own`), the `LIST_STATE` `share = SHARE_COW_TABLE` policy and `rx_state.cow_private` (a starting list is `per_type(copy_on_write)`), and `/datum/var/type_trait_overrides` (the `per_type_copies` row).

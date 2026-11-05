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

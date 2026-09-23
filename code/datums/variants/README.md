# Variants

BYOND builds a type table for every type path, so thousands of near-identical
subtypes cost real memory even if nothing spawns them. The measured cost was
about 12.5 KB per subtype. A variant collapses such a family into one type
plus a data table.

## How it works

- A family's registry is a global assoc list, for example
  `GLOB.dq_variants_accessory_gaiter`, mapping a variant key to the vars that
  differ (`name`, `icon_state`, `desc`, `item_state`, ...).
- The parent type reads its `variant` var in `Initialize()` and applies the
  matching entry through `apply_variant()`.
- Anything that used to name a subtype now names the parent plus a key:
  - spawn lists (`starts_with`, supply packs, vendors) use
    `list(count, "variant")` values, resolved by `dq_resolve_spawn_value()` in
    `spawn_with_variant.dm`;
  - loadout entries use `/datum/gear_tweak/variant` in
    `gear_tweak_variant.dm` to offer the variants in the picker.

## Where things are

| Path | Contents |
|---|---|
| `code/datums/variants/` | Shared plumbing and the crayon/marker variants. |
| `code/modules/clothing/variants/` | One file per collapsed clothing family. |
| `code/datums/components/sparse_vars/` | The same idea for per-instance vars: rarely used `/atom` vars moved into components so most atoms carry no storage for them. |

## Adding a family

Collapse a family only when its subtypes differ just in data (name, icon
state, description, colour). If a subtype overrides procs or behaviour, keep
it as a real subtype. Update every spawn list, loadout entry and map instance
that named the old subtypes (a map instance sets `variant = "key"` on the parent), then compile and run the unit tests.

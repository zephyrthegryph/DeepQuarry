# Look: appearance and the icon naming convention

Status: **[in progress]** on `rewrite/f-look` (owner W3); `look.state/overlay/gauge/glow/light/hide`
and the legacy standard state names are **[built]**. Overview: [foundation.md](foundation.md).

## 1. The idea

A type draws itself in `draw(datum/look/look)`. The look builder is the only writer of overlays
(`add_overlay`, `cut_overlay`, `update_icon` and `update_appearance` are not called). What the
draw reads is a reaction (`drawn_from`, generated from the body; see [reactions.md](reactions.md)),
so a change to a read redraws once per entity per frame, and an identical result costs almost
nothing. A property the look stops setting reverts to the type default.

The new part is **naming**: instead of a `layer =` argument on every capability constructor, states
in a `.dmi` follow a convention, and the look resolves them.

## 2. Naming convention

For a base icon state `<base>` (for example `apc`):

| Form | Resolves to | Use |
|---|---|---|
| `look.variant(name, when=)` | `<base>-<name>` if it exists, replacing the base | A whole-sprite alternative (`apc-broken`, `apc-open`). |
| `look.part(name, value_or_when)` | `<base>-<name>[-<v>]`, else `<name>[-<v>]` | An overlay part; a numeric or enum value picks the suffix (`apc-charge-3`, else `charge-3`). |
| `look.glow(name, value)` | Draws the part emissive (it adds the part, or upgrades the one already added) | Screens, lights, indicators. Glows are explicit in `draw()`; nothing glows by default. A part named twice draws once. |

Type-specific states win over shared ones, so a shared `panel_open` part works for every machine
and one machine overrides it by shipping `<base>-panel_open`. Standard part names live in
`code/__defines/look_names.dm` (`broken`, `cover_open`, `panel_open`, `wires`, `locked`, `sparks`,
`emagged`, `dark`, plus glow and gauge names). A per-icon state-set cache makes lookup free after
the first draw. `look.hide` keeps working.

Library capabilities switch to parts, so `cap_cover`, `cap_panel`, `cap_lock`, `cap_emag`, `cap_power` etc. no
longer take `layer =` **[built on master, G12: no library constructor takes `layer =`, `behind`, `blocked_by` or
`locked_by`; each capability draws its fixed standard name (`cap_bolts` LOOK_BOLTS, `cap_weld_shut` LOOK_WELDED,
`cap_emergency_access` LOOK_EMERGENCY, `cell_bay`/`cap_cell_holder` LOOK_CELL, ...); a slot names its part with
`part =`; a holder whose sprite shows the state another way drops the part with `look.hide(name)` in `draw()` (the
airlock hides bolts and emergency, the vendor its panel, wires, broken and dark parts); state gates are
requirements in `needs`]** (the lock takes `lamp =`: it shows as a glowing `locked` / `unlocked` lamp while the holder is lit, see `is_lit(A)`). `CAP_NO_LAYER` and `layer=` are the old form; see
[migration_guide.md](migration_guide.md) Part F.

## 2a. Reading a slot

A draw that shows what a holder keeps reads the slot through the builder, not through `contents` or `slot_contents()` (a walk needs real things;
the draw must not make them):

| Form | Answers | Use |
|---|---|---|
| `look.contents_of(src, slot, type)` | the types held in `slot` (null: the default slot) that are a `type`: a real thing by its own type, a latent one (declared by `starts_with`, not made yet) by its entry's type, once each | classify or count (`for(var/kind in look.contents_of(src, CONTAINER_SLOT_INTERIOR, /obj/item/gun))`, `ispath(kind, /obj/item/gun/energy)`): the gun cabinet draws a gun per laser or projectile gun it holds without making any |
| `look.things_in(src, slot, type)` | the real things of `type` in `slot`, each watched | show them (the vehicle cage draws the vehicle behind its frame) |

`look.picture_of(thing)` answers `list(icon, icon_state, dir)` of another atom (a cliff cuts the ground above it out of the turf's picture) and
`look.show_copy_of(thing, layer)` adds a copy of another atom as an overlay in its own plane (the caged vehicle); both watch the atom, so a change
published on it redraws the holder, and a draw never reads another atom's vars itself (the `dx_untracked_read` ratchet).

Both slot forms stand for `SLOT_OCCUPANCY_KEY` on the holder (`READS_AS`, read by `tools/analyze` from the builder call): a thing entering or leaving the slot, a
latent entry made or used (`latent_set_count()`), and the holder declaring its generator (`set_latent_declared()`) redraw it. `slot_kinds()`
(`code/engine/refs/containment/api.dm`) is the atom proc behind `contents_of()`: with a ledger it reads the ledger; without one it answers from the
declared generator when the holder has not declared it yet, else it opens the ledger. It never rolls the generator into things and never materializes.

## 3. Checks and tooling

- **Outputs have no side effects:** `draw()` is a reactive proc (`dx_reactive_write` flags a state write, `to_chat`
  or `playsound` in it), and `tools/ci/sys_rules/dx_look_side_effects.py` holds the legacy appearance procs
  (`appearance_overlays()` and `DECLARE_APPEARANCE_PROC` rows) to the same rule, their own appearance-var writes
  excepted; its baseline is the legacy offenders (vent_pump's sounds among them), shrink-only.

- **Unit test:** for each type, lists the standard parts it should have and lacks. A per-type
  `look_lacks()` allowlist records intentional gaps (a machine with no panel art).
- **Rename tool:** `tools/dq_icons/rename_states.py` renames states in `dmi.toml` and updates
  string references in code and maps in one pass. It has not been run on content except the APC (`apco3-*` is the APC's charge lamp, `charge-<n>`; only `apco0-2` are channels; the coverless frames
  are `apc0-cover-removed[-broken][-cell]` variants and `apcmaint` is the `maintenance` part).
  `icons/gen/` is never hand-edited.

## 4. Example

```text
/obj/machinery/power/apc/draw(datum/look/look)
    ..()                                    // capabilities draw first: broken, cover_open, panel_open, wires, emagged
    look.variant("off", when = !operating)
    look.glow("charge", charge_level)       // apc-charge-N, else charge-N, emissive
    look.light(2, 0.25, COLOR_GREEN)
```

## 5. A turf and its neighbour turfs (turf edges)

A turf's draw must not read its neighbours: a neighbour's state is not the turf's own, and the engine cannot hear it change. The adjacency index does
the listening (code/game/turfs/turf_edges.dm, `ADJ_KIND_TURF_EDGE`; every simulated turf is a member). When a member, or a turf beside it, is placed,
moved, removed or replaced (`ChangeTurf` ends with `turf_edges_refresh()`), or reports that something an edge reads changed (`edge_inputs_changed()`
from `on_change()` of its flooring, the state it draws or its density; it only acts when its `edge_key()` moved), the index recomputes the members
around it, and each one's `edges_changed()` writes its own TRACKED masks through their setters:

| Turf | Masks | The draw shows |
|---|---|---|
| floor, water, open space | `edge_mask` (border bits and inner-corner bits from `flooring.test_link()` against the eight neighbours), `edge_spill` (the edge overlays a stronger neighbour spills onto it), `no_ceiling` (open space above, not outdoors) | the flooring's edges and corners, the spilled edges, the ceiling gap |
| solid rock, flesh | `open_mask` (the cardinal neighbours that are not dense) | the lip toward each open side |
| wall | `wall_connections` (from the index mask, the doors and hull corners beside it) | the connections of its material's sprite |

What a neighbour reads of a floor's sprite is `edge_look_state()`, a function of the floor's tracked state (`flooring`, `flooring_override`, damage,
scorch), never of another turf's drawn `icon_state`. Nothing in these chains calls `update_icon()`, `changed(src)` or `appearance_notify_neighbours()`.

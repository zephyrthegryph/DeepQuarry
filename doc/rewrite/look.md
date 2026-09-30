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
longer take `layer =` (the lock takes `lamp =`: it shows as a glowing `locked` / `unlocked` lamp while the holder is lit, see `is_lit(A)`). `CAP_NO_LAYER` and `layer=` are the old form; see
[migration_guide.md](migration_guide.md) Part F.

## 3. Checks and tooling

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

# Hand-state hooks: what replaces `update_held_icon()`

Status: proposal, recommendation below. Lane: rewrite/finish.

## What is left

`update_held_icon()` (`code/game/objects/items.dm`, called from `update_twohanding()`, `mob/living/update_held_icons()` and the
inventory moves) used to end in a hand `changed(src)` mark. The mark is gone (a holder watches what it holds, and every setter
publishes). The proc stayed because nine item types override it to *recompute state that depends on how the item is held*:

| Type | Writes |
|---|---|
| `/obj/item/material/twohanded` (+ fireaxe, sledgehammer), `/obj/item/melee/baton/fluff/stunstaff`, `/obj/item/melee/shock_maul`, `/obj/item/shockpaddles`, `/obj/item/ghost_catcher` | `wielded`, `force`, `name`, `pry`, armor penetration |
| `/obj/item/gun`, `/obj/item/bork_medigun` | the per-hand `item_state_slots` |

Every write goes through a tracked setter, so nothing here needs a redraw ask. What remains is a *hook name* that says "icon" while it
recomputes gameplay state, and an imperative recompute at every hand change.

## Options

1. **Keep the hook, rename it** (`hands_changed()`). A rename dodge: the callers stay imperative. Rejected.
2. **Derive the state.** `wielded` becomes a derived value over the item's hand relation (`derives(nameof(wielded), PROC_REF(is_wielded))`
   reading the holder's hands through a relation hop), and `force`/`name`/`pry` follow `wielded` as contributions (`contributes(...)` once
   stats land; today `on_change(nameof(wielded), ...)`). The inventory moves then write the hand relation and nothing calls a hook.
3. **Leave it** until the stat layer (`stat(...)`, `hold()`) lands, then do option 2 for all nine types at once.

## Recommendation

Option 3 now, option 2 when `stat()` / `contributes()` are on master (doc section 5): the force and name changes are compositions
of sources, which is exactly what that layer is for, and converting the nine overrides earlier would invent a stand-in form.
Until then `update_held_icon()` is a documented no-op base hook (its comment says so) and no override may write a draw or a mark.

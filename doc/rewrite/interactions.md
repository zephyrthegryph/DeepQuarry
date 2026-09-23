# Interactions and input (track I)

Every interaction is a definition, not a proc override. So every interaction can be listed, can say why it isn't available, and can be bound to a key. Physical inputs map to a small set of abstract actions, and the interaction code never mentions mouse buttons or modifier keys.

## 1. Today

**Click handling**
- There is a tg-style chain already: `item_interaction` → `tool_interaction` → `tool_act` → `*_act`, falling back to `attackby` (`code/_onclick/item_attack.dm`).
- The modifier ladder is copied three times: `click.dm:61-87`, `observer.dm:54-80` and `ai.dm:52`. Borgs have their own dispatcher (`cyborg.dm:12`).

**Legacy handlers**

| Proc | Overrides |
|---|---|
| `attackby` | 874 |
| `attack_hand` | 635 |
| `attack_self` | 500 |
| `click_alt` | 88 |

- There are also 375 object verbs and 487 dynamic `verbs +=` calls.
- About 68 `*_act` handlers bounce back into `attackby`, and 6 construction state machines route through `focused_tool_stage`.

**Keybinds**
- There's no `/datum/keybinding` and no keybind preferences.
- Four macro sets are hardcoded in `interface/skin.dmf`, and they only call verbs on the player's own mob.

**Right-click** probably never reaches the game's secondary click chain (B21).

**Help text and screentips**
- Examine hints are 397 hand-written `description_info` strings, maintained separately from what the code does.
- The screentip signals are defined but unused.

**Non-player actors**
- 151 `attack_ai` overrides, about 83 of which just call `attack_hand`.
- 31 `attack_robot` overrides, 53 `attack_ghost`, 57 `attack_generic` and 19 `attack_tk`.

**Other patterns**
- Tools: 823 `do_after` calls, each doing sound, speed and fuel by hand.
- Intents: 211 `a_intent ==` gates.
- Surgery is the only place that already lists candidate interactions and lets the player choose. It belongs to the body rewrite.

## 2. Abstract actions

**Target actions** go through the target's interactions:

| Action | Meaning | Default binding (reproduces today) |
|---|---|---|
| **Use** | The default interaction | Left click |
| **Alternate** | The secondary interaction | Alt-click, and right-click once enabled |
| **Menu** | List every interaction, with availability and reasons | New: a key, or a modifier plus right-click |
| **Inspect** | Examine | Shift-click |
| **Drag** | Move or transfer from one thing to another | Drag and drop |
| **Self-use** | Use the held item on itself | Z, or clicking the held item |

**Mob actions** are not object interactions: pull, point, throw, swap hands, resist, rest, combat mode, movement.

**Categories** can be bound to keys: Toggle, Open/Close, Eject, Insert, Lock, Configure (opens a UI), Repair, Maintain, Attack.
- A category key runs the best available interaction in that category on the hovered target, or on the tile in front of the player.
- Every interaction declares a category and a priority, and optionally whether it answers **Use** or **Alternate** by default.

## 3. Bindings

- `/datum/keybinding` records map physical inputs to actions. A physical input is a key, or a mouse button plus modifiers.
- Bindings are stored in preferences and applied per client with `winset`, replacing the four static macro sets in `skin.dmf`.
- Default bindings reproduce today's controls. Players can rebind everything, and the Menu action is always available as a fallback.
- **Hover tracking.** `MouseEntered` on map atoms, throttled, records the hovered atom for category keys and screentips. It is only active for clients with screentips or hover-targeted bindings.
- **Right-click.** Enabled on the map element (B21), and routed to Alternate or Menu according to the player's binding.

## 4. The input router and actors

- One router turns physical inputs into actions for every mob. It replaces the three modifier ladders and the borg dispatcher.
- **Capability adapters.** Non-player actors (AI, borgs, ghosts, telekinesis, simple mobs) produce the same actions. An adapter decides which interactions are available: "remote, no hands, needs camera sight" for the AI, "observer-only" for ghosts, and so on.
- **Deletes the forwarding overrides:** the ~83 `attack_ai` → `attack_hand` forwards, ~13 of the `attack_robot` forwards, and the ghost UI openers.

**As built (I1).** Code lives in `code/modules/keybindings/`.
- `router.dm`: `GLOB.input_router`. Click tables (ordered rows of held modifiers → `INPUT_ACTION_*`) are the only place click modifiers are read; the `input: modifier ladders` lint in `tools/ci/check_grep.sh` enforces it.
- `adapters.dm`: singleton adapters `hands`, `ghost`, `ai`, `robot` and `telekinesis`. Each decides whether a click is accepted, which click table it reads (the AI has its own), and what Use does. Until I2, Use and Alternate reach the legacy handlers.
- `keybinding.dm`, `keybinding_defaults.dm`: `/datum/keybinding` records with default keys per profile (`default` reproduces the old `hotkeymode` set, `robot` reproduces `borghotkeymode`). Player overrides are stored in the preferences savefile as `key_bindings`, and `right_click_binding` holds the right-click choice.
- `client_macros.dm`: writes the bindings into the skin's one empty `default` macro set with a single `winset`, and sets `mapwindow.map.right-click`. When right-click is bound to Menu, BYOND's native popup is kept; the resolver's Menu replaces it in I2.
- `hover.dm`: `/atom/MouseEntered` returns early unless the client has a category key bound. Category keys (`.input-category`) are unbound by default and do nothing until I2.
- `keybind_editor.dm` with `KeybindingEditor.tsx`: the Keybindings verb.

## 5. Interaction definitions

```dm
/datum/interaction/toggle_power
	id = "toggle_power"
	name = "Toggle power"
	category = INTERACTION_CAT_TOGGLE
	priority = 10
	default_action = ACTION_ALTERNATE
	requires = list(REQ_REACH_ADJACENT, REQ_HAND_FREE, REQ_TARGET_STATE(/obj/machinery/proc/can_toggle_power))
	effect = /obj/machinery/proc/toggle_power
```

| Field | Meaning |
|---|---|
| `id`, `name`, `category` | Identity and grouping |
| `priority`, `default_action` | Which interaction Use or Alternate picks |
| `requires` | A predicate with reasons ([rules.md §2](rules.md#2-predicates)): tool quality and tier, a free hand, reach, which actors, access, target state |
| `cost` | A duration through the tool pipeline (§9), plus fuel, charge or resources |
| `effect` | A proc on the target, or a data transform |
| `feedback` | Messages, sounds and balloon alerts, generated from the definition unless overridden |
| `tags` | For filtering, e.g. `hostile` |

Definitions are shared singletons: a type lists or inherits them, and it costs no memory per instance.

## 6. Where interactions come from

- **Type declarations.**
- **Behaviours:**
  - **Maintainable** machines get open panel, anchor, deconstruct and repair. This replaces `maintenance_flags` and its four `*_act` procs in `machinery.dm:183-230`.
  - **Slot holders** get insert and eject for each slot ([containment.md](containment.md)).
  - **tgui** gives open UI (Configure).
  - **Construction graphs** give the next step (§10).
  - **Wires** give hack (§11).
- **Abilities** are interactions on oneself ([rules.md §5](rules.md#5-abilities)).
- **Surgery** is built on this by the body rewrite (their phase 9).

## 7. Resolver and the Menu action

- `interactions_for(actor, target, held, modifiers)` returns two lists:
  - the interactions available now, ordered by priority;
  - the blocked ones, each with the reason from its first failing clause.
- **Use** and **Alternate** run the top available interaction for that action. If several are tied, they open the Menu.
- **Menu** shows both lists, with the player's bound keys, in a context panel. It replaces BYOND's native verb popup and most radial menus.

**As built (I2).** Code lives in `code/datums/interactions/`; defines in `code/__defines/interactions.dm`.
- `interaction.dm`: `/datum/interaction` with `id`, `name`, `category`, `priority`, `default_action`, `requires` (a P2 spec), `tool` and `duration` (the cost stub I4 replaces), `effect` (a proc on the target, called as `effect(actor, held, interaction)`), `message_self`/`message_others`, `tags`. Hooks: `applies_to(target)` (is it offered at all, e.g. a behaviour flag), `display_name()`, `duration_for()`, `messages()`, `start_messages()`, `pay_cost()`, `perform()`. Singletons are in `GLOB.interactions_by_type` (`INTERACTION(path)`, `INTERACTION_BY_ID(id)`). Atom types list theirs in `declare_interactions(list/into)`, cached per type by `interaction_candidates()`.
- `resolver.dm`: `interactions_for(actor, target, held, modifiers)` returns a `/datum/interaction_resolution` (`available`, sorted by priority and stable; `blocked`, interaction -> reason). The actor's adapter filters with `allows_interaction()`: ghosts get nothing, the AI only `INTERACTION_TAG_REMOTE` (I3 widens both). `try_interaction()` runs the best for an action; a tie opens the Menu; if nothing answers it returns null and the caller falls back to the legacy handler.
- Where Use reaches it: the six atom-level `*_act` procs end in `interaction_tool_act()`, so tool interactions run after any subtype `*_act` override that calls `..()` (the type-specific legacy code keeps priority until I7 converts it). When the interaction the player meant is blocked (right tool, wrong state), they are told why and the click stops there instead of falling through to `attackby`. `item_interaction()` then tries tool-less interactions with an item in hand, and the hands adapter tries empty-handed ones before `UnarmedAttack`. Alternate tries the resolver before `click_alt`. Category keys use `try_interaction_category()`.
- `menu.dm`: the Menu (`InteractionMenu.tsx`). Right-click now always reaches the router; bound to Menu it opens this panel, which also lists the target's legacy verbs and the popup's mob actions (Examine, Pull, Point) so nothing is lost with the native popup. The `interaction_menu` keybinding (`.input-menu`) is unbound by default.
- `presentation.dm`: `interaction_keys()`, the examine "Interactions" section (`interaction_examine_lines()`, added by `examinate`) and screentips (`interaction_screentip_text()`, a per-client screen object refreshed on hover when the hovered atom or held item changes; the `screentips` preference, on by default, turns hover tracking on).
- First converted domain: Maintainable (`code/game/machinery/machinery_maintenance.dm`). `maintenance_flags` stays as the behaviour's per-type declaration (a type var costs nothing per instance); the four `/obj/machinery/*_act` procs are gone. The freezer and heater `description_info` maintenance hints are deleted; the snapshot test keeps them from coming back on Maintainable types.
- Tests: `code/modules/unit_tests/dq_interaction_tests.dm` (a test per definition, resolver ordering and ties, snapshots, the Menu data, examine lines, screentips, and Use end to end through the router).

## 8. Examine and screentips

- Examine gets a generated "Interactions" section: what you can do now, with its keys, and what you can't, with why. The 397 hand-written `description_info` strings are deleted as each type converts, so hints can't drift from behaviour.
- Screentips show the Use and Alternate interactions for the hovered target and the held item, from the same resolver. They update only when the hovered atom or the held item changes.

## 9. Tools

**`use_tool(actor, tool, target, interaction)`** is the one pipeline. It:
1. checks tool quality and tier;
2. checks fuel or charge;
3. plays the tool's sound;
4. runs `do_after`, scaled by the tool speed and a skill factor, so skills can be added later;
5. consumes resources;
6. sends generated messages.

**What goes away**
- the hand-written sound, `do_after` and fuel code at 155 tool sites;
- the deprecated `is_screwdriver()` helpers, and about 126 `istype(W, /obj/item/tool…)` checks.

**Tool qualities**
- `tool_qualities` and `has_tool_quality()` stay as the identity model.
- All 20 `TOOL_*` qualities route through interactions. Today `tool_act` routes only 6.

**As built (I4).** Code: `code/datums/interactions/tools.dm`.
- `use_tool(actor, tool, target, interaction, delay, quality, tier, amount, volume, message_self, message_others, extra_checks, silent)` returns TRUE when the tool was used. With an `interaction` it reads `tool`, `tool_tier`, `tool_amount`, `tool_volume` and `start_messages()` from it and times itself with `duration_for()`; I2's `pay_cost()` is now just `use_tool(actor, held, target, src)`. Hand-written sites pass `delay` (unscaled, exactly what they used to multiply by `toolspeed`), `quality`, `amount` and `volume` as named arguments.
- The steps: `tool_quality_failure()` (quality and `dq_tool_tier()`); `tool_start_check()` (a welder must be lit and hold `amount`, and checks the user's eyes; a stack must hold `amount`); the tool's `usesound`; the start messages; `do_after` for `tool_delay()` = delay × `toolspeed` × `tool_skill_factor()` (a stub returning 1); a re-check of the tool; `tool_use_resources()` (a welder burns `amount` through `remove_fuel()`, so an electric welder still pays its `charge_cost`; a stack `use()`s it). Items that lend a welder (`get_welder()`) forward both hooks. `get_multitool()` is the multitool counterpart of `get_welder()`, for sites that read the buffer.
- Timings are unchanged at every converted site. One deliberate difference: fuel is burned when the job completes, so an interrupted job no longer wastes it (it used to be paid up front at some sites).
- `tool_act` now sends every quality with no focused hook (the 14 besides screwdriver, crowbar, wrench, wirecutter, multitool and welder) to `interaction_tool_act()`, so all 20 reach interactions.
- The `*_act` procs that handed the tool back to `attackby(W, user, TOOL_X)` are gone: their branches moved into the hooks, on girders, door and windoor assemblies, machine frames, AI cores, the nuke, turrets and turret frames, and the item and gun cases (bodybags, tanks, traps, grave markers, armour inserts, voidsuits, crossbows, cannon and coilgun frames, modular, magnetic and kinetic guns). The deprecated `is_screwdriver()`-style helpers are deleted, and `istype` checks on tool types became quality checks.
- Lint (`tools/ci/check_grep.sh`): no `*_act` that calls `attackby` (the `focused_tool_stage` vehicle and secbot assemblies are allowlisted for I5), no `istype` on `/obj/item/tool`, `weldingtool` or `multitool` outside an allowlist of type-specific and not-yet-owned files, and no `is_<tool>()` calls.
- Tests: `code/modules/unit_tests/dq_tool_tests.dm`. `GLOB.dq_tool_last_use` (unit tests only) records each call's unscaled delay, quality, amount and volume, so parity tests assert the timings with a zero-speed tool.
- Left for I5: the `focused_tool_stage` machines (walls, floors, mechs and wreckage, mech and fighter chassis, vehicle and secbot assemblies) still bounce through `run_focused_tool()`, and walls keep their hand-written waits. Left for I7: sites whose wait isn't a plain `delay × toolspeed` (the microwave divides by it, the SMES repair, the generator screwdriver, turret salvage, the girder plasma cutter), bot pAI removal (next to I3's `attack_ai` code), and anything in surgery, organs, nanopaste and resleeving implants, which belong to the body rewrite.

## 10. Construction graphs

**The graph.** Machines, frames, walls, girders, windows, mechs and vehicles declare construction graphs:
- **States:** frame, wired, board installed, panel closed, and so on.
- **Edges:** interactions with tool requirements and costs.

The resolver shows the next steps, and examine explains them ("Next: weld the frame, needs a welder").

**Deleted**
- the `focused_tool_stage` and `run_focused_tool` state machines (walls, floors, mecha, mecha wreckage, vehicle construction, secbot);
- the 68 `*_act` handlers that bounce back into `attackby`.

## 11. Wires

**Hacking state**
- Wire state becomes a bitmask on the holder: which wires are cut or pulsed. It is zero, and costs nothing, until someone touches it.
- Wire definitions and colours are per type and read-only. Per-round randomization lives in a per-type table, and per-instance randomization is stored as a delta.
- Attached signalers sit in an external slot on the panel.

**Effects**
- The wires UI is built from the definitions plus the bitmask. The ~2,500 holders nobody opens get no wires datum at all.
- This also fixes B7, where changing one machine's colours changed them for its whole type.

## 12. Combat mode

- Intents are replaced by a combat mode toggle, which is a mob action, plus choosing an interaction.
- With combat mode on, attack interactions take priority on Use.
- The 211 `a_intent ==` gates become interaction requirements, or combat-mode checks in the melee swing (`melee_swing.dm`).

## 13. Migration, one domain at a time (I7)

**Order of conversion**
1. machinery;
2. structures;
3. items;
4. mobs;
5. turfs.

**What each domain converts**
- `attackby`, `attack_hand`, `attack_self`, `click_alt`, `MouseDrop_T` and object verbs.
- The domain's `description_info` strings are deleted.
- Its interaction snapshot is recorded.

**Order within the plan**
- The tool pipeline (I4) and construction graphs (I5) come first.
- Legacy procs are deleted in each domain as it converts. Once every domain is done, the fallback to `attackby` is removed.

## 14. Tests and lint

**Tests**
- **Interaction snapshots.** For each type, the resolved list for a standard set of actors and held items is recorded, and changes show up in review.
- Every interaction definition has a test.
- Every binding default has a test.

**Lint**
- No forwarding `attack_ai`/`attack_robot`/`attack_ghost` overrides (I3).
- No `*_act` that calls `attackby` (I4).
- No new `attackby`, `attack_hand` or `attack_self` overrides in domains that have converted (I7).
- No `description_info` in converted domains (I2).

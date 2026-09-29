# Generic systems (wave "sys")

Status: **design, authoritative for the API.** Branch `rewrite/sys`. Read
[om_in_10_minutes.md](om_in_10_minutes.md), [declarative_lifecycle.md](declarative_lifecycle.md),
[caching.md](caching.md) and [interactions.md](interactions.md) first. References (handles,
relations, rosters) belong to the ownership rewrite (`rewrite/own`, [ownership.md](ownership.md));
nothing here designs a reference kind.

Twenty generic systems replace twenty hand-rolled patterns. Each one has:

- a declaration (a macro next to the type, evaluated once per type into the `lifecycle_decls`
  table or a `TYPE_TABLE`, never per instance);
- a runtime in `code/datums/sys/<system>.dm`, defines in `code/__defines/sys_<system>.dm`;
- a focused test `code/modules/unit_tests/dq_sys_<system>_tests.dm`;
- a lint module `tools/ci/sys_rules/<system>.py` run by `tools/ci/sys_lint.py` (fingerprint
  ratchet in `tools/ci/sys_baseline/<system>.txt`, shrink-only, target 0).
  `// ALLOW(sys_<rule>): <reason>` keeps a site.

No system keeps the old pattern alive as an alias. When a system lands, its sites are converted
and the old proc/var is deleted in the same wave.

Dependency order: **2 (fields) → 1 (appearance), 5 (periodic), 3 (UI) → everything else.**
Numbering below follows the audit.

---

## 2. Core state as declared fields

```dm
OM_FIELD(/obj/machinery, on, FALSE, CHANGE_MACHINE_SETTINGS)
OM_FLAG_FIELD(/obj/machinery, stat, 0, CHANGE_MACHINE_BROKEN|CHANGE_MACHINE_POWER)
OM_DERIVE_FIELD(/obj/machinery, operable, CHANGE_MACHINE_BROKEN|CHANGE_MACHINE_POWER)
```

- `OM_FLAG_FIELD(T, F, D, C)` declares a bitfield: generates `set_F(v)`, `F_add(bits)`,
  `F_remove(bits)` and `has_F(bits)`, each raising `C` only on an actual change. Per-bit channels
  are allowed with `OM_FLAG_FIELD_BITS(T, F, D, list(BROKEN = CHANGE_MACHINE_BROKEN, NOPOWER =
  CHANGE_MACHINE_POWER, ...))`.
- Core fields declared on their natural roots: `active`, `state`, `anchored` (atom/movable,
  wraps `set_anchored`), `locked`, `on`, `density` (wraps `set_density`), `mode`, `emagged`,
  `stat` (machinery; mobs keep `set_stat`, which already is a setter).
- `operable` is a derived field: `!(stat & (NOPOWER|BROKEN|MAINT|EMPED))` unless
  `interact_offline`. It replaces every `stat & (NOPOWER|BROKEN)` read (`inoperable()`,
  `is_operational()` go away; `operable()` is the one reader).
- **Power draw per state:** `POWER_DRAW(type, list(STATE_IDLE = 10, STATE_ACTIVE = 500))` keyed on
  the `use_power` field; `update_use_power()` calls disappear, the draw follows the field.
- Lint `sys_stat_bits`: raw `stat & (`, `stat |=`, `stat &= ~` outside the field runtime.
  `sys_field_write`: direct writes to a core field (`on = `, `locked = `...) outside its setter
  (extends `field_write_lint.py`).

**As built (rewrite/sys-fields).**

- Macros (`code/__defines/om.dm`): `OM_FLAG_FIELD(T, F, D, C)`; `OM_FLAG_FIELD_BITS(T, F, D, ALL,
  list("[BIT]" = CHANNEL, ...))` (text keys; `ALL` is the registered union; a write raises only
  the changed bits' channels via `om_flag_channels()`); `OM_FIELD_SETTER(T, F, C)` registers an
  existing var whose hand-written `set_F()` is the setter (register it again on a family root to
  add that family's channel; `fields_of()` ORs them); `OM_DERIVE_FIELD(T, F, C)` registers a
  read-only field computed by `T/proc/F()` that changes with `C` (`om_set()` on it crashes).
- Declarations: `code/game/machinery/machinery_fields.dm`. On `/obj/machinery`: `on`, `active`,
  `state`, `mode`, `emagged` (CHANGE_MACHINE_SETTINGS), `locked` (CHANGE_MACHINE_MODE), `stat`
  (bits: BROKEN/MAINT/EMPED -> CHANGE_MACHINE_BROKEN, NOPOWER/POWEROFF -> CHANGE_MACHINE_POWER),
  derived `operable`. `anchored` (set_anchored; /obj/machinery CHANGE_MACHINE_ANCHORED, /mob
  CHANGE_MOB_CAN_MOVE), `density` (set_density; /obj/machinery CHANGE_MACHINE_SETTINGS) and
  `use_power` (set_use_power) are OM_FIELD_SETTER registrations. `/obj/vehicle` keeps its own
  `stat` as an OM_FLAG_FIELD. Items' same-named vars (flashlight `on`, ...) are unrelated vars and
  out of scope. Subtype `var/on = ...` redeclarations became plain overrides; colliding procs were
  renamed (`set_breaker_on`, `set_gravity_state`, `set_pump_on`) or made overrides (APC
  `set_locked`, readylight `set_state`); the verdigris binding generator emits an override when an
  OM_FIELD already declares `set_F` (binary pump `set_on`, APC `set_active` stay Rust-backed).
- `operable(additional_flags = 0)` = `!(stat & (MACHINE_INOPERABLE_FLAGS | additional_flags))`
  (NOPOWER|BROKEN|MAINT|EMPED). **Refinement:** `interact_offline` is not folded in; it stays a
  UI-reach rule in `tgui_status()`/`CanUseTopic()`. Single conditions read `has_stat(BITS)`;
  "anything wrong" is `has_stat(MACHINE_STAT_ANY)`. `inoperable()` is deleted. `power_change()`
  returns TRUE when NOPOWER changed and every override propagates it (`. = ..()`), which replaced
  the `var/old_stat = stat ... if(old_stat != stat)` snapshots.
- **Power draw refinement:** the type-body `idle_power_usage` / `active_power_usage` rows are the
  per-state declaration (a `POWER_DRAW()` macro would restate them); `update_use_power()` became
  the field setter `set_use_power()`, which moves the area tally, so the draw follows the field
  and the former direct `use_power =` writes (which skipped the tally) go through it.
- Lint (`tools/ci/sys_rules/fields.py`, all 0): `stat_bits` (any bare `stat` in a machine or
  vehicle proc, `x.stat` with a bit operator or a machine/vehicle-typed receiver), `stat_helper`
  (`inoperable(` / `is_operational(`), `field_write` (direct writes to the core fields, sharing
  `field_write_lint.py`, which is also api_lints `field_write` including unit tests).
  `field_write_lint.py` now resolves DM's implicit parents (/obj, /mob -> /atom/movable), untyped
  locals and parameters, named arguments/list entries, and typed member chains (`a.b.c.on`,
  `GLOB.x.on`). Limit: a read `x.stat` (no bit operator) through an untyped receiver is not
  flagged, since it can't be told from a mob's `stat`.
- Test: `code/modules/unit_tests/dq_sys_fields_tests.dm`.

## 1. Appearance keyed on declared state

Extends `DECLARE_APPEARANCE` (layers keyed on one var) into the one way to draw state.

```dm
APPEARANCE_TEMPLATE(/obj/machinery/recharger, "recharger[on][operable]")      // icon_state template over fields
APPEARANCE_LEVEL(/obj/machinery/recharger, "charge_percent", 5, "recharger-charge%d")  // numeric level, N steps
APPEARANCE_EMISSIVE(/obj/machinery/recharger, "on", list("1" = "recharger-glow"))       // emissive overlay, keyed
APPEARANCE_SLOT(/obj/machinery/recharger, SLOT_CHARGING, "recharger-cell")              // overlay while a slot is used
DECLARE_APPEARANCE(/obj/machinery/recharger, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("panel"))))
```

- Every row is a field read; the combination key is built from the field values and looked up in
  `DECLARE_SHARED_CACHE(decl_appearance, ...)` (interned).
- **Refresh is automatic:** every OM_FIELD a layer names gets its channel added to the type's
  appearance watch mask; the presentation lane re-applies on a raise, coalesced per frame.
  Slots raise `CHANGE_CONTENTS`. So `update_icon()` calls after a setter are deleted.
- `update_icon()` overrides remain only where a site is genuinely procedural (contents-dependent
  compositing, generated sprites); they carry `// ALLOW(sys_update_icon): <reason>`.
- `power_change()` overrides whose body is `..(); update_icon()` are deleted (power is a field).
- Mob icon caches (human, limb, tail) move from `/icon` blending to `mutable_appearance` stacks
  cached by `CACHED_KEY(..., key)` wherever the result does not need pixel-level blending.
- Lint `sys_update_icon_call` (manual `update_icon()` after a field setter or in a setter-owning
  proc) and `sys_update_icon_override` (override without ALLOW).

## 5. Periodic work declared by state

```dm
DECLARE_PERIODIC_WHILE(/obj/machinery/recharger, PERIODIC_SECOND, "charging")   // runs while field truthy
DECLARE_REPEAT(/obj/effect/beam, 2 SECONDS, PROC_REF(pulse), "active")          // om_after loop, declared
```

- `DECLARE_PERIODIC_WHILE(type, cadence, field)`: the field's channel starts and stops the
  periodic task (`om_task_periodic` / `_stop`). The body (`periodic_step` / `machine_step`) never
  guards on the field and never returns `PROCESS_KILL` for it. Cadence is a periodic pipeline or
  `MACHINE_PIPELINE`.
- Multiple fields: `DECLARE_PERIODIC_WHILE_ALL(type, cadence, list("on", "operable"))`.
- `DECLARE_REPEAT(type, delay, proc, field)`: a self-re-arming `om_after` loop replaced by a
  declared repeat that is armed while `field` is truthy (field `null` = always while
  materialized). The proc returns nothing; returning `REPEAT_STOP` ends it early.
- Lint `sys_periodic_guard` (`if(!field) return PROCESS_KILL` as a body's first statement),
  `sys_om_after_rearm` (an `om_after(src, ..., PROC_REF(p))` inside `p`).

## 3. Declared UI model

```dm
DECLARE_UI(/obj/machinery/recharger, "Recharger", tgui_default_state)
UI_DATA(/obj/machinery/recharger, "on", "charge_percent", "slot:SLOT_CHARGING")
UI_ACT(/obj/machinery/recharger, "toggle", PROC_REF(ui_toggle))
UI_ACT(/obj/machinery/recharger, "set_rate", PROC_REF(ui_set_rate), UI_ARG_NUM("rate", 0, 100))
UI_ACT(/obj/machinery/recharger, "select", PROC_REF(ui_select), UI_ARG_CHOICE("id", "valid_ids"))
```

- `DECLARE_UI(type, interface, state)` generates the `tgui_interact()` (open/reuse/bind) that
  311 overrides hand-wrote. It binds the window with `om_ui_bind(ui, src, mask)` where the mask is
  the union of the `UI_DATA` fields' channels: pushes are change-driven.
- `UI_DATA(type, fields...)`: fields exported by name; `"slot:X"` exports a slot fragment (#4);
  `"proc:x"` calls a getter for derived data. A remaining `tgui_data()` override may add to the
  generated one with `. = ..()`.
- `UI_ACT(type, action, proc, args...)`: each action row carries typed args
  (`UI_ARG_NUM(name, lo, hi)`, `UI_ARG_INT`, `UI_ARG_TEXT(name, maxlen)`, `UI_ARG_BOOL`,
  `UI_ARG_CHOICE(name, list_var_or_proc)`, `UI_ARG_REF(name, list_var_or_proc)` = locate-in).
  Parsing and clamping happen centrally; the proc receives `(mob/user, list/args)` with typed,
  validated values, and is not called when validation fails. This removes raw `text2num(params[...])`.
- Generated TS types: `tools/build/lib/ui_types.ts` reads the `UI_DATA`/`UI_ACT` tables from a
  `-DUI_TYPES_DUMP` boot and writes `tgui/packages/tgui/interfaces/generated/<Interface>.d.ts`.
- Lint `sys_tgui_interact_boilerplate`, `sys_text2num_params` (in `tgui_act`/`Topic`).

## 4. Slot-generated interactions, examine lines and UI fragments

```dm
SLOT_INTERACTIONS(/obj/machinery/recharger, SLOT_CHARGING, list(/obj/item/cell, /obj/item/gun/energy), \
	SLOT_INSERT_MSG("You insert %ITEM% into %SRC%."), SLOT_REQUIRE(REQ_FIELD("operable")))
```

- For a declared slot the system generates Insert (`INTERACT_INSERT` for the accepted types, with
  the full refusal "%SRC% already holds %ITEM%" generated from capacity), Eject (`INTERACT_ALT`
  and a UI act `eject_<slot>`), the examine line ("It holds X." / "It is empty."), and a UI data
  fragment (`slot:X` → `{name, icon, ...}`).
- Confirmations and refusals come from message templates (#15).
- Lint `sys_slot_refusal` (hand-written "already has"/"is full"/"is empty" strings next to a
  declared slot).

## 6. REFUSE_IF lifted into requirements

```dm
INTERACT_USE("Toggle", PROC_REF(toggle), REQ_FIELD("operable"), REQ_FIELD_NOT("locked", "it's locked"))
```

- New clauses: `REQ_FIELD(name[, reason])`, `REQ_FIELD_NOT`, `REQ_FIELD_EQ(name, v)`,
  `REQ_ACCESS` (target's `req_access` against the actor), `REQ_NOT_EMAGGED`, `REQ_ANCHORED`,
  `REQ_PANEL(open)`. Reasons are generated from the field name when omitted.
- `REFUSE_IF(cond, msg)` inside an effect proc is the legacy form being removed: each guard at
  the head of an interaction effect moves to a requirement, so the Menu shows why.
- Lint `sys_inline_refusal` (an `if(...) { to_chat(user, span_warning(...)); return }` block at
  the head of an interaction effect proc).

## 7. Per-type constant tables

```dm
TYPE_TABLE_DECLARE(/obj/machinery/vending, products, null)          // once per name, on the root
TYPE_TABLE(/obj/machinery/vending/coffee, products, list(/obj/item/soap = 5, ...))
var/list/p = TYPE_TABLE_GET(src, products)       // shared, read-only
var/list/mine = TYPE_TABLE_COPY(src, products)   // a private copy
var/list/r = COW_READ(src, products)             // the instance var if set, else the table
COW_LIST(src, products)[/obj/item/soap] = 3      // per-instance copy on first write
```

- `TYPE_TABLE(type, name, value)` declares a per-type constant, inherited and overridable by
  subtype. The value is any expression (a literal or a builder call); it is evaluated once per
  concrete type on first read and stored in the shared cache `tt_<name>` keyed by type path, so
  a read is one list index and nothing is allocated per instance or per call.
- As built: the root needs `TYPE_TABLE_DECLARE(root, name, default)` (it declares the hidden
  `_tt_<name>()` proc and the cache). Table names are global; a clash is a compile error.
- `COW_LIST(instance, name)`: copy-on-write; the instance var is null until written (a map
  varedit sets it, and `COW_READ` then prefers it).
- Values are shared: test builds runtime on a mutation (the shared-cache guard).
- Procs that allocate the same constant list per call become `TYPE_TABLE` or a module constant
  (`GLOBAL_LIST_INIT`, or a proc-free `var/static` table read directly).
- Global tables that must be built lazily (they need registries, subsystems or other globals)
  use `GLOBAL_TABLE(name, GLOBAL_PROC_REF(builder))` + `GLOBAL_TABLE_GET(name)` (a one-entry
  shared cache; `GLOBAL_TABLE_RESET(name)` rebuilds). Constant literal global tables are plain
  `GLOBAL_LIST_INIT`.
- As built (wave result): 139 declared tables with 1158 per-type overrides (the item
  `hold/suit_storage/fit/equip_constraint()` procs became the `*_spec` tables, `get_ai_behaviors`,
  `get_stages`, the cargo profiles, preference choices, ...). Before: 273 static getters, 437
  constant allocations, 47 "not worth it" annotations (first lint shape); after: 0 of each with
  the full-shape lint. Remaining keeps are `ALLOW(sys_*)` with reasons: loadout default
  metadata (owned by the player's preferences), the armour soak scratch buffer, the extrapolator
  result container, a one-shot builder's input rows, and the object model's
  `declared_cache_vars()` hook (owned by the refs lead).
- Lint (`tools/ci/sys_rules/tables.py`): `sys_static_getter` (a proc returning a proc-local
  `var/static/list` in any form, or a per-type override returning a `GLOB` list),
  `sys_const_list_alloc` (a non-empty constant `list(...)` returned per call from a proc whose
  every value-returning path returns a constant literal, one-line `if(x) return list(...)`
  branches included; or a local constant list that is only read), `sys_not_worth_it_annotation`
  (the old instance_list "not worth it" keep). Code in `/* */` blocks is skipped.

## 8. One loot system

```dm
DECLARE_LOOT(/obj/random/toolbox, LOOT_TABLE(/obj/item/storage/toolbox/mechanical = 3, \
	/obj/item/storage/toolbox/electrical = 2), LOOT_COUNT(1), LOOT_CHANCE(100))
```

- A loot table is a weighted `TYPE_TABLE`; nested tables by path (`LOOT_REF(/datum/loot/maint)`).
- The roll happens at materialize with a seeded RNG (`GLOB.loot_seed ^ hash(x,y,z,type)`), so a
  map's loot is reproducible per round seed. `/obj/random` never becomes a live atom (see #9).
- Replaces `item_to_spawn()` overrides and `code/datums/loot_tables/`.
- Lint `sys_item_to_spawn`, `sys_loot_table_datum`.

## 9. Map-time resolvers

```dm
MAP_RESOLVER(/obj/effect/floor_decal, /proc/resolve_decal)          // apply to the turf, no atom
MAP_RESOLVER(/obj/random, /proc/resolve_loot)                         // roll DECLARE_LOOT, spawn result
MAP_RESOLVER(/obj/effect/wingrille_spawn, /proc/resolve_wingrille)
MAP_RESOLVER(/obj/effect/landmark, /proc/resolve_landmark)            // record coords in a registry
```

- The map loader consults the resolver table per path before instancing: the resolver receives
  `(turf, path, varedits)` and does its work (overlay on the turf, spawn results, registry row).
  No atom is created, initialized or qdel'd.
- Measured with `tools/build/build.sh bench --scenario=boot` before and after.
- Lint `sys_init_qdel` (an `Initialize()` that ends in `return INITIALIZE_HINT_QDEL` on a
  resolvable family).

## 10. Declared examine lines

```dm
EXAMINE_LINE(/obj/machinery/recharger, "on", list("1" = "It is charging.", "0" = "It is idle."))
EXAMINE_SLOT(/obj/machinery/recharger, SLOT_CHARGING)
EXAMINE_REAGENTS(/obj/item/reagent_containers/glass)
EXAMINE_CHARGE(/obj/item/gun/energy, "power_supply")
EXAMINE_IF(/obj/machinery, "panel_open", "The maintenance panel is open.")
```

- Lines are built from fields, in declaration order, after the base description.
- Lint `sys_examine_override` (override without ALLOW).

## 11. Typed handle fields

Superseded by the ownership rewrite's relations. This wave only verifies: no text-handle var
survives the merge of `rewrite/own` (lint `sys_text_handle`, grep for `om_handle(`/`om_resolve(`
outside the relations runtime → 0).

## 12. Declared damage reactions

```dm
DAMAGE_REACTION(/obj/machinery/camera, DAMAGE_EMP, PROC_REF(emp_disable_view))
REFLECTS(/obj/structure/reflector, list(BRUTE, BURN), 100)
EMP_DISABLE(/obj/machinery/camera, 90 SECONDS, "emped")        // sets field, expiry restores
```

- Hooks on the damage-packet path (`receive_damage()`), by damage kind and flag. Replaces entry
  point overrides (`bullet_act`, `emp_act`, `ex_act`, `fire_act`, `blob_act`) that do a fixed thing.
- Lint `sys_entry_override`.

## 13. Emag as an interaction

```dm
DECLARE_EMAG(/obj/machinery/vending, PROC_REF(on_emagged), "You short out the product lock.")
```

- Generates an `INTERACT_INSERT(/obj/item/card/emag, ...)` with `REQ_NOT_EMAGGED`, sets the
  `emagged` field, consumes an emag use, shows the message template. Returns via the field.
- Lint `sys_emag_act` (overrides → 0; `emag_act` is deleted).

## 14. Keyed relation auto-link and rosters

Built on the ownership rewrite's relation API. `AUTO_LINK(type, relation, partner_type, key_var)`
links at materialize to the partner with the same key (`id_tag`, `frequency`), replacing
hand-written `for(var/obj/machinery/x in machines) if(x.id == id)` loops. `ROSTER(type, relation)`
exposes the linked set. Coverage: whatever `rewrite/own` does not already declare.

## 15. Message templates

```dm
act_message(user, target, MSG_SELF("You pry %T% open."), MSG_OTHERS("%U% pries %T% open."), \
	MSG_BLIND("You hear prying."), range = 7)
act_message_t(user, target, /datum/msg/pry)                          // declared template
```

- Tokens: `%U%` user, `%T%` target, `%I%` item, `%THEY%`/`%THEIR%` pronouns of the user.
- `/datum/msg/x` templates are DEF singletons; interactions reference them via `feedback`.
- Replaces `user.visible_message(self, others)` pairs and interaction `message_self/others`.
- Lint `sys_visible_pair`.

As built (rewrite/sys-messages):
- Runtime `code/modules/messages/act_message.dm`, defines `code/__defines/messages.dm`.
  `act_message(user, target, self, others, blind, range = world.view, item, exclude)`; a non-mob
  user (a machine acting) has only the others/blind lines. `MSG_SELF/MSG_OTHERS/MSG_BLIND` are
  readability wrappers; callers keep their own span_*() wrapping.
- Tokens render `	he [x]` (`%U%`, `%T%`, `%I%`), capitalised when they open a line (after
  leading tags). Pronoun tokens: `%THEY% %THEM% %THEIR% %THEIRS% %THEMSELVES% %THEYRE% %THEYVE%
  %S% %ES%` and capitalised `%They% %Them% %Their% %Theyre%`.
- `/datum/msg` (a DEF type in state_schema_lint): `self`, `others`, `blind`, `span_class`
  (default "notice"), `range`; `texts(user, target, item)` may be overridden for wording that
  depends on the call. `msg_def(type)` returns the singleton. One-line declarations:
  `MSG_DEF(name, self, others)`, `MSG_DEF_SELF(name, self)`.
- Interactions: `feedback` / `start_feedback` (msg types, picked by `feedback_for()` /
  `start_feedback_for()` before the effect runs) replace `message_self/message_others`,
  `messages()`, `start_messages()`, `fill_message()` and construction `start_self/start_others`.
  Templates mirror the interaction path: `/datum/msg/interaction/...` and
  `/datum/msg/start/interaction/...`. `use_tool()` takes `start_feedback` or inline
  `start_self/start_others` (renamed from message_self/message_others).
- Lint `sys_visible_pair` (tools/ci/sys_rules/messages.py): a visible_message call outside the
  runtime that passes a mob self message, interpolates the actor (`[R]` for a mob receiver R,
  `[src]` in a bare call in a /mob proc, `[user]`/`[usr]`), or follows `to_chat(R, ...)`.
  Named arguments are read by name (`self_message =` is the self line; `range =` is not), and
  `[R.name]` / `[R.real_name]` count as naming the actor.
- Migration (rewrite/msg2): every legacy site converted, baseline empty, no ALLOW. An atom
  emitting a line about its user (`visible_message("[user] ...")` in an /obj proc) became
  `act_message(user, src, others = ...)` (the line now originates at the user, no eye rune), or
  `act_message(src, user, ...)` where the user may be null. Obj calls that passed a self line
  as the blind argument (`visible_message(others, "You ...")`) now show it to the user.
  Tokens render `	he`, so proper names are unchanged and objects gain "the".
- Player text is literal: wrap it in `MSG_LITERAL()` (emotes, ghost emotes, narrate, package
  labels). It swaps `%` for a private-use mark that `msg_fill()` restores after filling, so a typed
  `%U%` shows as typed. Token names (`msg_name()`) are marked the same way, so a character named
  `%T%` stays literal. Only pass MSG_LITERAL text to act_message (the fill is what unmarks it).

## 16. Sound and effect sets

```dm
SOUND_SET(SFX_WELD, list('sound/items/welder.ogg', 'sound/items/welder2.ogg'), 50, TRUE)
play_sfx(src, SFX_WELD)
fx_sparks(src, 3)                   // pooled, replaces the new/set_up/start triple
```

- `SOUND_SET(id, files, volume, vary[, extrarange, falloff])` rows; `play_sfx(atom, id,
  volume_mult = 1, ...)`. Literal `playsound(x, 'file', ...)` calls become set ids.
- `fx_sparks(atom, n, cardinals = TRUE)` uses a pooled spark system.
- Lint `sys_literal_playsound`, `sys_literal_sound_var`, `sys_sfx_string_key`, `sys_spark_triple`.

As built:
- Ids are `#define SFX_* "key"` in `code/__defines/sfx.dm`; the rows are in
  `/proc/build_sound_sets()` in `code/game/sound_sets.dm` (a define file cannot hold statements).
  The table was generated from the literal call sites: one set per distinct file or literal
  `pick()` list, its defaults the most common volume/vary/extrarange/falloff at those sites.
- The old `get_sfx()` string keys ("sparks", "punch", "shatter", ...) are rows too, with their
  ids keeping the old key strings, so `get_sfx(id)` and string-keyed `hitsound` vars keep
  working. `get_sfx()` is now just a table lookup. There is one registry.
- `play_sfx(source, id, volume_mult = 1, volume = null, vary = null, extrarange = null,
  falloff = null, is_global, frequency, channel, pressure_affected, ignore_walls, preference,
  volume_channel)`: `volume` overrides the set volume outright (used where a site's volume was an
  expression); null `vary`/`extrarange`/`falloff` take the set's. It picks one file and calls
  `playsound()`, which stays the core for non-literal sounds (`usesound`, `hitsound` vars, ...).
- Sound vars and lists hold set ids too: every literal file assigned to a var/list/global that
  feeds `playsound()`/`playsound_local()`/`play_sfx()`/`get_sfx()` (`hitsound`, `usesound`,
  `drop_sound`, `fire_sound`, `apply_sounds`, label-to-sound maps such as `device_ringtones`,
  ...) was replaced by an id (a literal `list()`/`pick()` became a multi-file set and its
  `pick()` consumer was dropped). `playsound()` and `playsound_local()` resolve ids through
  `get_sfx()`, so non-literal call sites need no change; the few sinks that build a `/sound`
  themselves (`looping_sound.play()`, `user << activation_sound`) call `get_sfx()` first.
- Lint (`tools/ci/sys_rules/sfx.py`): `literal_playsound` (a literal anywhere in the call,
  pick lists and ternaries included), `literal_sound_var` (a literal assigned to a fed name,
  multi-line lists and `GLOBAL_LIST_INIT` included), `sfx_string_key` (a bare named-set key in a
  sound call or assigned to a fed var) and `spark_triple` (any `spark_spread` use).
- `fx_sparks()` (`effect_system.dm`) throws at most 10 sparks per call and keeps one world-wide
  live-spark budget (100) counted by the spark objects themselves; the `spark_spread` datum is
  deleted, including the persistent `spark_system` vars that were attached to items.

## 17. Expiry

```dm
EXPIRY_DECLARE(stun_until)                          // var/stun_until = 0 (EXPIRY_TMP_DECLARE: var/tmp)
EXPIRY_SET(src, stun_until, 5 SECONDS, CLOCK_WORLD)
EXPIRY_EXTEND(src, stun_until, 5 SECONDS, CLOCK_WORLD)  // never shortens
EXPIRY_LEFT(src, stun_until, CLOCK_WORLD)           // deciseconds left, 0 when expired
EXPIRY_ACTIVE(src, stun_until, CLOCK_WORLD)         // EXPIRY_EXPIRED is the negation
EXPIRY_CLEAR(src, stun_until)
EXPIRY_STAMP(src, started_at, CLOCK_WORLD)          // record now
ELAPSED(src, started_at, CLOCK_WORLD)               // clock-aware elapsed
// raw points (list slots, locals, records): EXPIRY_AT, ELAPSED_SINCE, LEFT_UNTIL, BEFORE
```

- Clock-aware. **As built:** DM has no per-var metadata, so the clock is passed on every read
  as well as the write (one var, one clock). `CLOCK_WORLD` compiles to `world.time`;
  `CLOCK_OWN` is the datum's OM timer clock (`om_timer_clock()`: bio for living mobs, machine
  for machinery), which follows the domain's rate and stops in stasis/suspension exactly like
  `om_after()` timers (`expiry_clock_now()`, `code/datums/sys/expiry.dm`).
- Distinct from COOLDOWN (a gate); expiry is state that ends. `TIMESTAMP_VAR` is gone
  (became `EXPIRY_DECLARE`). A world.time compare is owned by exactly one lint: a rate limit by
  `tools/ci/cooldown_lint.py`, a recorded time by `sys_world_time_expiry`
  (`tools/ci/sys_rules/expiry.py`, which also counts `world.time - x <cmp>` elapsed compares).
- `EXPIRY_ON_LAPSE(PATH, var, clock, PROC_REF(x))`: a declared hook in the lifecycle table that
  runs when the expiry lapses. It is armed as one `om_after` on the holder by every
  `EXPIRY_SET`/`EXPIRY_EXTEND` and again at materialize, so it fires however the holder was made;
  a holder that materializes with the expiry not running lapses at once. Hooks must be
  idempotent. The guest pass turns red through this, with no poll.
- Lints `sys_world_time_expiry`, `sys_world_time_write` (raw writes, including member writes
  through `EXPIRY_AT`) and `sys_expiry_undeclared` (a macro-used var that isn't `EXPIRY_DECLARE`d): all 0.

## 18. FOR_REAL_CONTENTS

`FOR_REAL_CONTENTS(var/x as anything, A)` iterates materialized direct contents without
resolving the latent generator or materializing entries (non-copying). Lint
`sys_materializing_walk` (`tools/ci/sys_rules/contents.py`) bans `FOR_CONTENTS`, `contents_of`,
`slot_contents`, `slot_item`, `latent_entries`, `get_all_contents`, `latent_materialize(_all)` and the raw
`in contents` / `in X.contents` / `in src` walks inside `tgui_data()` and
`examine()` bodies; latent things are shown from type data (`latent_names()`,
`latent_count()`) and materialized by the action that takes them. A single occupant is read with
`slot_item_real(slot)` (`code/datums/sys/contents.dm`), which never builds the ledger. **As built:** 37 sites fixed,
including `anomaly_harvester.dm` (its `tgui_data` materialized the whole machine every UI tick);
lint at 0.

## 19. Verbs through grants

`om_grant(M, GRANT_ABILITY, /datum/ability/x, source)`: the verb/ability appears while any source
grants it and disappears automatically when the source is removed/destroyed (the contribution
system already drops a destroyed source's holds). Replaces paired `add_verb`/`remove_verb`.
Lint `sys_add_verb_pair`.

## 20. TOPIC_ACTION registry

```dm
TOPIC_ACTION(/datum/admins, "adminplayeropts", PROC_REF(topic_player_opts), TOPIC_REF("adminplayeropts", /mob), TOPIC_RIGHTS(R_ADMIN))
```

- `Topic()` is one core proc: it finds the action by its href key, checks rights, resolves each
  `TOPIC_REF(name, type)` with `locate(ref) in <declared source>` and type check, then calls the
  proc with typed args. The 1,352-line admin topic becomes rows.
- Lint `sys_topic_override`.
- **As built, View Variables namespace.** VV hrefs keep their `_src_=vars` shape. They reach
  `/client/proc/vv_topic(href_list, trusted = FALSE)`, which checks R_VAREDIT and the admin href
  token (`trusted` skips only the token, for server-side tgui callers). It then calls
  `topic_dispatch_vv()`. That tries the `target` datum's `VV_TOPIC_ACTION(type, VV_HK_X,
  PROC_REF(h), specs...)` rows first (these replaced `vv_do_topic()`), then the admin client's
  `VV_ADMIN_TOPIC_ACTION(key, ...)` rows: basic edits, lists, `Vars`, rotate, the body editor.
  Namespaced rows come from `TOPIC_NS_ACTION` and live in their own per-namespace table, so a
  plain `Topic()` href never reaches them. The VV path skips the target's `topic_allowed()`; a
  datum can refuse its VV rows with `vv_topic_allowed(user)`. `TOPIC_REF` also takes a list of
  types, or `null` (whatever `locate()` finds, and the handler validates it). A handler that
  changes what VV shows calls `user.client.debug_variables(src)`; the `datumrefresh` key is gone.

As built (`code/__defines/topic.dm`, `code/datums/topic/topic_dispatch.dm`):

- `TOPIC_ACTION(type, key, PROC_REF(handler), specs...)` links onto `type/topic_actions()` (like
  `DECLARE_REF`); `topic_table()` flattens a type's rows into `GLOB.topic_tables[type]` once, on
  first use. Rows inherit; a subtype row with the same key replaces its parent's.
- Keys: `"key"` matches when the href carries `key`; `"key=value"` matches that exact value and
  is tried first, so `switch(href_list["op"])` chains become one row per value.
- Specs: `TOPIC_REF(name, type[, source])`, `TOPIC_NUM(name)`, `TOPIC_TEXT(name[, maxlen])`,
  `TOPIC_RIGHTS(R_*)`. Sources: `TOPIC_ANY` (istype only; the default except for clients and
  turfs), `TOPIC_IN_WORLD`, `TOPIC_IN_CLIENTS`, `TOPIC_IN_MOBS` (mob registry),
  `TOPIC_IN_CONTENTS`, or `PROC_REF(getter)` on the target returning the list to search. A ref
  that fails is logged (`log_href`) and the handler never runs.
- Handlers are `proc(mob/user, list/args)`: `args[name]` holds the validated value; the raw
  href_list rides in `args[TOPIC_HREF]` only so `topic_ask(user, args, ...)` can re-run the href
  (`om_topic_ask()` unwraps it and re-enters through `topic_dispatch()`).
- Gates: `/datum/proc/topic_allowed(user, href_list)` runs before any row (`/obj` does the
  CanUseTopic check against `topic_state()`, `/datum/admins` the owner and href-token check).
  `/datum/proc/topic_forward()` hands unmatched hrefs to another datum (codex pages to their
  codex, programs to their computer).
- Entry points: `/datum/Topic` is the dispatcher; `/client/Topic` keeps BYOND's transport work
  (rate limits, asset cache, tgui middleware, logging) then dispatches the client's own rows;
  `/world/Topic` keeps its shape (server query strings from world.Export/TGS, not hrefs).
  `topic_dispatch(target, user, href_list)` is callable directly; tgui panels call plain procs
  instead of faking hrefs, or `/datum/admins/proc/topic_internal()` for admin rows.
- Lint `tools/ci/sys_rules/topic.py`: `sys_topic_override` (Topic() overrides),
  `sys_topic_raw_dispatch` (`if`/`switch` on `href_list[...]`, `IF_VV_OPTION`),
  `sys_topic_raw_locate` (`locate(href_list[...])`) and `sys_topic_raw_num`
  (`text2num(href_list[...])`). Transport-level reads in the client entry point and the tgui
  message protocol carry `ALLOW` reasons.

## Hygiene

- "mob: 15 mobs at boot" annotations on non-mob sites are replaced with accurate reasons; the
  36 placeholder `ALLOW(state_ref)` get real reasons or the site is fixed.
- `om_derived` replaces `cached_*` vars; `om_deadline` replaces hand-rolled `world.time`
  deadline checks; construction graphs replace the hand-rolled light, AI core, camera, door
  assembly, emitter, field generator and PA state machines.

As built (rewrite/sys-hygiene; lint `tools/ci/sys_rules/hygiene.py`, all three rules at 0):

- `annotation_boilerplate` flags an `ALLOW(...)` whose reason is placeholder text ("baseline when
  CI was wired", "convert or give a real reason", "15 mobs at boot", "see audit") or names a kind
  (`mob:`, `obj:`, `item:`, `machine:`, `turf:`, `area:`) the site's type is not. The 71 pasted
  mob-count reasons now say what each list is (`d: per-mob X, filled at runtime`, `c: read-only
  per-subtype table`, or the proccall handler's one instance). Of the 36 placeholder
  `ALLOW(state_ref)`: runtime-only vars became `tmp` (overlay images, radio connections, the agent
  card's tgui module, glove special attacks), three stale annotations on already-`tmp` vars were
  dropped, and the rest got real reasons (mostly `owned: ... kept in contents`).
- `cached_var` flags a `cached_*` instance var, its writes and its manual invalidations, unless it
  is a declared cache (`declared_cache_vars()` with a `CACHE_ON_*` rule); a `= null` on a declared
  cache is still flagged (raise the channel with `om_changed()`). Converted: asset URL mappings and
  the overmap skybox image are declared caches cleared by `om_changed(src, CHANGE_EXPLICIT)`;
  preference choices are a shared cache (`preference_choices`); song legacy paths, samples and
  sustain dropoff are read from the instrument / computed (`linear_dropoff_rate()`). Vars that were
  never caches were named for what they hold (panel snapshots, `planned_path`,
  `available_designs`, `parsed_map`, `prototype_components`, `applied_particle_type`, SSair's
  `phase_cost`, `fetched_feedback_link`). `code/modules/tgs/` (vendored DMAPI) is exempt.
- `deadline_poll` reuses `tools/ci/check_deadline_polling.py`, which now scans every periodic body
  (`process()`, `periodic_step()`, `machine_step()`, `service_step()`, OM behaviour `tick()`), and
  also flags the writes that store a polled deadline. Converted to `om_after()` timers: bomb tester
  simulation, escape pod eject, supply beacon drop, anomaly device run, supermatter grenade
  implosion, meteor waves, supply payroll cycle, mob profile dump, artifact analyser completion.
  The rest carry `ALLOW(sys_deadline_poll)` with the reason (rate gates inside continuous work,
  sliding deadlines, state-machine pacing, admin-editable countdowns, and the status-effect /
  guest-pass expiry left to the EXPIRY_* work).

## Rollout

1. Primitives in order (2, 1, 5, 3, then 4, 6, 7, 10, 15, 16, 17, 18, 13, 12, 8, 9, 19, 20, 14),
   each with a focused test and its lint at the current count.
2. Domain migration fanned out to workers (disjoint directories), each lowering the ratchets.
3. Delete old procs (`emag_act`, `item_to_spawn`, loot datums, `inoperable()`, boilerplate
   `tgui_interact`), ratchets to 0, docs and AGENTS.md updated.

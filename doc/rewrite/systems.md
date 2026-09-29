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
OM_DERIVE_FIELD(/obj/machinery, operable, list("stat"), PROC_REF(compute_operable))
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
TYPE_TABLE(/obj/machinery/vending, products, list(/obj/item/soap = 5, ...))
var/list/p = TYPE_TABLE_GET(src, products)       // shared, read-only
COW_LIST(src, products)                           // per-instance copy on first write
```

- `TYPE_TABLE(type, name, value)` declares a per-type constant, inherited and overridable by
  subtype; stored in the `type_tables` shared cache keyed by `(type, name)`. Replaces the 144
  "getter returning a proc-local static list" procs and the "not worth it" instance_list
  annotations.
- `COW_LIST(instance, name)`: copy-on-write; the instance var is null until written.
- Procs that allocate the same constant list per call become `TYPE_TABLE` or a module constant.
- Lint `sys_static_getter`, `sys_const_list_alloc`, and the "not worth it" annotation text.

## 8. One loot system

```dm
DECLARE_LOOT(/obj/random/toolbox, LOOT_TABLE(/obj/item/storage/toolbox/mechanical = 3, \
	/obj/item/storage/toolbox/electrical = 2), LOOT_COUNT(1), LOOT_CHANCE(100))
```

- A loot table is a weighted table; nested tables by path (`LOOT_REF(/loot/maint)`).
- The roll happens at materialize with a seeded RNG (`GLOB.loot_seed ^ hash(x,y,z,type)`), so a
  map's loot is reproducible per round seed. `/obj/random` never becomes a live atom (see #9).
- Replaces `item_to_spawn()` overrides and `code/datums/loot_tables/`.
- Lint `sys_item_to_spawn`, `sys_loot_table_datum`, `sys_random_spawn_list`.

As built (`code/__defines/loot.dm`, `code/datums/loot/loot.dm`):

- `DECLARE_LOOT(PATH, SPECS...)` defines `/datum/loot_decl<PATH>/specs()`; `loot_decl_for(path)`
  builds and caches the declaration of a path or its nearest declared ancestor. A subtype's line
  merges over its parent's: it replaces only the specs it names, and what spawns (`LOOT_TABLE`,
  `LOOT_ALL`, `LOOT_PER_ROUND`) as one unit. Pure tables live under `/loot/...` and are named with
  `LOOT_REF(/loot/...)` (a `/datum/loot_decl` path).
- Specs: `LOOT_TABLE(entries)` (rolled `LOOT_COUNT` times), `LOOT_ALL(entries)` (always),
  `LOOT_CHANCE(percent)`, `LOOT_HOOK(proc)` (`proc(atom/spawned, path, varedits, rng)`, on what the
  declaration spawns itself, e.g. random mob faction/AI setup), `LOOT_PER_ROUND` (the table pick is
  made once per round per spawner type: the themed semi-random mob spawners).
- Entries: a path (`= weight`, default 1); a path with its own declaration or map resolver rolls it
  (nesting: `/obj/random/...` inside a table); a `/turf` path changes the turf; `LOOT_SET(w, ...)`
  spawns a group; `LOOT_SUB(w, ...)` a nested pick; `LOOT_STACK(w, path, amount)`;
  `LOOT_TYPES(w, list_expr)` a computed list (`subtypesof()`), each member weighing `w`.
- Searchable tiers for piles: `LOOT_UNLUCKY`, `LOOT_UNCOMMON(chance, ...)`, `LOOT_RARE(chance, ...)`,
  `LOOT_GAMMA(chance)`, `LOOT_DEPLETION(left, delete)`, `LOOT_REPEAT_SEARCH`, rolled by
  `loot_search(source, L, searched_by, wake_chance)`; a pile names its table in `loot_decl`.
- Seeding: `/datum/loot_rng` (Wichmann-Hill, exact in BYOND floats), seeded by `loot_rng_at()` from
  `GLOB.loot_seed`, the turf's x, y, z and the type's hash; rolls after map load also mix a serial
  so two runtime rolls on one tile differ. Nested rolls share the stream.
- `loot_spawn(path, loc, varedits, rng, direct_out)` is the one entry point (also for code that has
  a path which may be a spawner: contraband packages, falling objects, multi-point spawns).
- Migrated: 212 `item_to_spawn()` overrides (plus 7 by hand: junk, plushies, cutouts, cursed items,
  semi-random mobs, synx, single) across 23 files, the 5 custom `spawn_item()` overrides (random
  mobs, multi-mob packs, outside mobs, catslugs, turf swappers; now hooks), `spawn_nothing_percentage`
  (now `LOOT_CHANCE`), the `/obj/random/fromList` `to_spawn` lists, and all 28 `/datum/loot_table`
  types (`code/datums/loot/tables/`, each complete with its inherited tiers). `item_to_spawn`,
  `spawn_item` on spawners, `get_random_junk_type()`, `/datum/loot_table`, `loot_table_type` and
  `loot_reward()` are deleted.

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
  resolvable family) and `sys_init_self_delete` (an Initialize/LateInitialize that does its work
  then deletes itself: `qdel(src)`, `expire(0)`, `replace_with(src, ...)` at its top level).

As built (`code/__defines/map_resolvers.dm`, `code/modules/maps/map_resolvers.dm`):

- `MAP_RESOLVER(PATH, PROC)` sets the type var `map_resolver` (a type default: no per-instance
  cost, subtypes inherit and may override). The resolver is `proc(atom/loc, path, list/varedits)`
  and returns TRUE when it resolved (FALSE: make the atom normally, e.g. a landmark that stays).
  Read vars with `MAP_VAR(P, varedits, name)` (the edit if present, else `initial()`).
- Two entry points. The map reader (`build_coordinate()`) resolves before instancing, with the
  model's attributes as varedits: the atom is never created. `SSatoms.InitAtom()` resolves atoms
  that already exist before Initialize: the compiled station map (BYOND instances it before any DM
  code runs, so those atoms exist but are never initialized, materialized or qdel'd; they are
  detached and freed by refcount) and `new` at runtime (supply packs putting `/obj/random` in
  crates). Their varedits are `map_varedits_of(A)`: plain vars that differ from the type default,
  plus list vars (only an instance carries a type's list default).
- `map_resolve_later(proc, loc, path, varedits)`: for resolvers whose work needs the rest of the
  load (the device an airlock helper configures, neighbouring window spawners, the level above
  stairs, whole-level helpers, turbolifts). Rows run once the outermost `InitializeAtoms()` of the
  load has created its atoms, inside its frame (what they create initializes as mapload and joins
  the batch); outside a load they run at once. `GLOB.map_resolve_scratch` is per-load scratch
  (window spawner cells, duplicate low wall checks).
- Landmarks: the coordinate-only names (`start`, `blobstart`, `JoinLateCryo`, ...) of plain,
  `start` and `virtual_reality` landmarks become rows of their existing coordinate registries
  (`landmark_coordinate_registry()`); landmarks that stay (`JoinLate`, event triggers, ...) are made
  normally. Multi-point spawns (`/obj/random_multi`) become weighted rows in
  `GLOB.multi_point_spawns`, rolled at round start.
- Converted families: `/obj/random`, floor decals (incl. reset, asteroid, fancy shuttle; painted
  at runtime by `floor_decal_paint()`), warning stripes, window/plated catwalk/low wall/stairs
  spawners, landmarks and costume landmarks, map helpers (airlock, base turf, tele/phase blocks,
  in/outdoors), gib sprays (`gibs()` with static patterns), fifty/fruit/telecrystal/parts/animal/TTV/
  one-tank bomb spawners, wire deleters, floor breakers, falling effects (`drop_from_sky()`),
  turbolift holders, multi-point spawns, fossils, two-bagel snacks, instant explosions, graffiti,
  recycler beacons, mouse holes, map data, fancy shuttle previews.

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

## 16. Sound and effect sets

```dm
SOUND_SET(SFX_WELD, list('sound/items/welder.ogg', 'sound/items/welder2.ogg'), 50, TRUE)
play_sfx(src, SFX_WELD)
fx_sparks(src, 3)                   // pooled, replaces the new/set_up/start triple
```

- `SOUND_SET(id, files, volume, vary)` rows in `code/__defines/sfx.dm`; `play_sfx(atom, id,
  volume_mult = 1)`. Literal `playsound(x, 'file', ...)` calls become set ids.
- `fx_sparks(atom, n, cardinals = TRUE)` uses a pooled spark system.
- Lint `sys_literal_playsound`, `sys_spark_triple`.

## 17. Expiry

```dm
EXPIRY_DECLARE(stun_until)                 // var + clock
EXPIRY_SET(src, stun_until, 5 SECONDS, CLOCK_MOB)
EXPIRY_LEFT(src, stun_until)               // deciseconds left, 0 when expired
EXPIRY_ACTIVE(src, stun_until)
ELAPSED(src, started_at)                   // clock-aware elapsed
```

- Clock-aware (stasis, machine clock). Distinct from COOLDOWN (a gate); expiry is state that
  ends. Replaces `world.time + X` comparisons for expiry-shaped state.
- Lint `sys_world_time_expiry`.

## 18. FOR_REAL_CONTENTS

`FOR_REAL_CONTENTS(var/x as anything, A)` iterates materialized contents without resolving
latent entries. Lint `sys_materializing_walk` bans `FOR_CONTENTS`/`contents_of` in `tgui_data`
and `examine`. Fixes `anomaly_harvester.dm:171`.

## 19. Verbs through grants

`om_grant(M, GRANT_ABILITY, /datum/ability/x, source)`: the verb/ability appears while any source
grants it and disappears automatically when the source is removed/destroyed (the contribution
system already drops a destroyed source's holds). Replaces paired `add_verb`/`remove_verb`.
Lint `sys_add_verb_pair`.

## 20. TOPIC_ACTION registry

```dm
TOPIC_ACTION(/datum/admins, "adminplayeropts", PROC_REF(topic_player_opts), TOPIC_REF("target", /mob), TOPIC_RIGHTS(R_ADMIN))
```

- `Topic()` is one core proc: it finds the action by its href key, checks rights, resolves each
  `TOPIC_REF(name, type)` with `locate(ref) in <declared source>` and type check, then calls the
  proc with typed args. The 1,352-line admin topic becomes rows.
- Lint `sys_topic_override`.

## Hygiene

- "mob: 15 mobs at boot" annotations on non-mob sites are replaced with accurate reasons; the
  36 placeholder `ALLOW(state_ref)` get real reasons or the site is fixed.
- `om_derived` replaces `cached_*` vars; `om_deadline` replaces hand-rolled `world.time`
  deadline checks; construction graphs replace the hand-rolled light, AI core, camera, door
  assembly, emitter, field generator and PA state machines.

## Rollout

1. Primitives in order (2, 1, 5, 3, then 4, 6, 7, 10, 15, 16, 17, 18, 13, 12, 8, 9, 19, 20, 14),
   each with a focused test and its lint at the current count.
2. Domain migration fanned out to workers (disjoint directories), each lowering the ratchets.
3. Delete old procs (`emag_act`, `item_to_spawn`, loot datums, `inoperable()`, boilerplate
   `tgui_interact`), ratchets to 0, docs and AGENTS.md updated.

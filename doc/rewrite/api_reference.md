# DeepQuarry API reference

The practical catalogue of **what to use**. For every need there is one form or system: its signature, the file that defines it, a real example, and what it
replaces or bans. If a need is listed here, use the listed form; do not write a second way to do it.

- The design and the reasons are in [final_api.html](final_api.html) (the approved API and migration plan). This file is the quick reference to what is on master today.
  Where the two disagree, this file is checked against the code and `final_api.html` is the intent; fix whichever is wrong in the same commit.
- [../../AGENTS.md](../../AGENTS.md) says how to work in the repo (build, lanes, tests, ratchets). This file says which form to write.
- Everything here was derived from the code on master. `python3 tools/ci/check_docs_truth.py` (run by `bash tools/ci/check_ratchets.sh`) verifies it:
  every `Defined:` citation must point at a file and line that still contain the form's name, every other `path:line` citation must still be inside its
  file, every name in a **Banned** table must still be a banned name, and every **Landing** entry's probe must still find nothing in the code.
  When you rename or move a form, the checker fails until this file is updated. That is the point.

## How to read an entry

```
#### `form(signature)`
Need: the need it serves.
Defined: `path:line`            (the line where the form is defined; the checker finds the name within a few lines of it)
Example: real code, then the call site `path:line`.
Replaces / bans: what it replaced; which names are hard-banned because of it.
Notes: pitfalls.
```

- **Status.** An entry in the body is on master and usable. A **Landing** entry (section 19) is designed or in flight and **is not usable**: do not write it, stub it
  or invent it. Its probe tells the checker when it has landed so this file gets updated.
- Paths are repo-relative. `FORM(...)` in capitals is a macro, lower case is a proc or a CAPABILITIES entry.
- A form that is listed in the **Banned** tables is rejected by a hard lint (`[lint.legacy_forms.lists] banned` in `tools/ci/lint_scopes.toml`). Do not write it, and do not
  annotate it with `ALLOW`.

## Before you add a system

Adding a second way to do something that already has a way is the main source of rot in this codebase (see section 18, which lists the overlaps that exist today
and which lane removes each). Before you write a new helper, system, cache, lazy path, timer, relation, storage form, queue, watch or reference form:

1. **Search this reference** (section 2 is the need-to-form index) and `git grep` the repo for the need. If a form is listed, use it.
2. **Extend the existing system** instead of adding a sibling. A missing option on `after()`, a new `STAT`, a new part for `op()`, a new `/datum/metrics_source`,
   a new serial kind, a new `HEAT_SOURCE_*`, a new registry: these are all extensions. Say in the commit which form you extended.
3. If the need is genuinely new and **world-level** (state or periodic work that belongs to no one object), it is a `/datum/system` declared with `SYSTEM_DEF(x)`
   (section 10). Give it `needs`, a `phase`, `every()` items in `reactions()`, and an `api.dm` that other folders call. Do not add a global list, a `process()`, a
   hand-rolled loop, a second scheduler or a second queue.
4. A new per-object mechanism (a cache, a lazy record, a copy-on-write scheme, a time table, a reference token) is a **design change**: write it up in `doc/rewrite/`,
   name which entry in section 18 it replaces, and get it agreed. Section 18 exists to make the number of these go down.
5. **Update this reference in the same commit** as the form: add the entry (with `Defined:`), move anything it replaces to the Banned tables, and run
   `python3 tools/ci/check_docs_truth.py`. A form that is not in this file does not exist for the next author.
6. Add the matching lint or ratchet (section 16) in the commit that lands a replacement, and convert the callers in that commit.

## 2. Need-to-form index

| Need | Use | Section |
|---|---|---|
| Declare what a type does | `CAPABILITIES(T)` block of entries | 3 |
| A number or flag composed from several sources | `STAT` + `hold()` / `contributes()` / `factors()` | 4 |
| A var that other code reacts to | any var read by reactive code; write through the generated `set_<v>()` | 4 |
| A rare per-instance value on a base type | `owns_one(lazy = TRUE)` state datum, `burn_of(A).set_fuel(5)` (a `sparse()` slot is the old form) | 6 |
| A rate limit or "how long since" | `COOLDOWN_*` / `STAMP` + `ELAPSED` (subtype), `cooldowns()` / `stamps()` (base type) | 4 |
| A table shared by all instances of a type | `per_type()`, a type trait, `variants()` | 4 |
| A keyed global cache | `DECLARE_SHARED_CACHE` + `CACHED()` | 4 |
| Starting contents, owned children | `owns_one` / `owns_many` with `starts =` | 5, 6 |
| A value computed from the instance's place or params before init | `preset()` | 5 |
| Constructor arguments | `param()` and `make()` | 5 |
| Code that ran after `..()` in `Initialize()` | `setup(PROC_REF(x))` | 5 |
| Work after init or after a delay from init | `after_init()` | 5 |
| A non-owning link to another thing | `ref_one` / `ref_many` / `links`, written with `rel_set` | 6 |
| A weak reference to store | `ref_one(weak = TRUE)` or `ref_token()` / `resolve_token()` | 6 |
| Delete something | `qdel()`; consequences in `on_destroy(force)` | 6 |
| Do something later | `after(owner, delay, then(...))`; repeat with `every(...)` | 7 |
| Long work that yields | `job()` | 7 |
| A world-level state or periodic job | `SYSTEM_DEF(x)` + `/datum/system` | 10 |
| React to a click, drag or hover | `click_on()` / `drag_onto()` / `hover()` in `CAPABILITIES` | 8 |
| Let others refuse or change an event | `ACTION()` + `ACT_ATTEMPT`, `extend(... needs / instead / adjusts)` | 8 |
| React after something happened | `on_notice()`, `PUBLISH()`, `on_change()` | 8 |
| A player, AI or admin choice | `op(key, name, parts...)` with `needs()`, `asks()`, `wait()`, `then()` | 9 |
| A refusal | a requirement (`needs(req_*())`), never a boolean and never a message at the head of an effect | 9 |
| Ask a player a question | `asks()` in an op; `ask_steps()` for an admin verb; `ask_admin()` for an admin tool | 9, 11 |
| What a thing looks like | `draw(datum/look/look)` | 11 |
| A window | `interface("Name")` + `ui_data(datum/act/eval/A)` + `op(..., ui_act(...))` | 11 |
| A verb | `verb_entry()` / `grant()`; admin verbs `ADMIN_VERB` | 11 |
| Tell a player something | `to_chat()`, `visible_message()`, `says(MSG(...))` on an op | 11 |
| A sound, a spark | `play_sfx()`, `fx_sparks()` | 11 |
| Read the database or a URL | `sql_ask()`, `sql_write()`, `http_ask()` | 10 |
| A spawn table | `loot(table = ...)` + `loot_spawn()` | 12 |
| A build ladder | `construction(start(), stage(), dismantle())` | 12 |
| Hurt or heal | `receive_damage()` / `deal_damage()` (objects), `injure()` / `mend()` (mobs) | 13 |
| Temperature | `get_temperature()`, `add_heat()`, `heat_add()` / `heat_set()` | 13 |
| Gas | `/datum/gas_mixture` handle API, `gas_sample()`, `gas_release()` | 13 |
| Power | `set_power_supply()`, `use_power_oneoff()`, `power_net_*` | 13 |
| Reagents | `/datum/reagents` (`add_reagent`, `trans_to_holder`) | 13 |
| Move a thing into a holder or slot | `move_into()`; plain moves `forceMove()` | 6, 13 |
| Talk to Rust | the domain's `*_api.dm`, `native_read()` / `native_write()`; never a raw `vg_*` in content | 14 |
| A list, pick, typecache, text, time helper | section 15 | 15 |
| A unit test | `/datum/unit_test` with `Run()`, run with `tools/dq_focused_test.sh` | 16 |

## 3. Declaring a type

One inheriting block per type. The block is read from source by `analyze gen declare`; nothing runs it.

#### `CAPABILITIES(T)`
Need: declare a type's entries (ops, relations, timers, hooks, look, interface, stats) in one indented block.
Defined: `code/defines/engine/declare/markers.dm:30`
Example: `CAPABILITIES(/obj/machinery/media/jukebox)` then indented `interface("Jukebox", ...)` and `op("volume", ...)` lines, `code/content/machinery/jukebox.dm:35`
Replaces / bans: the `capabilities()`, `relations()`, `ownership()` table procs, `OM_FIELD`, every `DECLARE_*` macro (all Banned, section 17).
Notes: one entry per line, indented under the header. A subtype's block adds to its parent's; re-declaring the same form replaces the parent's entry.

#### `CAPABILITIES_PART(T, feature)`
Need: contribute entries to a type whose root `CAPABILITIES(T)` is in another file.
Defined: `code/defines/engine/declare/markers.dm:35`
Example: `CAPABILITIES_PART(T, feature)` after the root block; merged root first, then parts sorted by feature name.
Replaces / bans: none.
Notes: the root block is required.

#### `section(name, "doc")`
Need: group the entries of one type's block under a name.
Defined: `code/defines/engine/declare/markers.dm:66`
Example: `section(admin, "The admin actions of the Edit Player panel: rights, messages, moving, banning, muting")`, `code/content/admin/edit_player_panel.dm:42`
Replaces / bans: `BUNDLE`.
Notes: expands to nothing. Sharing entries between types is a capability or a plain proc returning entries, not a section.

#### `CAPABILITY_DEF(name, cap_id, params...)` and `CAPABILITY_TYPE(name, cap_id, type, params...)`
Need: a reusable capability (`powered()`, `cover()`, `swarming`): a body of entries, or one with its own code.
Defined: `code/defines/engine/declare/markers.dm:41`, `CAPABILITY_TYPE` at `code/defines/engine/declare/markers.dm:43`
Example: `CAPABILITY_TYPE(swarming, CAP_SWARMING, /datum/capability/swarming, key = NONE)`, `code/content/behaviours/swarming.dm:9`
Replaces / bans: `capabilities()` table proc.
Notes: shared capabilities live in `code/library/capabilities/` and `code/library/`.

#### `configure(changes, variant = null)`
Need: a subtype changes an inherited entry without redeclaring it.
Defined: `code/engine/declare/entries.dm:260`
Example: `configure(uses_power(idle = 45))`, `code/content/admin/magnetic_console_panel.dm:14`
Replaces / bans: none.
Notes: names only what changes; a null argument is inherited.

#### `STATIC_ENTRY(kind)` and the `static_entries` system
Need: entries that are read without an instance (loot tables, map resolvers, type-trait kinds), compiled once at world setup.
Defined: `code/defines/engine/declare/markers.dm:39`
Example: `STATIC_ENTRY(atom_rules)`, `code/content/atom/atom_rules.dm:14`
Replaces / bans: `DECLARE_LOOT`, `MAP_RESOLVER`, `MAP_RESOLVER_VARS`, lazily built rule caches.
Notes: the kind's engine sets `static_kind = TRUE` (`code/engine/declare/static_entries.dm:16`). A lookup before setup is reported.

## 4. State

### Tracked vars

Tracking is automatic. A var that reactive code reads (a draw, a stat, a requirement, a hop) or that is written through `set_<v>()` gets a generated setter.
Do not declare `TRACKED(...)`; it is hard-banned outside the generated file.

#### Generated `set_<v>()` setters and `TRACKED_UNCHANGED`
Need: change a var that others react to; the write publishes only when someone reads the key.
Defined: `TRACKED_UNCHANGED` at `code/defines/engine/capabilities.dm:31`, the macro `TRACKED` at `code/defines/engine/capabilities.dm:34` (generator-only)
Example: write `X.set_severity(v)`, not `X.severity = v`. `analyze fix --apply` rewrites a raw write.
Replaces / bans: `TRACKED(T, v)` outside generated code, `OM_FIELD*`, `TRACKED_BRIDGED`, `changed()` channels.
Notes: construction (`Initialize()` writing the instance's own var) is not a change and stays raw. Null is different from 0, "" and FALSE.

#### `SETTER(T, V)`
Need: a hand-written setter with side effects.
Defined: `code/defines/engine/capabilities.dm:47`
Example: `SETTER(/datum/affliction, severity)`, `code/content/body/affliction.dm:211`
Replaces / bans: `OM_FIELD_SETTER`.
Notes: the hand-written `set_<V>` must call `tracked_changed(src, nameof(V))`.

#### `TRACKED_DATA(T, V)`
Need: a tracked field on a profile record.
Defined: `code/defines/engine/capabilities.dm:39`
Example: `TRACKED_DATA(/datum/record/appearance, hair_style)`, `code/content/mob/living/carbon/human/profile_records.dm:35`
Replaces / bans: none.
Notes: the setter publishes on the record and on the holder.

#### `SCHEMA(T, var, schema_expr)`
Need: type a var that carries whatever its producer returns (a hook reply, a config value).
Defined: `code/defines/engine/declare/declare.dm:87`
Example: `SCHEMA(/datum/alarm, last_name, schema_text())`, `code/content/alarm/alarm.dm:171`
Replaces / bans: untyped vars (the `untyped` lint is a hard ban: an untyped var assigned an atom, datum or call result is a relation or a `SCHEMA`).
Notes: on its own line.

#### Tracked list mutators: add, include, remove, set_at, clear, insert, swap, cut (all `<verb>_<v>()`)
Need: mutate a list that reactive code reads.
Defined: `tracked_lists` at `tools/analyze/src/gens/tracked_lists.rs:1`
Example: `F.add_items("a")`, `F.remove_items("b")`, `code/tests/unit_tests/dq_tracked_list_tests.dm:12`
Replaces / bans: raw `LAZYADD`, `.Add()`, `v[i] = x` on a tracked list (the `tracked` lint; `analyze fix` rewrites them).
Notes: each returns TRUE when the list changed. A `<v>_version` counter backs copy-on-write holders.

### Lists

#### `LAZYADD`, `LAZYSET`, `LAZYREMOVE`, `LAZYLEN`, `LAZYACCESS`, `LAZYCLEARLIST`
Need: per-instance mutable lists that stay null until used.
Defined: `code/defines/host/_lists.dm:14`, `LAZYSET` at `code/defines/host/_lists.dm:25`, `LAZYLEN` at `code/defines/host/_lists.dm:28`
Example: `LAZYADD(tracers, user)`, `code/content/admin/verbs/debug.dm:102`
Replaces / bans: `var/list/foo = list()` on an instance (`instance_list`, hard ban).
Notes: `LAZYACCESS` evaluates its arguments more than once. A constant shared table is `var/static/list`. `LAZYINITLIST` is in `code/host/helpers/_lists.dm:44`.

### Stats: numbers and flags composed from sources

#### `STAT(T, name, RULE, base =, bounds =, schema =, reapply =, units =, formula =, reads =, virtual =)`
Need: declare a number or flag that is composed from sources (holds, contributions, factor tables).
Defined: `code/defines/engine/declare/markers.dm:56`; rules and options in `code/defines/engine/declare/stats.dm:4`
Example: `STAT(/mob/living, airway, PRODUCT, bounds = list(0, 1))`, `code/content/contracts/ids/body_stats.dm:14`
Replaces / bans: `BF_*`, `factor(`, `DERIVE_ANY/ALL/MIN`, hand-kept override vars.
Notes: rules are ALL, ANY, SUM, PRODUCT, MAX, MIN, TOP, SET, MASK_AND, MASK_OR, FORMULA, SUM_PER_KEY. The effective value is a var (`L.slowdown`) written only by the stat layer.
`virtual = TRUE` has no var and is read with `stat_value()`. The `stat(...)` entry form inside `CAPABILITIES` is **Landing**.

#### `hold(E, stat, value, source, lasts =, key =, priority =, clock =)` and `release(E, stat, source, key =)`
Need: a runtime contribution to a stat from a source, and its removal.
Defined: `code/engine/stats/store.dm:108`, `release` at `code/engine/stats/store.dm:276`
Example: `hold(A, STAT_INVISIBILITY, INVISIBILITY_ABSTRACT, SRC_UNDER_FLOOR)`, `code/content/atom/concealment.dm:8`
Replaces / bans: hand-kept override vars, `EXPIRY_*` on stats.
Notes: `hold_until` (`code/engine/stats/store.dm:112`) and `hold_override` (`code/engine/stats/store.dm:116`) are the timed and overriding forms. A `SUM_PER_KEY` stat needs `key =`.

#### `hold_table(E, source, table, scale =, stacks =, part =)`
Need: place a source's whole table of stat values at once.
Defined: `code/engine/stats/tables.dm:66`
Example: tables are keyed by stat id, `alist(STAT_SLOWDOWN = 1)`; the engine applies each `factors()` entry through it at `code/engine/stats/recompute.dm:794`.
Replaces / bans: `BF_*`, `factor(`.
Notes: normally reached through `factors()` rather than called.

#### `contributes(stat_id, value, priority =, key =, reads =)` and `contributes_to(rel_var, stat_id, ...)`
Need: a static contribution of a type's own state to a stat.
Defined: `code/engine/stats/contributes.dm:118`, `contributes_to` at `code/engine/stats/contributes.dm:121`
Example: `contributes(STAT_HAS_POWER, nameof(anchored))`, `code/content/machinery/jukebox.dm:32`
Replaces / bans: hand-written stat input vars.
Notes: `immune_to(STATUS_X, when =)` (`code/engine/stats/contributes.dm:132`) is the shortcut for a status immunity.

#### `factors(table, scale =, stacks =, rel =, part =)`
Need: a source type's stat table, held on the entity its relation names.
Defined: `code/engine/stats/contributes.dm:125`
Example: `factors(PROC_REF(factor_table), scale = PROC_REF(factor_scale), rel = nameof(owner))`, `code/content/body/affliction.dm:588`
Replaces / bans: a raw `factors =` var on a converted family (`factors_converted` in `tools/ci/lint_scopes.toml`), `BF_*`, `factor(`.
Notes: `rel` is required. A `factors = alist(...)` data var on a flyweight or prototype read by that type's one entry is final data and stays.

#### `grant(holder, what, source, lasts =, bound =)` and `revoke(holder, what, source)`
Need: give or remove a capability or a verb on one holder for as long as a source holds it.
Defined: `code/engine/declare/activation.dm:151`, `revoke` at `code/engine/declare/activation.dm:286`
Example: `grant(Tar, granted_verb(/mob/living/proc/ventcrawl), Tar)`, `code/content/admin/player_effects.dm:603`
Replaces / bans: `om_grant`, `DECLARE_VERB`.
Notes: `what` is a capability id or `granted_verb(path)`.

### Time as a value

Choose by shape; section 18 lists why there are several.

#### `STAMP(D, var, clock)` and `ELAPSED(D, var, clock)`
Need: record "now" in a declared var of a subtype and read how long ago.
Defined: `code/defines/engine/time_now.dm:19`
Example: `STAMP(src, last_refresh, CLOCK_WORLD)`, `code/content/admin/admin_tools.dm:57`
Replaces / bans: `EXPIRY_STAMP`, `STAMP_ELAPSED`, `STAMP_AT`, `STAMP_POINT`, `STAMPED`, `STAMP_CLEAR`, `ELAPSED_SINCE`, `BEFORE`.
Notes: read with the clock the stamp used. The var is a plain var.

#### `TIME_NOW(clock, owner)`, `CLOCK_WORLD`, `CLOCK_OWN`
Need: the one clock read; every time macro is built on it.
Defined: `code/defines/engine/time_now.dm:16`; clocks at `code/defines/engine/capabilities.dm:70`
Example: `payload["signed_at"] = TIME_NOW(CLOCK_WORLD)`, `code/content/contracts/agent_fieldwork.dm:210`
Replaces / bans: `EXPIRY_NOW`, `EXPIRY_AT`, raw `world.time` compares (the `cooldown` lint).
Notes: `CLOCK_OWN` is the owner's timer clock (slows with its domain's rate, stops in stasis).

#### `COOLDOWN_DECLARE`, `COOLDOWN_START`, `COOLDOWN_FINISHED`, `COOLDOWN_RUNNING`, `COOLDOWN_LAPSED`, `COOLDOWN_TIMELEFT`, `COOLDOWN_EXTEND`, `COOLDOWN_RESET`
Need: an end-time rate limit in a var of a subtype.
Defined: `code/defines/engine/cooldowns.dm:16`, `COOLDOWN_START` at `code/defines/engine/cooldowns.dm:22`
Example: `COOLDOWN_START(src, tgui_message_cooldown, 0.5 SECONDS)`, `code/content/admin/verbs/entity_narrate.dm:406`
Replaces / bans: `EXPIRY_DECLARE/SET/EXTEND/CLEAR/ACTIVE/EXPIRED/LEFT/ON_LAPSE`, `LEFT_UNTIL`, `STATIC_EXPIRY_DECLARE`.
Notes: `RUNNING`/`LAPSED` are the strict pair; `FINISHED` is `end < now` and `RUNNING` is `end > now`. The `_OWN` family reads the datum's own clock; use the family you started with.

#### `COOLDOWN_KEYED_DECLARE`, `COOLDOWN_KEYED_START`, `COOLDOWN_KEYED_FINISHED`
Need: cooldowns whose key is data (an ability id).
Defined: `code/defines/engine/cooldowns.dm:57`
Example: `COOLDOWN_KEYED_START(src, changeling_cooldowns, id, cooldown_time)`, `code/content/gamemodes/changeling/state/changeling.dm:97`
Replaces / bans: a var per key.
Notes: starting a key prunes lapsed keys. World clock only.

#### `cooldowns(names...)`, `cooldown_ready`, `cooldown_start`, `cooldown_left` and `stamps(names...)`, `stamp_now`, `stamp_elapsed`
Need: a rate limit or "how long since" on a **base type**, which holds no var.
Defined: `code/defines/engine/declare/sparse_slots.dm:6`, `stamps` at `code/defines/engine/declare/sparse_slots.dm:32`
Example: `cooldowns(next_emote, next_emote_refresh)` at `code/domains/world_model/mob/mob_defines.dm:164`; `stamp_now(user, last_bumped, CLOCK_WORLD)` at `code/content/machinery/doors/airlock.dm:939`
Replaces / bans: `COOLDOWN_DECLARE` on a base type (the `base_vars` lint), `STAMP_*` families.
Notes: both write one lazy `cooldown_table`. A write publishes nothing, so a draw or stat reading it needs a tracked var that also moves (Landing, section 19).

### Rare per-instance state

#### `sparse(T, name, type =)` with `sparse_get`, `sparse_set`, `sparse_get_or`, `sparse_has`
Need: a rare per-instance value without a var on a base type.
Defined: `code/defines/engine/declare/sparse_slots.dm:4`; procs at `code/engine/declare/sparse_slots.dm:41`
Example: `sparse(/mob/living, omen_damage, type = num)`, `code/content/behaviours/omen.dm:30`
Replaces / bans: base-type vars (the `base_vars` ratchet).
Notes: one lazy assoc on the datum. `type = weak` stores a `ref_token`. A write publishes no change.

### Per-type and shared data

#### `per_type(nameof(v), PROC_REF(build), copy_on_write = FALSE)`
Need: a lazily built read-only table shared by all instances of a type.
Defined: `code/engine/lifeforms/per_type.dm:28`
Example: `per_type(nameof(events), PROC_REF(build_events), copy_on_write = TRUE)`, `code/content/admin/orion_trail_panel.dm:89`
Replaces / bans: an `Initialize()` that built a per-type list.
Notes: with `copy_on_write = TRUE` the var becomes a tracked list and each mutator unshares first (one level deep).

#### `type_trait_of(holder, kind)`, `type_trait_own(holder, kind)`, `set_trait(holder, kind, field, value)`
Need: per-type constant data a domain owns, with a per-holder copy on write.
Defined: `code/engine/declare/type_traits.dm:114`, `type_trait_own` at `code/engine/declare/type_traits.dm:154`, `set_trait` at `code/engine/declare/type_traits.dm:167`
Example: `return type_trait_of(M, ENTRY_USES_POWER)`, `code/content/machinery/machinery_power.dm:51`
Replaces / bans: base-type data vars (the `base_vars` lint).
Notes: a new kind needs a `/datum/type_trait` subtype and `STATIC_ENTRY(kind)` (`code/engine/declare/type_traits.dm:16`).

#### `variants(nameof(var), PROC_REF(table))`
Need: collapse a family of data-only subtypes into one type plus a key-to-vars table.
Defined: `code/engine/lifeforms/variants.dm:14`
Example: `variants(nameof(variant), PROC_REF(variant_table))`, `code/content/clothing/variants/clothing_accessory_gaiter.dm:18`
Replaces / bans: `Initialize()` overrides that called `apply_variant()`.
Notes: the row is applied at preinit; a null, 0 or "" value is skipped. A subtype with its own procs stays a real subtype. Readme: `code/content/variants/README.md`.

#### `DECLARE_SHARED_CACHE(N, BUILDER, POLICY)`, `CACHED(N, key)`, `INVALIDATE_SHARED_CACHE(N)`, `SHARED_CACHE_UID(D)`
Need: a global keyed cache of built values.
Defined: `code/defines/engine/shared_cache.dm:43`, `SHARED_CACHE_UID` at `code/defines/engine/shared_cache.dm:52`, `INVALIDATE_SHARED_CACHE` at `code/defines/engine/shared_cache.dm:58`
Example: `DECLARE_SHARED_CACHE(damage_flavour_declared, GLOBAL_PROC_REF(build_damage_flavour_declared), SC_NEVER)`, `code/content/atom/damage_flavour.dm:56`
Replaces / bans: `var/static/list/..._cache`, `GLOBAL_LIST_*(...cache...)` (the `cache` lint, ceiling 0; typecaches are exempt by name).
Notes: keys are text, a type path or a `SHARED_CACHE_UID`; never a number or a ref. Returned lists are shared: copy before writing. Policies: `SC_NEVER`, `SC_ON_NOTICE(path)`, `SC_EXPLICIT`.

#### `derives(nameof(target), PROC_REF(x), from =)` and `starts_as(STATE)`
Need: keep a var equal to a pure function of other tracked vars; computed at init, recomputed when a `from` var is written.
Defined: `code/engine/lifeforms/derives.dm:23`, `starts_as` at `code/engine/lifeforms/derives.dm:20`
Example: `derives(nameof(default_material), PROC_REF(forced_material))`, `code/content/clothing/accessories/hands.dm:148`
Replaces / bans: an `Initialize()` that computed the value.
Notes: `x(target)` must be pure. With no `from` it is computed once at init.

#### `profile(nameof(v), /datum/record/T, fields =)`
Need: a per-instance record of data fields (a profile, a preferences block).
Defined: `code/engine/declare/profiles.dm:21`
Example: `profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_pred" = TRUE))`, `code/content/items/devices/denecrotizer.dm:43`
Replaces / bans: var-by-var copy procs.
Notes: a record holds data only; its procs are the `TRACKED_DATA` setters.

## 5. Init and construction

The `Initialize()` chain is `/atom`, `/atom/movable`, `/obj`, `/turf` and `/datum/controller/global_vars` (`init_roots`, `tools/ci/lint_scopes.toml:210`; adding one is a design change).
A type's own init code is declared, not overridden. An `Initialize()` override that remains sets per-instance state only and carries
`// ALLOW(init/INSTANCE_STATE|CTOR_ARGS|FRAMEWORK): <reason>`. There is no `preinit()` for atoms, no `LateInitialize()`, no `INITIALIZE_HINT_LATELOAD`.

#### `preset(nameof(v), PROC_REF(gen), from =, when =, overrides =, default =)`
Need: a value computed from the instance's own place or params, set before its init code reads it.
Defined: `code/engine/lifeforms/preset.dm:20`
Example: `preset(nameof(start_x), PROC_REF(start_at_x))`, `code/content/overmap/spacetravel.dm:11`
Replaces / bans: assignments before `..()`.
Notes: the generator reads, never writes. A map-edited or param-given value suppresses the preset. A claim on a resource stays a `setup()` effect.

#### `param(nameof(v), schema, default =, required =, pos =, apply =, keep =, overrides =, early =)` and `make(type, at =, name = value...)`
Need: named, typed constructor arguments set before init.
Defined: `code/engine/lifeforms/params.dm:52`
Example: `param(nameof(overmind), pos = 1)`, `code/content/blob2/blobs/base_blob.dm:28`; `make(/mob/observer/dead, at = M, from_body = M, admin_ghosted = TRUE)`, `code/content/admin/verbs/debug.dm:331`
Replaces / bans: positional constructor arguments and `Initialize(mapload, arg)` overrides.
Notes: `apply = PROC_REF(x)` runs a setter after the capabilities; `early = TRUE` runs it in phase 0, only for a setter the chain reads. An object that needs a body takes it as a param.

#### `setup(PROC_REF(x), with_params =, mapload =, early =)`
Need: the type's own init code that used to follow (or, with `early`, precede) `..()`.
Defined: `code/engine/lifeforms/setup.dm:38`
Example: `setup(PROC_REF(link_magnets))`, `code/content/admin/magnetic_console_panel.dm:13`
Replaces / bans: the part of an `Initialize()` override after `..()`; `early = TRUE` replaces the part before it.
Notes: `mapload = TRUE` gives `x(mapload)` and its return is the init hint (use it for `INITIALIZE_HINT_QDEL`). `early` cannot combine with `with_params` or `mapload`.

#### `keeps_if(PROC_REF(cond), warn =, instead =)`
Need: discard an atom whose init finds a condition false.
Defined: `code/engine/lifeforms/keeps_if.dm:26`
Example: `keeps_if(PROC_REF(off_space))`, `code/content/effects/dark_growth.dm:100`
Replaces / bans: `return INITIALIZE_HINT_QDEL` in an `Initialize()` override.
Notes: the condition reads and never writes. `instead =` runs once, when the instance is discarded.

#### `after_init(delay, then(...))`
Need: work after init has completed, after the map load, or after a delay from init.
Defined: `code/engine/actions/after_init.dm:28`
Example: `after_init(0, then(PROC_REF(join_frequency)))`, `code/content/assembly/signaler.dm:30`
Replaces / bans: `LateInitialize()` and `INITIALIZE_HINT_LATELOAD` (gone).
Notes: the delay is deciseconds, `nameof(var)` or a `PROC_REF`. A bare `new` of a plain datum that declares it is refused; use `make()`. Handler `x(datum/act/timer/A)`.

#### `on_holder_init(datum/act/eval/A)`
Need: capability setup once the holder exists.
Defined: `code/engine/declare/scopes.dm:148`
Example: `/datum/capability/swarming/on_holder_init(datum/act/eval/A)` with `holder_hooks = HOLDER_HOOK_INIT`, `code/content/behaviours/swarming.dm:11`
Replaces / bans: an `Initialize()` override for capability setup.
Notes: order is `on_holder_preinit`, relation init, then `on_holder_init` (`code/engine/declare/relations.dm:185`).

#### Capability runtime state: `capability_runtime(holder)`, `cap_has`, `cap_set`
Need: per-holder runtime bits and data of capabilities.
Defined: `code/engine/declare/capability_tables.dm:7`, `cap_set` at `code/library/capabilities/capabilities.dm:26`
Example: `LAZYSET(capability_runtime(O).data, /datum/material_assembly, assembly)`, `code/content/materials/engineering/material_state.dm:162`
Replaces / bans: none.
Notes: the record sits in a global list keyed by `SHARED_CACHE_UID`. `cap_set` re-derives every output of the holder (Landing: only the outputs that read the bit).

## 6. References, ownership and lifetime

Every datum another datum points at is **owned**, **borrowed** or a **token**. Never store a bare datum reference in a var, list or global that is not a declared relation
(the `stored_refs` and `untyped` lints).

#### `ref_one(var, type, ...)` and `ref_many(...)`
Need: a non-owning link to another entity; cleared when the target dies; the target keeps a reverse index.
Defined: `code/engine/declare/entries.dm:144`, `ref_many` at `code/engine/declare/entries.dm:153`
Example: `ref_one(nameof(paper), /obj/item/paper/admin)`, `code/content/admin/admin.dm:997`
Replaces / bans: the `OWN`/`REL` macros and the `relations()` table proc.
Notes: options `on_other_deleted`, `on_unlink`, `by`, `key`, `starts`, `weak`, `unindexed`. Write with the `rel_*` verbs.

#### `owns_one(var, type, starts =, on_destroy =, ...)` and `owns_many(..., count =)`
Need: an owned child, disposed of by a declared policy when the holder dies; `starts =` builds the initial occupant.
Defined: `code/engine/declare/entries.dm:175`, `owns_many` at `code/engine/declare/entries.dm:192`
Example: `owns_many(nameof(beakers), starts = PROC_REF(make_beakers), on_destroy = ON_DESTROY_CONTAINED)`, `code/content/admin/dartgun_panel.dm:10`
Replaces / bans: `OWN` macros, `ownership()`, ad-hoc `New()` child creation.
Notes: policies `ON_DESTROY_DELETE`, `SPILL`, `PRIVATE_COPY`, `HAND_OVER`, `CONTAINED` (`code/defines/engine/declare/declare.dm:61`). `copy_on_write = TRUE` makes a prototype copy (`code/content/hydroponics/grown.dm:26`). `lazy = TRUE` is the lazy owned state, next entry.

#### `owns_one(var, /datum/state, lazy = TRUE)` with the generated `x_of(holder)`: lazy owned state
Need: rarely used state on a type (a burn, a charge, a special voice). It lives in the vars of a small state datum the holder owns, made on the first write, so an instance that never uses it pays a null var and nothing else.
Defined: `owns_one(..., lazy = TRUE)` at `code/engine/declare/entries.dm:175`; `lazy_state_make()` at `code/engine/declare/lazy_state.dm:21`; the `TRACKED_STATE` setter at `code/defines/engine/capabilities.dm:43`; `x_of()` is generated into `code/engine/_generated/declare.dm` by `lazy_accessors` in `tools/analyze/src/gens/declare.rs`
Example: `owns_one(nameof(burn), /datum/dq_lazy_burn, lazy = TRUE)`, `code/tests/unit_tests/dq_lazy_state_tests.dm:14`
Replaces / bans: `sparse()` slots, `stamps()` / `cooldowns()` tables used as storage, ad-hoc lazy assoc-list stores (being converted by lane `engine/storage-contract`; the old forms are banned in the commit that converts the last caller).
Notes: declare the var (`var/datum/burn_state/burn`) and the entry; the state type is `/datum/<var>_state` (the generator refuses another name), no `starts`, no `copy_on_write`. A read is `STATE_GET(A, burn, fuel)` (`code/defines/engine/capabilities.dm:47`): the field, or the state type's own default (`/datum/burn_state::fuel`) while no state exists; `A` is a var or a path. It allocates nothing. A write is `burn_of(A).set_fuel(5)`: `burn_of()` makes the datum on its first call, owned by the holder (`rel_set`), so it dies with the holder and needs no collection; a write back to the default frees nothing. `burn_clear(A)` ends the feature and deletes the datum. Both are generated global procs, so no proc is added to the holder's type. The state datum's vars are tracked like any other var: a write publishes the var on the state and the holder's `burn` key (`lazy_state_changed()`), so a draw, stat or `on_change()` that reads `A.burn?.fuel` follows it. A write while the holder is being deleted returns a state that belongs to nobody (freed when the caller lets go) and keeps nothing. `GLOB.lazy_states_made` counts the datums made.

#### `links(a_end, b_end, ...)`
Need: a paired relation whose two ends are kept in step.
Defined: `code/engine/declare/entries.dm:219`
Example: `links(/obj/structure/redgate::target, /obj/structure/redgate::target)`, `code/content/awaymissions/redgate.dm:608`
Replaces / bans: the `REL` pair macros.
Notes: `analyze gen declare` rewrites the call to `entry_link()`; calling `links()` directly crashes. A `sparse = TRUE` pair keeps its ends in the holders' records and is written with `LINK_END`.

#### `slot(slot_id, accepts =, capacity =, exposure =, at =, on_destroy =, starts =, fits =, replace =, quantity =)`
Need: a declared place for contained objects, backed by the containment ledger.
Defined: `code/engine/declare/entries.dm:233`
Example: `slot(SLOT_HIDDEN_UPLINK, accepts = /obj/item/uplink/hidden, capacity = 1, on_destroy = ON_DESTROY_DELETE, starts = /obj/item/uplink/hidden)`, `code/content/items/devices/uplink.dm:240`
Replaces / bans: hand-rolled `contents` handling.
Notes: slot changes publish `slot_inserted` / `slot_removed` (`code/engine/refs/containment/notices.dm:2`).

#### `rel_set`, `rel_add`, `rel_remove`, `rel_clear`, `rel_take`, `rel_move`
Need: the one write verb set for declared relations; each dispatches on the declared kind (ref, owned, weak, shared).
Defined: `code/engine/declare/relations.dm:360`, `rel_add` at `code/engine/declare/relations.dm:390`
Example: `rel_set(src, nameof(focused_obj), req_thing)`, `code/content/admin/access_viewer.dm:81`
Replaces / bans: `own_set` accessors.
Notes: a raw write to a declared relation var skips the reverse index and the teardown.

#### `ref_token(D)` and `resolve_token(h)`
Need: store a weak reference to a datum, atom, turf or client in text, safely across deletion and id reuse.
Defined: `code/engine/time/handles.dm:59`, `resolve_token` at `code/engine/time/handles.dm:187`
Example: `resolve_token(LAZYACCESS(GLOB.dq_edit_player_panels, key))`, `code/content/admin/edit_player_panel.dm:15`
Replaces / bans: `/datum/weakref` (gone), `weakref()`, stored `REF()` text.
Notes: text `"id:gen"` from a slot table with a generation counter; a stale handle never resolves to a reused id. A deleted datum gives null. Landing: integer handles replace the text form.

#### `ref_one(..., weak = TRUE)` weak relations
Need: a stored weak link that publishes nothing and indexes nothing.
Defined: `code/engine/refs/weak.dm:1`
Example: `ref_one(nameof(holder), /atom, weak = TRUE)`, `code/content/entopics/entopics.dm:66`
Replaces / bans: a plain strong var holding a datum (`stored_refs`).
Notes: the var holds a `ref_token`; the generated `v()` reads the datum or null. `on_unlink`, `on_other_deleted` and `by =` are refused with it.

#### `qdel(D, force)` and `on_destroy(force)`
Need: delete with consequences declared, not written in `Destroy()`.
Defined: `qdel` at `code/world/systems/garbage.dm:403`, `on_destroy` at `code/engine/state/lifecycle_hooks.dm:15`
Example: `observe(target_datum, /datum/notice/qdeleting, src, then(PROC_REF(handle_tagged_del)))`, `code/content/admin/tag.dm:13`
Replaces / bans: a `Destroy()` override and `del()` (lint-banned); `QDEL_NULL` and `QDEL_LIST*` are in `code/defines/engine/qdel.dm:62`.
Notes: the destroy transaction (`code/library/lifecycle/transaction.dm:25`) runs fixed phases: guard, unbind, contents, links (`on_destroy`, owned values, relations), teardown of timers and hooks, effects, the core `Destroy()`.
`lifecycle_keep(force)` refuses an unforced qdel. The GC queue is `SYSTEM_DEF(garbage)` (`code/world/systems/garbage.dm:24`).

#### `/datum/pooled`, `take(type)`, `release()`
Need: recycled transient objects whose vars reset to initial values automatically.
Defined: `code/engine/state/pool.dm:60`, `take` at `code/engine/state/pool.dm:142`, `release` at `code/engine/state/pool.dm:68`
Example: `var/datum/act/eval/E = take(/datum/act/eval)`, `code/library/machine/popup_cover.dm:38`
Replaces / bans: `POOL_DECLARE`.
Notes: never `new` a pooled type; a pooled object refuses an unforced `qdel`; poisoning is on in test builds.

#### `move_into(holder, slot_id, item, actor, ledger_slot, force, log, key, amount)`
Need: the one transfer verb: checks both sides, releases, adopts into a declared owned var or ledger slot, records.
Defined: `code/engine/declare/transfer.dm:51`
Example: `move_into(holster, nameof(holster.holstered), primary)`, `code/content/antagonist/outsider/raider.dm:258`
Replaces / bans: raw `loc` / `contents` writes for owned slots (the `containment` lint).
Notes: a refusal changes nothing and logs `MOVE_INTO: ...`. `force` skips checks but not bookkeeping. To adopt without moving, use `rel_set` / `rel_add`.

## 7. Time: delays, repeats, long work

Effects never sleep. No `spawn`, gameplay `sleep`, `INVOKE_ASYNC`, `do_after`, `addtimer`, `stoplag`. Waiting is a timer, a job, or a `wait()` part on an op.

#### `after(owner, delay, handler, key =, clock = CLOCK_OWN, with =, keeps_dead =)`
Need: a one-shot delayed call owned by a datum.
Defined: `code/engine/time/after.dm:140`
Example: `after(shadekin, 10 SECONDS, TYPE_PROC_REF(/mob, death))`, `code/content/admin/player_effects.dm:203`
Replaces / bans: `om_after`, `addtimer`, `spawn` / `sleep` in effects.
Notes: the same `key` on the same owner replaces the pending timer; never store the returned id, use a key. Helpers: `cancel_after` (`code/engine/time/after.dm:73`), `after_pending` (`code/engine/time/after.dm:85`), `after_left`, `after_unique`, `after_if_alive`.
`CLOCK_OWN` pauses with stasis, `CLOCK_WORLD` is real time. Datum arguments in `with =` are captured as tokens; a gone argument arrives as null and the call is dropped and logged unless `keeps_dead = TRUE`.

#### `every(interval, then(...), when =, members =, phase =, lane =, budget =)`
Need: declared periodic work, gated by a condition.
Defined: `code/engine/actions/reactions.dm:164`
Example: `every(2 SECONDS, then(PROC_REF(mode_step)), when = nameof(mode_running))`, `code/content/admin/game_mode_panel.dm:133`
Replaces / bans: `DECLARE_PERIODIC_WHILE`, `DECLARE_REPEAT`, `PERIODIC_*`, `START_PROCESSING`, the `process()` model.
Notes: `when` takes a var name, a `PROC_REF`, or `all_of()` / `any_of()` / `not()`. A system's version is `. += every(1 SECOND, PROC_REF(sweep), lane = LANE_BACKGROUND)` in `reactions()`.

#### `wait(t, keeps =, repeats =, after_step =)` and `then(handler, checks =, early =)` (op parts)
Need: an op's timed delay, and the effect that runs when it ends.
Defined: `wait` at `code/engine/parts/part.dm:396`, `then` at `code/engine/actions/hooks.dm:83`
Example: `op("link_scanner", tool(TOOL_MULTITOOL), label("Link"), wait(0), then(PROC_REF(multitool_link)))`, `code/content/machinery/adv_med.dm:278`
Replaces / bans: `do_after`, `sleep` in effects; the task engine (gone).
Notes: `then` is also the handler wrapper in `every`, `after_init`, `on_notice` and `on_change`. `wait_until(until =)` is the unbounded form.

#### `job(owner, step, budget = 10, then =)`
Need: long work that must yield the tick, in chunks.
Defined: `code/engine/kernel/jobs.dm:32`
Example: `job(src, TYPE_PROC_REF(/datum/map_load, run_step), 20, TYPE_PROC_REF(/datum/map_load, finished))`, `code/content/maps/map_load.dm:110`
Replaces / bans: `stoplag`, `INVOKE_ASYNC`.
Notes: the step is `x(datum/act/timer/A)` and returns `JOB_MORE` or `JOB_DONE`.

#### Scheduler record and the deadline wheel (engine, not written by content)
Need: know what `after` / `every` sit on.
Defined: `/datum/scheduler_record` at `code/engine/time/records.dm:14`; wheel at `code/engine/time/deadlines.dm:13`
Example: not called by content.
Replaces / bans: `om_rec`, `om_sched`, `om_live_sched` (renamed `sched_rec`, `home_scheduler`, `live_scheduler`).
Notes: one wheel deadline per owner; timers are rows in the owner's record. Per-entity-frame sequences (mob Life) are `code/engine/kernel/sequence.dm`.

## 8. Events, input and reactions

#### Input: `click_on()`, `double_click_on()`, `drag_onto()`, `drag_over()`, `hover()`, `tooltip()`
Need: react to mouse input. One path: only `code/engine/kernel/entry.dm` overrides BYOND's `Click`, `DblClick`, `MouseDrop` and the other mouse procs; it reads `usr` once and builds a typed `/datum/input_event`.
Defined: `code/engine/lifeforms/input.dm:27`; `input_submit` at `code/engine/kernel/inbox.dm:553`
Example: `click_on(PROC_REF(dir_clicked))`, `code/content/admin/verbs/buildmode.dm:72`; `drag_onto(PROC_REF(rig_dragged))`, `code/content/clothing/spacesuits/rig/rig.dm:119`
Replaces / bans: any native mouse-proc override (`mouse_override`, hard ban, generated code included).
Notes: handler `x(datum/act/input/A)` with `A.actor`, `A.over`, `A.entered`, `A.params`. `INPUT_FALLTHROUGH` (`code/defines/engine/declare/lifeforms.dm:105`) sends the input on to default handling. A subtype re-declaring the form replaces the parent's entry; override the parent's handler and call `..()` to extend.

#### `ACTION(name, fields..., FIXED, notice =)` and `ACT_ATTEMPT(E, token, args)`, `act_done(A)`, `act_cancel(A)`
Need: a typed world event that others may refuse, take over or modify.
Defined: `ACTION` at `code/defines/engine/declare/markers.dm:54`, `ACT_ATTEMPT` at `code/defines/engine/declare/actions.dm:10`, `act_done` at `code/engine/actions/act.dm:260`
Example: `var/datum/act/attack_self/use = ACT_ATTEMPT(src, attack_self, user)` then `if(ACT_REFUSED_BY(use)) return TRUE` then `act_done(use)`, `code/content/click/item_attack.dm:33`
Replaces / bans: `intercept()`, `OM_EMIT`, `DAMAGE_REACTION`, `om_hook`, `TOPIC_ACTION`.
Notes: `ACT_ATTEMPT` returns an act, `ACT_PASS` (nothing hooked) or a refusal. `ACTION(name, FIXED, notice = /datum/notice/x)` is an event nothing can refuse (`code/library/input/input_notices.dm:5`).

#### `extend(/datum/act/x, needs(...) | instead(...) | adjusts(...))`
Need: refuse, take over or modify another type's action or op from your own block.
Defined: `extend` at `code/engine/declare/entries.dm:250`, `instead` at `code/engine/actions/hooks.dm:66`, `adjusts` at `code/engine/actions/hooks.dm:71`
Example: `extend(/datum/act/hit, instead(then(PROC_REF(mousetrap_thrown_trigger))))`, `code/content/assembly/mousetrap.dm:70`
Replaces / bans: `intercept()` and `acceptance()` (banned outside the engine).
Notes: an `instead()` with no `then` takes nothing. `adjusts_with(PROC_REF)` is the code form of `adjusts`.

#### `on_notice(/datum/notice/x, then(...))` and `observe(source, trigger, listener, parts...)`
Need: react after an event, on the type (`on_notice`) or on one source (`observe`).
Defined: `on_notice` at `code/engine/actions/hooks.dm:96`, `observe` at `code/engine/actions/hooks.dm:159`
Example: `on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))`, `code/content/artifice/telecube.dm:221`
Replaces / bans: `om_hook`.
Notes: `on_op("key", ...)` is sugar for an op-done notice.

#### `PUBLISH(E, token, args)`
Need: publish a past-tense fact that cannot be refused.
Defined: `code/defines/engine/declare/actions.dm:28`
Example: a notice type is declared with `ACTION(... FIXED, notice = ...)`; publishers call `PUBLISH`.
Replaces / bans: `OM_EMIT`. master's `NOTICE()` is an unrelated log macro (section 11).
Notes: pure fact; do not use it to ask permission.

#### `on_change(cond, ENTER|EXIT|ANY, then(...), at_most =, when =)`
Need: react to a state key or condition changing, batched per drain.
Defined: `code/engine/actions/change.dm:33`
Example: `on_change(nameof(density), ANY, then(PROC_REF(reset_path_repeat)))`, `code/content/admin/magnetic_console_panel.dm:16`
Replaces / bans: `om_changed`, `changed()` channels, `power_change()`-style overrides.
Notes: runs once per drain however many reads changed. A hop path like `nameof(terminal.charge)` watches the relation var and the far var.

#### `PUBLISH_CHANGE(E, key)`
Need: publish a key that is not one var (a tracked setter publishes its own key).
Defined: `code/defines/library/reactions.dm:92`
Example: `PUBLISH_CHANGE(M, MOB_KEY_STATUS)`, `code/content/atom/buckling.dm:90`
Replaces / bans: `state_changed` and the `CHANGE_EXPLICIT/RELATED/RELATION_ADDED/RELATION_REMOVED` channels outside the engine.
Notes: demand-gated by `READERS(E, key)`; an unread key costs one lookup. Engine entry points: `tracked_changed` (`code/engine/change/state.dm:100`), `state_changed` (`code/engine/change/refresh.dm:70`).

## 9. Ops, requirements and prompts

#### `op(key, parts...)`, `needs(...)`, `asks(...)`, `ui_act(...)`
Need: a player, AI or admin choice, with refusals, prompts, waits and effects.
Defined: `op` at `code/engine/parts/part.dm:85`, `needs` at `code/engine/parts/part.dm:380`, `asks` at `code/engine/parts/part.dm:445`, `ui_act` at `code/engine/parts/part.dm:227`
Example: `op("req_all", ui_act("req_all", arg("set_id", num())), then(PROC_REF(ui_act_req_all)))`, `code/content/admin/access_viewer.dm:11`
Replaces / bans: interactions, `DECLARE_INTERACTIONS`, the task engine, `om_ask`, the `/datum/req` flyweights, the `REQ_*` macros.
Notes: a window button is `op(key, ui_act(key, arg(...)), needs(...), asks(...), then(...))`, the action name stays the old string so TSX does not change.

#### `req(...)` and the native `req_*` parts
Need: a refusal. A requirement returns null to allow or a reason; never a boolean, never side effects.
Defined: `code/engine/parts/cond.dm:222`; `req_answer` at `code/engine/parts/answers.dm:20`; `req_empty_hand` at `code/library/requirements/actor_state.dm:6`, `req_access` at `code/library/requirements/actor_state.dm:30`
Example: `extend(/datum/act/equip, needs(req_arm_clearance()))`, `code/content/clothing/gloves/arm_guards.dm:10`
Replaces / bans: `/datum/req`, `requirement_composer()`, the `REQ_*` predicate macros.
Notes: a new requirement is a native `/datum/entry/part/req` in `code/library/requirements/`. A refusal that depends on what an `asks()` step was answered is `req_answer(PROC_REF(x), step = "name")`. The design is `doc/rewrite/proposals/admission.md`.

#### `all_of(...)`, `any_of(...)`, `not(cond, because =)`
Need: compose conditions and requirements into a tree.
Defined: `all_of` at `code/engine/parts/cond.dm:677`, `any_of` at `code/engine/parts/cond.dm:704`, `not` at `code/engine/parts/cond.dm:595`
Example: `every(PROC_REF(magnet_delay), then(PROC_REF(magnet_move_step)), when = all_of(nameof(path_moving), not(nameof(path_stopped))))`, `code/content/admin/magnetic_console_panel.dm:18`
Replaces / bans: `cond_not`, `cond_all`, `cond_any`, `none_of`.
Notes: take a var name, a stat id, a `PROC_REF` or a requirement.

#### `asks(/datum/prompt/kind, fields =, step =, optional =, default =)`
Need: ask a player a typed question inside an op; the handler reads `A.step_value("k")`.
Defined: `code/engine/parts/part.dm:445`; prompt kinds in `code/library/prompts/kinds.dm:14`
Example: `op("edit_memory", ui_act("edit_memory"), asks(/datum/prompt/text, fields = list("question" = "Write new memory"), step = "a2"), then(PROC_REF(ui_act_edit_memory)))`, `code/content/admin/edit_memory_panel.dm:29`
Replaces / bans: `rerun_ask`, `act_ask`, `cast_ask`, raw `input()` / `alert()` for players.
Notes: a cancel that must still proceed is `optional = TRUE, default = v`. Kinds: choice, text, number, yes_no, color, checklist, bitfield, colormatrix, file.

#### `open_request(owner, type, handler, fields...)` and `request_answer(actor, value, outcome =)`
Need: anything that waits for an answer (a prompt outside an op, an I/O request, a client query), with timeout, cancel and one outcome enum.
Defined: `code/defines/engine/kernel.dm:109`; `request_answer` at `code/engine/kernel/requests.dm:434`
Example: `open_request(src, /datum/prompt/choice/admin_restart_replay, PROC_REF(restart_replay_answered), answerer = user.mob, ...)`, `code/content/admin/admin.dm:137`
Replaces / bans: `prompt_flow`, `flow_ask`, `client_ask`, `om_ask`.
Notes: handler `x(datum/act/request/A)`; outcome `REQ_ANSWERED`, `REQ_CANCELLED`, `REQ_TIMED_OUT`.

#### `ask_sequence`: `start_ask_sequence`, `question_step`, `ask_child`, `ask_steps`
Need: ask a series of prompts for a tool that is not an op, with a done callback.
Defined: `code/defines/engine/prompts.dm:5`; `ask_child` at `code/content/prompts/sequence.dm:159`, `ask_steps` at `code/content/prompts/sequence.dm:238`
Example: `start_ask_sequence(/datum/ask_sequence/pin_value, user, null, list(question_step("type_name", /datum/prompt/choice, ...)), PROC_REF(value_ask))`, `code/content/prompts/sequence.dm:4`
Replaces / bans: `flow_ask`, `rerun_ask`, `verb_ask`, `client_ask`, `cast_ask`.
Notes: a step proc returns `ASK_STOP`, `ASK_WAIT` or `ASK_FINISH`. An admin verb uses `ask_steps`; an admin tool uses `ask_admin` (section 11).

## 10. Systems, kernel and I/O

#### `SYSTEM_DEF(x)` and `/datum/system`
Need: world-level state and periodic work; one global `SSx` per system. This is the only home for a new world-level mechanism.
Defined: `SYSTEM_DEF` at `code/defines/engine/kernel_timing.dm:52`; `/datum/system` at `code/world/kernel/system.dm:5`
Example: `SYSTEM_DEF(proximity)` with `periodic_runlevels`, `init_stage` and `VAR_PRIVATE/list/cells`, `code/world/systems/proximity.dm:30`
Replaces / bans: `SUBSYSTEM_DEF`, `fire()`, `SS_*` flags, `Recover()`, `world_service`, the Master Controller.
Notes: `needs` is the boot DAG; `phase` is `KERNEL_PHASE_K/S/N/U/D/P/R/G` (`code/defines/engine/kernel.dm:71`, default P); a periodic item is `every()` in `reactions()` with a `lane` (`code/defines/engine/scheduler.dm:5`); `roles` limits `join()`.
A system's `preinit()` runs from `New()`. Other folders call only the system's `api.dm` (the `system_boundary` lint). A system that walks a list saves its cursor and returns `STEP_YIELD` when `KERNEL_OVER_BUDGET`. The loop is `code/world/kernel/loop.dm`.

#### `safe_call(proc_ref, args...)`
Need: call something that can fail by design and get a `/datum/result`.
Defined: `code/engine/kernel/safe.dm:21`
Example: `var/datum/result/result = safe_call(PROC_REF(replay))`, `code/content/admin/news.dm:34`
Replaces / bans: raw `try` / `catch` outside the kernel (`silent_catch`).
Notes: the failure is not logged; the caller decides what it means.

#### `sql_ask(owner, query, params, PROC_REF(next), context...)` and `sql_answer_rows(result, error, what)`
Need: a database read whose answer the caller carries on from.
Defined: `code/engine/io/db.dm:73`, `sql_answer_rows` at `code/engine/io/db.dm:81`
Example: `sql_ask(src, "SELECT id FROM erro_player WHERE ckey = :ckey", list("ckey" = ckey), PROC_REF(ban_record_player_checked), bantype, ...)`, `code/content/admin/db_ban/functions.dm:47`
Replaces / bans: `prompt_flow`, `flow_select`, `flow_sql`, `flow_http_get`.
Notes: the callback is `on_done(result, error, context...)` on `owner`; a datum in the context is held weakly. `:name` placeholders only (SQL is parameterised); tables go through `format_table_name()`.

#### `sql_write(query, params)` and `http_ask(owner, url, PROC_REF(next), context...)`
Need: a write nobody reads back; an HTTP GET whose response the caller continues from.
Defined: `sql_write` at `code/engine/io/db.dm:63`, `http_ask` at `code/engine/io/db.dm:89`
Example: `sql_write("UPDATE [format_table_name("erro_player")] AS p ...")`, `code/content/admin/admin_ranks.dm:462`
Replaces / bans: `flow_sql` (no reader), `flow_http_get`.
Notes: the `http_ask` callback gets a `/datum/http_response`, or null on failure.

#### `/datum/io/sql` typed request and `db_query_now`
Need: a typed database read (declared row type); a blocking query only where BYOND itself waits.
Defined: usage header `code/engine/io/db.dm:3`; `db_query_now` at `code/engine/io/db.dm:116`
Example: `open_request(src, /datum/io/sql/permission_outer_admin_exists, PROC_REF(permission_outer_sql_ended), answerer = user, query = permission_query, ckey = .)`, `code/content/admin/permissionedit.dm:170`
Replaces / bans: positional rows.
Notes: `db_query_now` is allowed only for `world/IsBanned`, the boot schema check, boot-only loads and the shutdown flush; no `ALLOW` is accepted.

## 11. Presentation, UI, messages, logs

#### `draw(datum/look/look)` with `look.state`, `look.overlay`, `look.glow`, `look.watch`
Need: describe how an atom looks as a function of tracked state; a tracked write redraws it.
Defined: `/datum/look` at `code/engine/present/appearance_builder.dm:7`, `state` at `code/engine/present/appearance_builder.dm:88`, `overlay` at `code/engine/present/appearance_builder.dm:100`, `watch` at `code/engine/present/appearance_builder.dm:223`
Example: `/obj/effect/blob/draw(datum/look/look)` then `..()` then `look.state("[appearance_state()]")`, `code/content/blob/blob.dm:37`
Replaces / bans: `update_icon(`, `update_icons(`, the `APPEARANCE_*` look forms, raw `add_overlay()` and `overlays +=`.
Notes: the builder is reused and keyed, so an identical result churns no overlays. `look_overlay_image(...)` (`code/engine/present/appearance_builder.dm:470`) builds an overlay with plane, colour or flags; `look_cached_image` (`code/engine/present/appearance_builder.dm:919`) is the appearance cache. Cache appearances, not raw `/icon`. Draws never sleep and never write.

#### `interface("Window", title =, rights =, state =, forwards =)`
Need: declare the tgui window a type opens.
Defined: `code/engine/parts/part.dm:1021`
Example: `interface("AccessViewer", title = "Access Viewer", rights = R_DEBUG)`, `code/content/admin/access_viewer.dm:10`
Replaces / bans: `DECLARE_UI`, `DECLARE_UI_STATE`, `UI_ACT_FORWARD`, `UI_ACT`, `UI_DATA`, `UI_SUBACT` (all banned); `ui_window(mob/user)` (`code/library/sys/ui.dm:53`) survives only for `preinitialized = TRUE` hosts.
Notes: `interface("Foo")` maps to `tgui/packages/tgui/interfaces/<Name>.tsx` or `<Name>/index.tsx` (`tgui/packages/tgui/routes.tsx:51`). `tgui/packages/tgui/interfaces/generated/` is build output; never edit it.

#### `ui_data(datum/act/eval/A)`
Need: return the window's data (`A.actor` is the viewer, `A.holder` the holder).
Defined: `code/engine/present/outputs.dm:154`
Example: `/datum/access_viewer/ui_data(datum/act/eval/A)`, `code/content/admin/access_viewer.dm:69`
Replaces / bans: `UI_DATA`, `UI_DATA_REPLACE`.
Notes: merged over the capabilities' data under `data["caps"]`. Do not query the database inside it; load with `sql_ask` and show "loading".

#### `verb_entry(path, login =, when =, hidden =, name =, desc =, on =)` and `granted_verb(path)`
Need: declare a verb a type or capability has; grant one at run time.
Defined: `code/engine/present/verbs.dm:25`
Example: `verb_entry(/mob/living/proc/ventcrawl)`, `code/content/mob/living/carbon/alien/alien_damage.dm:5`; `grant(Tar, granted_verb(...), Tar)` (section 4)
Replaces / bans: `DECLARE_VERB`, `DECLARE_VERB_IF`, `DECLARE_VERB_HIDE`.
Notes: the verb store is the only writer of a verbs list. A gameplay ability is an op, not a verb.

#### `ADMIN_VERB(name, rights, "Name", "desc", category, args...)`, `ask_steps`, `ask_admin`
Need: define an admin verb and ask the admin a chain of questions; ask from an admin tool.
Defined: `ADMIN_VERB` at `code/defines/host/admin_verb.dm:39`, `ask_admin` at `code/content/admin/view_variables/pickers.dm:506`
Example: `ADMIN_VERB(change_weather, R_DEBUG|R_EVENT, "Change Weather", "Changes the current weather.", ADMIN_CATEGORY_DEBUG_EVENTS)`, `code/content/admin/verbs/debug.dm:666`
Replaces / bans: `verb_ask`, `rerun_ask`, `client_ask`, `flow_ask`, `DECLARE_VERB`.
Notes: reuse a picker with `asked.ask_child(/datum/ask_sequence/picker/vv_pick, ...)` (`code/content/prompts/sequence.dm:159`). A verb's tab is a `VERB_CAT_*` define.

#### `to_chat(target, html, type =)`, `visible_message(...)`, `says(MSG(x))` and `begins(MSG(x))`
Need: tell a player something; broadcast a sight or sound message; op feedback text.
Defined: `to_chat` at `code/library/ui/tgchat/to_chat.dm:67`, `visible_message` at `code/domains/world_model/atom/atom.dm:446`, `says` at `code/engine/parts/part.dm:820`
Example: `Tar.visible_message(span_danger("[target()] bursts into flames!"))`, `code/content/admin/player_effects.dm:164`
Replaces / bans: none.
Notes: op feedback is `says(MSG(...))`; world-visible text is `visible_message`; everything else is `to_chat`. Wrap text in `span_*` (`code/defines/host/span.dm:73`). `to_chat` is guarded by `OP_PURE_GUARD`.

#### `play_sfx(atom, SFX_ID, ...)` and `plays(SFX_X, at_start =)`
Need: play a named sound set; the op-part form.
Defined: `play_sfx` at `code/domains/damage/sound_sets.dm:42`, `plays` at `code/engine/parts/part.dm:854`
Example: `play_sfx(src, SFX_ARCADE_ORI_FAIL, ignore_walls = FALSE)`, `code/content/admin/orion_trail_panel.dm:26`
Replaces / bans: raw `playsound(...)` with a literal file.
Notes: an unknown id is a `CRASH`. Use `playsound(T, get_sfx(SFX_X), ...)` only when one shared file must play for everyone.

#### `fx_sparks(atom/where, amount = 3, cardinals = TRUE)`
Need: spark effect.
Defined: `code/content/effects/effect_system.dm:102`
Example: `fx_sparks(src, 3)`, `code/content/anomalies/anomaly.dm:27`
Replaces / bans: hand-rolled spark systems.
Notes: capped by `FX_SPARKS_MAX_LIVE`; returns with no turf.

#### Logging: `log_game`, `log_admin`, `log_attack`, `log_sql`, `WARNING(MSG)`, `NOTICE(MSG)`
Need: write to the right log.
Defined: `WARNING` at `code/host/helpers/logging/_logging.dm:8`, `NOTICE` at `code/host/helpers/logging/_logging.dm:25`, `log_game` at `code/host/helpers/logging/game.dm:2`, `log_admin` at `code/library/helpers/logging/admin.dm:7`
Example: `log_game("AI [holder ? "[holder] ([holder.type])" : "(no holder)"]: [text]")`, `code/domains/ai/brain/actions.dm:16`
Replaces / bans: none.
Notes: use the category helper when one exists, `WARNING()` for a broken invariant (it counts toward the boot gate, so a `WARNING` before the first test fails a focused run). AI tracing: `GLOB.ai_trace_all` or a brain's `traced` var and `/datum/ai_brain/proc/trace(text)`. Never remove existing tracing; add thorough logging for behaviour that is hard to observe.

#### `METRICS_EVENT(kind, category, signature, ckey, message, payload)` and `/datum/metrics_source`
Need: record a framework event, or sample a gauge every 10 s for the admin viewer.
Defined: `code/defines/engine/metrics.dm:39`; `/datum/metrics_source` at `code/content/metrics/metrics_sources.dm:7`
Example: `METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)`, `code/content/admin/admin.dm:1293`
Replaces / bans: metrics SQL written elsewhere.
Notes: to measure something new add a `/datum/metrics_source` with `collect()`; events come from single framework points only.

## 12. Content declarations

#### `loot(table =, count =, chance =, ...)`, `loot_spawn(path, loc, ...)`, `loot_search(table =, wake_chance =)`, `loot_decl_for(path)`
Need: a spawn table; roll it; a searchable pile.
Defined: `loot` at `code/library/loot/loot_entries.dm:37`, `loot_search` at `code/library/loot/loot_entries.dm:68`, `loot_decl_for` at `code/content/loot/loot.dm:88`, `loot_spawn` at `code/content/loot/loot.dm:244`
Example: `loot(table = list(/obj/item/clothing/head/cueball), chance = 30)`, `code/content/effects/landmarks.dm:126`; `configure(loot_search(table = /loot/mecha/odd_gygax))`, `code/content/structures/loot_pile.dm:21`
Replaces / bans: `DECLARE_LOOT` and the `LOOT_*` rows. Do not hand-roll spawn code.
Notes: a pure table is an abstract `/loot/...` type with its own `CAPABILITIES` block. Both are static entries compiled at world setup. Row constructors: `loot_set`, `loot_sub`, `loot_stack`, `loot_types`.

#### `map_resolver(GLOBAL_PROC_REF(x), vars = list(...))`
Need: a load-time map atom is resolved by a global proc.
Defined: `code/library/maps/map_resolver_entry.dm:24`; `map_resolver_proc` at `code/content/maps/map_resolvers.dm:13`
Example: `map_resolver(GLOBAL_PROC_REF(resolve_instantboom), vars = list("devastation", "flash", "heavyboom", "lightboom"))`, `code/content/effects/explosion.dm:66`
Replaces / bans: `MAP_RESOLVER`, `MAP_RESOLVER_VARS`.
Notes: a static entry; a subtype writes `configure(map_resolver(vars = ...))`.

#### `construction(start(...), stage(...), dismantle(...))`
Need: a build / dismantle ladder as declared stages.
Defined: `code/engine/declare/graph.dm:249`
Example: `construction(start(STAGE_FIREDOOR_ASSEMBLY_FRAME), stage(STAGE_FIREDOOR_ASSEMBLY_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(4 SECONDS), then(...)), dismantle(...))`, `code/content/machinery/doors/firedoor_assembly.dm:46`
Replaces / bans: hand-written `attackby` ladders.
Notes: `req_built(stage)` and `req_graph_at` are in `code/engine/parts/graph_ops.dm`. Add refusals with `extend("construction.dismantle", needs(...))`.

#### Icons: `*.png` + `*.dmi.toml`
Need: add or change an icon.
Defined: `tools/dq_icons/repack.py:1`
Example: edit the PNGs and `icons/<name>.dmi.toml`; the build repacks into `icons/gen/`.
Replaces / bans: hand-editing `icons/gen/`.
Notes: dirty-checked, 4 workers (`DQ_ICON_WORKERS`). Runtime DMI reads resolve to `icons/gen/`.

#### Changelog stub
Need: one YAML stub per user-visible PR.
Defined: `html/changelogs/example.yml:1`
Example: `html/changelogs/<author>-<branch>.yml` with `author`, `delete-after: true` and `changes: - rscadd: "..."`.
Replaces / bans: none.
Notes: `tools/ci/check_changelogs.sh` hashes `example.yml`; do not edit it.

## 13. Simulation domains

### Damage and health

#### `receive_damage(datum/damage_packet/packet)` and `deal_damage(kind, amount, armor_flag, source, ...)`
Need: deliver typed damage to any atom through one hookable path.
Defined: `receive_damage` at `code/domains/damage/damage_packet.dm:6`, `deal_damage` at `code/domains/damage/damage_packet.dm:114`
Example: `deal_damage(DAMAGE_THERMAL, joules / BURN_ENERGY_PER_INTEGRITY, FIRE, flags = DAMAGE_PACKET_SILENT)`, `code/content/behaviours/burning.dm:148`
Replaces / bans: `apply_damage`, `adjustBruteLoss` and `adjustFireLoss` (gone).
Notes: runs the `/datum/act/hit*` hooks, then `damage_sink()`; override `damage_sink()`, not this proc. A hand-built packet must be `release()`d. Variants: `receive_split`, `receive_explosion`, `receive_emp`, `receive_shock`.

#### `take_damage(damage_amount, damage_type, damage_flag, ...)`
Need: integrity damage on an atom with `uses_integrity`, skipping the hit hooks.
Defined: `code/domains/damage/atom_defense.dm:9`
Example: `take_damage(rand(100, 120) / brute_resist)`, `code/content/blob/blob.dm:26`
Replaces / bans: the old `health` / `maxhealth` model.
Notes: crashes without `uses_integrity`. Use `deal_damage` for damage from a source; `take_damage` only for integrity-internal ticks such as fire or decay.

#### `injure(kind, amount, zone, source, ...)` and `mend(tag, amount, target)`
Need: harm and heal a living mob. Every `/mob/living` has a `/datum/body`; there are no health pools.
Defined: `injure` at `code/domains/body/injury.dm:62`, `mend` at `code/domains/body/injury.dm:251`
Example: `Tar.injure(INJURY_BLUNT, organ_damage, our_organ, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)`, `code/content/admin/player_effects.dm:491`
Replaces / bans: health pools, `apply_damage`, `adjust*Loss`.
Notes: kinds `INJURY_*` and flags `INJURE_*` are in `code/defines/content/body.dm:34`, treatment tags `TREAT_*` at `code/defines/content/body.dm:79`. Numeric body stats are `STAT`s on `/mob/living` read as vars (`L.slowdown`). See `doc/body_architecture.md`.

### Heat

#### `get_temperature()` and `add_heat(joules)`
Need: read an atom's temperature (K); add or remove joules on it.
Defined: `code/domains/heat/heat.dm:28`, `add_heat` at `code/domains/heat/heat.dm:50`
Example: `add_heat(input_energy - useful_energy)`, `code/content/materials/engineering/material_equipment.dm:96`
Replaces / bans: `add_thermal_energy`.
Notes: a mob reads `body_temperature()` (`code/domains/heat/heat_mobs.dm:22`). `add_heat` creates the heat body on first divergence.

#### `heat_add(thing, joules, source)`, `heat_move(from, to, joules, source)`, `heat_set(thing, kelvin, source)`
Need: the booked network API; a reservoir may be a gas mixture, a turf, an atom, `HEAT_SPACE` or a store.
Defined: `code/domains/heat/heat_net.dm:74`, `heat_move` at `code/domains/heat/heat_net.dm:64`, `heat_set` at `code/domains/heat/heat_net.dm:105`
Example: `heat_add(air, joules, HEAT_SOURCE_FIRE)`, `code/content/behaviours/burning.dm:190`
Replaces / bans: any direct write of a mixture's temperature (there is none).
Notes: always pass a `HEAT_SOURCE_*` so the joules are booked. `heat_set` is an authority write (map load, admin, spawn) and the only way to set a mixture's temperature. Mob wrappers: `set_bodytemperature`, `adjust_bodytemperature` (`code/domains/heat/heat_mobs.dm:28`). Persistent flows are `heat_pump` / `heat_link` / `heat_engine` entries (`code/domains/heat/heat_entries.dm:1`).

### Atmospherics and gas

Gas math runs in the Rust arena. `/datum/gas_mixture` is an opaque handle; every call crosses the FFI, so cache reads in hot loops.

#### `/datum/gas_mixture` handle API
Need: read and write gas.
Defined: `code/domains/atmos/gasmixtures/gas_mixture.dm:163`
Example: `return_temperature()`, `return_volume()`, `total_moles()`, `get_moles(id)`, `get_gases()` (one call), `adjust_gas`, `set_moles`, `merge`, `remove`; write temperature with `heat_set(mix, K)`.
Replaces / bans: the DM `gases` assoc list and share / archive math (deleted).
Notes: `return_temperature` at `code/domains/atmos/gasmixtures/gas_mixture.dm:198`, `get_gases` at `code/domains/atmos/gasmixtures/gas_mixture.dm:182`. There is no `set_temperature()` on a mixture.
Gas ids are integers on the wire (`GAS_IDX`, `GAS_ID_*`, `code/defines/content/atmospherics_linda/atmos_gasses.dm:37`).

#### `gas_sample(air)` and `read_gas_mixtures(list)`
Need: the per-frame read cache; one call returns pressure, temperature, volume, heat capacity and every gas.
Defined: `code/domains/atmos/gas.dm:61`
Example: `var/datum/gas_sample/S = gas_sample(environment)`, `code/content/machinery/air_alarm.dm:340`
Replaces / bans: several getter calls per mixture in a loop.
Notes: a snapshot; it does not follow the mixture. Use `S.partial_pressure(id)`.

#### `return_air()`, `assume_air()`, `remove_air()`
Need: get or modify the air at an atom.
Defined: `code/domains/world_model/atom/atom.dm:95`; turf versions at `code/domains/atmos/environmental/linda_turf_tile.dm:159`
Example: `heat_add(loc.return_air(), released_joules, HEAT_SOURCE_REACTION)`, `code/domains/heat/heat_net.dm:30`
Replaces / bans: ZAS / XGM. `xgm_compat.dm` and `tg_infra_compat.dm` are stable compatibility API, not temporary shims.
Notes: DM reads the view pinned at the last `SSair` step plus its own writes; DM writes become ordered commands applied at the next frame (`code/domains/atmos/README.md`).

#### `gas_release(source, into, target_kpa, rate)`, `gas_dump`, `gas_fill`, `gas_touched(air)`
Need: add or move gas safely with the target woken and the pipenet revised.
Defined: `code/domains/atmos/gas.dm:22`
Example: `gas_release(air_contents, holding || loc, release_pressure, release_flow_rate)`, header example at `code/domains/atmos/gas.dm:17`
Replaces / bans: hand-rolled `remove` + `merge` loops.
Notes: after editing a mixture in place call `gas_touched`. `atmos_batch_transfer(list)` (`code/domains/atmos/native_air_api.dm:13`) applies many transfers in one call.

#### `gas_level(into =, reading =, above =, hysteresis =, air =)`
Need: react to a gas reading crossing a level.
Defined: `code/domains/atmos/gas_level.dm:1`
Example: `gas_level(into = nameof(overheated), reading = CH_GAS_TEMPERATURE, above = ARTIFACT_HEAT_BREAK, hysteresis = 50)`, `code/content/xenoarcheaology/artifacts/artifact.dm:27`
Replaces / bans: polling `return_pressure()` in a processing loop.
Notes: `CH_GAS_*` channels are in `code/defines/host/world_watch.dm:17`.

#### `sensed(reading =, bands | bands_from =, changed =, air =, strict | strict_from =)`
Need: hear a Rust-owned value move to another band, and only that.
Defined: `code/domains/verdigris/sense.dm:18`
Example: `sensed(reading = CH_GAS_TEMPERATURE, bands = list(T20C + 30), changed = PROC_REF(temperature_heard), air = nameof(watched_air))`, `code/tests/unit_tests/dq_sense_tests.dm:21`; handler `x(band, was)`.
Replaces / bans: nothing yet (it replaces `gas_level`, `watched(WATCH_GAS)` and per-holder band watches in later steps).
Notes: Rust keeps one `ThresholdSet` per (cell, channel) (`verdigris/ffi/src/sense.rs`); DM queues add/remove/forget and sends one `vg_sense_commit` per frame. Each add carries the band DM read, so a change between the read and the arming is still reported. `sensed_relevel(holder, changed)` re-registers after a limit is edited; `sensed_band(holder, changed)` reads the band now.

#### Gas reactions: `/transformation/gas/...`
Need: declare a gas reaction.
Defined: `code/domains/atmos/gasmixtures/reactions.dm:17`
Example: `takes = list(gas(/datum/gas/water_vapor, MOLES_GAS_VISIBLE)), holds = temperature_in(null, WATER_VAPOR_CONDENSATION_POINT)`, `code/domains/atmos/gasmixtures/reactions.dm:34`
Replaces / bans: `datum/gas_reaction`, `init_reqs`, `init_gas_reactions`, `priority_group`.
Notes: `air.react(holder)` walks the rules in declaration order; DM decides stoichiometry and rate, `gas_react(...)` (`code/domains/heat/heat_net.dm:127`) lets Rust settle the heat. The driver is `SYSTEM_DEF(air)` (`code/domains/atmos/ssair.dm:1`, phase N).

### Power, reagents, materials, life, AI

#### `set_power_supply(watts)`, `add_avail(watts)`, `use_power_oneoff`, `power_net_*`
Need: producers book supply; consumers draw; machines bind to the Rust cable network.
Defined: `code/domains/power/supply.dm:21`, `add_avail` at `code/domains/power/supply.dm:13`, `use_power_oneoff` at `code/content/machinery/machinery_power.dm:135`, `code/domains/power/power_net_api.dm:5`
Example: `set_power_supply(amount)` writes `native_write(src, NATIVE_PRODUCER_SUPPLY, amount)`, `code/domains/power/supply.dm:26`
Replaces / bans: DM-side powernet math; `use_power(` (deprecated).
Notes: `set_power_supply` is persistent and a repeat is free; `add_avail` is for the next step only. Declare consumption with the `powered(channel)` capability (`code/domains/power/powered.dm:1`). `apc.charge_now()` pulls the exact charge from Rust.

#### `/datum/reagents` holder API
Need: add, remove and move chemicals.
Defined: `add_reagent` at `code/domains/world_model/reagents/holder.dm:154`, `remove_reagent` at `code/domains/world_model/reagents/holder.dm:233`, `trans_to_holder` at `code/domains/world_model/reagents/holder.dm:338`
Example: `beaker.reagents.add_reagent(br.reagent_id, amt_to_actually_dispense)`, `code/content/machinery/biogenerator.dm:185`
Replaces / bans: `chemical_reactions*`, `required_reagents`, `distilling_temp_range` (reaction tables).
Notes: reactions are `/transformation/...` rules settled by `handle_reactions()` (`code/domains/world_model/reagents/holder.dm:142`). Transfers go through `trans_to_holder`; `begin_batch()` / `end_batch()` defer reaction checks across multi-step edits. Never write the shared empty `reagent_list`.

#### Material science
Need: engineered materials that change assembly behaviour.
Defined: `code/content/materials/engineering/material_service.dm:1`
Example: `damaged_object.material_service_event(MATERIAL_EVENT_DAMAGE, ...)`, `code/domains/damage/atom_defense.dm:45`
Replaces / bans: none.
Notes: `material_service_of(O)` is null until the object is admitted to continuous exposure. See `doc/material_engineering_implementation.md`.

#### Mob life: `life_steps()` and `/datum/sequence/life`
Need: a mob's Life as a kernel sequence of declared steps.
Defined: `code/domains/life/life_steps.dm:22`
Example: `. += seq_step(PROC_REF(life_light), after = list(LIFE_INPUT), ...)`, `code/domains/life/life_steps.dm:28`
Replaces / bans: a monolithic `/mob/living/Life()`.
Notes: per-subtype work goes in `life_type_pre` / `life_type_post`. Each step has a `_due()` proc that must be overridden with it.

#### AI: `/datum/ai_brain` public API
Need: external code steers a mob's AI.
Defined: `code/domains/ai/brain/public_api.dm:1`
Example: `ai_brain.go_wake()`, `code/content/mob/living/simple_mob/subtypes/animal/alien_animals/catslug/catslug.dm:152`
Replaces / bans: `/datum/ai_holder`.
Notes: behaviours are flyweights (`dq_get_behavior(type)`); per-mob state lives on the brain's `behavior_state_of(type)`. Pack, factions and standings are separate files under `code/domains/ai/`.

### Expeditions, flights, movement

#### `SSexpedition` and `SSflight`
Need: generate, materialize and release expedition sites; own vessels, destinations and flight plans.
Defined: `code/content/expedition/expedition_controller.dm:81`, `code/content/flight_operations/flight_controller.dm:4`
Example: `SSflight.register_vessel(ship)`, `SSflight.create_plan(vessel, destination)`, `code/content/flight_operations/api.dm:7`
Replaces / bans: `GLOB.expedition_service` and `GLOB.flight_service` (gone).
Notes: expedition sequence `plot_for_vessel`, `generate_site`, `materialize_site`, `release_site` (`code/content/expedition/api.dm:98`). Z-levels come from `load_new_z` (`code/content/maps/map_template.dm:136`) and are recycled inside `release_site`.

#### `forceMove(destination)` and `moveToNullspace()`
Need: change an atom's `loc` with hooks.
Defined: `code/domains/world_model/atom/atoms_movable.dm:402`
Example: `forceMove` crashes on a null destination and routes to `doMove`.
Replaces / bans: raw `loc` writes (the `containment` lint).
Notes: `abstract_move` is for ghosts and effects. For owned slots use `move_into` (section 6).

## 14. The Rust boundary

DM holds handles; simulation state lives in Rust (verdigris). `vg_*` binds are generated; content calls its domain's api, never the bind.

#### Generated binds: Rust functions become `vg_*` procs
Need: call Rust from DM.
Defined: `frame_set_tick_lag` at `verdigris/ffi/src/frame.rs:94` (the Rust fn becomes `vg_frame_set_tick_lag`)
Example: `vg_frame_set_tick_lag(world.tick_lag)`, `code/domains/verdigris/system.dm:66`
Replaces / bans: raw `call_ext` (rejected outside its allow list); `vg_*` in content (`banned_outside` in `tools/ci/lint_scopes.toml`).
Notes: to add a bind write the Rust fn with `#[auxmacros::bind]` and run `tools/build/build.sh verdigris-bindings`. The output `code/__defines/verdigris/_bindings.dm` is gitignored. `verdigris_init(VERDIGRIS_ABI)` checks the ABI hash at boot. Wrap binds in a domain `*_api.dm` proc as `code/domains/verdigris/native_api.dm` does.

#### `native_read(E, key, index)` and `native_write(E, key, value, index)`
Need: read or write a Rust-owned component field; `key` is `NATIVE_KEY(code, field)`.
Defined: `native_read` at `code/domains/verdigris/system.dm:325`, `native_write` at `code/domains/verdigris/system.dm:306`
Example: `native_write(serving, NATIVE_APC_STATIC_LOAD, equip_load, 0)`, `code/content/machinery/power_bridge.dm:64`
Replaces / bans: DM mirrors of Rust-owned fields.
Notes: reads are cached per frame by (entity, key). The domain wrapper (`heat_body_*`, `power_net_*`, `atmos_*`) wins where one exists.

#### `vg_frame` and the outbox
Need: the one per-tick call into the simulation; Rust events come back as records.
Defined: `code/domains/verdigris/system.dm:95`
Example: `var/list/box = vg_frame(elapsed, budget)`, `code/domains/verdigris/system.dm:95`
Replaces / bans: `vg_world_tick`, `vg_drain_events`, `vg_world_step`.
Notes: records are `NATIVE_REC_CHANGED` / `NOTICE` / `CROSSED`, delivered as `native_publish_change`, `native_publish_notice` and `native_crossed`. A frame over `NATIVE_SLOW_FRAME_MS` is logged with the Rust phases that grew.

#### Watches: `watched()`, `world_watch_when()`, `heat_watch_threshold()`
Need: wake DM when a Rust-owned value crosses a level. Five forms exist today (section 18).
Defined: `watched` at `code/domains/heat/watched.dm:45`, `world_watch_when` at `code/engine/time/world_watches.dm:47`, `heat_watch_threshold` at `code/domains/heat/heat.dm:395`
Example: `rel_set(src, nameof(thermostat_watch), heat_watch_threshold(src, src, limit, FALSE, PROC_REF(on_thermostat)))`, `code/content/food/kitchen/cooking_machines/_cooker.dm:191`
Replaces / bans: per-object `on_*_wake()` overrides.
Notes: reactive code (a draw, a stat, a requirement) reads `watched()` or uses `gas_level`; imperative code uses the `*_watch_*` procs. Hold the returned watch with `rel_add` / `rel_set`; cancel with `qdel(watch)`.

## 15. Shared helpers

Macros are in `code/defines/host/` and `code/defines/engine/`; procs in `code/host/helpers/`. Use these; do not write a second helper.

| Need | Use | Defined |
|---|---|---|
| Null-safe per-instance list | `LAZYADD` / `LAZYSET` / `LAZYLEN` | `code/defines/host/_lists.dm:14` |
| Random element with a fallback | `DEFAULTPICK(L, default)` | `code/defines/host/_lists.dm:5` |
| Weighted pick from `list(item = weight)` | `pickweight(L)` (read-only, null-safe) | `code/host/helpers/_lists.dm:247` |
| Take a random element out | `pick_n_take(list)` | `code/host/helpers/_lists.dm:273` |
| "Is this one of these types" | `typecacheof()` into a `var/static/list`, then `is_type_in_typecache()` | `code/host/helpers/_lists.dm:139` |
| Player text | `sanitize()`; names `reject_bad_name()` | `code/host/helpers/text.dm:42` |
| Time constants | `5 SECONDS`, `TICKS` (postfix macros) | `code/defines/engine/time.dm:19` |
| Constants in a global | `GLOBAL_LIST_INIT` / `GLOBAL_DATUM_INIT`, read as `GLOB.x` | `code/defines/host/__globals.dm:40` |
| All live instances of kind X | `REGISTRY_MEMBERS(id)`, declared with `DECLARE_REGISTRY` | `code/defines/engine/registries.dm:23` |
| A holder's contents | `contents_of(atom, type)`, `locate_within()`, `contents_count()` | `code/engine/refs/containment/spatial.dm:78` |
| What is on a tile or in an area | `turf_contents_of_type()`, `locate_on()`, `area_contents_of_type()` | `code/engine/refs/containment/spatial.dm:19` |
| Line-of-sight and range lists | `dview()`, `urange()` | `code/host/helpers/view_range.dm:12` |
| A server config entry | `CONFIG_GET(X)` | `code/defines/host/configuration.dm:2` |

#### `GLOBAL_LIST_INIT(X, v)`, `GLOBAL_DATUM_INIT(X, T, v)`
Need: declare a global.
Defined: `code/defines/host/__globals.dm:40`
Example: `GLOBAL_DATUM_INIT(AdminProcCallHandler, /mob/proccall_handler, new())`, `code/content/admin/callproc/callproc.dm:2`
Replaces / bans: raw `var/global`; `GLOBAL_REAL`, `GLOBAL_RAW`, `GLOBAL_VAR_CONST`; `GLOBAL_LIST_*(...cache...)`.
Notes: do not add a global list of instances; use a registry.

#### `REGISTRY_MEMBERS(id)`, `REGISTRY_COPY(id)`, `DECLARE_REGISTRY(PATH, ID)`
Need: "all live instances of kind X".
Defined: `code/defines/engine/registries.dm:23`, `DECLARE_REGISTRY` at `code/defines/engine/lifecycle_decl.dm:42`
Example: `for(var/mob/M in REGISTRY_MEMBERS(REGISTRY_MOBS))`, `code/content/admin/admin.dm:28`
Replaces / bans: `GLOB.x += src` lists and `GLOBAL_LIST_BOILERPLATE()` (the `registry` lint).
Notes: membership follows the lifecycle, so nobody adds or removes by hand. `REGISTRY_MEMBERS` is read-only; `REGISTRY_COPY` before anything that may delete members.

#### `contents_of(atom, type)`, `locate_within(atom, type)`, `turf_contents_of_type(T, type)`, `locate_on(T, type)`
Need: read a holder's contents, a tile, or an area without raw `contents` / `loc` reads.
Defined: `code/engine/refs/containment/spatial.dm:78`, `locate_within` at `code/engine/refs/containment/spatial.dm:92`, `turf_contents_of_type` at `code/engine/refs/containment/spatial.dm:19`
Example: `for(var/obj/tool in contents_of(mult_belt))`, `code/content/admin/modify_robot.dm:891`
Replaces / bans: `in X.contents`, `length(contents)`, `locate(...) in` over a raw list (the `spatial` lint, outright ban).
Notes: a justified raw read carries `// ALLOW(spatial): reason`.

## 16. Tests and tooling

#### `/datum/unit_test` with `Run()` and the `TEST_ASSERT*` macros
Need: write a unit test.
Defined: `TEST_ASSERT` at `code/tests/unit_tests/_unit_tests.dm:13`, `TEST_FAIL` at `code/tests/unit_tests/_unit_tests.dm:9`
Example: `TEST_ASSERT(powered(), "Machine is not powered")`, `code/tests/unit_tests/README.md:57`
Replaces / bans: `om_test_begin` / `om_test_end` (gone).
Notes: register a new file in `code/tests/unit_tests/_unit_tests.dm` by hand. `TEST_ASSERT*` returns from `Run()`, so a restore line after a failed assert never runs; use `defer_cleanup`. Test-only code stays behind `#if defined(UNIT_TESTS)`. Never commit a line in `code/tests/unit_tests/dq_focus.dm`.

#### `allocate(type, ...)`, `set_global`, `set_var`, `set_config`, `defer_cleanup`
Need: create objects and change shared state in a test with teardown that runs even on failure.
Defined: `allocate` at `code/tests/unit_tests/unit_test.dm:969`, `set_global` at `code/tests/unit_tests/unit_test.dm:683`, `defer_cleanup` at `code/tests/unit_tests/unit_test.dm:698`
Example: `defer_cleanup(src, PROC_REF(restore_tile), x, y, z, original_type)`, `code/tests/unit_tests/dq_a7_initialization_tests.dm:81`
Replaces / bans: raw global writes in tests (the state guard logs `STATE LEAK`).
Notes: put objects on the test's own block, not at a fixed coordinate.

#### `test_driver_begin()`, `test_time(t)`, `kernel_test_begin()`
Need: make kernel time pass or send input inside a test.
Defined: `test_driver_begin` at `code/tests/driver/driver.dm:133`, `test_time` at `code/tests/driver/driver.dm:209`, `kernel_test_begin` at `code/tests/driver/kernel_clock.dm:36`
Example: `test_driver_begin()`, then `test_time(0.1 SECONDS)`, `code/tests/unit_tests/dq_a4_initialization_tests.dm:122`
Replaces / bans: `sleep` in tests; `om_test_begin`.
Notes: use `test_driver_begin()` for new tests; `kernel_test_*` stays where a file already uses it.

#### `bash tools/dq_focused_test.sh <names>`
Need: run only the tests you touched. Agents never run `build.sh dm-test` (the full suite).
Defined: `tools/dq_focused_test.sh:1`
Example: `bash tools/dq_focused_test.sh belly_damage spritesheets`
Replaces / bans: none.
Notes: capped at `DQ_FOCUSED_MAX_MIN` (default 10); never wrap it in `timeout`. An exhaustive test is refused unless `--allow-exhaustive`; run its `/representative`. The same arguments on the same tree twice in two hours are refused. Reference: `doc/testing.md`.

#### `analyze`, `ALLOW(...)`, `check_ratchets.sh`
Need: lint, baseline and fix.
Defined: `tools/analyze/src/main.rs:223`, `tools/ci/check_ratchets.sh:1`
Example: `bash tools/ci/check_ratchets.sh --changed-only`; `spawn(0) // ALLOW(scheduler): world.Export() is a blocking external call`
Replaces / bans: the old Python lint scripts and allowlist files.
Notes: a site that is right as it is carries an inline `ALLOW(lint): reason` (reason of 20 characters or more, 3 words or more); an annotation no lint used fails the full run. Path exemptions, ceilings and lists live in `tools/ci/lint_scopes.toml`. `analyze baseline --update` drops fixed sites and never adds one. Do not annotate new debt to get under a ceiling.

#### `gen_dme.py`
Need: wire a file into the build.
Defined: `tools/build/gen_dme.py:1`
Example: `python3 tools/build/gen_dme.py`; a new order dependency needs a `before` rule in `tools/build/dme_spec.txt`.
Replaces / bans: hand-editing `deepquarry.dme`.
Notes: every build target that compiles or lints DM regenerates the manifest; commit the result.

#### `bash tools/dq_land.sh` and `bash tools/dq_lane_pool.sh`
Need: land a lane; get a worktree.
Defined: `tools/dq_land.sh:1`, `tools/dq_lane_pool.sh:1`
Example: `DQ_LANE_POOL_SIZE=7 bash tools/dq_lane_pool.sh lease <branch> --wait`
Replaces / bans: `git worktree add` by hand.
Notes: see AGENTS.md section 4.

## 17. Banned forms and what replaced them

These names are rejected by a hard lint (`[lint.legacy_forms.lists]` in `tools/ci/lint_scopes.toml`, empty baseline) or by their own hard lint. The checker verifies that every name in the
first column is still a banned name there. Full lists and hints are in that file; `bash tools/ci/legacy_form_counts.sh` is the census.

| Banned | Use instead |
|---|---|
| `om_after` | `after()` (section 7) |
| `om_hook`, `DAMAGE_REACTION`, `OM_EMIT` | `extend(... instead / needs / adjusts)`, `on_notice()`, `observe()` (section 8) |
| `om_ask`, `prompt_flow`, `flow_select`, `flow_sql`, `flow_http_get`, `rerun_ask`, `verb_ask`, `client_ask`, `cast_ask`, `flow_ask` | `asks()`, `ask_steps()`, `ask_admin()`, `sql_ask()`, `http_ask()` (sections 9, 10) |
| `om_grant`, `DECLARE_VERB`, `DECLARE_EMAG` | `grant()`, `verb_entry()` (sections 4, 11) |
| `OM_FIELD`, `TOPIC_ACTION`, `DECLARE_PERIODIC_WHILE`, `DECLARE_REPEAT`, `PERIODIC_PLANTS` | tracked setters, `op(... ui_act ...)`, `every()` |
| `DECLARE_UI`, `UI_ACT`, `UI_DATA`, `UI_SUBACT`, `act_ask`, `ui_act_allowed` | `interface()`, `ui_data(datum/act/eval/A)`, `op(... ui_act ...)`, `asks()` (section 11) |
| `DECLARE_INTERACTIONS`, `acceptance`, `topic_allowed` | `op()`, `needs()`, `extend(/datum/act/equip, needs(...))` (section 9) |
| `ownership()`, `relations()`, `capabilities()`, `world_service` | `CAPABILITIES(T)`, `SYSTEM_DEF(x)` (sections 3, 10) |
| `cond_not`, `cond_all`, `cond_any` | `not()`, `all_of()`, `any_of()` (section 9) |
| `DECLARE_LOOT`, `MAP_RESOLVER`, `MAP_RESOLVER_VARS` | `loot()`, `map_resolver()` (section 12) |
| `EXPIRY_AT`, `EXPIRY_NOW`, `STAMP_ELAPSED`, `STAMP_AT`, `STAMP_POINT`, `STAMPED`, `STAMP_CLEAR`, `ELAPSED_SINCE`, `BEFORE` | `STAMP` / `ELAPSED`, `COOLDOWN_*` (section 4) |
| `TRACKED`, `TRACKED_BRIDGED`, `state_changed`, `CHANGE_EXPLICIT`, `CHANGE_RELATED` | generated setters, `PUBLISH_CHANGE()` (sections 4, 8) |
| `BF_*`, `factor(`, `DERIVE_ANY`, `DERIVE_ALL`, `DERIVE_MIN` | `STAT`, `hold()`, `factors()` (section 4) |
| `init_reqs`, `init_gas_reactions`, `priority_group`, `required_reagents`, `distilling_temp_range` | `/transformation/...` rules (section 13) |
| `vg_*` in content | the domain's `*_api.dm` (section 14) |

Banned without a toml row but enforced elsewhere: `del()`, a `Destroy()` override, `spawn` / `sleep` / `INVOKE_ASYNC` in effects, `LateInitialize()`, `INITIALIZE_HINT_LATELOAD`,
`/datum/weakref`, a raw write to `loc` / `contents`, raw `call_ext`, a native mouse-proc override.

## 18. Duplicate-systems index

Several mechanisms overlap today. For each: which one wins, and the lane that removes the rest. **Do not add another member of any of these families.** If you think you need to,
you are extending the winner, or the design is changing (section 1 of "Before you add a system"). Lane names are from `E:/projects/dq-engine-migration-plan.md` (the S-numbers are its steps) and are *landing*, not usable.

| Family | Members on master | Winner | Removing lane |
|---|---|---|---|
| A rare or timed value on an object | base var; `sparse()` (`code/engine/declare/sparse_slots.dm:46`); `cooldowns()` / `stamps()` tables (`code/engine/declare/sparse_slots.dm:82`); `COOLDOWN_*` and `STAMP` vars (`code/defines/engine/cooldowns.dm:16`); `COOLDOWN_KEYED_*` | Base types hold no var: rare state is `owns_one(lazy = TRUE)` (a `sparse()` slot is the old form being converted; its writes publish nothing), a base-type time value is `cooldowns()` / `stamps()`, a subtype's own time value is `COOLDOWN_*` / `STAMP`, a data-keyed one is `COOLDOWN_KEYED_*`. Choose by shape, never by a new macro. | `engine/storage-contract` (lazy owned state replaces sparse slots and stamp/cooldown tables used as storage; the time family and `derives()` stay) |
| Copy-on-write | `per_type(copy_on_write)` (`code/engine/lifeforms/per_type.dm:28`); `type_trait_own` (`code/engine/declare/type_traits.dm:154`); `owns_*(copy_on_write)` with `proto_private` (`code/engine/declare/entries.dm:172`); `LIST_STATE` COW (`code/engine/declare/relations.dm:468`) | `per_type(copy_on_write)` for a starting list, `type_trait_own` for per-type data, `owns_*(copy_on_write)` only for prototype objects. No new `LIST_STATE`. | `state/fields` (S3.5: one shared copy-on-write rule) |
| Lazy per-instance records (seven shapes) | `rx` (`code/engine/change/state.dm:14`); `sparse_slots`; `cooldown_table`; `type_trait_overrides`; scheduler `rec.dv`; `capability_runtime` (global list, `code/engine/declare/capability_tables.dm:5`); `rx.stats` | Do not add an eighth. New rare state is a lazy owned state (`owns_one(lazy = TRUE)`) or a `profile` record. | `engine/storage-contract` (each lazy shape becomes an owned state datum) |
| Derived values | `derives()` (`code/engine/lifeforms/derives.dm:23`); `derive()` inside `derived()` (`code/engine/change/derived.dm:104`); `derived_derived` DV rows (`code/engine/state/derived_values.dm:24`); `STAT ... FORMULA` | `derives()` for a derived var, `STAT` for a composed number. Leave `derive()` and the DV rows alone (no content callers). | `engine/demand-refresh` (S2.5: values on read) |
| Weak reference tokens | `ref_token` (`code/engine/time/handles.dm:59`); `own_key` (`code/engine/refs/ownership.dm:28`); `REF()` text (`code/engine/refs/ref_text.dm:3`); `SHARED_CACHE_UID` (`code/defines/engine/shared_cache.dm:52`); weak relations (`code/engine/refs/weak.dm:1`) | Store a `ref_token` or a `weak = TRUE` relation. `REF()` is request-local, never stored. `SHARED_CACHE_UID` only inside cache keys. `own_key` is engine-internal and not for new code. | `engine/refs` (S4.1: generational integer handles replace `own_key`, `own_locate` and the text token) |
| Relation stores | views (`code/engine/refs/views.dm:1`); owned (`code/engine/refs/ownership.dm:1`); sparse `link_ends` (`code/engine/declare/link_state.dm:1`); containment ledger (`code/engine/refs/containment/ledger.dm:1`) | Declare through `ref_*` / `owns_*` / `links` / `slot` and write through `rel_*`. | `engine/refs` (S4.5: collapse the stores) |
| Pending-work queues | `GLOB.refresh_queue` (`code/engine/change/refresh.dm:262`); `refresh_push_queue`; `GLOB.stat_marked`; `rx_drain`; `look_effects_due` | Write tracked state and let the engine mark; never queue work by hand. | `engine/demand-refresh` (S2.4: one scheduler with lanes) |
| Watches on Rust state | `watched()` (`code/domains/heat/watched.dm:45`); `world_watch_*` (`code/engine/time/world_watches.dm:47`); `heat_watch_*` (`code/domains/heat/heat.dm:395`); `gas_dependency_watch` (`code/domains/atmos/gasmixtures/gas_mixture.dm:157`); `gas_level` (`code/domains/atmos/gas_level.dm:1`); `on_cross` | Reactive code: `watched()` or `gas_level`. Imperative code: the `*_watch_*` procs. Do not add a sixth. | `native/sensing` (S5: `sensed()` / `on_sense()`), after `gas/watch-on-read` |
| Timers | `after()`; `every()`; `after_init()`; `job()`; `wait()` on an op; `COOLDOWN_*` (a var, not a timer) | Delays are `after`, periodic work is `every` with `when =`, yielding work is `job`. | `engine/refs` (S4.7: timer fixes) |
| Appearance caches | `look_cached_image` (`code/engine/present/appearance_builder.dm:919`); the look key `rx.look_key`; `GLOB.overlay_cache` (`code/library/helpers/global_lists.dm:641`); `set_cached_examine_icon` (`code/host/helpers/icons.dm:342`); `getFlatIcon` (`code/host/helpers/icons.dm:103`) | `draw(look)` with `look_overlay_image` / `look_cached_image`. | none scheduled; do not add a cache |
| Temperature reads and writes | `get_temperature()` (`code/domains/heat/heat.dm:28`); `body_temperature()`; `return_temperature()` on a mixture; `set_bodytemperature` / `adjust_bodytemperature` | Reads: `get_temperature` (`body_temperature` for mobs, `return_temperature` for mixtures). Writes: always `heat_add` / `heat_set` with a `HEAT_SOURCE_*`. | none; the wrappers stay |
| Gas getters | per-call `return_*` / `get_moles`; batched `gas_sample` / `read_gas_mixtures`; `adjust_gas`, `adjust_moles`, `set_gas` (one bind) | `gas_sample` for multi-field reads, `adjust_gas` for writes. `assume_gas` is a stable compatibility shim. | `native/sensing` (S5.3-S5.4: snapshot reads and batched writes) |
| Damage entry points | `receive_damage` / `deal_damage`; `take_damage`; `injure`; `bullet_act`; `ex_act` | Damage from a source: `deal_damage` / `receive_damage`. Integrity-internal ticks: `take_damage`. A mob always sinks into `injure`. | none |
| Ways to place an item | `move_into`; `forceMove`; `abstract_move`; `make(type, at =)` | `move_into` for owned slots, `forceMove` for plain moves. | none |
| Power draw | `use_power` (deprecated); `use_power_oneoff`; `power_draw`; `set_power_supply` / `add_avail` | Consumers: `use_power_oneoff`. Producers: `set_power_supply` (steady), `add_avail` (pulse). | none |
| Asking a question | `asks()`; `ask_steps()`; `ask_admin()`; `open_request(... /datum/prompt/x ...)`; `sql_view` | Choose by call context (section 9). All share `/datum/prompt` types. | none |
| Window opening | `interface()`; `ui_window(mob/user)` (`code/library/sys/ui.dm:53`) | `interface()`. `ui_window` remains only for `preinitialized = TRUE` hosts. | none |
| Random pick | `pickweight` (`code/host/helpers/_lists.dm:247`); `pick_weight` (`code/host/helpers/_lists.dm:892`); `safepick`; `DEFAULTPICK`; `pick_n_take` | `pickweight`. `pick_weight` writes into the caller's list. `DEFAULTPICK(L, null)` replaces `safepick`. | helper cleanup (migrate `pick_weight` callers) |
| Text sanitising | `sanitize` (`code/host/helpers/text.dm:42`); `sanitize_simple`; `sanitize_old`; `strip_html_simple`; `pencode2html` (`code/host/helpers/text.dm:366`); `pencode_to_html` (`code/content/paperwork/paper.dm:862`) | `sanitize()` for free text, `reject_bad_name()` for names. | helper cleanup (`sanitize_old` goes; merge the two pencode procs) |
| Test clocks | `test_driver_begin` (`code/tests/driver/driver.dm:133`); `kernel_test_begin` (`code/tests/driver/kernel_clock.dm:36`) | `test_driver_begin()` for new tests. | none |
| Instance lists | ledger holders; registries; hand-rolled `GLOB.x +=` with an `ALLOW` | Registry. An `ALLOW` is only for ckey-keyed tables that outlive the client. | `registry` ratchet |

## 19. Landing: designed or in flight, not usable

Nothing in this section exists on master. Do not write these forms, stub them, or invent them. Each has a **Probe**: a regular expression the checker runs over `code/`. While the probe finds
nothing the entry is correctly marked landing; the moment it finds something, the checker fails until the entry is moved into the body of this file with a `Defined:` line.
The designs are in `E:/projects/dq-engine-migration-plan.md` and `E:/projects/dq-design-review/*.md`; the lane that lands each is named.

#### Generational reference handles (references)
Landing: a datum gets an integer slot lazily when it becomes a borrow target or a handle target; a handle is (slot, generation) and replaces the text `ref_token` / `own_key`; the reverse index becomes flat integer lists; `engine_forget(D)` and a typed `borrow_ended` event; the GC queue becomes a leak counter. Lane `engine/refs` (S4).
Probe: `engine_forget\(|borrow_ended`

#### Demand refresh and the interest system
Landing: `pending` and `owed` bits are separate, draw-only init marks stay lazy, `SYSTEM_DEF(interest)` with per-client chunk sets replaces `refresh_drain_near`, one scheduler with lanes replaces the five queues, values compute on read. API sketch `demand_mark(E, kinds)`, `demand_value(E, node)`, `interest_source_add(source, chunks)`. Lane `engine/demand-refresh` (S1-S2).
Probe: `demand_mark\(|demand_value\(|interest_source_add\(`

#### Gas sensing: `on_sense()` and `read_cells()`
Landing: `on_sense(source, SENSE_x, above / below / band, then(...))` reacts to a sensed value without a holder-declared handler; snapshot reads with `read_cells(list, mask)` and batched writes from `push_to_rust()`. `sensed()` itself is on master. Lane `native/sensing` (S5), after `gas/watch-on-read`.
Probe: `(^|[^a-z_])(on_sense|read_cells)\(`

#### First-load pipeline: `place_turfs(list)`
Landing: all post-boot construction (expedition carve, POIs, cave generation) goes through one `place_turfs(list)` primitive that runs inside an init frame with lighting and adjacency deferred, then one `atom_init_job`; generated stations are built as data and only final turfs are emitted. Lane `gen/first-loads` (S7).
Probe: `place_turfs\(`

#### `cap_set` marks only the outputs that read the capability bit
Landing: `cap_set` marks only the outputs that read the bit. Lane `state/observable-sparse` (S3.2). Sparse and time-table writes are not made observable: their callers move to lazy owned state (above), which is observable, and the old forms are deleted.
Probe: `cap_set_marks_outputs\(`

#### The `stat(...)` entry form inside `CAPABILITIES`
Landing: a stat declared as an entry rather than a `STAT` line with a var of its own. AGENTS.md section 3a marks it **new**.
Probe: `^[[:space:]]+stat\(STAT_`

# Proposal: one admission and gating model for slots, equipment, machines and joins (design only)

Status: proposal, awaiting your sign-off on D1 to D11 (the content below follows the decisions already approved in the working session; where a
point was left open it is marked **open**). It replaces `proposals/clothing_requirements.md` (renamed to this file by `git mv`, then rewritten).
Scope: doc section 6 (`slot()`, containment), section 9 (requirements), section 17 (old to new), section 19 (migration), `containment.md`
(sections 2, 3, 4, 6, 8, 9, 10, 12).

Evidence base: `origin/master` at `1c1d649c08` (17 Oct 2026). Every `file:line` below was read at that commit. A claim I did not read is marked
**unverified**. Counts come from `git grep` and are exact for the pattern named, not for the idea behind it. The previous proposal cited
`cee490f697`; its counts moved (stated where it matters). "Master" below means `1c1d649c08`.

## 0. Summary

1. **Every "may this go here, may this be done" question is already asked through one engine, but answered in seven languages.** The engine
   is `/datum/entry/part/req` (`code/engine/parts/cond.dm:137-162`): a requirement is a check that yields null (allowed) or a reason, with a
   boolean view for conditions. Around it live six more evaluators that the new code still calls: `/datum/predicate` with the `REQ_*` macros
   (`code/engine/parts/predicates.dm:29`), `HOLD_*`/`CONSTRAINT_*` spec tables (`code/datums/properties/constraints.dm:32-90`), the old
   `/datum/req` flyweights and the `/datum/requirement` compatibility shim (`code/datums/operations/req.dm`, `native_requirement_adapter.dm`),
   `acceptance_leaf` parts with their own `acceptance_either/both` (`code/library/requirements/acceptance.dm`, `equip_slots.dm:291-303`), and
   the `cond_not/cond_all/cond_any` condition lists (`code/engine/declare/relations.dm:229-235`). A seventh, the `CHECK(/datum/requirement_definition/...)`
   language (`code/engine/declare/checks.dm`), is used by `holds_while` links (`definition_registry.dm:229-231`) and is tiny (7 `holds_while`, 5 `FACT`).
   Decision D1 collapses all of them into `req_*` plus `any_of`/`all_of`, with one reason type, `/datum/msg`.
2. **The slot API is missing the things the content needs, so content grew its own gates.** There are 83 `op("...insert...")` ops
   (cell charger, replicator, suit cycler, pandemic and so on), 18 `insert_refusal`/`can_insert` procs, a 20-line mech `can_attach`, a gun
   `load_ammo` that is a boolean ladder with `to_chat`, an RPED that swaps parts in a loop, a NIF that has two install checks. Each does one of:
   per-instance capacity, "fits", replace-if-better, partial insertion, or a non-movable member. D2 lists the engine gaps (wave 0); D6 folds the
   machines onto them.
3. **Clothing fit is a species list kept on every item and accessory.** 72 declarations (43 `acceptance("fit", fits(` + 29 non-null `fit_spec`) carry at least
   260 species literals, 122 `species_allowed` lists carry 230 more (only 12 distinct values; 86 of them are `list(SPECIES_TESHARI)`), and
   81 `sprite_sheets`/`sprite_sheets_obj` blocks key worn sprites by species. D3 inverts it: a species declares the categories it `wears`, an
   item declares one fit category and sprite sheets per category.
4. **Smaller approved cleanups.** Delete the dead `equip_slots.dm` predicate block (D4), move appearance writes out of "requirements" that are
   not pure (D5), let movement share the vocabulary through a fast path (D7), classify requirements as type-level or instance-level so latent
   holders keep working (D8), stop two eager allocations in the acceptance check (D9), make SPILL the default fate of slot contents (D10).
5. **Counts (master, content only):** 159 live `TYPE_TABLE` constraint specs (fit 29 non-null of 44, equip 25, hold 19, suit_storage 86);
   73 `REQ_*` content lines; 115 `HOLD_*` uses; 260 `cond_*` uses; 150 content `acceptance("channel")` declarations (fit 67, suit_storage 72,
   hold 7, equip 4) plus 19 slot-id declarations in the equip catalog; 55 call sites of the old `/datum/req` constructors; 89 registry slot
   declarations (50 in `body/slots.dm`) plus 18 `slot()` entries; 1656 `needs(` lines.

## 1. The unified gating model

### 1.1 The language

- **Requirement.** A check on a typed act context (`datum/act/A`). It returns **null** to allow, or a **`/datum/msg`** reason: a type for a fixed
  reason (`MSG(slot/too_large)`), an instance when the reason carries detail (**new**; today detail is smuggled through the `%DETAIL%` template of
  `/datum/msg/req_refused`, `code/engine/parts/reasons.dm:5`, or through raw text). A detailed reason is a message instance, `msg_reason("too big: 3 > 2")` (**resolved**: `/datum/msg/instance`,
  `code/engine/present/messages.dm`). It never writes, publishes or messages (purity, enforced by
  `op_pure_begin()` around every evaluation, `engine/parts/acceptance.dm:156-164`). No booleans, no text, no `TRUE`-or-reason.
- **Condition.** The same check read without its reason: `holds = isnull(check)`. A library part implements `holds()` and `refusal()` apart, so a
  condition never builds a reason (`cond.dm:151-152`: `check()` is `holds(A) ? null : refusal(A)`). A requirement is accepted wherever a condition
  is. This is the state master already has: `requirement_bool` bans the boolean constructor and `boolean_callback`, and requirement callbacks
  return null or the exact refusal (`doc/requirements_hard_ban_1010_handoff.md`, merged; `cond.dm:228`).
- **Combinators.** `all_of`, `any_of`, `not(r, because =)`, and `with_reason(r, because)` (**resolved**, 18 Oct: a variadic proc rejects a named
  argument it does not declare, BYOND's "bad arg name", tested by `dq_slot_admission_with_reason`; so `any_of(..., because =)` cannot exist and a
  combinator gets its reason from the wrapper), and nothing else. `any_of` joins its reasons ("needs a wrench or a welder"),
  `all_of` reports the first failure (`cond.dm:614-647`).
- **Reason type.** `/datum/msg` only (`code/engine/present/messages.dm:15`). Retired: raw strings (85 `because = "` sites, about 15 literal reason returns in
  `library/requirements/acceptance.dm`, `pred_holding_knife_holds` returning "there is no knife in it" at `clothing.dm:615`), `TRUE`-or-reason procs
  (`dq_equip_*` at `equip_slots.dm:215-263`), bool-plus-`to_chat` guards (`stripping.dm:76-78`, `buckling.dm:223-244`, `nif.dm:429-447`,
  `projectile.dm:587-589`) and `GLOB.act_last_reason` as a side channel (35 reads and writes in 12 files). A refusal's text is derived from the
  type (`reason_text`, `cond.dm:39-50`); how it is shown is the message's `display`.

### 1.2 Attach points

| Attach point | Takes | Evaluated | State on master |
|---|---|---|---|
| Slot `accepts =` | a type, a type list, or a requirement: what may be in | on every insert into the slot, before capacity | `slot()` declared form takes type or native requirements but refuses to mix them (`slot_def.dm:316-328`); registry slot decls take only a legacy `/datum/predicate` type (`slot_def.dm:43-44`, `225-230`) |
| Slot `fits =` | a requirement on size and shape | after `accepts`, before capacity | in doc section 6, **absent** from `slot()` (`entries.dm:190`); only `cell_bay` has a `fits` argument (`cell_bay.dm:5,26`) |
| `needs()` on an op | requirements | Require stage, again after Wait and before Do | works (1656 lines) |
| `extend(/datum/act/insert \| remove \| equip, needs(...))` | requirements | at `ACT_TRY` and in the pre-check query | `insert` and `remove` work (`transfer_requirements.dm:12-41`, `api.dm:72,86`); `equip` and `unequip` are declared (`contracts/acts/world_actions.dm:38-39`) but nothing tries or hooks them |
| `when()` | conditions | Match stage (silent fall-through) | works |
| `links(..., holds_while =)` | a condition | one tick after either end moves | compiled by the `CHECK` language (`definition_registry.dm:229-231`) |
| `acceptance("channel", ...)` | requirements | by channel name (`fit`, `equip`, `hold`, `suit_storage`, or a slot id) | **interim**: 182 declarations (150 content, 19 equip catalog, 13 tests). Endgame per doc section 17: the channel becomes a slot `accepts =` or a hook on an action |

One question, one place: *what may be in a slot* is the slot's (`accepts`, `fits`, capacity); *what the machine or the actor must be like for it* is
a `needs()` on the action or op; *whether the thing may leave* is the same on `/datum/act/remove`.

### 1.3 What is out of scope, and why

| Out of scope | Why |
|---|---|
| Chemical reactions and recipes (matching data to products) | a data-matching system, not a gate; see `doc/rewrite/proposals/transformations.md` (branch `rewrite/transform-proposal`, commit `8b3ba3e2c9`, section 8). It uses conditions only in matched mode and bridges a chosen transformation to a player through a library requirement `can_transform(X)` whose reason is computed on demand (its 8.1), which is this document's condition/requirement split unchanged. Only the *gates* around them (can this beaker take 30 units) fold here |
| Stat composition (`stat`, `contributes`, `hold`) | owned by `proposals/stat_layer.md`; conditions gate contributions but the math is not ours |
| Costs, cooldowns, resource reservation (`costs`, `cooldown`) | a resource ledger (doc section 9, X2); `req_cooldown(key)` only *reads* it (D6) |
| Input matching (`hand()`, `item(T)`, `tool(Q)`, `ui_act`) | bindings are the Match stage, not requirements |
| The kernel's request outcome enum (`REQ_ANSWERED`, `REQ_CANCELLED`, ...) | kept by doc section 9; the lint must key on the macro list, not the `REQ_` prefix (previous proposal D6, unchanged) |
| Damage, armour and heat paths | propagation math (`containment.md` section 3.2); only "can a hit reach this slot" shares the vocabulary |
| UI-window access | already a requirement (`req_window_usable`, 16 uses) |
| Physics of passage | the *fast path* shares the vocabulary (D7); pass flags and density stay engine stats |

## 2. Census: what each language answers today

The same question, "may this go in a pocket", answered three ways (all read at master):

```
// 1. predicate language (dead code, equip_slots.dm:39-44)
spec = list(REQ_PROC(/proc/dq_equip_has_uniform, null), REQ_NO_TAG(PRED_TARGET, TAG_NO_POCKET),
    REQ_BECAUSE(REQ_ANY(REQ_AT_MOST(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(ITEMSIZE_SMALL)), REQ_TAG(PRED_TARGET, TAG_POCKETABLE)), "too big for a pocket"))
// 2. acceptance leaves with their own combinator (live, equip_slots.dm:275)
acceptance(SLOT_ID_POCKET_L, req_acceptance_has_uniform(), req_acceptance_tag(TAG_NO_POCKET, exclude = TRUE),
    req_acceptance_either(list(req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_SIZE_CLASS), req_acceptance_tag(TAG_POCKETABLE)), "too big for a pocket"), mode = ACCEPTANCE_REPLACE)
// 3. a storage capability reading w_class directly (storage.dm:190-192)
if(!isnull(biggest) && W.w_class > biggest)
    return "\the [W] is too big for \the [holder]"
```

| Language | Where | Size at master | Replaced by |
|---|---|---|---|
| `/datum/predicate` + `REQ_*` macros | `engine/parts/predicates.dm`, `datums/sys/requirements.dm`, `__defines/predicates.dm` | 73 content lines; `datum/predicate` is mentioned 157 times in 21 files | `req_*`, `any_of`, `all_of` |
| `HOLD_*` / `CONSTRAINT_*` spec tables (`fit_spec`, `equip_spec`, `hold_spec`, `suit_storage_spec`) | `constraints.dm`, content | 159 live specs (44 fit incl. 15 `null`, 25 equip, 19 hold, 86 suit storage), 115 `HOLD_*`, 132 `CONSTRAINT_*` | slot `accepts`, `extend(/datum/act/equip, ...)` |
| `/datum/req` flyweights + `/datum/requirement` shim | `datums/operations/req.dm` (469 lines), `native_requirement_adapter.dm`, `engine/parts/requirement.dm` | 55 call sites: `req_empty_hand` 40, `req_stance` 7, `req_access()` 5, `req_heard` 1, `req_set` 1, `req_self_held` 1 (`req_not_subverted` is already native, `library/access/emag.dm:72`) | native `req_*` parts of the same names |
| `req_*` parts (`/datum/entry/part/req`) | `engine/parts/cond.dm`, libraries | the target: 264 `req_is`, 214 `req_capable`, 169 `req_adjacent`, 111 `req_rights`, ... | stays |
| `acceptance_leaf` parts incl. `req_acceptance_either/both` | `library/requirements/acceptance.dm`, `equip_slots.dm:291-303` | 84 `req_acceptance_type`, 25 `req_acceptance_tag`, 6 either/both | the same parts without the `acceptance` prefix; `any_of`/`all_of` with `because =` |
| `cond_not/cond_all/cond_any` | `engine/declare/relations.dm:229-235`, evaluated by `condition_holds()` (a second evaluator beside `op_cond_eval`, `cond.dm:72`) | 173 + 50 + 37 = 260 | `not`, `all_of`, `any_of` |
| `CHECK(/datum/requirement_definition/...)`, `FACT()`, `ALL_OF/NOT_OF` | `engine/declare/checks.dm` | 7 `holds_while`, 5 `FACT`, 4 `NOT_OF`, 1 `ALL_OF`; also behind `wake_if`, `active_if`, `run_if` | `req_*` conditions |

Name collision to resolve first: `req_access()` and `req_set()` exist **only** as old `/datum/req` constructors (`req.dm:165,195`), while the doc and the new
engine plan the same names (doc section 9, "Actor: req_access()"). The new engine reads the old datums through `holds()` shims
(`native_requirement_adapter.dm:12`, `OP_LEGACY_REQ_FORMS` at `:60`). Until the old system is retired, a native `req_access` cannot be written.

Reason forms in use: `/datum/msg` types (508 `because = MSG(`/`/datum/msg`), raw strings (85 `because = "`, plus library literals), `TRUE`-or-text procs
(7 `dq_equip_*` helpers, the 6 `taur_fit` and 1 `match_ears` specs, `pred_holding_knife_holds`), and booleans with a side-channel (`GLOB.act_last_reason`). The reason order differs by path (D2h).

## 3. Decisions

### D1. One gating method

**Decision.** One requirement language (section 1.1), one set of attach points (1.2), one reason type. The old `/datum/req` system is retired **first**
because it owns the names the new language needs. The six predicate languages collapse into `req_*` + `any_of`/`all_of`. The `acceptance()` channels
are interim; the endgame is doc section 17 (channel -> slot `accepts`, or `extend(/datum/act/equip | insert | remove, needs(...))`).

**Before** (`code/library/machine/doors.dm:21-27`): four vocabularies in one declaration, and `req_access()` is the *old* flyweight run through a shim.

```
var/list/by_touch = list(inputs(hand(), item(/obj/item)),
    when(cond_not(nameof(/obj/machinery/door::operating))),          // cond_* tree, evaluated by op_cond_eval
    when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)),     // native req part used as a condition
    needs(req_access(), req_is(STAT_OPERABLE, because = MSG(door/unpowered))),  // req_access = old /datum/req, req_is = native
    wait(0))
```

**After** (end state names; the `acceptance_` prefix on parts and the `cond_` prefix go):

```
var/list/by_touch = list(inputs(hand(), item(/obj/item)),
    when(not(nameof(/obj/machinery/door::operating))),
    when(req_actor_kind(/mob/living/silicon/robot, not = TRUE)),
    needs(req_access(), req_is(STAT_OPERABLE, because = MSG(door/unpowered))),   // req_access is a native part over /obj/proc/allowed()
    wait(0))
```

**Retiring `/datum/req`** (first step of wave 0): re-implement the 6 live constructors as native parts (`req_empty_hand`, `req_self_held`, `req_set`
-> `req_is`, `req_access`, `req_stance`, `req_heard`; `req_clear`, `req_part`, `req_proc`, `req_claws`, `req_working`,
`none_of`, `req_on_route` have **zero** content callers (`req_not_subverted` is native already) and are deleted), convert the 55 call sites (mechanical, same names), delete `req.dm`,
`native_requirement_adapter.dm`, `op_legacy_req_has_form`, `GLOB.OP_LEGACY_REQ_FORMS`, `/datum/requirement`, `requirement_composer()` and the
`any_of`/`all_of` legacy branches (`cond.dm:594-598,621-625`). `req_access()` keeps the admin skip that the shim already has (`A.authority & AUTH_ADMIN`).

**Reasons.** `/datum/msg` only. A reason that needs detail ("size 3 > size 2") is a message instance built by a pure `because = PROC_REF(reason)`
(doc section 9, "dynamic reason"). The 15 literal reasons in `library/requirements/acceptance.dm` become `MSG(slot/...)` types (`slot/too_large`, `slot/too_small` already
exist, `library/items/size.dm:6-7`).

**Enforcement.** Wave ends switch on hard bans (section 4); `requirement_bool` already covers the boolean constructor.

### D2. Engine gaps (wave 0)

Each gap below is a thing content currently hand-rolls. They are engine and library work, behaviour-neutral until a wave uses them.

**D2a. Per-instance slot capacity, in four units.**
`slot()` takes a constant (`capacity` is `isnum`, `slot_def.dm:163,183`); the other form (`capacity_for(holder)`) needs a registry subclass per holder
(`closets.dm:139`, `storage.dm:217`). Mech hardpoints keep their limits in instance vars read by a hand-written ladder.

```
// before (mecha_equipment.dm:153-176): six if-blocks, one per equip_type; the slot itself is unlimited (mecha.dm:404)
if(equip_type == EQUIP_HULL && length(M.hull_equipment) < M.max_hull_equip) return 1
if(equip_type == EQUIP_WEAPON && length(M.weapon_equipment) < M.max_weapon_equip) return 1
...
// after (sketch)
slot(MECHA_HULL, accepts = req_equip_type(EQUIP_HULL), capacity = nameof(max_hull_equip), unit = COUNT)
slot(MECHA_WEAPON, accepts = req_equip_type(EQUIP_WEAPON), capacity = nameof(max_weapon_equip), unit = COUNT)
```

`capacity = nameof(var)` reads a tracked var of the holder (like `starts = nameof(...)`); `unit =` is `COUNT`, `SIZE`, `MASS` or `UNITS` (a named cost, D2b).
The four models exist as `SLOT_CAPACITY_*` (`containment.dm` defines 155-163) but `cost()` returns 1 for `UNITS` unless a subclass overrides it
(`slot_def.dm:211-222`), so each units holder subclasses.

**D2b. One size model replacing six.** Today: (1) `w_class` read directly (`size_is`, `library/items/size.dm:9-21`; storage `W.w_class > biggest`, `storage.dm:191`);
(2) storage cost, 1/2/4/8/16 by class (`inventory_storage.dm:15-20`, `get_storage_cost`, `storage.dm:865`); (3) `PROP_SIZE_CLASS`, a property that itself reads
`w_class` (`item_physical.dm:8-24`, used by `req_acceptance_max_size`); (4) the closet formula `CEILING(w_class / 2, 1)` (`__closets.dm:162,172`), computed twice, once from an instance and once from
a type; (5) mob size, `L.mob_size` (`__closets.dm:175`, buckle `smallest/largest`, `buckle.dm:111-115`) and the `size_probe` stand-in object that asks a bag whether it would take a mouse
(`storage.dm:79-91`); (6) per-type counts and material amounts (stack amounts, sheet snatcher, `entry_cost` per type, `latent.dm:519-529`).

Target: every thing has one **size class** (`PROP_SIZE_CLASS`, type-level default, instance override, mobs included via their size) and one **mass**. A slot's unit is
`SIZE`, `MASS`, `COUNT` or `UNITS(table)`, where `table` is a named class-to-cost map (`STORAGE_COST`, `CLOSET_COST`). Type-level cost comes from the same table
(`entry_cost`, `build_type_storage_cost` go away). `size_probe` is deleted; `size_at_most(ITEMSIZE_SMALL)` is one requirement.

```
// before (__closets.dm:129-143,162-179): two near-identical formulas, and a predicate for acceptance
/datum/relation_definition/slot/closet_interior
    capacity_model = SLOT_CAPACITY_UNITS
    accepts = /datum/predicate/slot_closet_interior
/datum/relation_definition/slot/closet_interior/cost(obj/structure/closet/holder, atom/movable/thing)
    return holder.storage_cost_of(thing)       // CEILING(w_class/2) | mob_size | storage_cost | 1
// after (sketch)
slot(CONTAINER_SLOT_INTERIOR, accepts = req_loose(), capacity = nameof(storage_capacity), unit = UNITS(CLOSET_COST), exposure = SLOT_EXPOSURE_INTERNAL)
```

**D2c. `fits =` as a requirement on insert.** Add the `fits` argument to `slot()` (doc section 6 promises it; `entries.dm:190` lacks it). Evaluated after `accepts`, before capacity.

```
// before (cell_bay.dm:26): only the cell bay capability has it
entries += op("insert", item(accepts), put_in(slot_var), at_space, fits ? needs(fits) : null)
// after
slot(SLOT_CELL, accepts = /obj/item/cell, fits = size_at_most(ITEMSIZE_NORMAL), capacity = 1)
```

**D2d. Declared `accepts` takes a type list or a requirement, everywhere.** Declared `slot()` entries already take either but not both together (`slot_def.dm:322-327`
crashes on a mix); registry slot decls take only a `/datum/predicate` type (`slot_def.dm:43-44`, `refusal()` at `225-230`; the two users are `closet_interior`
and `folder_pages`). Allow `accepts = any_of(type-list, req...)` and a requirement on registry decls (so the 89 registry declarations can migrate in any order),
then delete the predicate branch.

**D2e. Replace policy.** A full slot today answers "no room" (`api.dm:71`) or each caller re-implements swapping (RPED, equip over a worn item via `TAG_WEAR_OVER`,
`equip_slots.dm:190-194`). A slot declares `replace = REFUSE | REPLACE | REPLACE_IF_BETTER(by = STAT_X)` (default `REFUSE`). `REPLACE` removes the occupant through
`/datum/act/remove` (so removal requirements still apply) and hands it to the actor's source place.

```
// before (machinery.dm:522-554): the RPED loop; the "better" test, the swap, the messages and the bookkeeping are one body
if(B.get_rating() > A.get_rating())
    R.remove_from_storage(B, src, user)
    R.insert_item(A, user, TRUE)
    own_take_member(src, nameof(component_parts), A)
    move_into(src, CONTAINER_SLOT_INTERNALS, B, user)
// after (sketch)
slot(CONTAINER_SLOT_INTERNALS, accepts = req_part_of_circuit(), replace = REPLACE_IF_BETTER(by = STAT_RATING))
// the RPED op is item(/obj/item/storage/part_replacer) + put_in(CONTAINER_SLOT_INTERNALS) per candidate part
```

`OP_REPLACED` already exists (`vocabulary.dm:32`, `act.dm:254-262`) but means "a hook took the action over". A displaced occupant needs its own outcome name (**resolved**: DISPLACED, the move flag `LEDGER_MOVE_DISPLACED` its `on_unslotted()` sees; `OP_REPLACED` keeps its meaning).

**D2f. Partial and quantity insertion** (rounds, sheets, reagent units). Today `move_into` is all or nothing; a speedloader is a hand-written loop that checks
`length(loaded) >= max_shells` per round (`projectile.dm:612-630`), reaching into `rel_move`.

```
// after (sketch): the slot is quantity-aware; accepts and fits are asked of the unit
slot(GUN_ROUNDS, accepts = req_caliber(nameof(caliber)), capacity = nameof(max_shells), unit = COUNT, quantity = TRUE)
op("load_speedloader", item(/obj/item/ammo_magazine/speedloader), put_in(GUN_ROUNDS, amount = ALL))   // loads min(held, free) rounds; the rest stays
```

`/datum/act/insert` gains the moved amount (**new** field); `move_into` returns it. Sheets (`/obj/item/stack`) and reagent units (`UNITS` capacity, source a
`/datum/reagents`) use the same path; `trans_to` has 39 call sites that become inserts into a UNITS slot (D7).

**D2g. Non-movable members, or a slot-less requirement.** NIF software and robot matter synths are datums with no location (`nif.dm:450-470`
`rel_add(src, nameof(nifsofts), ...)`; `robot_simple_items.dm:450,482`). `ACTION(insert, atom/movable/item, slot_id)` (`world_actions.dm:36`) cannot carry them, so their rules sit in
free procs (`install_refusal`, `can_install_synth`). Two moves, both needed: (1) allow a slot to declare `members = DATUM` so the insert action's item is a `/datum`; (2) a
public `requirement_reason(R, holder, candidate, actor)` (**new**; today's `acceptance_reason()` generalised) that works on any candidate, including a **type path**, so a shop
can ask "would this install" before it charges (the reason `nif.dm:412-427` already exists for exactly that).

```
// before (nif.dm:429-447): a noisy twin of install_refusal(), no callers (git grep can_install( finds only the definition)
/obj/item/nif/proc/can_install(datum/nifsoft/path)
    if(nifsofts[initial(path.list_pos)])
        notify("The software \"[initial(path.name)]\" is already installed.", TRUE)
        return FALSE
// after: delete can_install; the single rule is a requirement the slot, the shop and the install op all take
slot(NIF_SOFTWARE, members = DATUM, accepts = req_nif_takes(), key = nameof(list_pos))
```

**D2h. Stated reason order.** The first reason a player sees depends on the path. A move checks (`api.dm:35-72`): sanity, no ledger, no slot, already there, source
release, destination `accepts` (body slot: part present, holder rule, equip catalog, legacy predicate: `slots.dm:59-71`), keyed duplicate, capacity, then `/datum/act/insert` needs.
Equip checks (`equip_slots.dm:166-197`): the slot, "already wearing" (unless `TAG_WEAR_OVER`), `slot_is_accessible`, then the item's fit and equip. `move_into` then runs `ACT_TRY(insert)`
again after `move_into_refusal` (`transfer.dm`; insert needs appear to run twice per move, **unverified: not traced**). One order for every insert, equip included:

1. sanity (gone, inside itself, no such holder or slot);
2. release (source `removal_refusal`, `/datum/act/remove` needs: can it leave);
3. holder state (the body part is there, the species has the slot);
4. `accepts`, type-level requirements first (D8), then instance-level;
5. `fits`;
6. occupancy and capacity (already there, keyed duplicate, replace policy, room);
7. `needs()` on `/datum/act/insert` or `/datum/act/equip` (machine state, consent, wearer-dependent fit);
8. takeovers (`instead`).

Reasons are cheap-and-static first, fixable-by-the-player last.

**D2i. Contract for actorless checks.** `op_transfer_query` calls `acceptance_act(destination, destination, candidate, null, mover, slot_id)` (`transfer_requirements.dm:24`);
conveyors, `Bumped` and `Cross` (`atoms_movable.dm:360-365`) have no actor. The convention exists but is unwritten: a part gated on the actor holds when there is none
(`req_capable`, `req_adjacent`, `req_self`: `cond.dm:371,471,412`; `allowed()` returns null for no actor, `req.dm:189`). Write it down and test it per part: **no actor means a system mover: actor-gated
parts hold, holder- and item-gated parts still evaluate.** Parts declare which they are (a `reads_actor` flag, which also feeds D8).

**D2j. `forced` and `silent` become an authority datum.** Today: `LEDGER_MOVE_FORCED` (18 uses), `disable_warning` (25), `ignore_obstruction` (10), `unEquip(force)` (about 14 call sites with a truthy second argument), `move_into(force =)`
(3), buckle `forced`/`silent` (`buckling.dm:64,143`; 37 `forced = TRUE` sites code-wide), and `slot_transfer(authority =)` where the mask is `AUTH_*` and anything else is a stack trace (`api.dm:183-185`).
Doc section 6 and 8 say "authority datum"; master has only the mask. One datum, granted not passed:

```
// before (inventory.dm:421, api.dm:178): three spellings of "skip the checks"
/mob/proc/unEquip(obj/item/I, force = 0, atom/target)
    if(!(force || canUnEquip(I))) return FALSE
slot_transfer(thing, new_holder, slot_id, actor, authority = AUTH_ADMIN)      // mask only
// after (sketch): the authority says who forced it, what it skips, and whether it speaks
slot_transfer(thing, new_holder, slot_id, actor, authority = admin_authority(actor, "undress", skips = REQUIREMENTS, quiet = TRUE))
```

`quiet` is feedback, not a check argument: `disable_warning` stops being a parameter of the refusal procs.

**D2k. Wire `/datum/act/equip`.** Declared (`world_actions.dm:38`), hooked by nothing. Design: the action runs on the **item** (holder = item, target = the wearer), so an item type's
`extend(/datum/act/equip, needs(req_fits_bodytype()))` is its own rule and the body slot's `accepts` is the wearer-side rule. This changes the declared fields from `(item, slot_id)`
to `(wearer, slot_id)` (**open**: confirm which end holds the hook). Equip then drops its parallel pipeline (`dq_equip_refusal`, `dq_equip_item_refusal`).

**D2l. `/datum/act/remove` wired to `req_removable`.** `canremove` (146 lines), `NOSTRIP` (18), `TRAIT_NODROP` and `mob_can_unequip` (`items.dm:481-492`) are four spellings of one question, and the strip menu
answers it in a bool-plus-`to_chat` guard.

```
// before (stripping.dm:76-78)
if(!target_slot.canremove || (worn_of(target_slot).flags & NOSTRIP))
    to_chat(user, span_warning("You cannot remove \the [src]'s [target_slot.name]."))
    return
// after: the body slot declares it once; the strip op shows the reason in the menu and has spent nothing
extend(/datum/act/remove, needs(req_removable()))     // req_removable reads the item's removable stat; a stripper adds req_strippable()
```

**D2m. The real actor through strip-equip.** `stripping.dm:135` calls `equip_to_slot_if_possible(wrapped, slot_to_strip, 0, 1, 1)` with no actor, and `dq_equip_refusal` passes the **wearer** as the
actor everywhere (`equip_slots.dm:178,186`; `dq_native_equip_slot_reason(M, slot, I, M)` at `:178`, `acceptance_reason(..., wearer, candidate, wearer, mover, ..., wearer_is_actor = TRUE)` at `:306`;
`constraints.dm:116-117` sets `wearer = actor`). So a stripper putting a mask on a stunned victim is judged as the victim doing it. After D2k the strip op calls the equip with `actor = user`
and `wearer = target`, and `wearer_is_actor` is deleted.

### D3. Clothing fit, inverted

**Decision.** A species or bodytype declares the fit **categories** it `wears`. An item declares **one** fit category and sprite sheets per category. A per-item tracked field
holds exceptions and refits. `req_fits_bodytype()` reads the category, then the override, and keeps the Vox/Teshari/Werebeast sprite rule inside it. Accessory `species_allowed`
lists become species tags.

**What exists** (the data to replace):

| Pattern | Count (master) | Where |
|---|---|---|
| item fit declarations | 72: 43 native `acceptance("fit", fits(...))` + 29 legacy `fit_spec` with `REQ_FITS_BODYTYPES`; plus 24 native `ACCEPTANCE_EMPTY` and 15 `fit_spec, null` resets ("fits anyone") | `acceptance("fit")` 67 in all, `TYPE_TABLE(..., fit_spec, ...)` 44 |
| species literals on those lines | at least 260 (single-line count; multi-line lists missed) | Vox 33, Teshari 33, Diona 17, Promethean 16, Human 16, Skrell 12, Unathi 11, ... |
| `SPECIES_*_CAN_WEAR` macros + `refit_for_species` switch | 10 macros, 1 switch of 15 lines | `global_lists.dm:1622-1631`, `clothing.dm:173-199` (17 uses of the macros) |
| accessory `species_allowed =` | 122 assignments, 230 literals, 12 distinct values | 94 in `sprite_accessories_markings.dm`, 21 in `sprite_accessories.dm`; `list(SPECIES_TESHARI)` x86, `list(SPECIES_VOX)` x16, `list(SPECIES_AKULA)` x5, `list(SPECIES_WEREBEAST)` x4; the base default is a 27-species list (`sprite_accessories.dm:39`) |
| `sprite_sheets` / `sprite_sheets_obj = list(` | 81 blocks (71 worn, 10 obj) in 39 files; 143 assignments incl. setters | `items.dm:54-63`; lookup `items.dm:759-786` |
| `SPECIES_X = 'icons/...'` lines | 586 (611 with string keys); includes non-clothing species icon tables, **unverified how many sit inside `sprite_sheets`** | whole `code/` |
| the Vox/Teshari/Werebeast rule, twice | fit: `dq_fits_bodytype`; sprite: `get_worn_icon_file` | `library/requirements/acceptance.dm:316-325`; `items.dm:783` |

The 25 distinct fit shapes at master (first number: sites): Teshari-only 13, Vox-only 12, `exclude(Teshari, Vox, Diona)` 8, `exclude(Diona, Vox)` 4, `list(Human, Promethean)` 4,
the 19-species rig list 4, the 18-species protean list 4, Unathi-only 3, Altevian-only 3 (+1), `exclude(Diona)` 3, `exclude(Diona, Vox, Teshari, Altevian)` 2, Zaddat+Promethean 2,
`list(Skrell, Human)` 2, and ten one-offs.

**Before** (three files for one species fact):

```
// rig_pieces.dm:81 (the 19-species list; four pieces repeat it, protean repeats an 18-species one)
TYPE_TABLE(/obj/item/clothing/suit/space/rig, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_HUMAN, SPECIES_SKRELL, SPECIES_TAJARAN, SPECIES_UNATHI, SPECIES_NEVREAN, SPECIES_AKULA, SPECIES_SERGAL, SPECIES_ZORREN_HIGH, SPECIES_VULPKANIN, SPECIES_PROMETHEAN, SPECIES_VOX, SPECIES_TESHARI, SPECIES_VASILISSAN, SPECIES_RAPALA, SPECIES_ALRAUNE, SPECIES_FENNEC, SPECIES_XENOHYBRID, SPECIES_ALTEVIAN, SPECIES_SHADEKIN))))
// teshari.dm:5
TYPE_TABLE(/obj/item/clothing/under/teshari, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_TESHARI))))
// sprite_accessories_markings.dm (86 times)
species_allowed = list(SPECIES_TESHARI)
```

**After** (end-state form, **new**; today's `fits()`/`species_allowed` are the legacy forms until wave 3):

```
// engine: eight categories (the draft list; wave 0's analyze report fixes it)
#define FIT_HUMANOID  "humanoid"     // the SPECIES_HUMANOID_CAN_WEAR set
#define FIT_UNATHI    "unathi"
#define FIT_TESHARI   "teshari"
#define FIT_VOX       "vox"
#define FIT_ALTEVIAN  "altevian"
#define FIT_ZADDAT    "zaddat"
#define FIT_STANDARD  "standard"     // not Teshari, Vox or Diona (the 8 + 1 sites that say exclude(...))
#define FIT_HARDSUIT  "hardsuit"     // the rig/void/protean 18-19 species set
// (Tajaran, Vulpkanin and Sergal appear only at runtime through refit_for_species: three more, FIT_TAJARAN, FIT_VULPKANIN, FIT_SERGAL)

// species: one line each, only where it differs from the humanoid default
/datum/species/teshari
    wears = list(FIT_TESHARI)
/datum/species/unathi
    wears = list(FIT_UNATHI, FIT_STANDARD, FIT_HARDSUIT)

// item: one category; sprite sheets keyed by category
/obj/item/clothing/under/teshari
    fit = FIT_TESHARI
/obj/item/clothing/suit/space/rig
    fit = FIT_HARDSUIT
    sprite_sheets = list(FIT_TESHARI = 'icons/...', FIT_VOX = 'icons/...')   // not species-keyed

// the requirement (extend(/datum/act/equip, needs(req_fits_bodytype())) on /obj/item/clothing)
//   1. cat = item.fit_override ?: item.fit             (fit_override: tracked, null by default; paint kits and refit tools write it)
//   2. wearer's wears-set must contain cat             (assoc set, O(1))
//   3. the sprite rule, unchanged in meaning: if the wearer's own category is Teshari, Vox or Werebeast, the item must have a sheet for it
```

**Arithmetic.** About 194 per-type declarations (72 fit + 122 accessory lists) and about 490 species literals (260 + 230) become: about 8 category defines (+3 refit-only), one
`wears` line per species that is not the humanoid default, about 7 accessory tags (Teshari, Vox, Akula, Werebeast, Shadekin pair, Lleill/Hanner, the default set), one `fit =` token on
the types that today carry a list (the *line* count falls only where types share a parent; the win is that species names leave content: a new species is one `wears` line, not about 25
edits across rigs, voidsuits and markings). The old `refit_for_species` switch (15 lines) and 10 macros go. **Open:** the 11 `exclude(...)` sites with sets other than
(Teshari, Vox, Diona) need a call: two more categories (`NO_DIONA_VOX`, `NO_DIONA`) or `fit_override` entries.

**Accessories.** `species_allowed` is read in 12 places (`_helpers/mobs.dm:50,73`, `organ_icon.dm:67,80`, `body_styles.dm:51`, `appearance.dm:183,215`, `human_look.dm:441,450`,
`species_shapeshift.dm:134,147`, `preferences_setup.dm:363,384`, `appearance_changer.dm:1169`). Species carry `accessory_tags`; an accessory declares the tag it needs. The 27-species
default (`sprite_accessories.dm:39`) becomes "no tag required", which fixes the "default to all species to avoid runtimes" workaround its own comment names. Custom species (user-built
species) read tags from their base (`appearance_changer.dm:1169` already special-cases `/datum/species/custom`).

### D4. Delete the dead equip-slot block; closets and folders into slots; containers are slots

**D4a. Dead block.** `equip_slots.dm:15-131` (the `/datum/predicate/equip_slot/*` subtypes and `dq_equip_slot_predicate`) and `:213-263` (the seven `dq_equip_*` REQ_PROC helpers) have **no callers**
outside tests: `git grep` finds `dq_equip_slot_predicate` only at its definition; `dq_equip_suit_storage_takes` and friends only in `dq_acceptance_old_grouped_tests.dm:211-218`;
`/datum/predicate/equip_slot` only in `dq_constraint_tests.dm:433`; and `slot/body/refusal` falls back to a legacy `accepts` that no body slot sets (`slots.dm:68-70`). Delete the block and those tests.
`dq_item_fits_slot_flags` (`equip_slots.dm:135`) is live (4 callers) and stays.

**D4b. `slot_closet_interior` and `slot_folder_pages` become `accepts`.**

```
// before (__closets.dm:134,145-147, folders.dm:19,24-26)
accepts = /datum/predicate/slot_closet_interior
/datum/predicate/slot_closet_interior
    spec = list(REQ_BECAUSE(REQ_ON(PRED_TARGET, /atom/movable/proc/slot_loose, null), "it is fastened down"))
accepts = /datum/predicate/slot_folder_pages
    spec = list(REQ_BECAUSE(REQ_TAG(PRED_TARGET, TAG_PAPERWORK), "only paper, photos and bundles fit"))
// after
accepts = req_loose()                                   // MSG(slot/fastened_down); reads anchored, buckled_to(), pinned
accepts = req_tag(TAG_PAPERWORK, because = MSG(folder/only_paper))
```

**D4c. Containers are slots, no hold channel.** A storage item already has one slot (`library/containers/storage.dm:209-231`) whose `refusal()` calls the `storage()` capability's
own checks (`accepts`, `refuses`, `max_size`, count, container-in-container, no-drop: `storage.dm:175-199`). Holsters, grippers and suit storage use the `hold` and `suit_storage` channels
(7 + 72 native declarations, 19 + 86 legacy specs, 115 `HOLD_*`). Make all of them slot declarations:
- `storage(accepts =, max_size =)` (152 `configure(storage(` sites, text unchanged) emits `slot(CONTAINER_SLOT_STORAGE, accepts =, fits = size_at_most(...), capacity = nameof(...))`; the capability's `refusal()` body is deleted, its checks become requirements (`req_not_container_as_big`, `req_not_stuck_to_hand`).
- A holster is `slot(HOLSTER, accepts = req_tag(TAG_HOLSTERABLE))` on the accessory (`holster.dm:78` is a `hold` channel today).
- Suit storage stays a body slot, but the suit declares what it takes as one trait value (`suit_storage = req_type(list(...))`), read by `req_suit_storage_takes()`; rigs "adopt" the suit's list (`adopt_constraint`, `constraints.dm:180-188`) by reading it, not copying a plan. **Open:** whether the suit's list is a slot on the suit or a trait (an item in suit storage sits in the mob's slot, not in the suit).

### D5. Impure requirements: appearance moves to equipped hooks first

A requirement must be pure (doc section 9; `op_pure_begin` guards it). Two live equip specs write.

```
// before (backpack.dm:586-593): a "fit" check that sets the sprite as a side effect, so a menu re-evaluation changes the item
/// Any taur half; the bags take the look of the wearer's.
/obj/item/storage/backpack/saddlebag_common/proc/taur_fit(mob/living/carbon/human/H)
    var/datum/sprite_accessory/tail/taur/TT = istype(H) ? H.tail_style : null
    if(!istype(TT))
        return lowertext(no_message)
    set_item_state("[icon_base]_[TT.icon_sprite_tag]")
    return TRUE
// custom_clothes.dm:787-793: match_ears() does the same (set_item_state inside the requirement) and "always fits"
```

```
// after: a pure requirement names the meaning; the appearance is set when the item lands in the slot (has_slot_hooks / on_slotted exist, ledger.dm:634)
CAPABILITIES(/obj/item/storage/backpack/saddlebag_common)
    extend(/datum/act/equip, needs(req_taur_body(), because = MSG(saddlebag/needs_taur)))
has_slot_hooks = TRUE
/obj/item/storage/backpack/saddlebag_common/on_slotted(atom/holder, slot_id, flags)
    . = ..()
    var/mob/living/carbon/human/H = holder
    if(istype(H) && istype(H.tail_style, /datum/sprite_accessory/tail/taur))
        set_item_state("[icon_base]_[H.tail_style:icon_sprite_tag]")      // the real code reads it into a typed local first
```

Confirmed impure: `saddlebag_common.taur_fit` (`backpack.dm:586-593`) and `avida.match_ears` (`custom_clothes.dm:787-793`). The other five `taur_fit` specs (`backpack.dm:562` saddlebag, `armor.dm:635`, `miscellaneous.dm:1326,1345`, `custom_clothes.dm:1425`) are pure reads of `tail_style`. The rest of the 39 `REQ_ON` sites are **unverified**; wave 0's purity report decides. One `req_taur_body(type)` and `req_limb_clearance()` replace the per-type `taur_fit`/`limb_clearance` procs.

### D6. Folds: bespoke gates onto slot plus requirement

Each row is one bespoke gate whose pieces map to the model: **what may be in** is the slot (`accepts`, `fits`, capacity, replace); **machine or wearer state** is a requirement on the insert; **who may** is `forced -> authority`.

| Site | Today | After |
|---|---|---|
| Cell charger, recharger, food replicator, suit cycler, partslathe and the other 83 `op("...insert...")` | `insert_refusal(A)` mixes type, "already full" and machine state (`cell_charger.dm:63-74`); the `charging` var is an owned var place, not a slot (`cell_charger.dm:39`) | `slot(CHARGING, accepts = /obj/item/cell, capacity = 1)`; `extend(/datum/act/insert, needs(req_operable(), req(PROC_REF(area_has_power), because = MSG(charger/no_area_power))))`; the "full" and "wrong type" reasons come from the slot |
| Mech hardpoints, internal components | ladder in `can_attach` (`mecha_equipment.dm:153-176`), duplicate refusal by type (`allow_duplicate`), "universal" fallback and a combat-only rule | slots with per-instance capacity (D2a), `key = nameof(type)` keyed duplicates (keyed slots exist: `slot()`'s `key`, `api.dm` J4), and an ordered fallback group **new**: `slot_group(MECHA_HARDPOINT, ordered = list(MECHA_HULL, MECHA_UNIVERSAL))` picks the first member that accepts and has room |
| NIF install | `install_refusal` (reason) + noisy `can_install` + a third check inside `install` (`nif.dm:412-470`) | D2g: one requirement; delete `can_install` (no callers) |
| Closets | units capacity with its own formula (`__closets.dm:129-179`) | D2a/D2b: `UNITS(CLOSET_COST)`, `accepts = req_loose()` |
| Gun magazines | `load_ammo` boolean ladder with `to_chat` (`projectile.dm:581-681`): `load_method`, `caliber`, `allowed_magazines`, already-has-one, bolt state | magazine well: `slot(MAG, accepts = all_of(req_caliber(...), req_mag_type(nameof(load_method)), req_type_in(nameof(allowed_magazines))))`, `replace = REFUSE`; the bolt rule is a requirement on insert; speedloader is partial insertion (D2f) into `GUN_ROUNDS` |
| RPED | D2e `REPLACE_IF_BETTER` | |
| Clothing accessories | bitmask conflict test (`valid_accessory_slots`, `restricted_accessory_slots`: `clothing_accessories.dm:1-22`) | `slot(ACCESSORY, accepts = req_accessory_bits(), capacity = UNLIMITED, key = nameof(slot_bit))` where the requirement reads the bitmasks; the existing `req_acceptance_accessory_attachable` is the seed |
| Recycler and material intake | **unverified: not read** | quantity insertion into a `UNITS` slot (D2f) |
| Buckling | `can_buckle_check` bool + `to_chat`, `forced` (`buckling.dm:223-244`); the library capability already returns `/datum/msg` (`buckle.dm:100-120`) | an occupant slot (sealed, `fits = mob_size_between(smallest, largest)`), `forced` becomes an authority datum (D2j) |
| Robot matter synths | `can_install_synth` returns bool (`robot_simple_items.dm:482`; callers `modify_robot.dm:875`, `robot_simple_items.dm:450`) | D2g: datum members, `key = nameof(synth_type)` |
| Access `allowed()` | `/obj/proc/allowed` (`access.dm:20`), `access_needs()` in the capability library, old `/datum/req/access` | one native `req_access()` over `allowed()` (D1); the list form `req_access(list)` is a wave-6 option |
| Cooldowns, tools, rights, wire and emag states | ad-hoc procs and flags | `req_cooldown(key)` (reads the cooldown table), `req_tool(quality)` (the actor's provider affordance), `req_rights(R_X)` (exists), `req_is(hacked)` for wire and emag keys (exists as `req_is`; `req_wire(W)` exists, 11 uses) |
| Construction and surgery gates | `req_built(STAGE_X)` exists (`graph_ops.dm:286`); surgery gates **unverified** | fold when the file is touched, not as a wave |

### D7. Movement, reagents, whitelists

**Movement (`CanPass`, `Cross`, `Enter`).** 66 `CanPass` overrides, 1 `Cross` (`atoms_movable.dm:360-365`: `ACT_TRY(cross)` then `CanPass`), 2 `Enter`, 16 `Bumped`. They share the
vocabulary as a **condition** on a fast path: a `CanPass` body that only tests pass flags compiles to a flag mask and no proc runs; a body that reads state is a condition over tracked state; a
body of arbitrary logic stays a proc until its owner converts it. The **reason** is computed only when a player bumps (`/datum/act/bump`, `world_actions.dm:17`), by evaluating the requirement form with the player as actor.

```
// before (barricades.dm:104-107): a flag test dressed as a proc, called on every Cross of every mover
/obj/structure/barricade/CanPass(atom/movable/mover, turf/target)
    if(istype(mover) && mover.checkpass(PASSTABLE)) return TRUE
    return FALSE
// after (sketch): one declaration, compiled to the pass mask; no per-cross proc
passable_if(req_passes(PASSTABLE))
// window.dm:88-96 is direction-dependent: it stays a condition over (dir, target) on the slow path
```

Density and pass flags are engine stats recomputed inline (doc section 7), so `passable_if` is a gated contribution, not a new mechanism. Perf is **unmeasured** (no bench until the end of the rewrite).

**Reagents.** Pouring into a container folds: a beaker is a slot with `UNITS` capacity and quantity insertion (D2f); the 39 `trans_to` call sites (`holder.dm:394`) become inserts, and "closed container" and
"not a valid reagent for this" are requirements. **Chemical reactions are a separate data-matching system**, not a gate (cross-reference: `proposals/transformations.md` at `8b3ba3e2c9`, section 8.2: its outputs go into slots through `move_into`, reserve output capacity with `RES_SLOT_CAPACITY` so a full target refuses before anything leaves the source, and round extents to a per-medium quantum. That is D2a (UNITS capacity) and D2f (partial insertion) here; the two proposals must share one quantity-insertion form, **open**: agree the `amount` field with the transformations author).

**Job and species whitelists.** `IsJobAvailable` returns 0 or 1 through eight unrelated gates and the caller shows a generic "not available" (`new_player.dm:103-132`, `do_late_spawn` `:134`);
`is_alien_whitelisted` (`whitelist.dm:227`) and `is_job_whitelisted` (`:300`) have 23 call sites. A join (and late join) op with the **client as actor**:

```
// after (sketch; join op is new)
op("join", client(), needs(req_job_open(), req_not_jobbanned(), req_old_enough(), req_playtime(), req_pto(),
    req_whitelisted(job), req_species_allowed(species), req(PROC_REF(play_mode_allows_job), because = MSG(join/wrong_play_mode))), then(PROC_REF(spawn_joiner)))
```

The reason shown is the one that failed, not "Please try another."

### D8. Latents: requirements say whether they read type-level data only

Latent entries are a type, a delta and a count; no instance exists (`latent.dm:37-70`). An `accepts` evaluated on them must read only what a type knows. Today **no acceptance is evaluated
for latent entries at all**: `latent_add` checks eligibility only (`latent.dm:416-420`), generator lines are trusted (`dq_latent_resolve`, `:231-233`), `entry_cost` is a separate type-level copy of `cost`
(`:519-529`), and collapse folds an already-accepted real thing.

- Every requirement part declares `reads = TYPE_LEVEL | INSTANCE` (**new**; analogous to the existing `read_keys`). `TYPE_LEVEL` means: the answer is the one a **pristine instance** of the type would give (type, size class, tags, initial vars, cost table). Instance-level parts read the wearer, the holder, instance vars, the deltas.
- `req_acceptance_type` is already type-level (its `read_keys` returns null, `library/requirements/acceptance.dm:200`); `max_size` and `tag` read properties the registry can answer per type (`dq_type_property`, `latent.dm:526`).
- A slot's `accepts` level is the maximum of its requirements, computed at compile time (`acceptance_compile`). A **type-level slot** can take latent entries without materializing (quantity insertion of rounds into a magazine, restock of a vending slot, `starts_with` lines checked in test builds); an **instance-level slot** materializes the candidate first.
- **Lint:** an instance-level `accepts` on a holder that declares `latent_contents` fails, unless annotated. Known hit: the closet interior (`req_loose()` reads `anchored`, `buckled_to()`, `pinned` of an instance). Resolution: `req_loose()` is type-level for items and structures (`initial(anchored)`) and instance-level only for mobs, which are never latent (`containment.md` section 4.4).

### D9. Performance: guard the eager reads, use sets

- `acceptance_plan.check` calls `op_menu_record_reads(read_keys(A))` on every evaluation (`engine/parts/acceptance.dm:91-97`); `read_keys` allocates a pair list per requirement and `pair.Copy()` for each row (`:98-112`),
  and `acceptance_reason` does the same with `declarer.acceptance_override_reads()` (`:130`). The recorder is a no-op when no menu frame is open (`menu_dependencies.dm:3-17`: it loops over `GLOB.op_menu_read_frame`),
  so the copy is wasted on every refusal check outside a menu. Guard both with `if(GLOB.op_menu_read_frame)`.
- `dq_fits_bodytype` does up to four linear `in` scans over lists of up to 19 names per check (`library/requirements/acceptance.dm:316-325`); fit sets become assoc sets (`alist`), and after D3 the check is a set lookup.
- No measurement is claimed (AGENTS: no benchmarks during the rewrite). Wave 0 adds the guard and a one-line counter, nothing more.

### D10. Destroy default and "survives container"

**Default fate of slot contents is SPILL.** DELETE only for the holder's **own built-in parts** (organs, a hidden uplink, a machine's own circuit). Today: `drop_policy` defaults to SPILL
(`slot_def.dm:50`) but `slot()` entries and registry decls choose otherwise: `SLOT_DROP_HOLDER` (9 sites; deprecated by `lifecycle.md` section 3 yet still the body slots' policy, `body/slots.dm:42,86`, with the comment
"SPILL here would litter every deleted mob's turf"), `SLOT_DROP_DELETE` (7: storage `storage.dm:215`, folders `folders.dm:20`, ...), `ON_DESTROY_DELETE` (7, 4 of them `slot(` hidden-uplink entries, which are built-in parts and stay).
Storage and folder contents change behaviour: a destroyed backpack spills its items instead of deleting them.

**Open (risk, not decided):** "litter on a forced delete". The destroy transaction has a `force` argument (`on_destroy(force)`); a cleanup or admin delete that spills a whole mob's loadout is the case the body-slot comment
fears. Proposed: spill is the default for gameplay destruction; a forced cleanup follows the type's declared `on_forced_destroy` (default SPILL, mobs in cleanup contexts DELETE through the destroy transaction's existing `force` branch). Needs the lifecycle owner's call.

**"Survives container."** A lifecycle property of the **contained** type: a mind or a client is never spilled or deleted by a holder's destruction; it is resolved by its declared `TRANSFER` resolver
(mind to ghost or MMI, `lifecycle.md` phase 0.5; `is_mind_slot` exists with no content user, `slot_def.dm:64`, `lifecycle.dm:21-79`). The declaration syntax belongs to `proposals/relations.md` D1
(lifecycle on destroy for a swept var); this proposal only needs the slot half: a slot honours `survives_container` of what it holds before applying its own drop policy.

### D11. Order of work and prerequisites

1. Retire the old `/datum/req` system (D1) before anything names `req_access`/`req_set`. 55 call sites.
2. The two Codex branches in the previous proposal's D7: `codex/requirements-hard-ban-1010` **merged** (the boolean constructor is gone, `requirement_bool` is a hard ban, baseline 2 lines). `codex/req-burndown` exists on origin and is **not merged** (32 commits, 344 files, last commit 15 Oct; what else it changes is **unverified**; the previous proposal said it fixes saddlebag, Avida hat, holder size and cloning-console behaviour, which are D5 sites). Two unmerged branches touch the same area and were not read beyond their stats: `codex/acceptance-final-1011` (8 commits, 40 files) and `codex/acceptance-retirement-1011` (41 commits, 221 files). **The merge agent decides** whether they land first.
3. Update AGENTS.md sections 3a (Refusals, Declare a type, Rows "Player/AI/admin choice") and 3b in the commit of each hard ban (previous proposal D6 rule, unchanged).

## 4. Waves

Each wave: edit everything first, then one compile and one focused test batch (`dq_acceptance_*`, `dq_conversion_pin`, equip pins, per-type fit pins); `analyze baseline --update` after. Counts are master; wave 0 replaces them with an exact `analyze` report.

| Wave | Content | Sites | End state (hard ban switched on in the same commit) |
|---|---|---|---|
| 0 | retire old `/datum/req` (6 constructors, 55 sites); D4a dead block + its tests; D9 guards; `/datum/msg` instance form; engine gaps D2a-D2m (additive, no content change); exact census; purity report for the 39 `REQ_ON` sites | ~55 + engine | `legacy_req`, `/datum/req`, `/datum/requirement`, `requirement_composer` banned, baseline empty |
| 1 | language collapse: `cond_*` (260) to `not/all_of/any_of`; `req_acceptance_either/both` (6) to `any_of/all_of(because=)`; `req_*` prefix names for the `acceptance_leaf` parts (84 + 25 + others); `CHECK`/`FACT`/`NOT_OF` (17) to `req_*` conditions; one evaluator (`condition_holds` into `op_cond_eval`) | ~400 | `cond_not`, `cond_all`, `cond_any`, `CHECK(`, `FACT(`, `req_acceptance_either`, `req_acceptance_both` banned |
| 2 | reasons: 85 `because = "`, 30 leaf literals, `pred_*`/`*_refusal` text returns, bool-plus-`to_chat` guards (stripping, buckling, NIF, projectile), `GLOB.act_last_reason` (35) | ~170 | raw-string reasons banned in `needs`/`accepts`; `act_last_reason` removed |
| 3 | fit inverted (D3): 72 fit declarations (+39 resets), 122 `species_allowed`, 81 `sprite_sheets` blocks, `refit_for_species`, paint and refit tools; `req_fits_bodytype()` | ~290 | `fits(`, `REQ_FITS_BODYTYPES`, `fit_spec`, `species_allowed`, `SPECIES_*_CAN_WEAR` banned |
| 4 | equip and strip (D2k/l/m, D5): `/datum/act/equip` and `remove` wired; 25 `equip_spec`, 2 confirmed impure procs; strip and equip pass the real actor; `canremove`/`NOSTRIP` (164) to `req_removable` | ~200 | `equip_spec`, `canremove`, `NOSTRIP`, `disable_warning`, `ignore_obstruction` banned; `dq_equip_refusal` deleted |
| 5 | holders (D4b/c): 19 `hold_spec`, 86 `suit_storage_spec`, 115 `HOLD_*`, 7 `hold` channels, storage capability checks, folders, closets, grippers, holsters | ~230 | `hold_spec`, `suit_storage_spec`, `HOLD_ONLY/NOT/MAX_SIZE`, `CONSTRAINT_*` (132), `dq_constraint_*` banned; `acceptance(` channels for `hold`/`suit_storage` gone |
| 6 | folds (D6): 83 insert ops, 18 insert-refusal procs, mech, NIF, guns, RPED, accessories, synths, buckling, recycler | ~200 | `*_refusal` text procs and `can_*` boolean gates for these types removed; `forced`/`silent` banned |
| 7 | D7: movement fast path (66 `CanPass`, 16 `Bumped`), reagent insertion (39 `trans_to`), join op and whitelists (23) | ~150 | `CanPass` overrides banned where a flag form exists; `is_job_whitelisted` and `is_alien_whitelisted` deleted |
| 8 | D8 latents (type-level/instance-level declaration, lint) and D10 drop defaults; delete the language: `/datum/predicate`, `REQ_*` macros, `predicates.dm`, `sys/requirements.dm`, 82 test lines, the last `acceptance(` interim channels (150 + 19) | -300 lines | `REQ_*` macros (outcome enum kept), `/datum/predicate`, `acceptance(` hard-banned, baseline empty |

Waves 3, 5, 6 and 7 are independent by directory after waves 0 to 2. A file moves into the new tree only when fully migrated (AGENTS.md section 3c).

## 5. Risks

1. **Behaviour parity of reasons and order.** D2h changes which reason a player sees first on some paths. Pin refusal text per converted type; the previous proposal's `dq_acceptance_old_grouped` tests are the model.
2. **Fit inversion drops a species silently.** A missed `wears` entry stops a species fitting. Mitigation: a generated test that every species wears every category its old lists allowed, and a diff of old and new answers over the 99 species datums, per item type.
3. **Slot contents spill instead of deleting** (D10): storage, folders and body equipment change fate; litter on forced delete is open. Needs the lifecycle owner.
4. **Type-level approximation** (D8): a type-level answer is the pristine instance's; an entry with a delta can differ. Acceptable because only new entries are admitted type-level; add a test that generator lines pass their own slot's `accepts` in test builds.
5. **Two unmerged acceptance branches** (`acceptance-final-1011`, `acceptance-retirement-1011`) overlap wave 0 to 5 files. **Unverified how.**
6. **Equip action ownership** (D2k): hook on the item or on the wearer changes the declared action fields; `ACT_TRY` call sites for `equip` are zero today, so the cost of choosing is low now and high later.
7. **Purity.** `REQ_ON` procs reading volatile state are re-run by menus under the pure guard; a write inside would trip it. D5 handles the 2 confirmed; the other `REQ_ON` sites are checked by wave 0.
8. **Outcome-enum confusion.** `REQ_ANSWERED` and the other request outcomes stay; ban by macro name, not prefix.
9. **Performance is unmeasured.** D7's fast path and D9's guard are asserted from reading, not benchmarked; the no-bench rule applies until the end of the rewrite.
10. **Doc drift.** `final_api.html` says requirement callbacks return TRUE/FALSE and `req_*` constructors change contract at E2 (sections 9 and 17); master and this proposal return null or a reason. The doc must change with wave 0 (section 6 lists the edits).

**Unverified list (in one place):** recycler/material intake and surgery gates (not read); the "insert needs run twice" reading of `move_into` (not traced); the purity of the `REQ_ON` procs I did not open;
the split of the 586 species-icon lines between `sprite_sheets` and other tables; the two unmerged acceptance branches' contents; `req_cooldown`/`req_tool` shapes (named in the approved list, no master form to read);
`transformations.md` beyond its section 8 (read at `8b3ba3e2c9`; the rest not read); `codex/req-burndown` (exists, unmerged; not read).

## 6. Comparison with the original design

Sources diffed: `doc/rewrite/containment.md` (C1 to C11 as built), `final_api.html` section 6 `slot()`, section 9 and section 17, and the previous `proposals/clothing_requirements.md` (commit `4ab5de33ec`).

### 6.1 Against `containment.md`

| | Item | Reason |
|---|---|---|
| Kept | Moves are transactions: both sides checked, then one commit (section 2, `api.dm:35-72`); drop policies as data (2.1, `lifecycle.md`); keyed slots (J4); exposure and layers (3.1); the three latent stages (4.1); no raw `contents` reads (2a); `slot_transfer` = remove + insert with hooks | the model is right and built |
| Changed | slot `accepts` is "a constraint" / "a P2 predicate" (sections 2.1, 3) -> a requirement returning null or `/datum/msg`; `holder_constraint = CONSTRAINT_HOLD` (8.1) -> the `storage()` capability emits slot `accepts`/`fits` | one language; the predicate and `CONSTRAINT_*` kinds retire |
| Changed | capacity models none/count/size/mass + custom `cost()` (2.1, 3) -> per-instance capacity in `COUNT/SIZE/MASS/UNITS(table)` over one size model | closets, storage, mobs and stacks each had their own formula (D2a, D2b) |
| Changed | `LEDGER_MOVE_FORCED` bit, `force`, `disable_warning` (2.1 J2) -> an authority datum | doc already says datum; master has only the mask (`api.dm:183`) |
| Changed | "Species gating becomes a constraint on the item type (body plan and fit), not `hud.equip_slots` plus `species_restricted` lists" (6) -> categories the species `wears` plus an item category | 72 + 122 species declarations survived the first intent (D3) |
| Changed | drop policy default: spill, with body slots on the deprecated `SLOT_DROP_HOLDER` (2.1, `slots.dm:42`) -> SPILL for slot contents, DELETE only for built-in parts | D10; litter on forced delete open |
| Changed | latents are enabled per holder by a hand-kept flag plus `latent_safe` (4.4, 4.7) -> adds a per-slot level: type-level `accepts` can take entries without materializing | D8 |
| Added | replace policy; quantity insertion; non-movable members; actorless-check contract; one stated reason order; `/datum/act/equip` and `req_removable`; the join op | gaps content hand-rolls (D2, D7) |
| Dropped | `holder_constraint`, the `hold` and `suit_storage` channels as separate machinery; `SLOT_DROP_HOLDER` (already deprecated) | containers are slots (D4c) |
| Not touched | propagation math (3.2), vore modes, circuits | out of scope (1.3) |

### 6.2 Against `final_api.html` section 6 `slot()`

| | Item | Reason |
|---|---|---|
| Kept | `slot(id, accepts =, fits =, capacity =, exposure =, at =, on_destroy =)`; `move_into/slot_remove/slot_transfer`; transfer = remove + insert; capacity as a resource (X2); `at = SPACE_X` | the signature is the target |
| Changed | `capacity =` a constant -> `capacity = nameof(var)` and a `unit =` | per-instance (D2a) |
| Changed | `fits =` documented but missing from the code signature -> built (D2c) | the doc was ahead of master |
| Changed | `accepts =` "type list or requirement" -> both, combinable, also on registry decls (D2d) | `slot_def.dm:322-327` crashes on a mix |
| Changed | forced transfer "only with an authority datum" -> now actually a datum (D2j) | master is a mask |
| Added | `replace =`, `quantity =`, `members = DATUM`, `unit = UNITS(table)`, `slot_group(ordered =)`, `survives_container` honouring | D2e, D2f, D2g, D6, D10 |
| Dropped | none | |

### 6.3 Against section 9 (requirements)

| | Item | Reason |
|---|---|---|
| Kept | `needs()` takes requirements only; library defaults carry a reason; `not(r, because =)`, `any_of` joins, `all_of` reports the first; `id =` relaxing; purity; generated reads; "strings are never conditions" | |
| Changed | "A requirement is a condition plus a reason" and "`req(PROC_REF(x), because =)`, x returns TRUE or FALSE" -> a requirement **is** the check (null or `/datum/msg`); a condition is its boolean view | matches master (`requirement_bool` hard ban, `cond.dm:228`); the TRUE/FALSE form was never what the code did |
| Changed | the one-signature table row "A requirement: returns TRUE or FALSE" -> "null or a reason; a dynamic reason returns a `/datum/msg`" | same |
| Changed | `req_fits_bodytype()` "the item fits the wearer's body type" -> reads category then override, keeps the sprite rule | D3 |
| Changed | `req_property_at_most(PROP_SIZE_CLASS, n)` and `size_is(min, max)` -> one `size_at_most`/`size_between` over the one size model | D2b |
| Added | `req_removable`, `req_loose`, `req_cooldown(key)`, `req_tool(quality)`, `req_whitelisted(job)`, `req_species_allowed(species)`, `req_taur_body`; the `reads = TYPE_LEVEL \| INSTANCE` declaration; `requirement_reason(R, holder, candidate, actor)` for any candidate | D2g, D6, D7, D8 |
| Dropped | `cond_*` and `CHECK()` as separate condition languages (they are not in the doc; they are code-only) | D1 |

### 6.4 Against section 17 (old to new) and the previous proposal

Section 17 rows that are **wrong or incomplete** against this design:

- `REQ_ON` 296, `REQ_TARGET_STATE` 192, `REQ_PROC` 36: "the proc becomes `x(datum/act/A)` returning TRUE or FALSE, the text moves to `because =`". This design keeps null-or-reason (the codemod must not rewrite `return "reason"` to `return FALSE`; it must rewrite it to `return MSG(x)`).
- `REQ_FITS_BODYTYPES` 73 (master: 32 lines) and `CONSTRAINT_*` 21 (master: 132): "a requirement on `/datum/act/equip`" is right for fit and equip; hold and suit storage go to slot `accepts` (D4c); the row needs the `fit`/`wears` categories (D3).
- `HOLD_ONLY` 299 and `HOLD_MAX_SIZE` 147 (master: 115 combined): target `accepts = req_property_at_most(PROP_SIZE_CLASS, ...)` is superseded by D2b.

| | Previous proposal (`clothing_requirements.md`) | Now |
|---|---|---|
| Kept | the census method; "this is a remaining sweep, not a design problem" for fit and equip; the outcome-enum caveat (ban the macro list, not the prefix); ban at the last wave with `legacy_form_counts.sh` through the waves; AGENTS.md updated in the ban commit | |
| Changed | D1 carrier: finish `acceptance("channel")` plans | interim only; endgame is slot `accepts` and `extend(act, needs)` (the doc's literal form) |
| Changed | D2 species fit: shared named lists, invert later | inversion now (D3): species `wears`, item category, `fit_override`; also covers the 122 accessory lists the old proposal never counted |
| Changed | D3 slot specs: `acceptance("equip")` on the slot type | slot `accepts =` (D4); the equip catalog (19) is an interim artifact |
| Changed | D4 non-admission uses (stance, vore consent, closet `slot_loose`): `needs(req(...))` on the op | kept for stance and vore; closet `slot_loose` goes to `accepts = req_loose()` (D4b); the vore predicates (6) become `req(PROC_REF(x), because =)` |
| Changed | D5 taur and clearance procs: library requirement per meaning | those procs are **impure** in two cases; the appearance moves to `on_slotted` first (D5) |
| Changed | D7 sequencing with Codex: merge two branches first | one merged; `req-burndown` exists, unmerged and unread; two other acceptance branches unmerged (D11) |
| Added | everything in D1 (old `/datum/req`, six-to-one collapse, `/datum/msg`), D2, D6 to D10 | the approved scope is "admission", not "clothing" |
| Dropped | the "stale `was REQ_*` comments" sweep as a wave item | folded into wave 0's census; trivial |
| Corrected | "163 `acceptance(` declarations" | 150 content declarations (fit 67, suit_storage 72, hold 7, equip 4) + 19 equip-catalog + 13 test = 182 at master |

### 6.5 `final_api.html` edits needed (not made here)

1. Section 9, "Conditions and requirements": rewrite the first paragraph and the combining list to "a requirement returns null or a `/datum/msg`; a condition is its boolean view"; delete "plus a reason".
2. Section 9, "The one signature" table: change the requirement row ("returns TRUE or FALSE") and the "dynamic reason" row to null-or-`/datum/msg`; add the actorless-check note (D2i).
3. Section 9, "The old REQ_ON, REQ_TARGET_STATE and REQ_PROC become req(PROC_REF(x), because = ...)... return a boolean" sentence: replace with the null-or-reason contract.
4. Section 9, "Library requirements" group: add `req_removable`, `req_loose`, `req_cooldown(key)`, `req_tool(quality)`, `req_whitelisted(job)`, `req_species_allowed(species)`; change `req_fits_bodytype()` text (category then override); replace `req_property_at_most(PROP_SIZE_CLASS, n)` with the single size requirement; state the type-level or instance-level declaration (D8).
5. Section 6 "Containment and slots": add `unit =`, `capacity = nameof(var)`, `replace =`, `quantity =`, `members =`, `slot_group(ordered =)`; give `fits =` as built; say `accepts` may combine a type list and requirements; document the stated reason order (D2h) and "no actor means a system mover".
6. Section 6: change "an authority datum" paragraph to describe the datum (`skips`, `quiet`, who granted); list `forced`, `silent`, `disable_warning`, `ignore_obstruction` in section 17 as replaced by it.
7. Section 6: specify `survives_container` (with `proposals/relations.md` D1) and the SPILL default; the DELETE exception for built-in parts.
8. Section 8 "World actions": `/datum/act/equip` fields `(wearer, slot_id)` and the hook-on-item rule; `/datum/act/remove` with `req_removable`; the `insert` action's moved amount.
9. Section 17: fix the `REQ_ON`, `REQ_TARGET_STATE`, `REQ_PROC` rows (return contract), the `REQ_FITS_BODYTYPES`, `CONSTRAINT_*`, `HOLD_*` rows and counts (use the master counts in this document); add rows for `cond_not/cond_all/cond_any` (260), `req_acceptance_*` and `acceptance(` channels (150 + 19), `/datum/predicate` and `PRED_*`, `/datum/req` and its 6 live constructors, `CHECK()`/`FACT()`/`ALL_OF/NOT_OF`, `species_allowed` (122), `sprite_sheets` keyed by species (81), `canremove` and `NOSTRIP` (164), `w_class` read as size, `storage_cost`, the closet formula and `size_probe`, `can_install`-style boolean gates, and `GLOB.act_last_reason` (35).
10. Section 19 migration: add this document's waves 0 to 8 as the E2 content sequence; note the retirement of `/datum/req` as a prerequisite of any native `req_access`.
11. Section 21 decisions: record the null-or-reason requirement decision and the one-reason-type (`/datum/msg`) decision.
12. Section 22 layout: library requirements move to `code/library/requirements/` without the `acceptance` file name; fit categories live in `code/library/clothing/`.

## 7. Census at the end of wave 2 (18 Oct 2026, `rewrite/admission` at `267576fccd`, content only: tests and generated files excluded)

The exact counts wave 0 promised, by `git grep -c -E` on the pattern named. `codex/req-burndown` (merged into master 17 Oct) retired the `REQ_*`
predicate tables, `/datum/predicate` and the `HOLD_*` macros before this lane reached wave 8, so their rows are zero here.

| Form (pattern) | Lines | Files | Wave |
|---|---:|---:|---|
| `REQ_*(` predicate macros | 0 | 0 | 8: done by req-burndown |
| `/datum/predicate` | 0 | 0 | 8: done |
| `HOLD_ONLY/NOT/MAX_SIZE` | 0 | 0 | 5: done |
| `fit_spec`, `equip_spec`, `hold_spec`, `suit_storage_spec` tables | 0 | 0 | 3-5: done (one comment left in `__defines/clothing.dm`) |
| `cond_not/cond_all/cond_any` | 0 | 0 | 1: done, hard-banned |
| `because = "..."` outside tests | 0 | 0 | 2: done, hard-banned |
| `GLOB.act_last_reason`, `ACT_TRY`, last-outcome/reply globals | 0 | 0 | 2: done, hard-banned |
| `acceptance("channel", ...)` declarations | 150 | 43 | 8 |
| `acceptance(CONSTRAINT_*, ...)` declarations | 176 | 40 | 3-5 |
| `CONSTRAINT_FIT/EQUIP/HOLD/SUIT_STORAGE` (all uses) | 199 | 49 | 3-5 |
| `req_acceptance_*` leaves | 224 | 62 | 1 (rename) |
| `fits(` | 102 | 52 | 3 |
| `species_allowed =` | 122 | 7 | 3 |
| `sprite_sheets(_obj) = list(` | 81 | 39 | 3 |
| `SPECIES_*_CAN_WEAR` | 17 | 2 | 3 |
| `canremove` | 116 | 45 | 4 |
| `NOSTRIP` | 21 | 17 | 4 |
| `disable_warning` | 25 | 7 | 4 |
| `ignore_obstruction` | 10 | 3 | 4 |
| `wearer_is_actor` | 11 | 3 | 4 |
| `dq_equip_refusal` | 2 | 1 | 4 |
| `LEDGER_MOVE_FORCED` | 20 | 10 | 6 (authority grant) |
| `insert_refusal(` | 17 | 9 | 6 |
| `op("...insert...")` | 83 | 68 | 6 |
| `CanPass(` (all, incl. callers) | 106 | - | 7 |
| `trans_to(` | 42 | 23 | 7 |
| `is_job_whitelisted` / `is_alien_whitelisted` | 23 | 13 | 7 |

**Purity report (D5).** req-burndown converted the two confirmed impure previews (saddlebag `taur_fit`, Avida `match_ears`) to pure requirements with the
appearance set through equipment notices (its handoff, `intended_changes.md`); no `REQ_ON` proc is left to audit.

**Wave 4 decisions (18 Oct, recorded by the admission lane; canremove/NOSTRIP **resolved**, confirmed by the coordinator).** `canremove` and `NOSTRIP` stay: `canremove` is a rig's or a locked item's own tracked
*state* (sealed, locked on: 53 reads, most of them the rig deciding what it is), and `NOSTRIP` is item flag data. What wave 4 removes is their use
as *gates*: removal is asked through `req_removable()` (strip menu) and the pure `mob_can_unequip()`; banning the names would only rename state.
`ignore_obstruction` stays as the equip check's explicit "skip the covering check" mode (tape over clothes) until the authority datum carries
skips (D2j); `dq_equip_refusal` stays until `/datum/act/equip` carries the whole pipeline (D2k). `disable_warning` and the `*_spec` table
names are hard-banned.

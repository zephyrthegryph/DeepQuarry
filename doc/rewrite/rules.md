# Properties, rules, constraints and abilities (track P)

This engine answers four questions. Containment, interactions, damage, temperature and abilities all ask them the same way, through one predicate language:
- **What is this thing?** Its properties.
- **What does a container imply?** Aggregates of its contents' properties.
- **Is this allowed?** Constraints.
- **What happens when a value crosses a line?** Rules.

## 1. Properties

- **Per-type properties** are computed lazily, once per type, from `initial()` on the type path plus its variant table (`code/datums/variants/`). No instance is created.
- **Tags** are capability flags, stored as bitsets per type:
  - `wearable:head`, `suit_storable`, `holster:small_gun`;
  - `tool:screwdriver`, `sharp`, `liquid_container`, `flammable`, `conductive`, `radio`.
- **Measures** are numbers with units: size class, volume, mass, heat capacity, integrity, thresholds (melting, ignition, cook-off, boiling) and resistances.
- **Providers.** Each property has one provider:
  - the type table;
  - a domain (temperature comes from heat, charge from power);
  - or instance state (the object's delta).
- **Aggregators** are declared once per property:
  - sum: mass, heat capacity;
  - minimum: the lowest threshold, kept as a count per value so removals are cheap;
  - maximum;
  - OR: flags;
  - per-zone composition: equipment ([containment.md §6](containment.md#6-equipment)).

  The ledger keeps aggregates current as contents change.
- **Boot validation.** Every property used by a predicate, constraint or rule must have a provider and, where it's aggregated, an aggregator. Units must match.

## 2. Predicates

A predicate is a small compiled expression over properties and context:
- **Clauses:** tag present or absent; measure compared with a value (with units); state compared with a value; actor capability present; access present.
- **Combinators:** AND and OR.
- **Reasons.** Every clause carries reason text: "too big (size 4, fits 3)", "needs a screwdriver", "the panel is closed". The first failing clause produces the reason.
- **Compiled.** Each predicate compiles once per type into bitset tests and numeric comparisons, using typecaches only where tags don't fit.

Constraints, rule conditions and interaction requirements all use this language, so "melts at 800 K", "can be welded" and "this armour covers the head" are the same kind of check.

## 3. Constraints

Constraints attach at three points:
- **Slot definitions** say what a slot accepts. A holster accepts `holster:small_gun`, and a pocket accepts size 2 or smaller.
- **Item types** say what they require: a body plan, species fit, size, or a free hand.
- **Interactions** say what the actor needs ([interactions.md](interactions.md)).

The ledger's `can_insert` (both sides), equipping and interaction availability all evaluate constraints through one code path, so the answer and the reason are the same everywhere.

**What they replace:**

| Today | Count |
|---|---|
| `can_hold` lists | 147 |
| `cant_hold` lists | 7 |
| `species_restricted` lists | 83 |
| `allowed = list(…)` lists (suit storage and similar) | 287 |
| `slot_flags` assignments | 425 |
| `max_w_class` values | 83 |
| `mob_can_equip` (`code/game/objects/items.dm`) | 1 proc: 88 lines, 39 conditionals, 40 callers |
| Storage `can_be_inserted`, which re-adds every item already inside on each call | 1 proc |
| `slot_in_backpack`, which skips storage insertion entirely | 1 path |

Tags replace most of the type lists: an item declares `suit_storable`, and a suit's storage slot accepts that tag.

### 3.1 As built (P3)

The code is in `code/datums/properties/constraints.dm` (API), `code/datums/properties/equip_slots.dm` (equip slots) and `code/datums/properties/families/wearable.dm` (tags). Defines are in `code/__defines/constraints.dm`.

- **Declaring.** An item type overrides a proc and returns a spec (a list of `REQ_*` clauses), or null for none. The proc runs once per type and the spec is compiled and cached by type:
  - `hold_constraint()`: what a holder takes (storage, holsters). `HOLD_ONLY(types)`, `HOLD_NOT(types)` and `HOLD_MAX_SIZE(size)` are shorthands.
  - `suit_storage_constraint()`: what a worn suit's suit-storage slot takes. Null means no suit storage. PDAs and pens always fit a suit that has one.
  - `fit_constraint()`: whose body the item fits, with `REQ_FITS_BODYTYPES(list)` (the old `species_restricted` rules, include or `"exclude"` form, and the Teshari and Werebeast sprite rule).
  - `equip_constraint()`: what the item needs of its wearer in any slot (taur halves, a robotic head, not wielded, owner-only fluff items).
- **New clauses.** `REQ_TYPE(subject, types)` compiles a typecache; `REQ_FITS_BODYTYPES` evaluates the fit rule against `PRED_ACTOR`.
- **Instances.** `set_constraint(kind, spec, key)` installs a compiled override on one instance: `restrict_hold()` (exact-fit boxes, internal pockets, random xenoarch boxes), `restrict_fit()` (refits, paint kits), `adopt_constraint()` (a rig's chest piece takes the rig's suit storage).
- **Reading.** `dq_constraint(I, kind)` gives the compiled predicate, and `dq_constraint_refusal(I, kind, thing, actor)` the reason.
  - `storage.insert_refusal(W, user)` is the hold constraint, then space and stuck items. It replaced `can_be_inserted()`.
  - `item.equip_refusal(M, slot, ...)` checks that the species has the slot, the slot's predicate, that the slot is free (unless `TAG_WEAR_OVER`) and reachable, then `CONSTRAINT_FIT` (except in pockets and suit storage) and `CONSTRAINT_EQUIP`. It replaced `mob_can_equip()` and its 27 overrides.
- **Equip slots.** Each slot has a `/datum/predicate/equip_slot` subtype, with the wearer as `PRED_ACTOR` and the item as `PRED_TARGET`. The `slot_flags` checks became wearable tags (`TAG_WEAR_HEAD`, `TAG_POCKETABLE`, `TAG_NO_POCKET`, `TAG_HOLSTERABLE`, …) that read the instance's current `slot_flags`. Slot rules are proc clauses: pockets and IDs need a jumpsuit, suit storage asks the worn suit, the backpack slot asks the backpack, gloves layer, and two-ear items need both ears.
- **Slots.** `slot_def.holder_constraint` names a `CONSTRAINT_*` kind that `refusal()` reads from the holder after `accepts`. A C4 storage slot sets `holder_constraint = CONSTRAINT_HOLD`, and a C3 equip slot uses the matching `equip_slot` predicate as `accepts`.
- **Parity.** `code/modules/unit_tests/data/dq_constraint_parity.json` holds the legacy answers, captured before the conversion: every storage type × 824 items, every suit with storage × 824 items, 17 holsters, and 4,734 equip items × 22 slots × naked and dressed for a human, plus the species-sensitive items for 38 species. That is 3.2 million cells, and `dq_constraint_parity/*` requires every cell to match.
- **Left as they were.** The champion belt's legacy list named its mask as a string, so it has never held anything, and it still doesn't. Robot grippers keep their own `can_hold` (robot modules move with C3).

## 4. Rules

**Rule = trigger + condition + effect.**
- **Trigger:**
  - a property crossing a value (temperature, integrity, pressure, charge, radiation dose, time);
  - or an event: damage packet, EMP, contact, entered, exited.
- **Condition:** a predicate (§2).
- **Effect**, one of two kinds:
  - **Data transform.** Works on latent entries without creating an object: set a delta, swap the type (cooked, ash, shards), remove, add entries, add heat.
  - **Behaviour.** A proc on the real object. The ledger materializes the object first, then calls it.

**Where rules come from**
- Rules are declared per type and inherited, and they compose through elements. Every instance of the type has them without registering anything.

**How they run**
- Rules compile to reactor watches:
  - a real item with its own heat node gets watches on that node;
  - latent contents get one `ThresholdSet` per container. The ledger adds and removes each entry group's thresholds. When a threshold is crossed, the ledger applies the rule to that group, with one binomial roll for a stack of identical items.
- Time triggers use rate models, or a catch-up when read.

**Tests**
- For every declared threshold, a generated test pushes a sandboxed instance past it and checks that the effect happened.

**Examples:**

| Type | Rule |
|---|---|
| Paper | At 506 K or above, transform into ash and add the heat released |
| Plastic | At its material's melting point, transform into slag |
| Food | Once it has been above its cooking temperature for a set time, swap to the cooked variant |
| Ammo box | At its cook-off temperature, materialize and detonate (behaviour) |
| Cell | On EMP, drain its charge (data) |
| Glass | When integrity hits 0, transform into shards |
| Any object | At integrity thresholds, show the matching damage flavour text (generated, replacing about 26 hand-written lines) |

## 5. Abilities

An ability is an interaction the actor performs on themselves or a target:
- **Requirements**, as constraints with reasons.
- **Cost**, as a formula over properties.
- **Commit.** The cost and the effect are applied together, only after every requirement passes. An ability can't spend a resource and then fail.
- **Ongoing state**, if any: rate models and rules.

Abilities appear in the ability list and in the Menu action with their live cost, and can be bound to keys ([interactions.md](interactions.md)).

### Worked example: Shadekin phase shift

Today (`code/datums/components/species/shadekin/powers/phase_shift.dm:22-103`) it is an ~80-line chain of checks:
1. component;
2. special considerations;
3. consciousness;
4. phase-blocked area, with an admin bypass;
5. turf;
6. `doing_phase`, checked twice;
7. darkness from light level;
8. a watcher count;
9. a cost formula;
10. energy.

Energy is deducted before the final `CanPass` check, so a failed shift still costs energy (B13). The watcher loop also recomputes `oviewers(7, src)` for every candidate.

As an ability:

```dm
/datum/ability/shadekin_phase_shift
	name = "Phase shift"
	category = ABILITY_CAT_MOVEMENT
	requires = list(
		REQ_COMPONENT(/datum/component/shadekin),
		REQ_CONSCIOUS,
		REQ_ON_TURF,
		REQ_NOT(STATE_DOING_PHASE),
		REQ_AREA_ALLOWS(AREA_BLOCK_PHASE_SHIFT) /* admins bypass */,
		REQ_TURF_PASSABLE,
		REQ_RESOURCE(SHADEKIN_ENERGY, /datum/ability/shadekin_phase_shift/proc/cost),
	)

/datum/ability/shadekin_phase_shift/proc/cost(mob/living/user)
	var/darkness = 1 - PROPERTY(get_turf(user), LIGHT_LEVEL)
	var/watchers = PERCEPTION_OBSERVERS(user, 7)   // one shared query, computed once
	return clamp(100 / (0.01 + darkness * 2), 50, 80) + 15 * watchers
```

**Commit** spends the energy and phases in or out only after every requirement passes.

**While phased:**
- Energy is a rate model.
- Entering a phase-blocked area, or light rising above the limit, are rules that fire a dephase event. Today the area check lives in `/area/proc/check_phase_shift`.

The same structure fits species and borg abilities, and the body rewrite's protean powers registry (their phase 8).

## 6. Other systems to move onto rules

Move a system when at least one of these holds:
- its conditions are shared or duplicated across sites;
- players need to see what's available and why not;
- its conditions depend on simulation state that changes (light, energy, temperature);
- it is listed in menus or bound to keys.

Candidates:
- species and borg abilities;
- access checks (`req_access`);
- door states (bolted, welded, powered);
- crafting and chemistry recipe requirements;
- construction steps;
- vore consent;
- status effects;
- job and role restrictions;
- shuttle and docking conditions.

**Not candidates.** One-off scripted behaviour (unique items, events, antagonist objectives) stays as plain procs that rules call as effects: the rule system decides when, and the code decides what.

## 7. Limits

This is not a scripting language. Predicates stay small and declarative, and effects that need logic are DM procs. If a rule needs loops, state machines or several steps, it is behaviour: write a proc and trigger it from a rule.

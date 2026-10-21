# Proposal: transformations, one vocabulary for "inputs under conditions become outputs"

Status: **proposal, design only** (17 October 2026). Nothing here is implemented and no decision has been taken; section 11 lists the
decisions with a recommendation each. Branch `rewrite/transform-proposal` (from origin/master `1c1d649c08`). No code, no build and no test
was run to write this; every number below is from `git grep` and reading code on that commit, and measurements that do not exist yet are
said to be unmeasured.

Scope: every place the codebase declares "when these inputs are present under these conditions, consume these and produce those": chemical
reactions (instant, distilling, slime, blob, brain), gas reactions (DM and the Rust side), R-UST fusion, heat and phase changes, kitchen
recipes, crafting and stack recipes, smelting and alloys, grinding, material-science processes, and the lathe and xenoarch edges.

## 0. Summary

1. **Nine systems declare the same shape with nine private vocabularies.** Chemistry (`/datum/decl/chemical_reaction`, 749 types), gas
   (`/datum/gas_reaction`, 23), fusion (`/datum/decl/fusion_reaction`, 10), kitchen (`/datum/recipe`, 344), crafting (`/datum/crafting_recipe`,
   53), stacks (`/datum/stack_recipe`, about 549 construction sites), alloys (`/datum/alloy`, 8), grinding (two global tables) and heat rules
   (`/datum/rule`, 38). Each spells inputs, catalysts, temperature windows, outputs, energy and side effects differently, and each has its own
   matcher, its own ordering trick and its own tests (or none).
2. **They split on one axis the code never names.** In *matched* systems the world holds contents and something must discover which rule
   applies (chemistry, gas, kitchen, alloys, slime, fusion). In *chosen* systems an actor picks the rule (stack recipes, crafting, lathe
   designs). Chosen systems need no matcher at all; they need the same declaration form and an op. The proposal unifies the declaration for
   both and builds a matcher only for the first.
3. **One declaration, one compiled flyweight, one matcher architecture.** A transformation is a type with a `transformation(...)` entry in
   its `CAPABILITIES` block, a `STATIC_ENTRY` kind exactly like `loot()`: read without an instance, compiled once at world setup, indexed by
   input key, evaluated when a medium's contents change.
4. **Gas stays Rust-resident, declared from DM.** The DM declaration generates the registry the native gate already reads (requirements,
   priority) and the enthalpy table `reaction_energy.rs` hard-codes today. Rate laws stay DM callbacks in the first wave and move to named
   Rust laws only where a measurement says to.
5. **Effects are typed notices plus a small stock vocabulary.** The 134 `on_reaction` overrides, the logging and the contract events become a
   `/datum/notice/transformed` publish and listeners; only a counted, shrinking tail keeps a `then(PROC_REF)`.
6. **Conditions are reason-less; reasons appear only on demand.** Transformations are world processes, so they never refuse with a message.
   A chosen transformation reaches a player through an op, whose `needs()` asks the transformation for a lazily computed diagnosis.
7. **The risk is behavioural parity, not the engine.** Overlapping rules compete for reactants and today's winner is decided by declaration
   order, bucket order and holder order. The first wave records those outcomes as pins on the legacy code before converting anything.

## 1. Naming: why not "reactions"

`doc/rewrite/reactions.md` already uses **reaction** for something else: an event trigger (`on_notice`, `on_change`, `every`, `before_op`,
the `reactions()` table proc, `/datum/reaction`, `rx_*`). Chemistry's own `/datum/decl/chemical_reaction`, `/datum/gas_reaction` and
`handle_reactions()` use the word the other way. Reusing it would make "a reaction reacts to a reaction" a real sentence in this tree.

`recipe` clashes too (`/datum/recipe` is the kitchen's, `/datum/stack_recipe` and `/datum/crafting_recipe` are the other two, `select_recipe`).
This proposal uses **transformation** for the declared rule, **subject** for the thing that holds the inputs (a beaker, a turf's air, a
microwave, an ore processor), **medium** for how a subject stores them (reagents, gas, contents, ore stock, batch), and **term** for one
input or output. The path root for abstract rule types is `/transformation/...` (as `/loot/...` is for loot tables). The entry constructor
is `transformation(...)`; `transform` is avoided because `/atom/var/transform` exists. Section 11 D1 offers the alternatives.

## 2. Inventory

Counts are type declarations (`^/datum/...` lines with no proc suffix) outside `code/engine/_generated/`. "Matcher" is how candidate rules are
found; "trigger" is what makes the engine look.

| System | Defined | Rules | Declared as | Matcher and trigger | Inputs | Outputs | Side effects | DM / Rust | Tests |
|---|---|---|---|---|---|---|---|---|---|
| Chemistry, instant | `code/modules/reagents/reactions/instant/{instant,drinks,food,virology}.dm`, base `reactions/_reactions.dm:13` | 547 (233 + 258 + 27 + 29) | `/datum/decl/chemical_reaction/instant/x` with vars `required_reagents`, `catalysts`, `inhibitors`, `result`, `result_amount`, `reaction_rate`, `yield`, `min_reaction`, `mix_message`, `reaction_sound`, `log_is_important` | `/datum/system/chemistry` (`chemistry_service.dm:5`) builds `instant_reactions_by_reagent[first required reagent]` once, lazily; `handle_reactions()` (`holder/holder.dm:142`) unions the buckets of every reagent in the holder, runs `can_happen()` then `react_step()`, loops until nothing reacts. Triggered by every `add_reagent` / `remove_reagent` / transfer that is not `safety` | reagent ids with amounts; catalysts are minimum amounts, not consumed; inhibitors are maximum-zero | one `result` reagent plus its `data` | `on_reaction` (134 overrides: explosions, smoke, foam, spawns), `send_data` (43), `post_reaction` message and sound, `emit_contract_event`, chemistry log | DM driver; step maths in Rust (`vg_chem_reaction_progress`, `verdigris/domains/chem/src/reaction.rs`) | `chemical_reactions_shall_not_conflict`, `..._use_and_produce_valid_reagents`, `dq_chem_reaction_progress_pin` (5,800 rows) |
| Chemistry, distilling | `reactions/distilling/*.dm`, holder `holder/distilling.dm` | 75 (27 + 7 + 14 + 21 + 4 + 2) | `/datum/decl/chemical_reaction/distilling/x`; adds `TYPE_TABLE(..., distilling_temp_range, list(lo, hi))`, `temp_shift`, `require_xgm_gas`, `rejects_xgm_gas`, `minimum/maximum_xgm_pressure`, `consumes_xgm_gas` | same loop over `distilled_reactions_by_reagent`, chosen by the holder class (`get_reaction_lookup()`); the holder hand-builds one heat `ThresholdSet` over every candidate's temperature bounds and reacts on a crossing | reagents, temperature window, surrounding gas amount and pressure | reagent; heat to the room gas (`heat_add(GM, temp_shift * 1000)`); gas consumed | `on_reaction` for gas and heat | DM, same Rust step | same pins |
| Slime, blob, brain | `xenobio/items/extracts.dm`, `slimess/xenobio.dm`, `blob2/core_chunk.dm`, `body/organs/internal/brain.dm` | 123 (86 + 37), 2, 1 | `/datum/decl/chemical_reaction/instant/slime/x` with `required = /obj/item/slime_extract/x`, `can_happen()` override checking `my_atom` type and `uses` | same instant buckets (the subject check is a `can_happen()` override, so every slime rule is a candidate in every beaker that holds its reagent) | one reagent (phoron 5, blood 5) in a typed subject | usually no reagent; a spawn, a message, `uses--` | all in `on_reaction` | DM | none specific |
| Gas | `code/ATMOSPHERICS/gasmixtures/reactions.dm:46`, dispatch `gas_mixture.dm:361`, factors `reaction_factors.dm` | 23 types, 22 enthalpy kinds | `/datum/gas_reaction/x` with `init_reqs()` returning `requirements = list(gas = min_moles, "MIN_TEMP", "MAX_TEMP")`, `priority_group`, `id`, `expands_hotspot`; behaviour in `react(air, holder)`; docs in `init_factors()` | priority numbers assigned at boot (`group * 1000 + counter`); native frame gate checks registry requirements per cell on frame threads (`verdigris/domains/gas/src/gate.rs`) and emits `CellReactionReady`; DM `air.react(turf)` then re-checks every requirement itself and runs all that hold, re-reading the mixture after each | gas moles, min and max temperature (the gate also knows `min_energy`, `min_fire`) | gas deltas and an extent; temperature by enthalpy | hotspot, radiation, `reaction_results`, hot ice, fire spread; returns flags (`REACTING`, `VOLATILE_REACTION`, `STOP_REACTIONS`) | DM chooses rate and stoichiometry; Rust applies deltas and books enthalpy (`gas_react()`, `heat_net.dm:127`, `reaction_energy.rs`, a `match` on 22 hand-numbered kinds) | `dq_gas_reaction_energy_pins` (temperature and total moles after one step, per reaction) |
| R-UST fusion | `code/modules/power/fusion/fusion_reactions.dm`, consumer `core/core_field.dm:392`; `reagents/reactions/fusion/fusion.dm` is a three-line TODO comment | 10 | `/datum/decl/fusion_reaction/x` with `p_react`, `s_react`, `energy_consumption`, `energy_production`, `radiation`, `instability`, `products`, `minimum_energy_level`, `minimum_reaction_temperature`; `handle_reaction_special()` | symmetric hash of hashes `GLOB.fusion_reactions[p][s]`, built on first call; the field picks random reactant pairs from its own pool every cycle | two reactant keys in a field's pool | products back into the pool, field energy, radiation, instability | `handle_reaction_special` (supermatter) | DM | none |
| Kitchen | `code/modules/food/recipe.dm`, `recipes_{microwave,oven,fryer,grill}.dm`, `compile_recipes.dm`; matcher `select_recipe()` at `recipe.dm:317` | 344 (192 + 84 + 28 + 40) | `/datum/recipe/x` with `reagents`, `items`, `fruit`, `coating`, `result`, `result_quantity`, `time`, `reagent_mix` (MAX, MIN, SUM, REPLACE), `appliance` bitfield; 14 procs overridden | `GLOB.available_recipes[appliance]` list; `select_recipe()` tests every recipe of the appliance (reagents, then items, then fruit) and keeps the one with most terms, ties to the last; called when cooking starts and again inside `while(select_recipe(...) == recipe)` | reagents (contents must be exactly the listed set), item types (non-exact by default), `fruit` by seed kitchen tag, coating | `result_quantity` objects, reagents merged by `reagent_mix` | `before_cook`, `after_cook`, mob-holder ghosting in `make_food` | DM | `recipe_test` (a result exists; nothing about selection) |
| Crafting | `code/datums/crafting/{recipes,tyr_tribal}.dm` | 53 | `/datum/crafting_recipe/x` with `reqs` (list of `list(type = n)`), `result`, `time`, `category` | chosen from a menu | item and stack types | one item | none | DM | none |
| Stack recipes | `code/game/objects/items/stacks/stack.dm:491`; built in `material.dm:275` and about 25 files | about 549 `stack_recipe(` sites | `new /datum/stack_recipe(title, result_type, req_amount, res_amount, max_res_amount, time, one_per_turf, on_floor, supplied_material, pass_color)` constructed into per-stack lists at run time, per material | chosen: `op("make", ...)` with a `/datum/stack_recipe` argument | units of one stack | `res_amount` of a type | none | DM | none |
| Alloys and smelting | `code/modules/mining/alloys.dm`, matcher in `mining/machinery/machine_processing.dm:329` | 8 | `/datum/alloy/x` with `metaltag`, `requires = list(ORE_X = n)`, `product_mod`, `product` | `for(A in GLOB.alloy_data)` in file order; a comment demands subset alloys be ordered by hand ("steel comes after plasteel"); gated by the per-ore setting `PROCESS_ALLOY` | ore units in the machine's stock | `max(1, round(total * product_mod))` sheets | none | DM | none |
| Grinding | `code/_helpers/refinery.dm:2` with `GLOB.sheet_reagents`, `GLOB.ore_reagents` | two tables | item type to reagent id or list | the grinder walks `holdingitems`, looks each up | one item or stack units | reagents split evenly, clamped to free volume | `puny_protons()` for supermatter | DM | `chemical_grinding_must_produce_valid_results` |
| Material science | `code/modules/materials/engineering/material_batch.dm:124` (`apply_process`, `can_process`) | 7 processes (melt, cast, quench, forge, purify, homogenize, solution treat) plus additives, surface layers, dissolved gas, field treatment | a `switch` of conditions and clamped deltas on a batch's fields; the batch says "recipes do not select an alloy" | chosen by a machine or tool | batch phase, temperature as a fraction of its melting point, counts | state deltas, heat into a Rust heat store, a contract event | `emit_contract_event` | DM, heat in Rust | `dq_material_science_tests` (slots, design cost, feedstock; no process outcomes) |
| Heat rules | `code/datums/rules/declarations.dm:12` and `binding.dm:376` | 38 rule types | `/datum/rule/x` with `applies_to`, `effect_proc` or `transform = list(RULE_SWAP_TYPE(...))`, `hold_for` | threshold crossing on a heat body, delivered by native watch | temperature against a per-type point | a type swap (`/obj/effect/decal/cleanable/molten_item`), a state, a behaviour | per rule | DM with a Rust watch | generated `dq_rule_thresholds` |
| Metabolism | `holder/` metabolism and `verdigris/domains/chem/src/metabolism.rs`; reagent `affect_blood/ingest/touch` | per reagent | reagent datum procs | per Life cycle, one Rust call per holder | reagent dose | body stats and injury | per-reagent procs | Rust maths, DM effects | `dq_chem_metabolism_pin` |
| Lathe designs | `code/modules/research/tg/designs/` | 1,364 `/datum/design` type lines (abstract bases included) | `materials`, `build_path`, category, research gating | chosen from a UI | materials | one item | none | DM | none |
| Xenoarch | `code/modules/xenoarcheaology/effect.dm` | 22 effects | `/datum/artifact_effect` with a per-instance random `trigger` and `effect` | stimulus check per artifact | a stimulus (heat, chemical, force) | an area effect | the effect | DM | none |

### 2.1 What the inventory shows

* **Index shape differs and one index is accidentally order-dependent.** Chemistry indexes a rule only under its *first* `required_reagents`
  key (`chemistry_service.dm:68`, `if(i > 1) continue`). That is safe for membership (all required keys must be present) but it fixes the
  cross-bucket evaluation order to *holder reagent order, then bucket order, then `subtypesof` order*. When two rules want the same reactant,
  the winner is whichever is reached first. Nobody declared that order; it falls out of the data structure.
* **Gas does the gate's work twice.** The native gate already holds every reaction's requirements and reports readiness per cell
  (`Gate::ready`, `all_ready`), and then `gas_mixture.dm:361` loops all 23 reactions in DM comparing the same requirements again and
  re-reads the mixture after each one that fires. Each `react()` body then makes its own FFI reads. The Rust side owns the heat of the
  reaction and the extent stays in DM, so the boundary is drawn through the middle of one calculation.
* **Enthalpy lives in Rust as a `match` on 22 magic numbers, with constants exported to DM by `@dm-define`.** Seventeen are `coefficient *
  extent`; five are not (sterilization scales with the new heat capacity, BZ blends two enthalpies by `aux`, freon formation follows a
  temperature curve, noblium divides by `aux`, supermatter's extent is a device energy). A declared table covers the seventeen; the five are
  named laws.
* **Chemistry's fixed point does a lot of small steps.** `handle_reactions()` loops until no reaction progresses. A reaction with a half-life
  of six ticks takes `1 - 0.5^(1/(6*5))` (about 2.3 percent) of its limit per step and completes only when the remainder is under
  `min_reaction`; for a 30-unit batch that is on the order of a hundred iterations per call, each building a list and crossing the FFI. This
  is arithmetic from the code, not a measurement. It also means `reaction_rate` mostly shapes yield-capped products, not elapsed time: a
  holder reacts to completion inside one call. `reagents.md` section 4 already names "the whole fixed point for plain holders" as the next
  Rust candidate.
* **Kitchen recipes require exact reagents but not exact items.** `check_reagents()` fails when the container holds any reagent the recipe
  does not list (`LAZYLEN(reagents) < reagent_list.len`), while `check_items()` ignores extras unless `exact`. Chemistry instead names
  inhibitors. Both are "what else may be present"; they are one parameter (`exclusive`) per currency.
* **Subset ordering is hand-maintained twice.** The alloy file warns that alloys whose ingredients contain another alloy's must be ordered by
  hand; the kitchen picks by term count with a tie rule of "last wins". Both are the same policy (the more specific rule wins) written as
  prose in one place and as a counter in another.
* **A full container silently destroys matter.** `react_step()` removes the reactants and then `add_reagent()` clamps the product to free
  space (`holder.dm:181: amount = min(amount, get_free_space())`), so a reaction whose product exceeds the free volume loses the difference.
* **Several consumers read the rule data and need a reverse index:** the wiki (`internal_wiki.dm`), `recipe_dump.dm`, the medical book's
  reagents tab, the synthesizer's product lookups, and the hand-written `init_factors()` prose in `reaction_factors.dm` (216 lines that
  repeat requirement numbers as text). The product-keyed buckets (`chemical_reactions_by_product`) exist for them.
* **Debug and audit paths ride on the rule base class.** `react_step()` emits a contract event and `Chemistry-Logging.dm` and
  `log_is_important` message admins. AGENTS.md section 3e forbids dropping those without permission; they must move, not vanish (section 6).

## 3. The shared model

A transformation is a pure description: **which terms are taken and made, under which conditions, how far per step, with what energy, and
what is announced.** Everything below is a part of one entry.

| Part | Meaning | Chemistry | Gas | Kitchen | Alloy | Slime |
|---|---|---|---|---|---|---|
| `takes` | terms consumed, with amounts | `required_reagents` | `requirements` minus catalysts, with stoichiometry | `reagents`, `items`, `fruit` | `requires` | `required_reagents` |
| `catalysts` | present at least this much, not consumed | `catalysts` | the gas that gates a formation (BZ for N2O) | none | none | none |
| `blocked_by` | absent (or below this) | `inhibitors` | `MAX_TEMP`, a rejecting gas | `exclusive` | none | none |
| `when` | reason-less conditions on the subject and its surroundings | `can_happen()` overrides | `MIN_TEMP`, `MAX_TEMP`, location | `appliance` | `PROCESS_ALLOY` setting | the subject's type and `uses` |
| `extent` / `rate` | how far one step goes | `reaction_rate`, `yield`, `min_reaction` | the body of `react()` | `time` | one batch | instant |
| `makes` | terms produced | `result`, `result_amount`, `send_data` | deltas | `result`, `result_quantity`, `reagent_mix` | `product`, `product_mod` | usually none |
| `energy` | heat released or absorbed per unit of extent | `temp_shift` (room gas) | the enthalpy kind | the appliance's heat | none | none |
| `effects` | what is announced and shown | `on_reaction`, `mix_message`, `reaction_sound` | hotspot, radiation, `reaction_results` | `before_cook`, `after_cook` | none | spawn, message |
| `priority` | which of several rules wins | order of data structures | `priority_group` | most terms, last wins | file order | none |

**Terms.** A term is `currency(key, amount)`. Currencies are the existing resource adapters of foundation X2 (`RES_REAGENTS`, `RES_STACK`,
`RES_ITEM`, `RES_SLOT_CAPACITY`, ...) plus one new adapter, `RES_GAS`, backed by `gas_react()`. A term set against a subject resolves through the
adapter, so *atomicity and refunds come from the adapter*: a transformation either reserves everything it takes and commits, or touches
nothing. The hot media (reagents, gas) have a bulk path that checks and commits in one call instead of reserving term by term.

```dm
reagent(REAGENT_ID_WATER, 5)          // a reagent amount in the subject's reagents() holder
gas(GAS_PLASMA, 1)                    // moles in the subject's mixture
item(/obj/item/reagent_containers/food/snacks/egg, 1)
stack(/obj/item/stack/material/steel, 4)
ore(ORE_CARBON, 1)                    // a smelter's stock key
fruit(PLANT_CHILI, 1)                 // a grown item matched by seed kitchen tag
```

**Two selection modes, one declaration.**

| | Matched | Chosen |
|---|---|---|
| Who decides | the engine, from the subject's contents | an actor, from a menu or a click |
| Systems | chemistry, gas, kitchen, alloys, slime, fusion, grinding | stack recipes, crafting, lathe designs, material processes |
| Needs a matcher | yes (section 5) | no |
| Needs an index | yes | no (a list for the menu) |
| Entry point | medium change, event or timer | an `op()` whose `then()` calls `transform_apply(X, subject, actor)` |

**Two kinds of effect on state.** An *exchange* takes terms and makes terms. A *mutation* changes named state on the subject with no terms
made (material-batch processes, a heat rule's type swap). Both share conditions, energy, effects and priority; a mutation replaces `makes`
with `sets` / `adds` on tracked vars (through their generated setters, so reads and notices flow).

## 4. The declaration form

All of this is **new**; today's legacy forms remain what is written until a wave lands (section 10). `transformation()` is a
`STATIC_ENTRY(transformation)` kind with `singleton = TRUE`: one per type, a subtype changes it with `configure(transformation(...))`, parents
compile first, an argument left null is inherited. The compiled result is a lean `/datum/xform` flyweight (the same mechanics as
`loot_decl_for()`, `code/engine/declare/static_entries.dm`).

Parameters (all optional except the terms that define the rule):

```dm
transformation(
	medium = MEDIUM_REAGENTS,              // how the subject stores the terms; inferred from the currencies when omitted
	regime = REGIME_INSTANT,               // which holders run it (a holder declares runs(REGIME_X)); replaces the instant/distilling bucket split
	takes = list(...), catalysts = list(...), blocked_by = list(...),
	exclusive = list(CURRENCY_REAGENT),     // any currency not listed here may not be present (kitchen reagents)
	when = <condition>,                    // reason-less; all_of / any_of / not; temperature_in(lo, hi), pressure_in(lo, hi), subject_is(T), appliance(F)
	rate = instant | half_life(n) | rate(r), yield = 1, floor = 2,   // chemistry's three numbers
	extent = EXTENT_STOICH | PROC_REF(x) | law(LAW_X, ...),          // how far one step goes when it is not the stoichiometric rate
	makes = list(...), data = PROC_REF(x),                           // x(datum/act/A) returns the product's data (send_data)
	energy = per_extent(J) | law(ENERGY_X), heat_to = HEAT_SUBJECT | HEAT_AMBIENT,
	priority = PRIORITY_DEFAULT,           // named bands (PRIORITY_FIRE, PRIORITY_FORMATION, ...); within a band the more specific rule wins
	capacity = CAPACITY_TRUNCATE | CAPACITY_LIMIT_EXTENT,            // section 8
	says = ..., plays = ..., notice = /datum/notice/transformed/x,   // effects, section 6
	then = PROC_REF(x)                     // the bespoke tail; counted
)
```

Examples with the current declarations beside them are in section 9. `when` takes the conditions the doc already defines (`nameof(v)`, a stat,
`not` / `all_of` / `any_of`, `PROC_REF(x)` returning TRUE or FALSE, a library requirement's boolean view) plus a few library constructors that
read facts the engine can watch: `temperature_in()` and `pressure_in()` read the subject's heat and gas, `subject_is()` reads its type.

**Compile (once, at `static_entries_built`).** For each type: intern term keys per currency to small integers; flatten `takes`, `catalysts` and
`blocked_by` to parallel arrays; precompute `plain` (no `then`, no PROC_REF condition, no PROC_REF extent), `specificity` (term count),
`order` (declaration order, stamped), the anchor key, the temperature and pressure bounds, and the product list for the reverse index.
`analyze gen` checks at build time: a duplicate signature (same takes, regime and priority) is an error, and a *shadow* (rule A's takes a
subset of rule B's takes where A is not lower priority, so B can never fire) is an error that names both. That replaces the alloy file's
ordering comment and most of `chemical_reactions_shall_not_conflict` with a build-time answer.

## 5. The matcher

### 5.1 Index

`xform_index[medium][regime][anchor_key]` is a list of `/datum/xform` sorted by `(priority, order)`. The anchor is the *first* `takes` key
in wave 1 (today's behaviour, so each bucket holds the same members in the same order). After the parity pins are green an optional pass
may re-anchor on the most selective key (as gas's `major_gas` already picks the rarest gas); that changes evaluation order and is a
separate, pinned, intentional change. A second index by product key (`xform_by_product`) serves the wiki, the synthesizer and the
handbooks.

### 5.2 When it runs

A medium publishes a change key when composition changes (`MEDIUM_KEY_CONTENTS` for reagents and contents, a gas channel for gas). Each
medium declares how that turns into a settle:

| Medium | Settle | Why |
|---|---|---|
| Reagents (chemistry, slime) | **inline at the end of the outermost write transaction** | callers read the product right after `add_reagent()` returns; a depth counter makes a burst of writes (a transfer, a spawn with contents) one settle |
| Reagents, timed (`half_life`, distilling) | **drained**, re-armed by `every()` while a candidate exists and parked otherwise | removes the hundred-step inner loop (section 5.4) |
| Gas | **event**: the native gate's `CellReactionReady`, frame-coalesced | already the design; unchanged |
| Kitchen, alloys | **on the appliance's own cycle** (cook start, smelter tick) | the appliance decides when, as now |
| Fusion | the field's own cycle | the field loop stays domain-specific |

The existing hand-rolled temperature watch in `holder/distilling.dm` (`reaction_temperatures()`, `watch_reaction_temperatures()`, one
`ThresholdSet` over every candidate's bounds) becomes generic: a declared `temperature_in(lo, hi)` is a condition whose reads include the
subject's heat, so the engine registers the union of the bounds as `on_cross` bands (hysteresis in Rust) and settles on a crossing. The
holder carries no watch code.

### 5.3 What a settle does

1. Gather candidates: for each key present in the subject (in the subject's own order, matching today), take its bucket; dedupe.
2. Test in cheap-to-expensive order, as `can_happen()` does today: amounts, catalysts, blocked-by, bounds, `when`, then any PROC_REF.
3. For each that passes, compute the extent, apply the deltas through the medium (reserve and commit; one call for a bulk medium), add the
   energy, collect an effect record.
4. Repeat until a pass fires nothing (a bounded iteration count, logged when hit).
5. After the fixed point: publish one `/datum/notice/transformed` per rule that fired (deduped per settle, as `post_reaction` and
   `effect_reactions` are today), run the effect parts, and publish the subject's contents-changed key once.

### 5.4 Bulk and Rust evaluation

* **Chemistry.** Step maths is already Rust. The next move, which `reagents.md` §4 already names, is the closed-form fixed point for a *plain*
  rule: for geometric progress `limit_k = L(1 - r)^k` with the `floor` completion, the final state after the loop is computable in one call,
  so a plain holder settles in one FFI crossing instead of a hundred. The `plain` flag in the flyweight is exactly the eligibility test
  ("no `can_happen`/`on_reaction` override", in `reagents.md`'s words). Parity: the closed form must reproduce the loop's end state to the
  float; the end-state pin of section 12 decides. If it cannot, the loop stays and the saving is not taken.
* **Gas.** The registry the native gate reads is built from DM at boot today (`min_requirements`, `priority`, `id`; the comment in
  `reactions.dm:4` describes the old auxmos route that dropped duplicate priorities). Declaring `takes`/`catalysts`/`when` as data makes that
  registry a *generated product of the declaration*: `analyze gen` writes a flat table (dense index from the rule's id, priority band and
  order, min and max temperature, `(gas index, min moles)` pairs, an energy-kind index and flags) to `code/engine/_generated/`, and a boot
  call hands it to the existing registry bind, as `update_reactions` does now. There is **no build-time Rust input**, so the verdigris
  DLL cache key (`AGENTS.md` §4) is unaffected. Three staged consequences:
  1. *Data only.* Requirements, priority and the seventeen linear enthalpies come from the declaration; Rust's `released()` reads the table
     for those and keeps a small named-law enum for the five irregular kinds. DM still computes extent and deltas through a pure callback
     `extent = PROC_REF(plasmafire_step)` that returns `list(extent, deltas, aux)`; the callback no longer calls `gas_react()` or touches the
     turf, because the framework does, then runs the declared effects (hotspot, radiation, results). The DM requirement loop is replaced by
     the native `all_ready` ids (a candidate to measure: today's DM loop re-reads the mixture after each fired reaction and the gate's list is
     a snapshot, so the pin must include multi-reaction cells).
  2. *Named laws in Rust.* For the reactions a profile shows hot (fires, nitrous decomposition, water vapor are the likely few), the step
     function is ported to a `GasLaw` variant selected by `extent = law(LAW_PLASMA_FIRE)`; the cell then settles entirely in Rust and returns
     a fired bitmask and extents for DM to publish. The 22 DM bodies are 400 to 600 lines of branching arithmetic; each port is pinned by the
     existing golden table, extended (section 12).
  3. *No expression language.* Laws are code, not data. A mini language for rate formulas would be a second implementation of every
     reaction in an interpreter nobody tests; D6 recommends against it.

## 6. Effects

The rule base class carries side effects today (`on_reaction`, `post_reaction`, the contract event, the log). The proposal splits them:

1. **The engine publishes one typed notice**, `/datum/notice/transformed` (pooled, `notice_wanted()` gates it so an unobserved rule costs one
   check), with `rule`, `subject`, `extent`, and the took/made term lists. A rule may name a subtype with extra fields
   (`notice = /datum/notice/transformed/mix`). Anyone who needs to react does `on_notice(/datum/notice/transformed, ...)`.
2. **Stock effect parts** cover the common tail so it needs no proc: `says(text, range)` (chemistry's `mix_message`, once per settle),
   `plays(SFX)` (`reaction_sound`), `spawns(type, n, at)`, `explodes(...)`, `irradiates(power)`, `ignites()`, and for gas `hotspot()`. They run
   after the fixed point.
3. **Audit and observability move onto listeners, not away.** The contract event (`CONTRACT_EVENT_CHEMISTRY_RESULT`), the admin message for
   `log_is_important` and the chemistry log become listeners on the notice, registered by the systems that own them; a unit test asserts a
   reaction marked important still messages and still logs. Nothing in the debug path is removed (AGENTS.md §3e).
4. **A counted tail keeps `then(PROC_REF(x))`** for the bespoke (promethean revival, blob reconstitution, supermatter's special). The
   `on_reaction` override count (134 today) becomes a ratchet that only falls. `send_data` (43 sites) becomes `data = PROC_REF(x)`, a pure
   function of the settle (it reads, never writes).

Effects never sleep and never refuse; a settle cannot be vetoed by a message. A rule that "fails" is simply not matched.

## 7. What stays domain-specific

| Stays | Why |
|---|---|
| Gas rate laws (until ported as named laws) | variable stoichiometry (`plasmafire` makes tritium or carbon dioxide and water by oxygen ratio) is code, not a table |
| The five irregular energy laws | not `coefficient * extent` |
| Fusion's random pair picking and its energy pool | the extent is a per-cycle random split over a pool; the table lookup and the numbers are declared, the loop is the field's |
| Metabolism | continuous per-cycle dose on the body clock with organ clearance; it consumes a reagent but its outputs are body stats (`reagents.md` §3). It shares the *rate* vocabulary, not the entry |
| Material-batch recalculation | `recalculate()` derives properties from composition and history; the process conditions and deltas can be declared (mutation kind), the recomputation is the domain |
| Construction ladders | staged, undoable and refundable (doc §12); a one-step stack recipe is not one |
| Lathe designs (1,364) | a catalogue with research gating, categories and build time; they select, they do not match. They share the term vocabulary for costs and nothing else in v1 |
| Xenoarch triggers | a per-instance random stimulus table, not a static rule |
| Heat thresholds (`/datum/rule`) | the *trigger* layer: a crossing with `hold_for`; its data effect `transform = list(RULE_SWAP_TYPE(...))` becomes a reference to a mutation or swap transformation |
| Bodies' temperature and phase mechanics | heat stores and links are the heat domain's (doc §14); a transformation books energy into them, it does not own them |

## 8. Relation to gating and containment

### 8.1 Requirements versus conditions

The doc (§9, ground rule 6) separates a *condition* (a boolean) from a *requirement* (a condition plus a reason, taken by `needs()`). A
transformation uses **conditions only**: the matcher evaluates `when` thousands of times and nobody can be told why a beaker did not react,
and a reason string per negative would be wasted work. That is the same split `when()` and `needs()` already have.

A *chosen* transformation is different: a player is refused, and refusals say why. Two things bridge it without putting reasons in the
matcher:

* `xform_lacks(X, subject, actor)` returns the unmet terms and conditions as a list (`"3 more steel"`, `"too cold"`), computed **only on
  demand**, under the same no-write, no-publish guard as every requirement.
* a library requirement `can_transform(X)` wraps a transformation for an op: `needs(can_transform(X))`. Its boolean view is the matcher's
  test (so it is also a valid `when()`), and its reason is the first entry of `xform_lacks()`. Reads are generated from the transformation's
  terms and conditions, so a pending craft re-checks when the contents change.

So reasons exist in chosen mode and in the recipe UIs and medical book (which want "missing: X"), not in matched mode.

### 8.2 Containment, slots, UNITS, partial amounts

* **Outputs go into slots.** `makes = item(T, n, into = SLOT_X)` places the product in a named slot through the ledger (`move_into`), never
  `new X(container)` plus `contents +=`. The microwave's `new result(container)` in `recipe.make_food()` becomes an insert into the cooking
  container's slot. A stack product is `stack(T, n)`: one ledger entry of `n` units, split and merged by the ledger (containment invariant 4),
  not `n` objects.
* **Capacity.** A product that does not fit must be a decision, not an accident. Slot capacity models include `SLOT_CAPACITY_UNITS`
  (custom `cost()` units) and a reagent holder's volume. `RES_SLOT_CAPACITY` is the adapter: the transformation reserves output capacity
  with its inputs, so a full target refuses *before* anything leaves the source (the stated rule for reagent transfers, doc 16.5).
  `capacity = CAPACITY_TRUNCATE` preserves today's behaviour for chemistry (clamp the product, lose the excess); `CAPACITY_LIMIT_EXTENT`
  caps the extent at what the outputs can hold. D10 recommends parity first, then flipping a family at a time through
  `intended_changes.md`.
* **Partial amounts.** Each medium declares an extent *quantum*: reagents are continuous (floats), gas is moles with `QUANTIZE`, items and
  stacks are integers. A rule's extent is rounded down to the medium's quantum, and a rule with `result_quantity` greater than one (kitchen)
  or `product_mod` (alloys: `max(1, round(total * product_mod))`) says so as a `makes` rounding policy rather than in a proc.
* **Reagents as a fluid store behind the same API** (containment §665): the reagents adapter reserves volume on source and capacity on target
  and commits both, which is the all-or-nothing the bulk path needs.
* **Aggregates** (mass, heat capacity, tags) update through the ledger on every insert and remove, so a transformation does not recompute
  its subject's properties; `energy` books into the subject's heat body (`HEAT_SUBJECT`) or its surroundings (`HEAT_AMBIENT`), through
  `heat_move()` / `gas_react()`, never by writing a temperature.

## 9. Before and after

All "after" blocks are proposed syntax. "Before" blocks are the code on master, trimmed only where noted.

### 9.1 A chemical reaction with a catalyst

```dm
// before: code/modules/reagents/reactions/instant/instant.dm:24
/datum/decl/chemical_reaction/instant/carthatoline
	name = REAGENT_CARTHATOLINE
	id = REAGENT_ID_CARTHATOLINE
	result = REAGENT_ID_CARTHATOLINE
	required_reagents = list(REAGENT_ID_ANTITOXIN = 1, REAGENT_ID_CARBON = 2, REAGENT_ID_PHORON = 0.1)
	catalysts = list(REAGENT_ID_PHORON = 1)
	result_amount = 2
```

```dm
// after: the same rule; defaults are rate = instant, yield = 1, floor = 2, regime = REGIME_INSTANT, capacity = CAPACITY_TRUNCATE
CAPABILITIES(/transformation/chem/carthatoline)
	transformation(
		takes = list(reagent(REAGENT_ID_ANTITOXIN, 1), reagent(REAGENT_ID_CARBON, 2), reagent(REAGENT_ID_PHORON, 0.1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 1)),      // present at 1 or more, of which 0.1 is consumed: kept as written
		makes = list(reagent(REAGENT_ID_CARTHATOLINE, 2)))
```

`name` and `id` come from the type and the first `makes` key (the reverse index and the wiki read them from the flyweight). A distilling rule adds
its window and heat:

```dm
// before: reactions/distilling/distilling.dm:73 (biomass)
/datum/decl/chemical_reaction/distilling/biomass
	result = REAGENT_ID_BIOMASS
	required_reagents = list(REAGENT_ID_BLOOD = 1, REAGENT_ID_SUGAR = 1, REAGENT_ID_PHORON = 0.5)
	result_amount = 6
	temp_shift = -2
TYPE_TABLE(/datum/decl/chemical_reaction/distilling/biomass, distilling_temp_range, list(T20C + 80, T20C + 130))

// after
CAPABILITIES(/transformation/chem/distilling/biomass)
	transformation(regime = REGIME_DISTILLING, rate = half_life(6),
		takes = list(reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHORON, 0.5)),
		makes = list(reagent(REAGENT_ID_BIOMASS, 6)),
		when = temperature_in(T20C + 80, T20C + 130),
		energy = per_extent(-2000), heat_to = HEAT_AMBIENT)     // temp_shift * 1000 J into the room gas, as heat_add() does today
```

### 9.2 A slime rule: the subject check becomes a condition

```dm
// before: xenobio/items/extracts.dm:59 and :89 (grey, spawn)
/datum/decl/chemical_reaction/instant/slime
	var/required = null
/datum/decl/chemical_reaction/instant/slime/can_happen(datum/reagents/holder)
	if(holder.my_atom && istype(holder.my_atom, required))
		var/obj/item/slime_extract/T = holder.my_atom
		if(T.uses > 0) return ..()
	return FALSE
/datum/decl/chemical_reaction/instant/slime/grey_new_slime
	required_reagents = list(REAGENT_ID_PHORON = 5)
	required = /obj/item/slime_extract/grey
/datum/decl/chemical_reaction/instant/slime/grey_new_slime/on_reaction(datum/reagents/holder)
	holder.my_atom.visible_message(span_warning("Infused with phoron, ..."))
	new /mob/living/simple_mob/slime/xenobio(get_turf(holder.my_atom))
	..()                                                       // uses--, goes inert

// after: the base gives every slime rule its condition and its bookkeeping once
CAPABILITIES(/transformation/chem/slime)
	transformation(when = all_of(PROC_REF(extract_has_uses)), then = PROC_REF(spend_extract_use))

CAPABILITIES(/transformation/chem/slime/grey_new_slime)
	configure(transformation(
		takes = list(reagent(REAGENT_ID_PHORON, 5)),
		when = subject_is(/obj/item/slime_extract/grey),
		says = MSG(slime/grey_spawn), spawns = spawns(/mob/living/simple_mob/slime/xenobio, 1, at = SUBJECT_TURF)))
```

`subject_is()` is an index key, so a slime rule is a candidate only in a slime extract's holder instead of in every beaker that holds
phoron. The 123 slime rules shrink to a base plus a declaration each, and the bespoke ones (secret slime, sepia) keep a `then()`.

### 9.3 A gas reaction

```dm
// before: reactions.dm:217-289 (plasmafire), trimmed (the body is 60 lines of arithmetic)
/datum/gas_reaction/plasmafire
	priority_group = PRIORITY_FIRE
	name = "Plasma Combustion"
	id = "plasmafire"
	expands_hotspot = TRUE
/datum/gas_reaction/plasmafire/init_reqs()
	requirements = list(/datum/gas/plasma = MINIMUM_MOLE_COUNT, /datum/gas/oxygen = MINIMUM_MOLE_COUNT, "MIN_TEMP" = PLASMA_MINIMUM_BURN_TEMPERATURE)
/datum/gas_reaction/plasmafire/react(datum/gas_mixture/air, datum/holder)
	... temperature_scale, oxygen_burn_ratio, plasma_burn_rate, super_saturation ...
	gas_react(air, GAS_REACTION_PLASMA_FIRE, plasma_burn_rate, deltas)       // Rust: applies deltas, books FIRE_PLASMA_ENERGY_RELEASED * extent
	SET_REACTION_RESULTS(...)
	location.hotspot_expose(temperature, CELL_VOLUME)                         // side effect inside the reaction
	. |= REACTING | VOLATILE_REACTION
```

```dm
// after (stage 1: data from the declaration, extent a pure DM callback)
CAPABILITIES(/transformation/gas/plasma_fire)
	transformation(medium = MEDIUM_GAS, priority = PRIORITY_FIRE,
		takes = list(gas(GAS_PLASMA, MINIMUM_MOLE_COUNT), gas(GAS_OXYGEN, MINIMUM_MOLE_COUNT)),   // minimums; amounts consumed come from the callback's deltas
		when = temperature_in(PLASMA_MINIMUM_BURN_TEMPERATURE, null),
		extent = PROC_REF(plasma_fire_step),          // pure: returns list(extent, deltas, aux); no gas_react(), no turf access
		energy = per_extent(FIRE_PLASMA_ENERGY_RELEASED),
		effects = list(hotspot(), results(), expands_hotspot()))

// the callback keeps the arithmetic and loses the side effects
/proc/plasma_fire_step(datum/act/A) ...
```

Stage 2 replaces `extent = PROC_REF(plasma_fire_step)` with `extent = law(LAW_PLASMA_FIRE)`: the same arithmetic in `GasLaw::PlasmaFire`, evaluated
inside the cell's native settle. The declaration, requirements, enthalpy, priority and effects do not change between stages, which is the
point: the declaration is the stable contract and the evaluator moves behind it. The constants `FIRE_PLASMA_ENERGY_RELEASED` and 16 others
stop being Rust constants exported to DM; they are declared once, and the Rust test fixture builds its table through the same registry call.

### 9.4 A kitchen recipe

```dm
// before: recipes_microwave.dm (boiled egg) and recipe.dm's select_recipe()/make_food()
/datum/recipe/boiledegg
	reagents = list(REAGENT_ID_WATER = 5)
	reagent_mix = RECIPE_REAGENT_REPLACE
	items = list(/obj/item/reagent_containers/food/snacks/egg)
	result = /obj/item/reagent_containers/food/snacks/boiledegg
	// appliance defaults to MICROWAVE; time = 100; contents must hold exactly water, items non-exact

// after
CAPABILITIES(/transformation/kitchen/boiled_egg)
	transformation(medium = MEDIUM_CONTENTS, regime = REGIME_COOKING, rate = cook_time(10 SECONDS),
		takes = list(reagent(REAGENT_ID_WATER, 5), item(/obj/item/reagent_containers/food/snacks/egg, 1)),
		exclusive = list(CURRENCY_REAGENT),                       // any other reagent present blocks it, as check_reagents() does
		when = appliance(APPLIANCE_MICROWAVE),
		makes = list(item(/obj/item/reagent_containers/food/snacks/boiledegg, 1, into = SLOT_COOK_OUTPUT)),
		reagent_mix = MIX_REPLACE)
```

Selection becomes the matcher's policy: priority band, then specificity (term count), with the legacy "last wins on a tie" frozen as the
stamped `order` for converted rules. The three appliance lists in `GLOB.available_recipes` become `regime` buckets.

### 9.5 An alloy

```dm
// before: mining/alloys.dm, and the loop at machine_processing.dm:329 that depends on file order
/datum/alloy/bronze
	metaltag = MAT_BRONZE
	requires = list(ORE_COPPER = 2, ORE_TIN = 1)
	product = /obj/item/stack/material/bronze

// after
CAPABILITIES(/transformation/smelting/bronze)
	transformation(medium = MEDIUM_ORE_STOCK, regime = REGIME_SMELTING,
		takes = list(ore(ORE_COPPER, 2), ore(ORE_TIN, 1)),
		when = ore_setting(PROCESS_ALLOY),                         // every taken ore must be set to alloy, as the loop checks
		makes = list(stack(/obj/item/stack/material/bronze, 1)), output_scale = 1)
```

`durasteel` (diamond 1, platinum 1, carbon 2, hematite 2, `product_mod` 0.3) and `plasteel` (platinum 1, carbon 2, hematite 2) overlap with
`steel` (carbon 1, hematite 1). Specificity ranks durasteel above plasteel above steel without the ordering comment, and the build's shadow
check proves none is unreachable.

### 9.6 Mutation, briefly

```dm
// before: material_batch.dm:134 (cast), one of seven switch arms
if(MATERIAL_PROCESS_CAST)
	if(phase != MATERIAL_PHASE_MOLTEN) return FALSE
	phase = MATERIAL_PHASE_SOLID
	bring_to_temperature(T20C + 80, HEAT_SOURCE_MATERIAL)
	grain_size = 72 ...

// after (wave 6, optional)
CAPABILITIES(/transformation/material/cast)
	transformation(kind = XF_MUTATE, medium = MEDIUM_BATCH,
		when = batch_phase(MATERIAL_PHASE_MOLTEN),
		sets = list(nameof(phase) = MATERIAL_PHASE_SOLID, nameof(grain_size) = 72, nameof(internal_stress) = 28, nameof(solution_treated) = FALSE),
		adds = list(nameof(porosity) = 8),
		energy = to_temperature(T20C + 80), heat_to = HEAT_SUBJECT)
```

## 10. Migration waves

Each wave converts its callers in the same commit that switches on a hard ban of the legacy form (baseline empty), per AGENTS.md §3b. Counts are
from section 2. A wave's files move to the new tree only when fully migrated (§3c); the targets below are `code/library/transformations/`
for the framework and `code/content/<domain>/` for rules, one type per file where a family permits.

| Wave | Content | Counts | Legacy form banned at the end |
|---|---|---|---|
| **W0** engine and harness | `transformation()` kind, `/datum/xform`, the term and adapter layer (`RES_GAS`, extent quantum), index, settle loop, `xform_lacks`, `can_transform`, the typed notice, the build checks (duplicate, shadow), the pin harness (section 12) recorded on the legacy code | no rules converted | none yet; the harness lands first so every later wave records before it converts |
| **W1** chemistry | instant, distilling, slime, blob, brain; reagent holder's `handle_reactions()` becomes the settle; the hand-built heat watch goes; the 134 `on_reaction` and 43 `send_data` convert; contract and log listeners | 749 types | `/datum/decl/chemical_reaction` subtypes and its vars (`required_reagents`, `result`, `TYPE_TABLE(..., distilling_temp_range)`); `SSchemistry.chemical_reactions*` lists |
| **W2** gas data | declarations replace `init_reqs()` and `priority_group`; the generated registry replaces the DM-built one; enthalpy table from the declaration for the 17 linear kinds; callbacks pure; DM requirement loop replaced by the gate's ready ids if the pin allows | 23 types, 22 kinds | `/datum/gas_reaction` subtypes, `init_reqs`, `build_min_requirements`, `GAS_REACTION_*` energy-kind defines as hand-numbered constants |
| **W3** kitchen, alloys, grinding | recipes into regimes, `select_recipe()` becomes the matcher's policy, ore loop becomes the matcher, grinder tables become declarations | 344 recipes, 8 alloys, 2 tables | `/datum/recipe` subtypes and `select_recipe`, `/datum/alloy`, `GLOB.sheet_reagents` / `GLOB.ore_reagents` as hand-written tables |
| **W4** gas laws and fusion | named Rust laws for the profiled hot reactions; fusion's table and numbers declared, its field loop unchanged | up to 23 laws, 10 fusion types | `/datum/decl/fusion_reaction` subtypes and `get_fusion_reaction`; the DM step callback for each ported law |
| **W5** chosen mode | stack recipes and crafting recipes as transformations behind the existing `make` op; per-material families (D12) | about 549 stack sites, 53 crafting recipes | `new /datum/stack_recipe(...)` and `/datum/stack_recipe_list`, `/datum/crafting_recipe` subtypes |
| **W6** optional | material-batch processes as mutations; heat rules' type swaps as swap transformations | 7 processes, the data-effect rules among the 38 | `apply_process`'s switch arms once each has a declaration |

Order is chosen so the largest set with the best existing pins (chemistry) goes first, gas data second (the pins exist and the boundary
work is the most contested), and the chosen-mode forms last because they need the family design (D12) and have the weakest pins.

## 11. Decisions

**D1. The name.** Options: (a) `transformation` / `/transformation/...`; (b) `recipe`; (c) `conversion`; (d) keep `reaction`.
(b) clashes with three existing `recipe` types and `select_recipe`; (d) clashes with `reactions.md`'s event triggers.
**Recommend (a).** `conversion` is acceptable if `transformation` reads too long; do not reuse `reaction`.

**D2. One entry kind or one per system.** Options: (a) one `transformation()` entry, terms as typed constructors; (b) `chem_reaction()`,
`gas_reaction()`, `recipe()` each with its own parameters; (c) (a) plus per-medium sugar. **Recommend (a).** (b) rebuilds today's nine
vocabularies; (c) can follow if a call site reads badly after W1.

**D3. Where gas numbers live.** Options: (a) Rust stays the source (today: `@dm-define` constants exported to DM); (b) the DM declaration
is the source and registers the table at boot; (c) a neutral data file read by the generator and by `build.rs`. **Recommend (b).** It is
what the registry already does for requirements, adds no build-time Rust input (the DLL cache key is untouched), and gives one source for
each number. Rust keeps a test fixture that builds the table through the same registration call. (c) would be data outside DM and a new
build coupling.

**D4. When a medium settles.** Options: (a) always inline at write; (b) always drained and coalesced; (c) declared per medium.
**Recommend (c)**, as the table in 5.2: inline at the end of the outermost write for instant reagent chemistry (callers read the product
right away), drained for timed rules, the existing event for gas. (a) reintroduces the per-write scan; (b) breaks every caller that reads
a product after `add_reagent()`.

**D5. Ordering between overlapping rules.** Options: (a) preserve today's accidental order forever; (b) explicit `priority` bands plus
specificity within a band; (c) specificity only. **Recommend (b), with a transition:** converted rules carry a stamped `order` equal to
their legacy position so wave outcomes are unchanged, the pin proves it, and new rules may not depend on declaration order. Gas keeps its
bands (`PRIORITY_FIRE` and friends) as named priorities.

**D6. How far a step goes.** Options: (a) data only (a closed set of parametric laws); (b) a pure DM callback; (c) named Rust laws;
(d) an expression language. **Recommend data for chemistry, kitchen and alloys; (b) for gas in W2; (c) for the profiled few in W4; no (d).**
A rate-law interpreter is a second implementation of 23 reactions that would need its own test suite.

**D7. Effects.** Options: (a) notice only; (b) stock parts plus `then(PROC_REF)`; (c) keep `on_reaction`. **Recommend (b)**: typed notice always,
stock parts for the common tail, `then()` allowed on the declaring type and counted by a ratchet. (a) would force every spawn and explosion
into a listener far from its rule; (c) keeps the side-effect procs this design exists to remove.

**D8. Scope.** In: chemistry (all four families), gas, fusion (declarations), kitchen, alloys, grinding, stack and crafting (chosen mode).
Optional: material-batch mutations, heat-rule swaps. Out: metabolism, lathe designs, xenoarch triggers, construction ladders. **Recommend
exactly this.** Lathe designs are 1,364 declarations with no matching problem to solve; converting them is churn. Revisit after W5 if the
term vocabulary lets the lathe UI share a cost renderer.

**D9. Matched versus chosen.** Options: (a) one declaration form, a matcher only for matched rules; (b) two forms. **Recommend (a).** Chosen
rules reuse `takes`, `makes`, `when` and the diagnosis; they skip the index. It keeps a stack recipe and a kitchen recipe the same kind of
thing, so a crafting menu can offer a matched recipe's contents as a checklist.

**D10. A full output container.** Options: (a) truncate the product as today; (b) limit the extent to what fits; (c) refuse the step.
**Recommend (a) for every converted family in its wave, then (b) per family, recorded in `intended_changes.md`.** It is a real behaviour
change (matter conservation) and must not ride in with a refactor. Items and stacks use (c) from the start, because a refused insert is how
slots already behave.

**D11. Conditions.** Options: (a) reuse the doc's condition language and add library constructors (`temperature_in`, `pressure_in`,
`subject_is`, `appliance`); (b) a transformation-specific predicate syntax. **Recommend (a).** The bounds then double as watch bands.

**D12. Families that differ only by material** (stack recipes are built per material at run time, `material.dm:275`). Options: (a) one
declaration per concrete recipe; (b) a template entry expanded over a registry at compile; (c) leave per-material lists as data and declare
only the non-material recipes. **Recommend (b), reusing the variants registry (`code/datums/variants/README.md`), decided in W5**, not now;
until then stack recipes keep their constructor.

**D13. Reverse index and generated documentation.** Options: (a) keep the product-keyed lists hand-fed; (b) the compile builds them and
the wiki, `recipe_dump.dm` and the handbooks read the flyweight; the requirement lines of `reaction_factors.dm` are generated. **Recommend
(b).** The hand-written `init_factors()` prose repeats numbers that the declaration holds; generated text cannot drift. The explanatory
prose for variable laws stays hand-written.

**D14. Boot cost.** Options: (a) compile every transformation at world setup, as `STATIC_ENTRY` does; (b) keep chemistry's lazy build
(`SYSTEM_DEF(chemistry)` builds on first use and is deliberately outside the boot DAG). **Recommend (a) after a measurement:**
`startup_profile_1013.md` is the baseline; if 749 + 344 flyweights add more than the boot gate allows, compile a medium's table on first
use inside the static-entries system (a `lazy` flag on the kind, still read-only after build) rather than a second mechanism.

## 12. Pins

Existing pins and their gaps:

| Existing | Covers | Does not cover |
|---|---|---|
| `dq_chem_reaction_progress_pin` | per-step progress for every chemistry rule at four scales, with and without product | the end state of a settle (the loop), ordering, side effects |
| `dq_chem_metabolism_pin` | a human's cycle | out of scope here |
| `chemical_reactions_shall_not_conflict` | no two rules interfere on their own fixtures | which rule wins on a mixed fixture |
| `chemical_reactions_shall_use_and_produce_valid_reagents` | ids exist | amounts |
| `dq_gas_reaction_energy_pins` | per reaction, one step on a built mixture: temperature and total moles | per-gas deltas, multi-reaction cells, flags |
| `recipe_test` | a result path exists | which recipe is selected |
| `dq_material_science_tests` | slots, design cost, feedstock | process outcomes |
| none | alloys, stack recipes, crafting, slime outcomes, fusion | everything |

New, recorded **on the legacy code first** (the `dq_pin.sh` routine: empty files, one recording run, commit, convert, compare, bless only an
intended change):

1. **`dq_xform_outcome_pin`** per family under `snapshots/xform/<family>.txt`. For each rule, a generated canonical subject (each input at
   four times its minimum, as `gas_reaction_test_mixture()` does; catalysts present; the subject type the rule's `when` names) is settled;
   a row records the rules that fired *in order*, each remaining and produced amount, the energy booked and the notices published. Chemistry
   rows include the end state of the fixed point, which closes the `progress` pin's gap and is the oracle for the closed-form fixed point.
2. **`dq_xform_overlap_pin`**: for every pair of rules in one bucket whose `takes` overlap, a fixture holding the union; the row records the
   winner and the leftovers. This is the pin that proves ordering is unchanged by W1 to W3 and is regenerated, not blessed blindly, by the
   re-anchoring pass.
3. **`dq_xform_select_pin`** for kitchen and alloys: each recipe's exact contents select itself; each recipe's contents plus one extra item
   (and plus one extra reagent) select the recorded rule or none; each alloy fixture yields the recorded sheets.
4. **`dq_gas_cell_pin`**: extends the energy pin to per-gas deltas, the fired list in priority order and the returned flags, on a set of
   multi-reaction mixtures. It guards stage 2 (named laws) and the use of the gate's ready ids.
5. **Randomised families** (fusion, any rule with `prob()`): seeded with `rand_seed()` so the row is reproducible; the pin records the seed.
6. **Debug-path test**: a rule marked important still messages admins and logs; a produced reagent still emits its contract event.
7. **Build checks** (not pins): duplicate signature, shadowed rule, a `takes` key with no provider, a `then` count that rises.

Rows key on what is observable (rule id, amounts, fired order), not on type paths, so a faithful conversion keeps them. The harness lives in W0
so no later wave converts before its pin exists.

## 13. Risks

* **Balance parity.** Chemistry's step maths is `f32` in DM's order (the Rust port was built to reproduce it). A closed-form fixed point, a
  re-anchored index or a changed iteration order can shift a product by a float or by a whole step. Mitigation: no re-anchoring and no
  closed form until the end-state and overlap pins are green on the straight conversion; each is its own pinned commit.
* **Ordering and priority.** The bucket order was never declared, so some real recipe may depend on it. The overlap pin finds those; each one
  needs a declared `priority` and a line in `intended_changes.md` if the winner changes.
* **Inline settle cost.** Making every write settle is today's cost; a depth counter reduces bursts to one settle, but a pathological holder
  (many reagents, many candidates) could still be slow. Measure `handle_reactions()` call counts and time under the existing benchmark
  scenarios before and after; this proposal has no such number yet.
* **RNG.** Fusion and several `on_reaction` tails call `rand`/`prob`/`pick`. Moving them behind notices or `then()` must not change the call
  order, or seeded rounds diverge. The seeded pin records it.
* **Boot cost and memory.** Static compilation moves chemistry's lazy build to setup (D14). The flyweights replace the decl instances one for
  one, so memory should be flat or better; unmeasured.
* **Gas gate snapshot versus loop.** Replacing the DM requirement loop with the gate's `all_ready` ids changes a re-read-after-each-reaction
  into a snapshot. If any pair of reactions depends on the first's output, the cell pin catches it; if not, the saving is real.
* **Slime fan-out.** `subject_is()` as an index key changes which rules are candidates in a beaker (fewer). That is intended and invisible
  unless a slime rule depended on firing outside an extract; the overlap pin checks it.
* **Debug and audit loss.** Moving `on_reaction`, the log and the contract event onto listeners can silently drop one if the listener is not
  registered. The debug-path test is the guard; the commit that moves each names where it went (AGENTS.md §3e).
* **Per-material stack recipes** (D12) can multiply declarations if done naively; deferring the decision to W5 keeps W1 to W4 unaffected.
* **Scope creep.** Lathe designs and metabolism look like the same shape and are not worth moving; D8 is a decision so it stays one.

## 14. Not verified here

* Perf numbers for every system above (nothing was run).
* That `handle_reactions()` truly runs a half-life rule to completion inside one call for every real rule (read from the code at
  `holder.dm:142` and `_reactions.dm`, not exercised).
* The exact count of stack and crafting declarations (a `grep` count of constructor sites; some are generated per material at run time).
* Whether the gas gate's `min_energy` and `min_fire` requirement fields are populated by any DM reaction today (the DM `requirements` list
  names only gases and temperatures).
* How `GLOB.sheet_reagents` and `GLOB.ore_reagents` are populated (their entry counts were not taken).

## 15. Implementation notes (waves 0 and 1)

Where the code differs from the syntax this proposal sketched, and why. The decisions D1 to D14 are unchanged.

* **`holds`, not `when`.** The condition argument of `transformation()` is `holds = ...`. The handler lints read every `when` as an op condition
  (`x(datum/act/A)`), and a transformation has no act. Conditions are `temperature_in()`, `pressure_in()`, `ambient_gas_over()`,
  `ambient_gas_under()`, `subject_is()`, `appliance()` and the combinators `xform_all()`, `xform_any()`, `xform_not()`; `all_of()` and `any_of()` already mean
  the op requirements. A subtype's `holds` is ANDed over the one it inherits (the proposal's slime example would otherwise have replaced the base's).
* **Terms.** `reagent()` and `gas()` as proposed; `item_term()`, `stack_term()`, `ore_term()` and `fruit_term()` because `item()` and `stack()` are the op input parts.
* **Procs in a static block.** A static block is read in a global proc, so `PROC_REF(x)` has no type to resolve against: a tail, a data proc or a proc condition is
  `TYPE_PROC_REF(/the/rule/type, x)`. The compile keeps the name and calls it on the rule's one owner instance, so an override in a subtype answers for itself.
  A reagent rule's tail is called as `x(holder, made)` and its data as `x(holder, extent)`: the shapes of the old `on_reaction()` and `send_data()`.
* **Energy.** `energy = per_step(joules)`, booked once per step (chemistry's `temp_shift` was a flat amount per step, not per extent), into the air around the
  subject (`XFORM_HEAT_AIR`, the default) or its own heat body (`XFORM_HEAT_SUBJECT`). `HEAT_AMBIENT` already names the heat-rejection loop, so it is not reused.
* **Ambient gas.** `takes_ambient = list(gas(id, moles))` is the gas a step takes from the air around the subject (distilling's `consumes_xgm_gas`).
* **`made`, `wiki`, `important`.** `made = n` is what the tail is told was made when a rule has no product term (a rule that spawns things); `wiki` carries the
  WIKI_X flags; `important` is the old `log_is_important`.
* **Index.** A rule is indexed under its first take only (as before), so each bucket holds the same rules in the same order. `subject_is()` is a pre-filter in the
  matcher rather than an index key; the order a bucket is walked in is unchanged, so the overlap pin holds.
* **Order.** `order` is the rule type's place in `subtypesof(/transformation)`; converted files keep their declaration order, so it equals the legacy order. A type's path
  below `/transformation/chem/` is the same as its path below `/datum/decl/chemical_reaction/` was, which is what the pins key on.
* **Outputs.** Reagent products truncate to the free volume (`CAPACITY_TRUNCATE`, the only capacity built). Item and stack products go through
  `xform_prepare_item()` (made in nullspace and checked against the destination slot before anything is spent) and `xform_commit_item()` (the ledger's `move_into()`);
  a slot that refuses refuses the step. The one quantity-insertion form belongs to the admission lane; this layer does not build its own.
* **`log_chemical_reaction()` has no caller.** The proposal's section 6 moves the chemistry log onto a listener of `/datum/notice/transformed`; on master nothing
  calls it, so mixing an important reaction has never messaged admins. The log proc is kept and takes a rule; no listener is registered, so behaviour is unchanged.
  The contract event is still emitted by the settle, and the pins count it.
* **Boot cost (D14).** `xform_build()` logs how long the compile took (`Transformations compiled: n rule(s) in s`).
* **Wave 3, alloys.** The eight alloys are `/transformation/smelting/*` (`code/modules/mining/alloys.dm`), `medium = MEDIUM_ORE_STOCK`, `regime = REGIME_SMELTING`,
  `id` the material made. The processor (`machine_processing.dm`) walks `xform_rules_in()` with the legacy loop unchanged (every taken ore set to alloy, once per
  alloy per tick); no generic ore settle was built, since one caller has it. `product_mod` became the sheet count written out. `/datum/alloy` and `alloy_data`
  are hard-banned.
* **Wave 3, kitchen.** The 355 `/datum/recipe` types are `/transformation/kitchen/*` (`recipes_{microwave,oven,fryer,grill}.dm`, `superfoods.dm`, the splat recipe in
  `kitchen/microwave.dm`), `medium = MEDIUM_CONTENTS`, `regime = REGIME_COOKING`: `takes` are `reagent()`, `item_term()` (one per item, duplicates kept) and `fruit_term()`,
  `makes` one `item_term(result, quantity)`, and the entry gains `cooks_in` (the appliance bitfield), `cook_time`, `mix` (the `RECIPE_REAGENT_*` modes) and `coating`.
  `code/library/transformations/kitchen.dm` holds the policy: `cooking_select(appliancetype, container, exact)` is `select_recipe()` (the same checks, the most terms wins,
  a tie goes to the later rule, rules in declaration order), `/datum/xform/proc/cook()` is `make_food()`, and `cooking_rules_for(appliancetype)` replaces
  `GLOB.available_recipes[appliancetype]`. The four recipes that override `make_food` (donkpocket, donkpocket/warm, amanitajelly, validsalad) and the splat recipe's
  `before_cook`/`make_food` are procs on their rule type, called on the owner instance. `before_cook`/`after_cook` keep their (single) callers as they were: nothing calls
  `before_cook`. The acceptable item and reagent lists became lazy procs (`kitchen_acceptable_items()`), since the rules compile at setup, after the global lists
  initialize. `dq_xform_select_pin` (recorded on the legacy recipes, unchanged through the conversion) pins selection and the recipe facts; `dq_xform_cooking_make` pins what
  is made. `/datum/recipe`, `select_recipe`, `available_recipes` and the `build_kitchen_*` procs are hard-banned. Recipe type paths are now
  `/transformation/kitchen/*`, which the microwave UI's class names and the wiki keys follow.

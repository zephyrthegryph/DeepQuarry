// Transformations (doc/rewrite/proposals/transformations.md): one declared rule form for "inputs under conditions become outputs".
// The entry constructor is transformation() (code/library/transformations/transformation_entry.dm); a rule is a type under /transformation
// with that entry in its CAPABILITIES block, compiled once at world setup into a /datum/xform and indexed by input key.

/// Entry kinds. A term (reagent(), gas(), ...) and a condition (temperature_in(), subject_is(), ...) are interned entries nested in a transformation()'s arguments.
#define ENTRY_TRANSFORMATION "transformation"
#define ENTRY_XTERM "xterm"
#define ENTRY_XCOND "xcond"
#define ENTRY_XCHOSEN "xchosen"
#define ENTRY_XCRAFTED "xcrafted"

/// Currencies: what a term counts. Each names the resource a subject's medium keeps it in.
#define XCUR_REAGENT "reagent"
#define XCUR_GAS "gas"
#define XCUR_ITEM "item"
#define XCUR_STACK "stack"
#define XCUR_ORE "ore"
#define XCUR_FRUIT "fruit"

/// Media: how a subject stores the terms. Inferred from the currencies of `takes` when a rule does not name one.
#define MEDIUM_REAGENTS "reagents"
#define MEDIUM_GAS "gas"
#define MEDIUM_CONTENTS "contents"
#define MEDIUM_ORE_STOCK "ore_stock"
#define MEDIUM_BATCH "batch"
#define MEDIUM_FIELD "field"

/// Regimes: which holders run a rule. A holder declares the regime it runs (/datum/reagents/proc/xform_regime()).
#define REGIME_INSTANT "instant"
#define REGIME_DISTILLING "distilling"
#define REGIME_COOKING "cooking"
#define REGIME_SMELTING "smelting"
#define REGIME_GAS "gas"
#define REGIME_GRINDING "grinding"
#define REGIME_FUSION "fusion"
#define REGIME_CHOSEN "chosen"
#define REGIME_CRAFTING "crafting"

/// What happens to a product that does not fit its container. CAPACITY_TRUNCATE keeps today's chemistry: the product is clamped to the free volume and the
/// excess is lost (D10). Items and stacks never truncate: a refused insert is how slots already behave.
#define CAPACITY_TRUNCATE "truncate"
#define CAPACITY_LIMIT_EXTENT "limit_extent"

/// Where a transformation's energy goes: into the subject's own heat body, or into the air around the subject (heat_add() on return_air()).
#define XFORM_HEAT_SUBJECT "subject"
#define XFORM_HEAT_AIR "air"

/// The heat source a transformation's energy is booked under (code/domains/heat).
#define XFORM_HEAT_SOURCE HEAT_SOURCE_DEVICE

/// The rate of a rule that completes in one step (the fraction of the limit one step goes). half_life() and rate() are in transformation_entry.dm.
#define RATE_INSTANT 1.0

/// Most settle passes one settle may make before it stops and logs (a fixed point that never settles is a bug in a rule set).
#define XFORM_MAX_PASSES 20000

// Gas condensing (code/content/reagents/reactions/distilling/gas_condensing.dm): moles of the gas a step takes, units of the product it makes, the heat it
// books (kelvin-ish units, times 1000 joules) and the coolant it uses. Here because the generated declarations name them before that file is read.
#define CONDENSING_RATE 50
#define CONDENSING_RESULT 0.5
#define CONDENSING_HEAT 2
#define COOLANT_CONSUMPTION_RATE 0.01

// Stack recipes (code/library/transformations/stack_recipes.dm)
/// The cost term of a stack recipe: units of the stack the recipe is made from.
#define STACK_SELF "self"
/// In `material` and `recycle`: the material of the stack. Title text uses {display_name} and {name}.
#define STACK_MATERIAL_SELF "{name}"

/// The keys of the stack recipe lists a stack asks stack_own_recipes() for (code/game/objects/items/stacks/own_recipes.dm).
#define STACK_RECIPES_SANDBAGS "sandbags"
#define STACK_RECIPES_WAX "wax"
#define STACK_RECIPES_RODS "rods"
#define STACK_RECIPES_STEEL_RECYCLER "steel_recycler"
#define STACK_RECIPES_GLASS_RECYCLER "glass_recycler"

// sets_off(): the stock effect a reagent step sets off (code/library/transformations/transformation_effects.dm).
/// Chemical smoke at the subject, carrying the reagents.
#define XFORM_FX_SMOKE "smoke"
/// Foam (variant 0 plain, 1 metal, 2 iron) at the subject.
#define XFORM_FX_FOAM "foam"
/// An explosion of reagents scaled by what the step made.
#define XFORM_FX_EXPLOSION "explosion"
/// An electromagnetic pulse scaled by what the step made.
#define XFORM_FX_EMP "emp"

/// A plain explosion with rolled ranges (blast = list(devastation, heavy, light, flash), each a number or list(lo, hi)).
#define XFORM_FX_BLAST "blast"
/// A frost smoke cloud of `amount` at the subject.
#define XFORM_FX_FROST "frost"
/// A procedure on the subject, `delay` later, after an optional admin line, message and sound.
#define XFORM_FX_LATER "later"
/// A lightning strike on the subject's turf (delay, audit, tell, sfx as for XFORM_FX_LATER).
#define XFORM_FX_LIGHTNING "lightning"
/// A radiation pulse from the subject: range and strength (delay, audit, tell, sfx as above).
#define XFORM_FX_RADIATION "radiation"
/// A gravity effect around the subject: direction GRAVITY_PULL (the grav_pull system draws movable things in) or GRAVITY_PUSH (they are thrown away).
#define XFORM_FX_GRAVITY "gravity"
#define GRAVITY_PULL "pull"
#define GRAVITY_PUSH "push"
/// Gas added to turfs around the subject with a hotspot (gases, temperature, hotspot, range, line_of_sight, floors_only, scale_by_made, consumes).
#define XFORM_FX_BURN "burn"
/// A mood put on the slimes (and slime-bodied people) the subject can see: MOOD_CALM or MOOD_ENRAGE.
#define XFORM_FX_MOOD "mood"
#define MOOD_CALM "calm"
#define MOOD_ENRAGE "enrage"
/// An edit of the engineered contagion in the blood the subject holds: CONTAGION_EVOLVE (levels), CONTAGION_PICKY (symptoms), CONTAGION_DEVOLVE, CONTAGION_NEUTER, CONTAGION_FALTER.
#define XFORM_FX_CONTAGION "contagion"
#define CONTAGION_EVOLVE "evolve"
#define CONTAGION_PICKY "picky"
#define CONTAGION_DEVOLVE "devolve"
#define CONTAGION_NEUTER "neuter"
#define CONTAGION_FALTER "falter"
/// A body effect on every mob within a range of the subject.
#define XFORM_FX_AREA "area"

// spawns(): where a product is made, and how many.
/// At the turf of the subject (the only place built).
#define SUBJECT_TURF "subject_turf"
/// n copies each step the rule goes, whatever its extent (what every legacy tail did).
#define SPAWN_PER_STEP "per_step"
/// n copies per whole unit the step made: n * FLOOR(made).
#define SPAWN_PER_MADE "per_made"
/// One stack of n * FLOOR(made) units (nothing when that is 0).
#define SPAWN_STACK_MADE "stack_made"

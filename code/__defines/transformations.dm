// Transformations (doc/rewrite/proposals/transformations.md): one declared rule form for "inputs under conditions become outputs".
// The entry constructor is transformation() (code/library/transformations/transformation_entry.dm); a rule is a type under /transformation
// with that entry in its CAPABILITIES block, compiled once at world setup into a /datum/xform and indexed by input key.

/// Entry kinds. A term (reagent(), gas(), ...) and a condition (temperature_in(), subject_is(), ...) are interned entries nested in a transformation()'s arguments.
#define ENTRY_TRANSFORMATION "transformation"
#define ENTRY_XTERM "xterm"
#define ENTRY_XCOND "xcond"

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

// Gas condensing (code/modules/reagents/reactions/distilling/gas_condensing.dm): moles of the gas a step takes, units of the product it makes, the heat it
// books (kelvin-ish units, times 1000 joules) and the coolant it uses. Here because the generated declarations name them before that file is read.
#define CONDENSING_RATE 50
#define CONDENSING_RESULT 0.5
#define CONDENSING_HEAT 2
#define COOLANT_CONSUMPTION_RATE 0.01

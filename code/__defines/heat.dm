// The heat domain (doc/rewrite/temperature.md, verdigris/domains/heat).
// HEAT_CELL_*, HEAT_TARGET_* and HEAT_WATCH_* are generated from the Rust into
// code/__defines/verdigris/_bindings.dm.

// Indices of the list thermal_properties() returns.
/// Heat capacity, J/K.
#define THERMAL_CAPACITY 1
/// Conductance to the surroundings, W/K (for a turf: its thermal_conductivity).
#define THERMAL_CONDUCTANCE 2
/// Emissivity of a surface exposed to space, 0..1.
#define THERMAL_EMISSIVITY 3

// The defaults (THERMAL_EMISSIVITY_DEFAULT, THERMAL_CAPACITY_DEFAULT,
// THERMAL_CONDUCTANCE_DEFAULT, THERMAL_CAPACITY_PER_W_CLASS,
// THERMAL_CONDUCTANCE_PER_W_CLASS) and the shared temperatures and heat
// capacities are generated from verdigris/domains/heat/src/consts.rs (H1).

// Wake lanes for heat watches (vg-core outbox lanes).
#define HEAT_LANE_URGENT 0
#define HEAT_LANE_NORMAL 1
#define HEAT_LANE_BACKGROUND 2

// ---- Objects (H3, code/modules/heat/heat_objects.dm) ----
/// Seconds of flame contact one explicit fire_act() exposure stands for.
#define FIRE_EXPOSURE_SECONDS 10
/// Conductance between a flame (or a burning tile's gas) and an item, per size class, W/K.
#define FIRE_CONDUCTANCE_PER_W_CLASS 20
/// The same for objects without a size class (structures, machines), W/K.
#define FIRE_CONDUCTANCE_DEFAULT 60

/// Overheating damage stream: integrity per second per kelvin over the limit, and its bounds.
#define OVERHEAT_DAMAGE_PER_KELVIN 0.01
#define OVERHEAT_DAMAGE_MIN 1
#define OVERHEAT_DAMAGE_MAX 20

/// Food cooks after FOOD_COOKING_TIME at or above this (the cookers' old 80 C minimum).
#define FOOD_COOKING_TEMPERATURE (T0C + 80)
#define FOOD_COOKING_TIME (30 SECONDS)
/// Small-arms propellant cooks off here.
#define AMMO_COOK_OFF_TEMPERATURE (T0C + 180)

// ---- Burning (code/datums/behaviours/burning.dm) ----
/// Heat a burning object releases, W. With BURN_ENERGY_PER_INTEGRITY this is
/// the old flat 10 integrity per second.
#define BURN_POWER 10000
/// Fuel: joules of heat per point of max integrity.
#define BURN_ENERGY_PER_INTEGRITY 1000
/// Oxygen a fire uses per joule released, mol/J (about 450 kJ per mol of O2).
#define BURN_OXYGEN_PER_JOULE (1 / 450000)
/// Below this much oxygen on the tile a burning object goes out, mol.
#define BURN_MIN_OXYGEN_MOLES 0.5
/// A burning object goes out this far below its ignition point, K.
#define BURN_EXTINGUISH_MARGIN 100

// ---- Reagents ----
/// Heat capacity of one unit of a reagent with no specific heat of its own, J/K.
#define REAGENT_SPECIFIC_HEAT_DEFAULT 2
/// Water: J/K per unit, boiling point, and latent heat of vaporisation per unit.
#define REAGENT_SPECIFIC_HEAT_WATER 4.2
#define WATER_BOILING_POINT (T0C + 100)
#define WATER_LATENT_HEAT 19000
/// A bunsen burner's flame, W.
#define BUNSEN_HEAT_POWER 15000
/// Distillery thermostat: watts per kelvin from the target (capped at its power rating).
#define DISTILLERY_THERMOSTAT_GAIN 200
/// Distillery heat exchanger to its port's gas, W/K.
#define DISTILLERY_GAS_CONDUCTANCE 100
/// Why a burning object went out (/obj/var/burn_ended_by).
#define BURN_ENDED_FUEL "fuel"
#define BURN_ENDED_OXYGEN "oxygen"
#define BURN_ENDED_COOLED "cooled"
/// Cookers: seconds per machine process (their heat capacity is resistance x this),
/// the casing's loss to the room (W/K), and the coupling to their contents (W/K).
#define COOKER_SECONDS_PER_PROCESS 2
#define COOKER_CONDUCTANCE 3
#define COOKER_CONTENT_CONDUCTANCE 60
/// A hibernating cooker wakes this far below its optimal temperature, K.
#define COOKER_THERMOSTAT_BAND 5

// Mob reactions to fire exposure (/mob/living/var/fire_reaction).
/// Ignores flame contact.
#define FIRE_REACTION_NONE 0
/// Gains fire stacks and ignites (the default).
#define FIRE_REACTION_BURN 1
/// Ignites without gaining stacks from hotspots (silicons).
#define FIRE_REACTION_IGNITE 2
/// Runs fire_trigger_proc instead of burning (volatile slimes).
#define FIRE_REACTION_TRIGGER 3

// ---- The heat network (code/domains/heat/) ----
/// Outer space as a heat reservoir (heat_move(), the heat entries): infinite, at TCMB.
#define HEAT_SPACE "heat:space"
// Endpoints of a heat entry, besides a var name of the declaring side (nameof(v): a gas mixture or an atom):
/// The activation's holder: the occupant of a while_slotted(..., on = ON_CONTENTS) entry, the machine itself at type level.
#define HEAT_HOLDER "heat:holder"
/// The side that declares the entry: the container of a while_slotted(..., on = ON_CONTENTS) entry, the machine itself at type level.
#define HEAT_DECLARER "heat:declarer"
/// The air around the declaring side (its turf's).
#define HEAT_AIR "heat:air"
/// The solid of the declaring side's turf (the hull a machine rejects heat into).
#define HEAT_HULL "heat:hull"
/// The station's heat-rejection loop as a reservoir: infinite, at 20 °C. What a heat pump with nothing better to reject into (a space
/// heater, a thermoregulator) pumps against, booked in the heat ledger as leaving the simulation.
#define HEAT_AMBIENT "heat:ambient"
/// Port `i` of the declaring pipe machine: the gas of the pipeline the port is in, followed through merges and splits.
#define HEAT_PORT(i) "heat:port:[i]"
/// An infinite reservoir at `kelvin` (the sky a radiator sees).
#define HEAT_SKY(kelvin) "heat:sky:[kelvin]"

/// A heat store's handle as a reservoir for heat_move(), heat_equalize(), heat_conduct() (code/domains/heat/heat_store.dm).
#define HEAT_STORE(h) list(HEAT_TARGET_BODY, h)

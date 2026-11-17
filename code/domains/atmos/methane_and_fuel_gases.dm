// CHOMP-flavor /datum/gas subtypes for LINDA.
//
// LINDA's vendored gas_types.dm doesn't have direct equivalents for some
// CHOMP gases (methane, volatile_fuel). CHOMP code references them by string
// ID ("methane", "volatile_fuel"). To make get_xgm_id_for_gas() find them,
// we add /datum/gas subtypes with the matching IDs.
//
// These are bare-bones — they exist as gas types but don't participate in
// LINDA reactions (which would need /transformation/gas rules). For full
// gameplay parity, methane combustion / volatile_fuel ignition reactions can
// be added when needed.

/datum/gas/methane
	idx = GAS_ID_METHANE
	id = GAS_CH4
	specific_heat = 34	// matches CHOMP /datum/decl/xgm_gas/methane
	name = "Methane"
	rarity = 50
	purchaseable = FALSE
	base_value = 0.05
	desc = "A flammable hydrocarbon gas. Smells faintly of rotten eggs."
	primary_color = "#664422"

/datum/gas/volatile_fuel
	idx = GAS_ID_VOLATILE_FUEL
	id = GAS_VOLATILE_FUEL
	specific_heat = 30
	name = "Volatile Fuel"
	rarity = 10
	purchaseable = FALSE
	base_value = 0.1
	desc = "Vaporized fuel — combustible at low temperatures."
	primary_color = "#ffaa00"

// Chemistry gases (code/domains/world_model/reagents/vapour.dm routes a boiled-off reagent to the gas of its id).

/datum/gas/chlorine
	idx = GAS_ID_CHLORINE
	id = GAS_CHLORINE
	specific_heat = 34
	name = "Chlorine"
	dangerous = TRUE
	gas_overlay = "nitryl"
	moles_visible = MOLES_GAS_VISIBLE
	rarity = 150
	base_value = 1.5
	desc = "A dense yellow-green gas. It burns the lungs and eyes."
	primary_color = "#b5d33d"

/datum/gas/ammonia
	idx = GAS_ID_AMMONIA
	id = GAS_AMMONIA
	specific_heat = 36
	name = "Ammonia"
	rarity = 120
	base_value = 1
	desc = "A pungent colourless gas. It irritates the airway."
	primary_color = "#9fd8ff"

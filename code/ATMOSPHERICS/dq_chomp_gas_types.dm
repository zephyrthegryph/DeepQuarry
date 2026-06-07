// CHOMP-flavor /datum/gas subtypes for LINDA.
//
// LINDA's vendored gas_types.dm doesn't have direct equivalents for some
// CHOMP gases (methane, volatile_fuel). CHOMP code references them by string
// ID ("methane", "volatile_fuel"). To make get_xgm_id_for_gas() find them,
// we add /datum/gas subtypes with the matching IDs.
//
// These are bare-bones — they exist as gas types but don't participate in
// LINDA reactions (which would need /datum/gas_reaction subtypes). For full
// gameplay parity, methane combustion / volatile_fuel ignition reactions can
// be added when needed.

/datum/gas/methane
	id = GAS_CH4
	specific_heat = 34	// matches CHOMP /datum/decl/xgm_gas/methane
	name = "Methane"
	rarity = 50
	purchaseable = FALSE
	base_value = 0.05
	desc = "A flammable hydrocarbon gas. Smells faintly of rotten eggs."
	primary_color = "#664422"

/datum/gas/volatile_fuel
	id = GAS_VOLATILE_FUEL
	specific_heat = 30
	name = "Volatile Fuel"
	rarity = 10
	purchaseable = FALSE
	base_value = 0.1
	desc = "Vaporized fuel — combustible at low temperatures."
	primary_color = "#ffaa00"

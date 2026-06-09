// Raw chemistry resources mined from quarry walls.
//
// Three forms, all dropped by the existing mineral-wall pipeline. The
// generator marks a wall's `mineral` to one of the /datum/ore subtypes
// declared here; when a player mines it, `DropMineral` spawns the item
// the datum's `ore` typepath points to.
//
//   Solid form (sulfur, saltpeter, lithium, copper sulfate):
//     A plain stackable item the player picks up and delivers to the
//     bay. Goal type: deliver_item (count items of a type).
//
//   Liquid form (water ice for v1):
//     A sealed flask containing the reagent. Player can pour it into
//     a beaker; goals count flasks delivered, not reagent units —
//     keeps the goal predictable.
//
//   Gas form (phoron):
//     The pipeline still "drops" an item, but the item is a one-shot
//     vent that releases its gas into the local turf during Initialize
//     and qdels itself. Players capture the gas with a portable atmos
//     tank and deliver the tank to the bay. Goal type: deliver_gas
//     (sum moles of a specific gas across tanks in the bay).


// === ITEMS ===========================================================

/obj/item/raw_chem
	name = "raw chemistry sample"
	desc = "An unprocessed lump of raw chemistry, fresh from the rock."
	icon = 'icons/obj/mining.dmi'
	icon_state = "ore2"
	w_class = ITEMSIZE_SMALL
	randpixel = 8


/obj/item/raw_chem/saltpeter
	name = "saltpeter chunk"
	desc = "A pale, gritty lump of potassium nitrate."
	icon_state = "ore_glass"
	color = "#f4eed5"


/obj/item/raw_chem/lithium
	name = "lithium nodule"
	desc = "A soft, silvery nodule. Stings the tongue if you'd be so unwise."
	icon_state = "ore_silver"
	color = "#bcbfb8"


/obj/item/raw_chem/copper_sulfate
	name = "copper sulfate crystal"
	desc = "Brilliant blue crystals shot through with native copper."
	icon_state = "ore_diamond"
	color = "#1f6bcc"


// --- gas form: vent capsule ------------------------------------------
//
// Drops at the mined turf, vents its gas into the turf's air during
// Initialize, then qdels. From the player's POV mining the wall just
// "puffs" — the gas mixes into the local air and they need a tank to
// scoop it back out.

/obj/item/raw_chem_vent
	name = "rupturing gas pocket"
	desc = "A spurt of gas escapes — too late."
	icon = 'icons/obj/mining.dmi'
	icon_state = "ore_phoron"
	color = "#a040c0"
	var/vent_gas_id = null
	var/vent_moles = 5
	var/vent_temperature = T20C

/obj/item/raw_chem_vent/Initialize(mapload)
	. = ..()
	if(!vent_gas_id)
		return INITIALIZE_HINT_QDEL
	var/turf/T = get_turf(src)
	if(!T)
		return INITIALIZE_HINT_QDEL
	var/datum/gas_mixture/release = new
	release.adjust_gas_temp(vent_gas_id, vent_moles, vent_temperature)
	T.assume_air(release)
	if(SSquarry)
		SSquarry.emit_noise(T, QUARRY_NOISE_VENT, src)
		SSquarry.on_layer_gas_vented(T.z, vent_gas_id, vent_moles)
	return INITIALIZE_HINT_QDEL

/obj/item/raw_chem_vent/phoron
	vent_gas_id = GAS_PHORON
	vent_moles = 8


// === ORE-DATUM REGISTRATIONS =========================================
//
// The generator looks up walls by name in GLOB.ore_data. The
// ORE_RAWCHEM_* macros are declared in quarry_defines.dm so feature
// files can reference them at parse time.

/datum/ore/raw_saltpeter
	name = ORE_RAWCHEM_SALTPETER
	display_name = "saltpeter"
	result_amount = 4
	spread_chance = 10
	ore = /obj/item/raw_chem/saltpeter
	scan_icon = "mineral_common"
	reagent = "potassium"

/datum/ore/raw_lithium
	name = ORE_RAWCHEM_LITHIUM
	display_name = "lithium"
	result_amount = 3
	spread_chance = 8
	ore = /obj/item/raw_chem/lithium
	scan_icon = "mineral_uncommon"
	reagent = "lithium"

/datum/ore/raw_copper_sulfate
	name = ORE_RAWCHEM_COPPER_SULFATE
	display_name = "copper sulfate"
	result_amount = 3
	spread_chance = 8
	ore = /obj/item/raw_chem/copper_sulfate
	scan_icon = "mineral_uncommon"
	reagent = "copper"

/datum/ore/raw_phoron_gas
	name = ORE_RAWCHEM_PHORON_GAS
	display_name = "pressurized phoron"
	result_amount = 2
	spread_chance = 6
	ore = /obj/item/raw_chem_vent/phoron
	scan_icon = "mineral_rare"
	reagent = "phoron"

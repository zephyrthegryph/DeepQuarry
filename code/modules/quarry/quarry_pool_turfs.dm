// Liquid-pool floor turfs for quarry features.
//
// Each subtype overrides /turf/proc/pump_reagents so the upstream
// /obj/machinery/pump (in code/modules/reagents/machinery/pump.dm)
// extracts the right reagent when placed on top of the pool. Players
// haul a fluid pump down the elevator, anchor it on the pool, attach
// a hose / beaker, and pump to harvest.
//
// All quarry pool turfs override pump_reagents to call the parent's
// reagent-adding behavior, then dispatch SSquarry.on_layer_reagent_pumped
// so the layer's pump_reagent goals tick. The dispatch is what makes
// goal completion event-driven rather than delivery-driven: the work
// (running the pump) is the metric, not the haul.


// --- water-based pools ------------------------------------------------

/turf/simulated/floor/water/quarry_freshwater
	name = "freshwater pool"
	desc = "An icy pool of fresh drillwater seeping up from the rock below."
	outdoors = OUTDOORS_NO
	can_be_plated = FALSE
	depth = 1
	reagent_type = REAGENT_ID_WATER

// Parent adds water at volume * 1, plus a cold-water ice bonus and
// nearby-ore frack bonus. We only credit the water portion toward the
// goal — bonuses are gravy.
/turf/simulated/floor/water/quarry_freshwater/pump_reagents(datum/reagents/R, volume)
	. = ..()
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_WATER, round(volume, 0.1))


/turf/simulated/floor/water/quarry_sulfuric
	name = "sulfuric pool"
	desc = "A pale-yellow pool of mineralised water. The fumes sting your eyes."
	outdoors = OUTDOORS_NO
	can_be_plated = FALSE
	depth = 1
	reagent_type = REAGENT_ID_SACID
	watercolor = "#d7d24a"

/turf/simulated/floor/water/quarry_sulfuric/pump_reagents(datum/reagents/R, volume)
	. = ..()
	var/sacid_added = round(volume / 2, 0.1)
	R.add_reagent(REAGENT_ID_SACID, sacid_added)
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_SACID, sacid_added)


// --- gas_crack subtypes -----------------------------------------------
//
// Upstream /turf/simulated/floor/gas_crack/* provides pump-able O2,
// N2, CO2, etc. We subtype each one to (a) tag it as a quarry-owned
// pool so goals dispatch and (b) provide quarry-specific dispatch
// without touching upstream code. Also author hydrogen / halite /
// chlorine subtypes that upstream doesn't define individually.

/turf/simulated/floor/gas_crack/oxygen/quarry
/turf/simulated/floor/gas_crack/oxygen/quarry/pump_reagents(datum/reagents/R, volume)
	. = ..()
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_OXYGEN, round(volume / 2, 0.1))

/turf/simulated/floor/gas_crack/nitrogen/quarry
/turf/simulated/floor/gas_crack/nitrogen/quarry/pump_reagents(datum/reagents/R, volume)
	. = ..()
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_NITROGEN, round(volume / 2, 0.1))

/turf/simulated/floor/gas_crack/carbon/quarry
/turf/simulated/floor/gas_crack/carbon/quarry/pump_reagents(datum/reagents/R, volume)
	. = ..()
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_CARBON, round(volume / 2, 0.1))


// Hydrogen, halite, chlorine: no upstream gas_crack subtype to inherit.

/turf/simulated/floor/gas_crack/hydrogen
	gas_type = list()
	desc = "Cracked sand. A faint hiss escapes when struck."

/turf/simulated/floor/gas_crack/hydrogen/pump_reagents(datum/reagents/R, volume)
	. = ..()
	var/added = round(volume / 2, 0.1)
	R.add_reagent(REAGENT_ID_HYDROGEN, added)
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_HYDROGEN, added)

/turf/simulated/floor/gas_crack/hydrogen/examine(mob/user)
	. = ..()
	. += "A thin, dry breeze rises from it."


/turf/simulated/floor/gas_crack/halite
	gas_type = list()
	desc = "Cracked sand crusted with pale, gritty salt crystals."

/turf/simulated/floor/gas_crack/halite/pump_reagents(datum/reagents/R, volume)
	. = ..()
	var/added = round(volume / 2, 0.1)
	R.add_reagent(REAGENT_ID_SODIUMCHLORIDE, added)
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_SODIUMCHLORIDE, added)

/turf/simulated/floor/gas_crack/halite/examine(mob/user)
	. = ..()
	. += "Briny crystals coat the edges of the crack."


/turf/simulated/floor/gas_crack/chlorine
	gas_type = list()
	desc = "Cracked sand stained yellow-green. The air bites at your nose."

/turf/simulated/floor/gas_crack/chlorine/pump_reagents(datum/reagents/R, volume)
	. = ..()
	var/added = round(volume / 2, 0.1)
	R.add_reagent(REAGENT_ID_CHLORINE, added)
	if(SSquarry)
		SSquarry.on_layer_reagent_pumped(z, REAGENT_ID_CHLORINE, added)

/turf/simulated/floor/gas_crack/chlorine/examine(mob/user)
	. = ..()
	. += "An acrid, eye-watering reek wafts up."

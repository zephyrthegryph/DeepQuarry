//R-UST port
// Produced during deuterium synthesis. Super poisonous, SUPER flammable (doesn't need oxygen to burn).
/datum/reagent/toxin/hydrophoron
	name = REAGENT_HYDROPHORON
	id = REAGENT_ID_HYDROPHORON
	description = "An exceptionally flammable molecule formed from deuterium synthesis."
	dermal_absorption = 1 //same as phoron
	strength = 80
	poison_affliction = /datum/affliction/poisoning/phoron
	var/fire_mult = 30
	supply_conversion_value = REFINERYEXPORT_VALUE_PROCESSED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/toxin/hydrophoron/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		L.adjust_fire_stacks(amount / fire_mult)

/datum/reagent/toxin/hydrophoron/affect_touch(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_CORROSIVE, removed * 0.1, source = src) //being splashed directly with hydrophoron causes minor chemical burns
	// ZAS pl_effects() (phoron contamination side-effect) removed; the
	// burn damage above is the meaningful remainder under LINDA.
	..()

/datum/reagent/toxin/hydrophoron/touch_turf(turf/simulated/T)
	if(!istype(T))
		return
	..()
	T.assume_gas(GAS_PHORON, CEILING(volume/2, 1), T20C)
	for(var/turf/simulated/floor/target_tile in range(0,T))
		target_tile.assume_gas(GAS_PHORON, volume/2, 400+T0C)
		target_tile.hotspot_expose(700, 400)
	remove_self(volume)

/datum/reagent/toxin/hydrophoron/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(alien == IS_SLIME)
		M.adjust_fire_stacks(removed * 10)
		if(prob(10))
			to_chat(M, span_critical("You feel something boiling within you!"))
			after(M, rand(3, 6) SECONDS, TYPE_PROC_REF(/mob/living, ignite_mob))

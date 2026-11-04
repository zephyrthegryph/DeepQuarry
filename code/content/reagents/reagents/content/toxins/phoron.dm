/datum/reagent/toxin/phoron
	name = REAGENT_PHORON
	id = REAGENT_ID_PHORON
	description = "Phoron in its liquid form."
	taste_mult = 1.5
	reagent_state = LIQUID
	color = "#9D14DB"
	strength = 30
	poison_affliction = /datum/affliction/poisoning/phoron
	touch_met = 5
	dermal_absorption = 1
	supply_conversion_value = 5 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PHORON
	coolant_modifier = 0.85

/datum/reagent/toxin/phoron/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		L.adjust_fire_stacks(amount / 5)

/datum/reagent/toxin/phoron/affect_touch(mob/living/carbon/M, alien, removed)
	..()
	M.adjust_fire_stacks(removed / 5)
	if(alien == IS_VOX)
		return
	M.injure(INJURY_CORROSIVE, removed * 0.1, source = src) //being splashed directly with phoron causes minor chemical burns
	// ZAS pl_effects() removed (see hydrophoron/affect_touch).

/datum/reagent/toxin/phoron/affect_blood(mob/living/carbon/M, alien, removed)
	if(alien == IS_VOX)
		// Vox breathe phoron: species-gated, so it mends directly rather than via a tag.
		M.mend(TREAT_OXYGENATION, 100 * removed) //5 asphyxia healed per tick.
		return //You're wasting plasma (a semi-limited chemical) to save someone, so it might as well be somewhat strong.
	if(alien == IS_SLIME)
		M.adjust_fire_stacks(removed * 3) //Not quite 'converting' it. It's like mixing fuel into a jelly. You get explosive, or at least combustible, jelly.
	..()

/datum/reagent/toxin/phoron/touch_turf(turf/simulated/T, amount)
	..()
	if(!istype(T))
		return
	T.assume_gas(GAS_VOLATILE_FUEL, amount, T20C)
	remove_self(amount)

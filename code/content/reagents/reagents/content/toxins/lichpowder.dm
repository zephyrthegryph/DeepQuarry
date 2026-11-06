/datum/reagent/lichpowder
	name = REAGENT_LICHPOWDER
	id = REAGENT_ID_LICHPOWDER
	description = "A stablized nerve agent that puts the subject into a strange state of un-death."
	reagent_state = SOLID
	color = "#666666"
	dermal_absorption = 0 //Has its own custom affect_touch effect. The parent has this set to 0, but this is just here for the comment.
	metabolism = REM * 0.75
	mrate_static = TRUE
	scannable = SCANNABLE_SECRETIVE
	supply_conversion_value = REFINERYEXPORT_VALUE_MASSINDUSTRY
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/lichpowder
	immune_species_touch = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/lichpowder/affect_touch(mob/living/carbon/M, alien, removed)
	if(!(M.status_flags & FAKEDEATH))
		M.emote("deathgasp")
		STATE_SET(M, living_misc, tod, stationtime2text())
		STAMP(M, timeofdeath, CLOCK_WORLD)
	M.set_status_flags(M.status_flags | FAKEDEATH)
	M.status_at_least(STAT_MUTED, 10)
	M.status_set(STAT_PARALYZED, max(M.status_units(STAT_PARALYZED), 10))

	if(prob(0.1))
		act_message(M, null, MSG_SELF("You wheeze sharply... it's cold."), MSG_OTHERS("%U% wheezes."))
		M.adjust_bodytemperature(-(10 * TEMPERATURE_DAMAGE_COEFFICIENT), min_temp = T0C - 10)

// its mob wakes from fake death.
/datum/reagent/lichpowder/on_destroy(force)
	if(holder && holder.my_atom && ismob(holder.my_atom))
		var/mob/M = holder.my_atom
		M.set_status_flags(M.status_flags & ~FAKEDEATH)
	..()

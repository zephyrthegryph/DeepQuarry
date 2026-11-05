/datum/reagent/toxin/zombiepowder
	name = REAGENT_ZOMBIEPOWDER
	id = REAGENT_ID_ZOMBIEPOWDER
	description = "A strong neurotoxin that puts the subject into a death-like state."
	taste_description = "numbness"
	reagent_state = SOLID
	dermal_absorption = 0 //No splashing someone to isnta KO them.
	color = "#669900"
	metabolism = REM
	strength = 3
	mrate_static = TRUE
	scannable = SCANNABLE_SECRETIVE
	// The death-like state: breathing all but stops.
	factors = alist(STAT_RESP_DRIVE = 0.2)
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_MEDSCI

/datum/reagent/toxin/zombiepowder/affect_blood(mob/living/carbon/M, alien, removed)
	..()
	if(inert_for(M))
		return
	if(!(M.status_flags & FAKEDEATH))
		M.emote("deathgasp")
		living_misc_of(M).set_tod(stationtime2text())
		STAMP(M, timeofdeath, CLOCK_WORLD)
	M.set_status_flags(M.status_flags | FAKEDEATH)
	M.status_at_least(STAT_MUTED, 10)
	M.status_set(STAT_PARALYZED, max(M.status_units(STAT_PARALYZED), 10))

// its mob wakes from fake death.
/datum/reagent/toxin/zombiepowder/on_destroy(force)
	if(holder && holder.my_atom && ismob(holder.my_atom))
		var/mob/M = holder.my_atom
		M.set_status_flags(M.status_flags & ~FAKEDEATH)
	..()

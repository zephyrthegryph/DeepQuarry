/datum/reagent/carbon
	name = REAGENT_CARBON
	id = REAGENT_ID_CARBON
	description = "A chemical element, the building block of life."
	taste_description = "sour chalk"
	taste_mult = 1.5
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#1C1300"
	ingest_met = REM * 5
	supply_conversion_value = REFINERYEXPORT_VALUE_UNWANTED
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/carbon
	immune_species_ingest = SPECIES_TAG_BIT(IS_DIONA) // P2-S13

/datum/reagent/carbon/affect_ingest(mob/living/carbon/M, alien, removed)
	if(M.ingested && M.ingested.reagent_list.len > 1) // Need to have at least 2 reagents - cabon and something to remove
		var/effect = 1 / (M.ingested.reagent_list.len - 1)
		for(var/datum/reagent/R in M.ingested.reagent_list)
			if(R == src)
				continue
			M.ingested.remove_reagent(R.id, removed * effect)

/datum/reagent/carbon/touch_turf(turf/T)
	..()
	if(!istype(T, /turf/space))
		var/obj/effect/decal/cleanable/dirt/dirtoverlay = locate(/obj/effect/decal/cleanable/dirt, T)
		if (!dirtoverlay)
			dirtoverlay = new/obj/effect/decal/cleanable/dirt(T)
			dirtoverlay.set_alpha(volume * 30)
		else
			dirtoverlay.set_alpha(min(dirtoverlay.alpha + volume * 30, 255))

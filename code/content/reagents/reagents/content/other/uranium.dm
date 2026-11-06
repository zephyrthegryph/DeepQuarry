/datum/reagent/uranium
	name = REAGENT_URANIUM
	id = REAGENT_ID_URANIUM
	description = "A silvery-white metallic chemical element in the actinide series, weakly radioactive."
	taste_description = "metal"
	reagent_state = SOLID
	scannable = SCANNABLE_ADVANCED
	color = "#B8B8C0"
	supply_conversion_value = 2 SHEET_TO_REAGENT_EQUIVILENT // has sheet value
	industrial_use = REFINERYEXPORT_REASON_PRECURSOR

/datum/reagent/uranium/affect_touch(mob/living/carbon/M, alien, removed)
	affect_ingest(M, alien, removed)

/datum/reagent/uranium/affect_blood(mob/living/carbon/M, alien, removed)
	M.apply_effect(5 * removed, IRRADIATE, 0)

/datum/reagent/uranium/touch_turf(turf/T)
	..()
	if(volume >= 3)
		if(!istype(T, /turf/space))
			var/obj/effect/decal/cleanable/greenglow/glow = locate(/obj/effect/decal/cleanable/greenglow, T)
			if(!glow)
				new /obj/effect/decal/cleanable/greenglow(T)
			return

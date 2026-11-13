/datum/reagent/sterilizine
	name = REAGENT_STERILIZINE
	id = REAGENT_ID_STERILIZINE
	description = "A topical that sterilizes wounds and surfaces, preventing wound and surgical infection, and thoroughly removes blood. It stings on contact."
	taste_description = "bitterness"
	reagent_state = LIQUID
	dermal_absorption = 0 //Custom touch handling.
	color = "#C8A5DC"
	scannable = SCANNABLE_BENEFICIAL
	touch_met = 5
	supply_conversion_value = REFINERYEXPORT_VALUE_HIGHREFINED
	industrial_use = REFINERYEXPORT_REASON_CLEAN
	species_injuries_blood = alist(IS_SLIME = alist(INJURY_CORROSIVE = 1, INJURY_TOXIN = 2))
	species_injuries_touch = alist(IS_SLIME = alist(INJURY_CORROSIVE = 1, INJURY_TOXIN = 2))

/datum/reagent/sterilizine/affect_touch(mob/living/carbon/M, alien, removed)
	M.adjust_germ_level(-removed * 20)
	// It stings: a little pain where it touches.
	var/sting = M.injure(INJURY_PAIN, removed * STERILIZINE_STING_PER_UNIT, source = src, flags = INJURE_SILENT)
	if(GLOB.chem_trace)
		log_world("CHEM: sterilizine stings [M] for [sting] pain (removed [removed])")
	for(var/obj/item/I in contents_of(M))
		dq_set_was_bloodied(I, null)
	dq_set_was_bloodied(M, null)

/datum/reagent/sterilizine/touch_obj(obj/O)
	..()
	O.adjust_germ_level(-volume * 200)
	dq_set_was_bloodied(O, null)

/datum/reagent/sterilizine/touch_turf(turf/T)
	..()
	T.adjust_germ_level(-volume * 200)
	for(var/obj/item/I in turf_contents_of_type(T, /obj/item))
		dq_set_was_bloodied(I, null)
	for(var/obj/effect/decal/cleanable/blood/B in turf_contents_of_type(T, /obj/effect/decal/cleanable/blood))
		dissolved(B)

	if(istype(T, /turf/simulated))
		var/turf/simulated/S = T
		S.dirt = -50

/datum/reagent/sterilizine/touch_mob(mob/living/L, amount)
	..()
	if(istype(L))
		if(istype(L, /mob/living/simple_mob/slime))
			var/mob/living/simple_mob/slime/S = L
			S.injure(INJURY_CORROSIVE, rand(15, 25) * amount, source = src)	// Does more damage than water.
			act_message(S, null, MSG_SELF(span_danger("Your flesh burns in the fluid!")), \
				MSG_OTHERS(span_warning("%U%'s flesh sizzles where the fluid touches it!")))
		remove_self(amount)

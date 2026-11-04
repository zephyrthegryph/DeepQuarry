/datum/reagent/space_cleaner
	name = REAGENT_CLEANER
	id = REAGENT_ID_CLEANER
	description = "A compound used to clean things. Now with 50% more sodium hypochlorite!"
	taste_description = "sourness"
	reagent_state = LIQUID
	dermal_absorption = 0
	scannable = SCANNABLE_ADVANCED
	color = "#A5F0EE"
	touch_met = 50
	supply_conversion_value = REFINERYEXPORT_VALUE_COMMON
	industrial_use = REFINERYEXPORT_REASON_CLEAN

/datum/reagent/space_cleaner/touch_obj(obj/O)
	..()
	O.wash(CLEAN_SCRUB)

/datum/reagent/space_cleaner/touch_turf(turf/T)
	..()
	if(volume >= 1)
		if(istype(T, /turf/simulated))
			var/turf/simulated/S = T
			S.dirt = 0
		T.wash(CLEAN_SCRUB)
		for(var/obj/effect/O in turf_contents_of_type(T, /obj/effect))
			if(istype(O,/obj/effect/rune) || istype(O,/obj/effect/decal/cleanable) || istype(O,/obj/effect/overlay))
				dissolved(O)

		for(var/mob/living/simple_mob/slime/M in turf_contents_of_type(T, /mob/living/simple_mob/slime))
			M.injure(INJURY_CORROSIVE, rand(5, 10), source = src)

		for(var/mob/living/simple_mob/vore/aggressive/macrophage/virus in turf_contents_of_type(T, /mob/living/simple_mob/vore/aggressive/macrophage))
			virus.injure(INJURY_TOXIN, rand(5, 10), source = src)

	T.apply_fire_protection() // Apply fire protection

/datum/reagent/space_cleaner/affect_touch(mob/living/carbon/M, alien, removed)
	if(M.get_equipped_item(SLOT_ID_HAND_R))
		M.get_equipped_item(SLOT_ID_HAND_R).wash(CLEAN_SCRUB)
	if(M.get_equipped_item(SLOT_ID_HAND_L))
		M.get_equipped_item(SLOT_ID_HAND_L).wash(CLEAN_SCRUB)
	if(M.get_equipped_item(SLOT_ID_MASK))
		M.get_equipped_item(SLOT_ID_MASK).wash(CLEAN_SCRUB)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(alien == IS_SLIME)
			M.injure(INJURY_CORROSIVE, rand(5, 10), source = src)
		if(H.get_equipped_item(SLOT_ID_HEAD))
			H.get_equipped_item(SLOT_ID_HEAD).wash(CLEAN_SCRUB)
		if(H.get_equipped_item(SLOT_ID_SUIT))
			H.get_equipped_item(SLOT_ID_SUIT).wash(CLEAN_SCRUB)
		else if(H.get_equipped_item(SLOT_ID_UNIFORM))
			H.get_equipped_item(SLOT_ID_UNIFORM).wash(CLEAN_SCRUB)
		if(H.get_equipped_item(SLOT_ID_SHOES))
			H.get_equipped_item(SLOT_ID_SHOES).wash(CLEAN_SCRUB)
		else
			H.wash(CLEAN_SCRUB)
			return
	M.wash(CLEAN_SCRUB)

/datum/reagent/space_cleaner
	// Prometheans take a doubled dose instead of the usual poisoning.
	immune_species_ingest = SPECIES_TAG_BIT(IS_SLIME)
	species_injuries_ingest = alist(IS_SLIME = alist(INJURY_TOXIN = 6))

/datum/reagent/space_cleaner/affect_ingest(mob/living/carbon/M, alien, removed)
	M.injure(INJURY_TOXIN, 3 * removed, source = src)
	if(prob(5))
		M.vomit()

/datum/reagent/space_cleaner/touch_mob(mob/M, amount)
	..()
	if(iscarbon(M))
		var/mob/living/carbon/C = M
		C.wash(CLEAN_SCRUB)

	if(istype(M, /mob/living/simple_mob/vore/aggressive/macrophage)) // Big ouch for viruses
		var/mob/living/simple_mob/macrophage = M
		macrophage.injure(INJURY_TOXIN, 20, source = src)

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(H.get_equipped_item(SLOT_ID_MASK))
			if(istype(H.get_equipped_item(SLOT_ID_MASK), /obj/item/clothing/mask/smokable))
				var/obj/item/clothing/mask/smokable/S = H.get_equipped_item(SLOT_ID_MASK)
				if(S.lit)
					S.quench() // No smoking in my medbay!
					act_message(H, null, others = span_notice("%U%\'s [S.name] is put out."))

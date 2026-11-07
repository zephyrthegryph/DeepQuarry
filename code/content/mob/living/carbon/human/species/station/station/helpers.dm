/// WEAKER XENOMORPH HYBRID ABILITIES / ORGANS. ///

// ABILITIES //

/mob/living/carbon/human/proc/plant_weak()
	set name = "Plant Weeds (150)"
	set desc = "Plants some alien weeds."

	if(check_alien_ability(150,1,O_RESIN))
		act_message(src, null, others = span_alium(span_bold("%U% has planted some alien weeds!")))
		new /obj/effect/alien/weeds/node/weak(get_turf(src))	// Aliens.dm for weed node origin.
		play_sfx(src, SFX_EFFECTS_BLOBATTACK, volume = 40)
	return

/mob/living/carbon/human/proc/check_plasma_amount()
	set name = "Check Plasma Reserves"

	var/obj/item/organ/internal/xenos/plasmavessel/I = organ_in(O_PLASMA)
	if(!istype(I))
		to_chat(src, span_alium("Our plasma vessel is missing!"))
		return

	to_chat(src, "Our plasma reserves are at [I.stored_plasma]/[I.max_plasma].")
	return 0

/mob/living/carbon/human/proc/resin_weak() // Technically stronger in some aspects.
	set name = "Secrete Resin (25)"
	set desc = "Secrete tough, malleable resin in front of us."

	var/list/options = list("resin door","resin wall","resin membrane","nest","resin blob")
	for(var/option in options)
		LAZYSET(options, option, new /image('icons/mob/alien.dmi', option)) // based off 'icons/effects/thinktank_labels.dmi'

	open_request(src, /datum/prompt/choice, PROC_REF(resin_weak_chosen), answerer = src, choices = options, anchor = src, radius = 42, require_near = TRUE, radial = TRUE, autopick_single_option = TRUE, timeout = 0)

/// Radial answer: secrete the picked resin structure in front of us.
/mob/living/carbon/human/proc/resin_weak_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/choice = A.answer.value
	if(!choice || QDELETED(src) || src.incapacitated())
		return

	var/targetLoc = get_step(src, dir)

	if(iswall(targetLoc))
		targetLoc = get_turf(src)

	var/obj/O

	switch(choice)
		if("resin door")
			if(!check_alien_ability(25,1,O_RESIN))
				return
			else O = new /obj/structure/simple_door/resin(targetLoc)
		if("resin wall")
			if(!check_alien_ability(25,1,O_RESIN))
				return
			else O = new /obj/structure/alien/wall(targetLoc)
		if("resin membrane")
			if(!check_alien_ability(25,1,O_RESIN))
				return
			else O = new /obj/structure/alien/membrane(targetLoc)
		if("nest")
			if(!check_alien_ability(25,1,O_RESIN))
				return
			else O = new /obj/structure/bed/nest(targetLoc)
		if("resin blob")
			if(!check_alien_ability(25,1,O_RESIN))
				return
			else O = new /obj/item/stack/material/resin(targetLoc)

	if(O)
		act_message(src, null, MSG_SELF(span_alium("You shape a [choice].")), \
			MSG_OTHERS(span_warning(span_bold("%U% vomits up a thick purple substance and begins to shape it!"))))
		play_sfx(src, SFX_EFFECTS_BLOBATTACK, volume = 40)

	return

// ORGANS //

/obj/item/organ/internal/xenos/resinspinner/weak
	name = "hybrid resin spinner"
	parent_organ = BP_HEAD
	icon_state = "xenode"
	organ_tag = O_RESIN

	organ_verbs = list(
		/mob/living/carbon/human/proc/resin_weak,
		/mob/living/carbon/human/proc/plant_weak,
		/mob/living/carbon/human/proc/check_plasma_amount
		)

/obj/item/organ/internal/xenos/plasmavessel/weak
	name = "hybrid plasma vessel"
	stored_plasma = 250 // Starts with max plasma.
	max_plasma = 250 // Maximum of 250 plasma stored at any one time. Drones normally have 500.

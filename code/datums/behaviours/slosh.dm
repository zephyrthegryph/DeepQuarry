/// Vore footstep sloshing (was /datum/element/slosh). A shared behaviour singleton on the
/// moved event; the step counter and cached volume/chance live on the mob (the element
/// kept them on itself, shared by every mob). A capability hooked on the moved notice: L.enable_slosh() grants it.
CAPABILITY_TYPE(slosh, CAP_SLOSH, /datum/capability/slosh, key = NONE)
/datum/capability/slosh

/datum/capability/slosh/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(slosh_step))))

/// Grants the slosh capability (once: a second grant from the same source keeps the first).
/mob/proc/enable_slosh()
	grant(src, /datum/capability/slosh, src)

/// Per-mob counters and cached samples persist between capability grants.
sparse(/mob/living, slosh_steps, type = num)
sparse(/mob/living, slosh_volume, type = num)
sparse(/mob/living, slosh_chance, type = num)

/// Returns the old step count, preserving each caller's postfix increment.
/mob/living/proc/slosh_next_step()
	var/previous = sparse_get_or(src, slosh_steps, 0)
	sparse_set_or(src, slosh_steps, previous + 1, 0)
	return previous

/datum/capability/slosh/proc/slosh_step(datum/act/A)
	var/mob/living/source = A.holder
	if(istype(source))
		slosh_moved(source)

/// One step of `source` (the mob that moved): humans slosh by intent, silicons every other step.
/datum/capability/slosh/proc/slosh_moved(mob/living/source)
	if(ishuman(source))
		var/mob/living/carbon/human/source_human = source
		if(source_human.m_intent == I_WALK && source.slosh_next_step() % 20 == 0)
			return
		if(source_human.m_intent == I_RUN && source.slosh_next_step() % 2 != 0)
			return
		choose_vorefootstep(source)
	if(issilicon(source))
		if(source.slosh_next_step() % 2)
			choose_vorefootstep(source)


/datum/capability/slosh/proc/choose_vorefootstep(mob/living/source)
	if(source.slosh_next_step() >= 5)

		var/highest_vol = 0

		for(var/obj/belly/B in source.vore_organs)
			var/total_volume = B.reagents.total_volume

			if(B.show_liquids && B.vorefootsteps_sounds && highest_vol < total_volume)
				highest_vol = total_volume

		if(highest_vol < 20)
			sparse_set_or(source, slosh_volume, 0, 0)
			sparse_set_or(source, slosh_chance, 0, 0)
		else
			sparse_set_or(source, slosh_volume, 20 + highest_vol * 4/5, 0)
			sparse_set_or(source, slosh_chance, highest_vol/4, 0)

		sparse_set_or(source, slosh_steps, 0, 0)

		if(!sparse_get_or(source, slosh_volume, 0) || !sparse_get_or(source, slosh_chance, 0))
			return

		if(prob(sparse_get_or(source, slosh_chance, 0)))
			handle_vorefootstep(source)

/datum/capability/slosh/proc/handle_vorefootstep(mob/living/source)
	if(!CONFIG_GET(number/vorefootstep_volume) || !sparse_get_or(source, slosh_volume, 0))
		return

	var/S = pick(GLOB.slosh)
	if(!S) return
	var/volume = CONFIG_GET(number/vorefootstep_volume) * (sparse_get_or(source, slosh_volume, 0)/100)

	if(ishuman(source))
		var/mob/living/carbon/human/human_source = source

		if(!human_source.get_equipped_item(SLOT_ID_SHOES) || human_source.m_intent == I_WALK)
			volume = CONFIG_GET(number/vorefootstep_volume) * (sparse_get_or(source, slosh_volume, 0)/100) * 0.75
		else if(human_source.get_equipped_item(SLOT_ID_SHOES))
			var/obj/item/clothing/shoes/feet = human_source.get_equipped_item(SLOT_ID_SHOES)
			if(istype(feet))
				volume = feet.step_volume_mod * CONFIG_GET(number/vorefootstep_volume) * (sparse_get_or(source, slosh_volume, 0)/100) * 0.75
		if(!human_source.has_organ(BP_L_FOOT) && !human_source.has_organ(BP_R_FOOT))
			return

	if(source?.buckled_to() || source.lying || source.throwing || source.is_incorporeal())
		return
	if(!get_gravity(source) && prob(75))
		return

	playsound(source.loc, S, volume, FALSE, preference = /datum/preference/toggle/digestion_noises)
	return

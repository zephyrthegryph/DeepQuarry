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

/mob/living
	/// Steps counted by the slosh behaviour.
	var/slosh_steps = 0
	/// Cached slosh footstep volume (0: silent).
	var/slosh_volume = 0
	/// Cached slosh footstep chance.
	var/slosh_chance = 0

/datum/capability/slosh/proc/slosh_step(datum/act/A)
	var/mob/living/source = A.holder
	if(istype(source))
		slosh_moved(source)

/// One step of `source` (the mob that moved): humans slosh by intent, silicons every other step.
/datum/capability/slosh/proc/slosh_moved(mob/living/source)
	if(ishuman(source))
		var/mob/living/carbon/human/source_human = source
		if(source_human.m_intent == I_WALK && source.slosh_steps++ % 20 == 0)
			return
		if(source_human.m_intent == I_RUN && source.slosh_steps++ % 2 != 0)
			return
		choose_vorefootstep(source)
	if(issilicon(source))
		if(source.slosh_steps++ % 2)
			choose_vorefootstep(source)


/datum/capability/slosh/proc/choose_vorefootstep(mob/living/source)
	if(source.slosh_steps++ >= 5)

		var/highest_vol = 0

		for(var/obj/belly/B in source.vore_organs)
			var/total_volume = B.reagents.total_volume

			if(B.show_liquids && B.vorefootsteps_sounds && highest_vol < total_volume)
				highest_vol = total_volume

		if(highest_vol < 20)
			source.slosh_volume = 0
			source.slosh_chance = 0
		else
			source.slosh_volume = 20 + highest_vol * 4/5
			source.slosh_chance = highest_vol/4

		source.slosh_steps = 0

		if(!source.slosh_volume || !source.slosh_chance)
			return

		if(prob(source.slosh_chance))
			handle_vorefootstep(source)

/datum/capability/slosh/proc/handle_vorefootstep(mob/living/source)
	if(!CONFIG_GET(number/vorefootstep_volume) || !source.slosh_volume)
		return

	var/S = pick(GLOB.slosh)
	if(!S) return
	var/volume = CONFIG_GET(number/vorefootstep_volume) * (source.slosh_volume/100)

	if(ishuman(source))
		var/mob/living/carbon/human/human_source = source

		if(!human_source.get_equipped_item(SLOT_ID_SHOES) || human_source.m_intent == I_WALK)
			volume = CONFIG_GET(number/vorefootstep_volume) * (source.slosh_volume/100) * 0.75
		else if(human_source.get_equipped_item(SLOT_ID_SHOES))
			var/obj/item/clothing/shoes/feet = human_source.get_equipped_item(SLOT_ID_SHOES)
			if(istype(feet))
				volume = feet.step_volume_mod * CONFIG_GET(number/vorefootstep_volume) * (source.slosh_volume/100) * 0.75
		if(!human_source.has_organ(BP_L_FOOT) && !human_source.has_organ(BP_R_FOOT))
			return

	if(source?.buckled_to() || source.lying || source.throwing || source.is_incorporeal())
		return
	if(!get_gravity(source) && prob(75))
		return

	playsound(source.loc, S, volume, FALSE, preference = /datum/preference/toggle/digestion_noises)
	return

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
	/// Cached slosh footstep volume (0: silent).
	/// Cached slosh footstep chance.

/datum/capability/slosh/proc/slosh_step(datum/act/A)
	var/mob/living/source = A.holder
	if(istype(source))
		slosh_moved(source)

/// One step of `source` (the mob that moved): humans slosh by intent, silicons every other step. The step counter is read once and written once a step (it was a lazy
/// state read and write at each of up to three counts, and a state made and dropped every few steps: the dearest moved-notice listener of a walk).
/datum/capability/slosh/proc/slosh_moved(mob/living/source)
	var/steps = STATE_GET(source, slosh, slosh_steps)
	var/was = steps
	if(ishuman(source))
		var/mob/living/carbon/human/source_human = source
		var/skip = FALSE
		if(source_human.m_intent == I_WALK)
			skip = steps % 20 == 0
			steps++
		if(!skip && source_human.m_intent == I_RUN)
			skip = steps % 2 != 0
			steps++
		if(!skip)
			steps = choose_vorefootstep(source, steps)
	else if(issilicon(source))
		var/odd = steps % 2
		steps++
		if(odd)
			steps = choose_vorefootstep(source, steps)
	if(steps != was)
		STATE_SET(source, slosh, slosh_steps, steps)

/// The step count after this step's pick: counts it, and every fifth recomputes the cached volume and chance from the bellies and may play a sound. `steps` is the count before.
/datum/capability/slosh/proc/choose_vorefootstep(mob/living/source, steps)
	var/before = steps
	steps++
	if(before >= 5)
		var/highest_vol = 0

		for(var/obj/belly/B in source.vore_organs)
			var/total_volume = B.reagents.total_volume

			if(B.show_liquids && B.vorefootsteps_sounds && highest_vol < total_volume)
				highest_vol = total_volume

		if(highest_vol < 20)
			STATE_SET(source, slosh, slosh_volume, 0)
			STATE_SET(source, slosh, slosh_chance, 0)
		else
			STATE_SET(source, slosh, slosh_volume, 20 + highest_vol * 4/5)
			STATE_SET(source, slosh, slosh_chance, highest_vol/4)

		steps = 0

		if(!STATE_GET(source, slosh, slosh_volume) || !STATE_GET(source, slosh, slosh_chance))
			return steps

		if(prob(STATE_GET(source, slosh, slosh_chance)))
			handle_vorefootstep(source)
	return steps

/datum/capability/slosh/proc/handle_vorefootstep(mob/living/source)
	if(!CONFIG_GET(number/vorefootstep_volume) || !STATE_GET(source, slosh, slosh_volume))
		return

	var/S = pick(GLOB.slosh)
	if(!S) return
	var/volume = CONFIG_GET(number/vorefootstep_volume) * (STATE_GET(source, slosh, slosh_volume)/100)

	if(ishuman(source))
		var/mob/living/carbon/human/human_source = source

		if(!human_source.get_equipped_item(SLOT_ID_SHOES) || human_source.m_intent == I_WALK)
			volume = CONFIG_GET(number/vorefootstep_volume) * (STATE_GET(source, slosh, slosh_volume)/100) * 0.75
		else if(human_source.get_equipped_item(SLOT_ID_SHOES))
			var/obj/item/clothing/shoes/feet = human_source.get_equipped_item(SLOT_ID_SHOES)
			if(istype(feet))
				volume = feet.step_volume_mod * CONFIG_GET(number/vorefootstep_volume) * (STATE_GET(source, slosh, slosh_volume)/100) * 0.75
		if(!human_source.has_organ(BP_L_FOOT) && !human_source.has_organ(BP_R_FOOT))
			return

	if(source?.buckled_to() || source.lying || source.throwing || source.is_incorporeal())
		return
	if(!get_gravity(source) && prob(75))
		return

	playsound(source.loc, S, volume, FALSE, volume_channel = VOLUME_CHANNEL_VORE)
	return

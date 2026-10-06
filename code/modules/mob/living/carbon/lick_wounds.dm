/// Licks one untreated wound per timed action.
/mob/living/carbon/human/proc/lick_step(mob/living/carbon/human/H, obj/item/organ/external/affecting, list/wounds, index)
	while(index <= length(wounds))
		var/datum/affliction/wound/W = wounds[index]
		if(!QDELETED(W) && !(W.bandaged && W.salved && W.disinfected))
			task_start(/datum/task/timed/human_lick, src, src, duration = W.damage/5, H = H, affecting = affecting, wounds = wounds, index = index)
			return
		index++

/mob/living/carbon/human/proc/lick_interrupted(datum/task/timed/human_lick/task)
	to_chat(src, span_notice("You must stand still to clean wounds."))

/datum/task/timed/human_lick
	complete_proc = /mob/living/carbon/human/proc/lick_done
	cancel_proc = /mob/living/carbon/human/proc/lick_interrupted
	var/mob/living/carbon/human/H
	var/obj/item/organ/external/affecting
	var/list/wounds
	var/index

/mob/living/carbon/human/proc/lick_done(datum/task/timed/human_lick/task)
	var/mob/living/carbon/human/H = task.H
	var/obj/item/organ/external/affecting = task.affecting
	var/list/wounds = task.wounds
	var/index = task.index
	if(affecting.is_bandaged() && affecting.is_salved()) // We do a second check after the delay, in case it was bandaged after the first check.
		to_chat(src, span_warning("The wounds on [H]'s [affecting.name] have already been treated."))
		return
	var/datum/affliction/wound/W = wounds[index]
	act_message(src, H, MSG_SELF(span_notice("You treat \a [W.desc] on %T%'s [affecting.name] with your antiseptic saliva.")), \
		MSG_OTHERS(span_notice("%U% [pick("slathers \a [W.desc] on %T%'s [affecting.name] with their spit.", "drags their tongue across \a [W.desc] on %T%'s [affecting.name].", "drips saliva onto \a [W.desc] on %T%'s [affecting.name].", "uses their tongue to disinfect \a [W.desc] on %T%'s [affecting.name].", "licks \a [W.desc] on %T%'s [affecting.name], cleaning it.")]")))
	adjust_nutrition(-20)
	W.salve()
	W.bandage()
	W.disinfect()
	H.UpdateDamageIcon()
	play_sfx(src, SFX_EFFECTS_OINTMENT, 0.5, vary = FALSE)
	lick_step(H, affecting, wounds, index + 1)

/mob/living/carbon/human/proc/lick_wounds(mob/living/carbon/M as mob in view(1)) // Allows the user to lick themselves. Given how rarely this trait is used, I don't see an issue with a slight buff.
	set name = "Lick Wounds"
	set category = VERB_CAT_ABILITIES_GENERAL
	set desc = "Disinfect and heal small wounds with your saliva."

	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED))
		to_chat(src, span_warning("You can't do that in your current state."))
		return

	if(nutrition < 50)
		to_chat(src, span_warning("You need more energy to produce antiseptic enzymes. Eat something and try again."))
		return
	//Added the distance check to here. this allows the ability to lick ones own wounds. although this also means that all living/carbon/M appear on the list if used.
	if (get_dist(src,M) >= 2)
		to_chat(src, span_warning("You need to be closer to do that.")) // don't use src << unless you have to.
		return

	if (get_dist(src,M) >= 2)
		to_chat(src, span_warning("You need to be closer to do that."))
		return

	if ( ! (ishuman(src) || issilicon(src)) )
		to_chat(src, span_warning("If you even have a tongue, it doesn't work that way."))
		return

	if (ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(src.zone_sel.selecting)

		if(!affecting)
			to_chat(src, span_warning("No body part there to work on!"))
			return

		if(affecting.organ_tag == BP_HEAD)
			if(H.get_equipped_item(SLOT_ID_HEAD) && istype(H.get_equipped_item(SLOT_ID_HEAD),/obj/item/clothing/head/helmet/space))
				to_chat(src, span_warning("You can't seem to lick through [H.get_equipped_item(SLOT_ID_HEAD)]!"))
				return

		else
			if(H.get_equipped_item(SLOT_ID_SUIT) && istype(H.get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit/space))
				to_chat(src, span_warning("You can't lick your way through [H.get_equipped_item(SLOT_ID_SUIT)]!"))
				return

		if(affecting.robotic == ORGAN_ROBOT)
			to_chat(src, span_warning("You don't think your spit will help a robotic limb."))
			return

		if(affecting.robotic >= ORGAN_LIFELIKE)
			to_chat(src, span_warning("You lick [M]'s [affecting.name], but it seems to have no effect..."))
			return

		if(affecting.open)
			to_chat(src, span_notice("The [affecting.name] is cut open, you don't think your spit will help them!"))
			return

		if(affecting.is_bandaged() && affecting.is_salved())
			to_chat(src, span_warning("The wounds on [M]'s [affecting.name] have already been treated."))
			return

		if(affecting.get_trauma() > 20 || affecting.get_burn() > 20)
			to_chat(src, span_warning("The wounds on [M]'s [affecting.name] are too severe to treat with just licking."))
			return

		else
			act_message(src, M, MSG_SELF(span_notice("You start licking the wounds on %T%'s [affecting.name] clean.")), \
				MSG_OTHERS(span_infoplain(span_bold("%U%") + " starts licking the wounds on %T%'s [affecting.name] clean.")))

			lick_step(H, affecting, affecting.get_wounds().Copy(), 1)

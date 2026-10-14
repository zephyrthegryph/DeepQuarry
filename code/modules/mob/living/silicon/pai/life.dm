/mob/living/silicon/pai
	life_set = LIFE_SET_PAI

/// Cable retraction and `if(stat == DEAD) return`.
/mob/living/silicon/pai/proc/life_pai_cable(datum/seq_frame/life/F)
	src.check_retract_cable()

	if(src.stat == DEAD)
		return F.abort()

/// Death from injury is decided by the body (see death.dm for card damage); card faults.
/mob/living/silicon/pai/proc/life_pai_body(datum/seq_frame/life/F)
	src.body?.life_tick()
	if(src.stat == DEAD)
		return F.abort()

	var/obj/item/paicard/card = src.card
	if(card.cell != PP_FUNCTIONAL|| card.processor != PP_FUNCTIONAL || card.board != PP_FUNCTIONAL || card.capacitor != PP_FUNCTIONAL)
		src.death()

	if(card.projector != PP_FUNCTIONAL && card.emitter != PP_FUNCTIONAL)
		if(src.loc != card)
			src.close_up()
			to_chat(src, span_warning("ERROR: System malfunction. Service required!"))
	else if(card.projector  != PP_FUNCTIONAL|| card.emitter != PP_FUNCTIONAL)
		if(prob(5))
			src.close_up()
			to_chat(src, span_warning("ERROR: System malfunction. Service recommended!"))

/// The communication circuit comes back after a silence.
/mob/living/silicon/pai/proc/life_pai_silence(datum/seq_frame/life/F)
	if(src.silence_time)
		if(world.timeofday >= src.silence_time)
			src.silence_time = null
			to_chat(src, span_green("Communication circuit reinitialized. Speech and messaging functionality restored."))

/// Folded into the card, the pAI slowly self-repairs.
/mob/living/silicon/pai/proc/life_pai_repair(datum/seq_frame/life/F)
	if(src.is_injured() && istype(src.loc, /obj/item/paicard))
		src.mend(TREAT_PLATING_REPAIR, 0.5)
		src.mend(TREAT_WIRING_REPAIR, 0.5)

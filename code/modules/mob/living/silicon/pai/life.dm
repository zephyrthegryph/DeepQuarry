/mob/living/silicon/pai/Life()
	check_retract_cable()

	if(stat == DEAD)
		return

	// Death from injury is decided by the body (see death.dm for card damage).
	body?.life_tick()
	if(stat == DEAD)
		return

	if(card.cell != PP_FUNCTIONAL|| card.processor != PP_FUNCTIONAL || card.board != PP_FUNCTIONAL || card.capacitor != PP_FUNCTIONAL)
		death()

	if(card.projector != PP_FUNCTIONAL && card.emitter != PP_FUNCTIONAL)
		if(loc != card)
			close_up()
			to_chat(src, span_warning("ERROR: System malfunction. Service required!"))
	else if(card.projector  != PP_FUNCTIONAL|| card.emitter != PP_FUNCTIONAL)
		if(prob(5))
			close_up()
			to_chat(src, span_warning("ERROR: System malfunction. Service recommended!"))

	handle_regular_hud_updates()
	handle_vision()

	if(silence_time)
		if(world.timeofday >= silence_time)
			silence_time = null
			to_chat(src, span_green("Communication circuit reinitialized. Speech and messaging functionality restored."))

	handle_statuses()
	handle_sleeping()

	// Folded into the card, the pAI slowly self-repairs.
	if(is_injured() && istype(src.loc, /obj/item/paicard))
		mend(TREAT_PLATING_REPAIR, 0.5)
		mend(TREAT_WIRING_REPAIR, 0.5)

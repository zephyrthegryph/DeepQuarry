/mob/living/silicon/robot/proc/leap(bluespace = FALSE)
	if(!COOLDOWN_FINISHED(cooldowns_view(src), last_special))
		to_chat(src, span_filter_notice("Your leap actuators are still recharging."))
		return

	var/minimum_power = bluespace ? 2500 : 1000
	if(!cell || cell.charge < minimum_power)
		to_chat(src, span_filter_notice("Cell charge too low to continue."))
		return

	if(src.incapacitated(INCAPACITATION_DISABLED))
		to_chat(src, span_filter_notice("You cannot leap in your current state."))
		return

	var/list/choices = list()
	var/leap_distance = bluespace ? 5 : 3
	for(var/mob/living/M in view(leap_distance,src))
		if(!istype(M,/mob/living/silicon))
			choices += M
	choices -= src

	open_request(src, /datum/prompt/choice/robot_leap, PROC_REF(leap_target_chosen), answerer = src, ask_flags = ASK_CONSCIOUS, title = "Target Choice", question = "Who do you wish to leap at?", choices = choices, bluespace = bluespace, timeout = 0)

/// A borg's leap target. `bluespace`: the longer, costlier bluespace leap.
/datum/prompt/choice/robot_leap
	var/bluespace = FALSE

/mob/living/silicon/robot/proc/leap_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/robot_leap/leap_question = A.request
	var/mob/living/T = A.answer.value
	if(QDELETED(T))
		return
	var/bluespace = leap_question.bluespace
	var/power_cost = bluespace ? 1000 : 750
	var/minimum_power = bluespace ? 2500 : 1000
	var/leap_distance = bluespace ? 5 : 3

	if(get_dist(get_turf(T), get_turf(src)) > leap_distance) return

	if(isliving(T))
		var/mob/living/M = T
		var/datum/shadekin/SK = M.get_shadekin_state()
		if(SK && SK.in_phase)
			power_cost *= 2

	if(!draw_power(ROBOT_CELL_JOULES(power_cost), src, ROBOT_CELL_JOULES(minimum_power - power_cost)))
		to_chat(src, span_warning("Warning, low power detected. Aborting action."))
		return

	if(!COOLDOWN_FINISHED(cooldowns_view(src), last_special))
		return

	if(src.incapacitated(INCAPACITATION_DISABLED))
		to_chat(src, span_filter_notice("You cannot leap in your current state."))
		return

	STATE_SET(src, cooldowns, last_special, world.time + (1 SECOND))
	set_status_flags(status_flags | LEAPING)
	set_pixel_y(pixel_y + 10)

	act_message(src, T, others = span_danger("%U% leaps at %T%!"))
	/* // disable for now
	if(bluespace)
		src.forceMove(get_turf(T))
		T.hitby(src)
	else
		src.throw_at(get_step(get_turf(T), get_dir(src, T)), 4, 1, src)
	*/
	src.throw_at(get_step(get_turf(T), get_dir(src, T)), 4, 1, src) // no bluespace pounce
	play_sfx(src, SFX_MECHA_MECHSTEP2)
	set_pixel_y(default_pixel_y)

	if(!bluespace)
		after(src, 0.5 SECONDS, PROC_REF(leap_land), with = list(T), keeps_dead = TRUE)
		return
	leap_land(T)

/mob/living/silicon/robot/proc/leap_land(mob/living/T)
	if(status_flags & LEAPING) set_status_flags(status_flags & ~LEAPING)

	if(!T || !src.Adjacent(T))
		to_chat(src, span_warning("You miss!"))
		return

	if(ishuman(T))
		var/mob/living/carbon/human/H = T
		if(H.species.lightweight == 1)
			H.status_at_least(STAT_STUNNED, 3) // Crawling made this useless. Changing to stun instead.
			H.drop_both_hands() //Stuns no longer drop items, so were forcing it >:3
			return

	var/armor_block = T.armor_against(INJURY_PAIN)
	T.injure(INJURY_PAIN, 20, null, src, flags = INJURE_ARMORED)
	if(prob(75)) //75% chance to stun for 5 seconds, really only going to be 4 bcus click cooldown+animation.
		T.apply_effect(5, STUN, armor_block)
		T.drop_both_hands() // Stuns no longer drop items

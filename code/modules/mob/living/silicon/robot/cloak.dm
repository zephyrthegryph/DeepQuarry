//Personal shielding for the combat module.
/obj/item/borg/cloak
	name = "personal cloaking"
	desc = "A powerful experimental module that allows one to adjust their visiblity."
	icon = 'icons/obj/decals.dmi'
	icon_state = "shock"

/// Percent of visibility, 0 is visible, 1 is fully invisible.
/obj/item/borg/cloak/var/cloak_strength = 0.5
TRACKED(/obj/item/borg/cloak, cloak_strength)
/// If the cloak is on.
/obj/item/borg/cloak/var/active = FALSE
TRACKED(/obj/item/borg/cloak, active)
CAPABILITIES(/obj/item/borg/cloak)
	op("set_level", in_hand(), then(PROC_REF(cloak_ask_level)))
	op("strength", menu(), label("Toggle Cloak Strength"), needs(carried()), then(PROC_REF(cloak_ask_level)))
	op("toggle", menu(), label("Toggle Cloak"), needs(carried()), then(PROC_REF(cloak_toggled)))
	/// Draws power while cloaked at a non-zero strength.
	every(2 SECONDS, then(PROC_REF(cloak_step)), when = cond_all(nameof(active), nameof(cloak_strength)))

/// Using the cloak in hand, or its menu entry: ask the strength.
/obj/item/borg/cloak/proc/cloak_ask_level(datum/act/op/A)
	set_cloaking_level(A.actor)

/// The menu entry: switch the cloak on or off.
/obj/item/borg/cloak/proc/cloak_toggled(datum/act/op/A)
	toggle_cloak(A.actor)

/obj/item/borg/cloak/item_ctrl_click(mob/user)
	toggle_cloak(user)
	return

/obj/item/borg/cloak/proc/cloak_step(datum/act/timer/A)
	if(!isliving(src.loc)) //It's not currently in our active modules.
		set_active(FALSE)
		if(isrobot(loc.loc)) //The robot
			var/mob/living/silicon/robot/R = src.loc.loc
			update_cloak(R)
	else if(isrobot(src.loc)) //We are in a robot.
		var/mob/living/silicon/robot/R = src.loc
		//MATH: CELLRATE = 0.002 CYBORG_POWER_USAGE_MULTIPLIER = 2 and power_use = amount * CYBORG_POWER_USAGE_MULTIPLIER...
		//So 250W = 1 charge. Syndi battery has 25000 charge.
		//Let's make it so that 20 charge is used per 2 seconds if we are 100% dq_get_cloaked(src). We subtract 100 since that's the idle power used for a module being selected.
		if(!R.draw_power(((cloak_strength * 5000) - 100) * CYBORG_POWER_USAGE_MULTIPLIER, src))
			set_active(FALSE)
			update_cloak(R) //Update the cloak strength on the robot.
			return //We ran out of power. RIP.

/obj/item/borg/cloak/proc/update_cloak(mob/living/silicon/robot/robot)
	if(!robot || !isrobot(robot))
		return
	if(active && cloak_strength) //We remove any cloaks they might have
		robot.remove_body_effect(/datum/body_effect/robot_cloak)
		robot.apply_body_effect(/datum/body_effect/robot_cloak)
	else
		robot.remove_body_effect(/datum/body_effect/robot_cloak)
		set_active(FALSE)

/obj/item/borg/cloak/proc/set_cloaking_level(mob/living/silicon/robot/R)
	if(!isrobot(R)) //sod off
		return

	open_request(src, /datum/prompt/number, PROC_REF(cloaking_level_chosen), answerer = R, ask_flags = ASK_CARRIED | ASK_CAPABLE, title = "Cloak Level", question = "How obscured do you want to be? In %", default = cloak_strength*100, max_value = 100, min_value = 0, timeout = 0)

/obj/item/borg/cloak/proc/cloaking_level_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/silicon/robot/R = A.request.answerer
	var/N = A.answer.value
	if(!isnull(N) && N >= 0 && N <= 100)
		set_cloak_strength(N/100)
		to_chat(R, span_warning("You will now be [N]% obscured when the cloak is active."))
		update_cloak(R)
	else if(!N)
		return
	else
		to_chat(R, span_warning("Invalid cloak level. Must be between 0 and 100."))
		return

/obj/item/borg/cloak/proc/toggle_cloak(mob/living/silicon/robot/R)
	if(!isrobot(R)) //sod off
		return

	set_active(!active)
	to_chat(R, span_notice("You [active ? "re" : "de"]activate your personal cloaking device."))
	update_cloak(R)

/datum/body_effect/robot_cloak
	tick_interval = 2 SECONDS
	name = "robotic stealth"
	desc = "You are currently cloaked and harder to see!."

	on_created_text = span_warning("You become harder to see.")
	on_expired_text = span_notice("You become fully visible once more.")
	///How many hits it can sustain before the cloak drops
	var/cloak_durability = 3
	///How slow we are to reset the hit counter.
	var/hit_dissipation = 5 SECONDS //How long we wait before resetting the hit counter.

	stacks = MODIFIER_STACK_FORBID

/// Per-application state of a robot's cloak (body_effect_state() on the robot).
/datum/robot_cloak_state
	/// Alpha while cloaked (0..255), from the module's strength.
	var/visibility
	///How many times we have been hit in a short succession.
	var/times_hit = 0
	///When we were last hit.
	EXPIRY_DECLARE(last_hit_time)
	///If our cloak is currently up or not
	var/cloaked = TRUE
	///Body factors while the cloak is up (built once from the module's strength).
	var/alist/cloaked_factors

/datum/body_effect/robot_cloak/can_apply(mob/living/L, suppress_output = FALSE)
	return isrobot(L) && L.stat != DEAD

/datum/body_effect/robot_cloak/on_start(mob/living/L)
	var/mob/living/silicon/robot/R = L
	var/obj/item/borg/cloak/cloak = locate_in_list(R, /obj/item/borg/cloak) //Find the borg cloak module
	var/cloak_strength = cloak ? cloak.cloak_strength : 0.5
	var/datum/robot_cloak_state/state = new
	state.visibility = 255 * (1 - cloak_strength)
	state.cloaked_factors = alist(BF_EVASION = 60 * cloak_strength) //60 at full strength, 30 at half strength.
	L.set_body_effect_state(type, state)
	L.set_body_effect_factors(type, state.cloaked_factors)
	L.set_alpha_source(SRC_ALPHA_ROBOT_CLOAK, state.visibility/255, animate_time = 1 SECOND)
	observe(L, /datum/notice/mob_apply_damage, src, then(PROC_REF(damage_inflicted)))
	observe(L, /datum/notice/robot_item_attack, src, then(PROC_REF(attacked_in_cloak)))

/datum/body_effect/robot_cloak/on_end(mob/living/L, expired)
	L.clear_alpha_source(SRC_ALPHA_ROBOT_CLOAK)
	unobserve(L, /datum/notice/mob_apply_damage, src)
	unobserve(L, /datum/notice/robot_item_attack, src)
	robot_cloak_remove_wibble(L, TRUE)

/datum/body_effect/robot_cloak/on_tick(mob/living/L)
	var/datum/robot_cloak_state/state = L.body_effect_state(type)
	if(L.stat == DEAD || !state)
		L.end_body_effect(type, TRUE)
		return
	if(state.times_hit && ELAPSED_SINCE(src, state.last_hit_time, CLOCK_WORLD) > hit_dissipation) //If we have been hit, but the time has passed, reset the hit counter.
		if(!state.cloaked)
			to_chat(L, span_warning("Your cloak whirrs back to life!"))
		reset_cloak(L, state)

	if(state.cloaked && !state.times_hit) //The !times_hit is here so it doesn't interfere with the animation.
		L.set_alpha_source(SRC_ALPHA_ROBOT_CLOAK, state.visibility/255, animate_time = 1 SECOND)

/datum/body_effect/robot_cloak/proc/damage_inflicted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/source = A.target
	var/datum/notice/mob_apply_damage/event = A
	var/damage = event.damage
	var/datum/robot_cloak_state/state = source.body_effect_state(type)
	if(!state || damage < 5) //weak, don't do anything.
		return
	state.times_hit++
	var/alpha_to_show = CLAMP((source.alpha+(damage*10)), source.alpha, 255) //The more damage we take, the more visible we become.
	flick_cloak(source, alpha_to_show)
	EXPIRY_STAMP(state, last_hit_time, CLOCK_WORLD)
	if(damage >= 50 || state.times_hit >= cloak_durability)
		to_chat(source, span_warning("Your cloak buzzes and fails after sustaining too much damage!!"))
		drop_cloak(source, state)
		robot_cloak_remove_wibble(source, TRUE)

/datum/body_effect/robot_cloak/proc/flick_cloak(mob/living/L, alpha_to_show)
	animate(L, alpha = alpha_to_show, time = 0.1 SECONDS, loop = 0.5 SECONDS)
	// Settle back to the mob's full combined alpha (this cloak's own
	// contribution plus any other concurrently active alpha source), not a
	// raw `visibility`, so we don't clobber another source mid-flourish.
	L.apply_combined_alpha(0.1 SECONDS)
	apply_wibbly_filters(L, 0.5 SECONDS)
	after(L, 0.5 SECONDS, GLOBAL_PROC_REF(robot_cloak_remove_wibble), with = list(L, FALSE))

/datum/body_effect/robot_cloak/proc/attacked_in_cloak(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/source = N.target
	if(!source.get_filter("wibbly-[1]")) //We're not wibbled at the moment.
		var/alpha_to_show = CLAMP((source.alpha+(rand(50,200))), source.alpha, 255) //Become more visible by a significant margin, randomly.
		flick_cloak(source, alpha_to_show)

/proc/robot_cloak_remove_wibble(mob/living/L, instant)
	if(L?.get_filter("wibbly-[1]")) //We just check for the first wibble. If it has one it has them all.
		if(instant)
			remove_wibbly_filters(L)
		else
			remove_wibbly_filters(L, 0.1 SECOND)

/datum/body_effect/robot_cloak/proc/drop_cloak(mob/living/L, datum/robot_cloak_state/state)
	L.clear_alpha_source(SRC_ALPHA_ROBOT_CLOAK)
	state.cloaked = FALSE
	L.set_body_effect_factors(type, null)

/datum/body_effect/robot_cloak/proc/reset_cloak(mob/living/L, datum/robot_cloak_state/state)
	state.times_hit = 0
	state.cloaked = TRUE
	L.set_body_effect_factors(type, state.cloaked_factors)

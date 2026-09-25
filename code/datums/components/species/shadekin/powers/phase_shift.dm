/////////////////////
///  PHASE SHIFT  ///
/////////////////////
// Ported to the ability framework (doc/rewrite/rules.md §5). Every shadekin
// component variant grants this ability (shadekin.dm's shadekin_granted_abilities),
// so every shadekin has it.
//
// Fixes doc/rewrite/fixes.md B13: the legacy verb (git history) spent energy
// and played the phase sound before its final CanPass check, so a failed
// shift could still cost energy, and its watcher count called oviewers() once
// per watcher rather than once overall. Here the framework itself enforces
// "commit only after every requirement passes" (interaction.dm's attempt():
// why_not() must pass in full before pay_cost() runs, and pay_cost() before
// the effect) so the ordering bug can't recur; the cost proc
// (dq_phase_shift_afford) computes the watcher count exactly once per attempt
// and caches the amount to spend, rather than recomputing it (possibly
// differently) when the cost is actually paid.

/obj/effect/temp_visual/shadekin
	randomdir = FALSE
	duration = 5
	icon = 'icons/mob/vore_shadekin.dmi'

/obj/effect/temp_visual/shadekin/phase_in
	icon_state = "tp_in"

/obj/effect/temp_visual/shadekin/phase_out
	icon_state = "tp_out"

/datum/interaction/ability/self/shadekin_phase_shift
	id = ABILITY_ID_SHADEKIN_PHASE_SHIFT
	name = "Phase shift"
	category = ABILITY_CAT_MOVEMENT
	requires = list(
		REQ_CONSCIOUS,
		REQ_ON_TURF,
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_vr, "the VR systems cannot comprehend this power"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_shadekin, "you aren't shadekin"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_phasing, "you are already trying to phase"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_phase_area_allows, "you can't do that here"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_phase_turf_passable, "you can't use that here"),
		REQ_RESOURCE(/mob/living/proc/dq_phase_shift_afford),
	)
	effect = /mob/living/proc/dq_do_phase_shift

/datum/interaction/ability/self/shadekin_phase_shift/applies_to(atom/target)
	if(!..())
		return FALSE
	var/mob/living/L = target
	return L.get_shadekin_component() ? TRUE : FALSE

// pay_cost() is deliberately trivial: phase shift is instant (no duration, no
// tool), and the framework re-checks why_not() again right after pay_cost()
// runs, before the effect. If pay_cost() spent the energy, that second check
// would re-run dq_phase_shift_afford() against the now-lower balance and
// almost always fail it - spending on a check that then blocks itself. So the
// spend happens in the effect (dq_do_phase_shift), which only ever runs once
// every requirement has passed for good.

// ---- Requirement clauses ----

/mob/living/var/tmp/dq_phase_shift_pending_cost = 0

/// TRUE if `actor` has the shadekin component, else a reason.
/mob/living/proc/dq_pred_shadekin(mob/living/actor, atom/target, obj/item/held)
	return actor.get_shadekin_component() ? TRUE : "you aren't shadekin"

/// TRUE if `actor` isn't already mid-phase, else a reason.
/mob/living/proc/dq_pred_not_phasing(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	return !SK.doing_phase || "you are already trying to phase"

/// TRUE unless the current area blocks phase shift (admins bypass), else a reason.
/mob/living/proc/dq_pred_phase_area_allows(mob/living/actor, atom/target, obj/item/held)
	var/area/A = get_area(actor)
	if(check_rights_for(actor.client, R_HOLDER))
		return TRUE
	return !A?.flag_check(AREA_BLOCK_PHASE_SHIFT) || "you can't do that here"

/// TRUE if `actor`'s current turf will let them through, else a reason.
/mob/living/proc/dq_pred_phase_turf_passable(mob/living/actor, atom/target, obj/item/held)
	var/turf/T = get_turf(actor)
	if(!T)
		return "you can't use that here"
	return (T.CanPass(actor, T) && actor.loc == T) || "you can't use that here"

/**
 * Whether `actor` can afford to phase shift, and how much: cheaper in
 * darkness, +15 energy per watcher within 7 tiles. Phasing back IN (out of
 * phase-space) is always free. The watcher count is computed exactly once
 * here (not once per candidate, as the legacy loop's nested oviewers() call
 * did - fixes.md B13) and the resulting cost is cached on the actor so
 * pay_cost() spends precisely the amount that was checked.
 */
/mob/living/proc/dq_phase_shift_afford(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	if(SK.in_phase)
		actor.dq_phase_shift_pending_cost = 0
		return TRUE
	var/turf/T = get_turf(actor)
	var/darkness = 1 - T.get_lumcount() // Brightness in 0.0 to 1.0, inverted

	var/watchers = 0
	// oviewers() is computed once; every mob it returns is also within orange(7).
	// Neither loop uses `as anything`: orange()/oviewers() return every atom
	// type in range, and the type filter (mob/living, obj/machinery/camera)
	// must actually skip the rest, not just cast blindly onto it.
	for(var/mob/living/watcher in oviewers(7, actor))
		if(!ishuman(watcher) && !isrobot(watcher))
			continue
		if(watcher.get_shadekin_component() || watcher.stat || isbelly(watcher.loc))
			continue
		if(ishuman(watcher) && istype(watcher.loc, /obj/item/holder)) // Held humans can't watch.
			continue
		watchers++
	if(SK.camera_counts_as_watcher)
		for(var/obj/machinery/camera/camera in orange(7, actor))
			if(camera.can_use() && (actor in camera.can_see()))
				watchers++

	var/cost = CLAMP(100 / (0.01 + darkness * 2), 50, 80) + 15 * watchers // 1 watcher in full light is free-ish
	actor.dq_phase_shift_pending_cost = cost
	if(SK.shadekin_get_energy() < cost)
		return "not enough energy for that ability"
	return TRUE

// ---- Effect: phase in or out. Runs only once every requirement passed and the cost was paid. ----

/mob/living/proc/dq_do_phase_shift(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return FALSE
	var/turf/T = get_turf(actor)
	if(!T)
		return FALSE
	var/cost = actor.dq_phase_shift_pending_cost
	actor.dq_phase_shift_pending_cost = 0
	if(cost)
		SK.shadekin_adjust_energy(-cost)
	playsound(actor, SK.phase_noise, 75, 1)
	if(SK.in_phase)
		phase_in(T, SK)
	else
		phase_out(T)
	return TRUE

/mob/living/proc/phase_in(turf/T, datum/component/shadekin/SK)
	//In case we're not passed args, do it ourself.
	if(!T)
		T = get_turf(src)
		if(!T)
			return
	if(!SK)
		SK = get_shadekin_component()
		if(!SK)
			return
	if(SK.in_phase)

		// pre-change
		if(!isturf(T)) //Sanity
			return
		forceMove(T)
		var/original_canmove = canmove
		status_set(EFFECT_STUNNED, 0)
		status_set(EFFECT_WEAKENED, 0)
		if(buckled)
			buckled.unbuckle_mob()
		if(pulledby)
			pulledby.stop_pulling()
		stop_pulling()

		// change
		canmove = FALSE
		SK.in_phase = FALSE
		SK.doing_phase = TRUE
		throwpass = FALSE
		name = get_visible_name()
		for(var/obj/belly/B as anything in vore_organs)
			B.escapable = initial(B.escapable)

		//cut_overlays()
		invisibility = initial(invisibility)
		see_invisible = initial(see_invisible)
		incorporeal_move = initial(incorporeal_move)
		density = initial(density)
		can_pull_size = initial(can_pull_size)
		can_pull_mobs = initial(can_pull_mobs)
		dq_clear_hovering(src) // reset to type-default
		update_icon()

		//Cosmetics mostly
		var/obj/effect/temp_visual/shadekin/phase_in/phaseanim = new SK.phase_in_anim(src.loc)
		phaseanim.pixel_y = (src.size_multiplier - 1) * 16 // Pixel shift for the animation placement
		phaseanim.adjust_scale(src.size_multiplier, src.size_multiplier)
		phaseanim.dir = dir
		alpha = 0
		automatic_custom_emote(VISIBLE_MESSAGE,"phases in!")

		addtimer(CALLBACK(src, PROC_REF(shadekin_complete_phase_in), original_canmove, SK), SK.phase_time, TIMER_DELETE_ME)


/mob/living/proc/shadekin_complete_phase_in(original_canmove, datum/component/shadekin/SK)
	canmove = original_canmove
	alpha = initial(alpha)
	remove_modifiers_of_type(/datum/modifier/shadekin_phase_vision)
	remove_modifiers_of_type(/datum/modifier/phased_out)

	//Potential phase-in vore

	if(can_be_drop_pred || can_be_drop_prey) //Toggleable in vore panel
		var/list/potentials = living_mobs(0)
		var/mob/living/our_prey
		if(potentials.len)
			var/mob/living/target = pick(potentials)
			if(can_phase_vore(src, target))
				vore_selected.nom_atom(target)
				to_chat(target, span_vwarning("\The [src] phases in around you, [vore_selected.vore_verb]ing you into their [vore_selected.get_belly_name()]!"))
				to_chat(src, span_vwarning("You phase around [target], [vore_selected.vore_verb]ing them into your [vore_selected.get_belly_name()]!"))
				our_prey = target
			else if(can_phase_vore(target, src))
				our_prey = src
				target.vore_selected.nom_atom(src)
				to_chat(target, span_vwarning("\The [src] phases into you, [target.vore_selected.vore_verb]ing them into your [target.vore_selected.get_belly_name()]!"))
				to_chat(src, span_vwarning("You phase into [target], having them [target.vore_selected.vore_verb] you into their [target.vore_selected.get_belly_name()]!"))
			if(our_prey)
				for(var/obj/item/flashlight/held_lights in our_prey.contents)
					if(istype(held_lights,/obj/item/flashlight/glowstick) ||istype(held_lights,/obj/item/flashlight/flare) ) //No affecting glowsticks or flares...As funny as that is
						continue
					held_lights.on = 0
					held_lights.update_brightness()

	SK.doing_phase = FALSE
	if(SK.flicker_time < 5 || SK.flicker_distance < 5 || SK.flicker_break_chance < 5)
		status_at_least(EFFECT_STUNNED, SK.calculate_stun())
	if(!SK.flicker_time)
		return //Early return. No time, no flickering.
	//Affect nearby lights
	for(var/obj/machinery/light/L in range(SK.flicker_distance, src))
		if(prob(SK.flicker_break_chance))
			addtimer(CALLBACK(L, TYPE_PROC_REF(/obj/machinery/light, broken)), rand(5,25), TIMER_DELETE_ME)
		else
			if(SK.flicker_color)
				L.flicker(SK.flicker_time, SK.flicker_color)
			else
				L.flicker(SK.flicker_time)
	for(var/obj/item/flashlight/flashlights in range(SK.flicker_distance, src)) //Find any flashlights near us and make them flicker too!
		if(istype(flashlights,/obj/item/flashlight/glowstick) ||istype(flashlights,/obj/item/flashlight/flare)) //No affecting glowsticks or flares...As funny as that is
			continue
		flashlights.flicker(SK.flicker_time, SK.flicker_color, TRUE)
	for(var/mob/living/creatures in range(SK.flicker_distance, src))
		if(isbelly(creatures.loc)) //don't flicker anyone that gets nomphed.
			continue
		for(var/obj/item/flashlight/held_lights in creatures.contents)
			if(istype(held_lights,/obj/item/flashlight/glowstick) ||istype(held_lights,/obj/item/flashlight/flare) ) //No affecting glowsticks or flares...As funny as that is
				continue
			held_lights.flicker(SK.flicker_time, SK.flicker_color, TRUE)

/mob/living/proc/phase_out(turf/T)
	var/datum/component/shadekin/SK = get_shadekin_component()
	if(!(SK.in_phase))
		// pre-change
		forceMove(T)
		var/original_canmove = canmove
		status_set(EFFECT_STUNNED, 0)
		status_set(EFFECT_WEAKENED, 0)
		if(buckled)
			buckled.unbuckle_mob()
		if(pulledby)
			pulledby.stop_pulling()
		stop_pulling()
		if(SK.normal_phase && SK.drop_items_on_phase)
			drop_both_hands()
			if(get_equipped_item(SLOT_ID_BACK))
				unEquip(get_equipped_item(SLOT_ID_BACK))

		can_pull_size = 0
		can_pull_mobs = MOB_PULL_NONE
		dq_set_hovering(src, TRUE)
		canmove = FALSE

		// change
		SK.in_phase = TRUE
		SK.doing_phase = TRUE
		throwpass = TRUE
		automatic_custom_emote(VISIBLE_MESSAGE,"phases out!")

		if(real_name) //If we a real name, perfect, let's just set our name to our newfound visible name.
			name = get_visible_name()
		else //If we don't, let's put our real_name as our initial name.
			real_name = initial(name)
			name = get_visible_name()

		for(var/obj/belly/B as anything in vore_organs)
			B.escapable = B_ESCAPABLE_NONE

		var/obj/effect/temp_visual/shadekin/phase_out/phaseanim = new SK.phase_out_anim(src.loc)
		phaseanim.pixel_y = (src.size_multiplier - 1) * 16 // Pixel shift for the animation placement
		phaseanim.adjust_scale(src.size_multiplier, src.size_multiplier)
		phaseanim.dir = dir
		alpha = 0
		add_modifier(/datum/modifier/shadekin_phase_vision)
		if(SK.normal_phase)
			add_modifier(/datum/modifier/phased_out)
		addtimer(CALLBACK(src, PROC_REF(complete_phase_out), original_canmove, SK), SK.phase_time, TIMER_DELETE_ME)


/mob/living/proc/complete_phase_out(original_canmove, datum/component/shadekin/SK)
	invisibility = INVISIBILITY_SHADEKIN
	see_invisible = INVISIBILITY_SHADEKIN
	see_invisible_default = INVISIBILITY_SHADEKIN // Allow seeing phased entities while phased.
	update_icon()
	alpha = 127

	canmove = original_canmove
	incorporeal_move = TRUE
	density = FALSE
	SK.doing_phase = FALSE

/datum/modifier/shadekin_phase_vision
	name = "Shadekin Phase Vision"
	factors = alist(BF_SIGHT_FLAGS = SEE_THRU)

/datum/modifier/phased_out
	name = "Phased Out"
	desc = "You are currently phased out of realspace, and cannot interact with it."
	hidden = TRUE
	//Stops you from using guns. See /obj/item/gun/proc/special_check(var/mob/user)

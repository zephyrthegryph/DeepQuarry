/////////////////////
///  PHASE SHIFT  ///
/////////////////////
// An ability op (the shadekin_phase capability below); every shadekin variant grants it (shadekin.dm's shadekin_capabilities()), so every
// shadekin has it.
//
// Fixes doc/rewrite/fixes.md B13: the legacy verb (git history) spent energy and played the phase sound before its final CanPass check, so a
// failed shift could still cost energy, and its watcher count called oviewers() once per watcher rather than once overall. Here every
// requirement is checked before the effect runs, and the effect alone spends the energy.

/obj/effect/temp_visual/shadekin
	randomdir = FALSE
	duration = 5
	icon = 'icons/mob/vore_shadekin.dmi'

/obj/effect/temp_visual/shadekin/phase_in
	icon_state = "tp_in"

/obj/effect/temp_visual/shadekin/phase_out
	icon_state = "tp_out"

MSG_DEF_SELF(shadekin_ability/not_shadekin, "you aren't shadekin")
MSG_DEF_SELF(shadekin_ability/phase_shifted, "you can't use that while phase shifted")
MSG_DEF_SELF(shadekin_ability/vr, "the VR systems cannot comprehend this power")
MSG_DEF_SELF(shadekin_ability/no_turf, "you can't use that here")
MSG_DEF_SELF(shadekin_ability/low_energy, "not enough energy for that ability")
MSG_DEF_SELF(shadekin_ability/already_phasing, "you are already trying to phase")
MSG_DEF_SELF(shadekin_ability/phase_area, "you can't do that here")

// Every shadekin variant grants this (shadekin.dm's shadekin_capabilities()). The energy is the shadekin state's (shadekin_get_energy(), which
// honours dark_energy_infinite), not a var of the mob, so the cost is checked by a requirement and spent by the effect, once every
// requirement has passed: a refused shift never costs anything (doc/rewrite/fixes.md B13). The watcher count is computed by phase_shift_cost() alone.
CAPABILITY_DEF(shadekin_phase, CAP_SHADEKIN_PHASE, key = NONE)

/datum/capability/def/shadekin_phase/entries()
	return list(
		op("shift", label("Phase shift"), menu(button = "Phase shift", bind = "ability_shadekin_phase_shift"),
			needs(req_self(), req_conscious(),
				req(TYPE_PROC_REF(/mob/living, ability_on_turf), because = MSG(shadekin_ability/no_turf)),
				req(TYPE_PROC_REF(/mob/living, ability_not_in_vr), because = MSG(shadekin_ability/vr)),
				req(TYPE_PROC_REF(/mob/living, ability_is_shadekin), because = MSG(shadekin_ability/not_shadekin)),
				req(TYPE_PROC_REF(/mob/living, ability_not_phasing), because = MSG(shadekin_ability/already_phasing)),
				req(TYPE_PROC_REF(/mob/living, ability_phase_area_allows), because = MSG(shadekin_ability/phase_area)),
				req(TYPE_PROC_REF(/mob/living, ability_phase_turf_passable), because = MSG(shadekin_ability/no_turf)),
				req(TYPE_PROC_REF(/mob/living, ability_phase_shift_affordable), because = MSG(shadekin_ability/low_energy))),
			then(TYPE_PROC_REF(/mob/living, ability_phase_shift))))

// ---- Requirement helpers shared by the shadekin powers ----

/// TRUE if the actor is standing on a real turf.
/mob/living/proc/ability_on_turf(datum/act/op/A)
	return !!get_turf(src)

/// TRUE unless the actor is in a VR simulation. VR can't run most shadekin abilities (comp_helpers.dm's special_considerations()).
/mob/living/proc/ability_not_in_vr(datum/act/op/A)
	return !istype(get_area(src), /area/vr)

/// TRUE if the actor has shadekin state.
/mob/living/proc/ability_is_shadekin(datum/act/op/A)
	return !!get_shadekin_state()

/// TRUE if the actor is a shadekin and is not phased out.
/mob/living/proc/ability_not_shifted(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return !!SK && !SK.in_phase

/// TRUE if the actor isn't already mid-phase.
/mob/living/proc/ability_not_phasing(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return !!SK && !SK.doing_phase

/// TRUE unless the current area blocks phase shift (admins bypass).
/mob/living/proc/ability_phase_area_allows(datum/act/op/A)
	var/area/area_here = get_area(src)
	if(check_rights_for(client, R_HOLDER))
		return TRUE
	return !area_here?.flag_check(AREA_BLOCK_PHASE_SHIFT)

/// TRUE if the actor's current turf will let them through.
/mob/living/proc/ability_phase_turf_passable(datum/act/op/A)
	var/turf/T = get_turf(src)
	if(!T)
		return FALSE
	return T.CanPass(src, T) && loc == T

/**
 * What a phase shift costs the actor now: cheaper in darkness, +15 energy per watcher within 7 tiles. Phasing back IN (out of
 * phase-space) is always free. The watcher count is computed exactly once per call (fixes.md B13).
 */
/mob/living/proc/phase_shift_cost(datum/shadekin/SK)
	if(SK.in_phase)
		return 0
	var/turf/T = get_turf(src)
	if(!T)
		return 0
	var/darkness = 1 - T.get_lumcount() // Brightness in 0.0 to 1.0, inverted

	var/watchers = 0
	// oviewers() is computed once; every mob it returns is also within orange(7).
	// Neither loop uses `as anything`: orange()/oviewers() return every atom
	// type in range, and the type filter (mob/living, obj/machinery/camera)
	// must actually skip the rest, not just cast blindly onto it.
	for(var/mob/living/watcher in oviewers(7, src))
		if(!ishuman(watcher) && !isrobot(watcher))
			continue
		if(watcher.get_shadekin_state() || watcher.stat || isbelly(watcher.loc))
			continue
		if(ishuman(watcher) && istype(watcher.loc, /obj/item/holder)) // Held humans can't watch.
			continue
		watchers++
	if(SK.camera_counts_as_watcher)
		for(var/obj/machinery/camera/camera in orange(7, src))
			if(camera.can_use() && (src in camera.can_see()))
				watchers++

	return CLAMP(100 / (0.01 + darkness * 2), 50, 80) + 15 * watchers // 1 watcher in full light is free-ish

/mob/living/proc/ability_phase_shift_affordable(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return FALSE
	return SK.shadekin_get_energy() >= phase_shift_cost(SK)

// ---- Effect: phase in or out. Runs only once every requirement passed. ----

/mob/living/proc/ability_phase_shift(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return OP_FAILED
	var/turf/T = get_turf(src)
	if(!T)
		return OP_FAILED
	var/cost = phase_shift_cost(SK)
	if(cost)
		SK.shadekin_adjust_energy(-cost)
	playsound(src, SK.phase_noise, 75, 1)
	if(SK.in_phase)
		phase_in(T, SK)
	else
		phase_out(T)
	return OP_OK

/mob/living/proc/phase_in(turf/T, datum/shadekin/SK)
	//In case we're not passed args, do it ourself.
	if(!T)
		T = get_turf(src)
		if(!T)
			return
	if(!SK)
		SK = get_shadekin_state()
		if(!SK)
			return
	if(SK.in_phase)

		// pre-change
		if(!isturf(T)) //Sanity
			return
		forceMove(T)
		var/original_canmove = canmove
		status_set(STAT_STUNNED, 0)
		status_set(STAT_WEAKENED, 0)
		var/obj/buckled = src?.buckled_to()
		if(buckled)
			buckled.unbuckle_mob()
		var/mob/pulledby = src?.pulled_by_mob()
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

		invisibility = initial(invisibility)
		see_invisible = initial(see_invisible)
		incorporeal_move = initial(incorporeal_move)
		set_density(initial(density))
		can_pull_size = initial(can_pull_size)
		can_pull_mobs = initial(can_pull_mobs)
		dq_clear_hovering(src) // reset to type-default

		//Cosmetics mostly
		var/obj/effect/temp_visual/shadekin/phase_in/phaseanim = new SK.phase_in_anim(src.loc)
		phaseanim.pixel_y = (src.size_multiplier - 1) * 16 // Pixel shift for the animation placement
		phaseanim.adjust_scale(src.size_multiplier, src.size_multiplier)
		phaseanim.dir = dir
		alpha = 0
		automatic_custom_emote(VISIBLE_MESSAGE,"phases in!")

		after(src, SK.phase_time, PROC_REF(shadekin_complete_phase_in), with = list(original_canmove, SK))


/mob/living/proc/shadekin_complete_phase_in(original_canmove, datum/shadekin/SK)
	canmove = original_canmove
	alpha = initial(alpha)
	remove_body_effect(/datum/body_effect/shadekin_phase_vision)
	remove_body_effect(/datum/body_effect/phased_out)

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
				for(var/obj/item/flashlight/held_lights in contents_of(our_prey))
					if(istype(held_lights,/obj/item/flashlight/glowstick) ||istype(held_lights,/obj/item/flashlight/flare) ) //No affecting glowsticks or flares...As funny as that is
						continue
					held_lights.set_on(0)
					held_lights.update_brightness()

	if(!SK)
		return
	SK.doing_phase = FALSE
	if(SK.flicker_time < 5 || SK.flicker_distance < 5 || SK.flicker_break_chance < 5)
		status_at_least(STAT_STUNNED, SK.calculate_stun())
	if(!SK.flicker_time)
		return //Early return. No time, no flickering.
	//Affect nearby lights
	for(var/obj/machinery/light/L in range(SK.flicker_distance, src))
		if(prob(SK.flicker_break_chance))
			after(L, rand(0.5 SECONDS, 2.5 SECONDS), TYPE_PROC_REF(/obj/machinery/light, broken))
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
		for(var/obj/item/flashlight/held_lights in contents_of(creatures))
			if(istype(held_lights,/obj/item/flashlight/glowstick) ||istype(held_lights,/obj/item/flashlight/flare) ) //No affecting glowsticks or flares...As funny as that is
				continue
			held_lights.flicker(SK.flicker_time, SK.flicker_color, TRUE)

/mob/living/proc/phase_out(turf/T)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!(SK.in_phase))
		// pre-change
		forceMove(T)
		var/original_canmove = canmove
		status_set(STAT_STUNNED, 0)
		status_set(STAT_WEAKENED, 0)
		var/obj/buckled = src?.buckled_to()
		if(buckled)
			buckled.unbuckle_mob()
		var/mob/pulledby = src?.pulled_by_mob()
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
		apply_body_effect(/datum/body_effect/shadekin_phase_vision)
		if(SK.normal_phase)
			apply_body_effect(/datum/body_effect/phased_out)
		after(src, SK.phase_time, PROC_REF(complete_phase_out), with = list(original_canmove, SK), keeps_dead = TRUE)


/mob/living/proc/complete_phase_out(original_canmove, datum/shadekin/SK)
	invisibility = INVISIBILITY_SHADEKIN
	see_invisible = INVISIBILITY_SHADEKIN
	set_see_invisible_default(INVISIBILITY_SHADEKIN) // Allow seeing phased entities while phased.
	alpha = 127

	canmove = original_canmove
	incorporeal_move = TRUE
	set_density(FALSE)
	if(SK)
		SK.doing_phase = FALSE

/datum/body_effect/shadekin_phase_vision
	stacks = MODIFIER_STACK_FORBID
	name = "Shadekin Phase Vision"
	factors = alist(BF_SIGHT_FLAGS = SEE_THRU)

/datum/body_effect/phased_out
	stacks = MODIFIER_STACK_FORBID
	name = "Phased Out"
	desc = "You are currently phased out of realspace, and cannot interact with it."
	hidden = TRUE
	//Stops you from using guns. See /obj/item/gun/proc/special_check(var/mob/user)

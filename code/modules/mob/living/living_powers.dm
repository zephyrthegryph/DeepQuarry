/mob/living/proc/reveal(silent, message = span_warning("You have been revealed! You are no longer hidden."))
	if(status_flags & HIDING)
		set_status_flags(status_flags & ~HIDING)
		reset_plane_and_layer()
		if(!silent && message)
			to_chat(src, message)

/mob/living/proc/hide()
	set name = "Hide"
	set desc = "Allows to hide beneath tables or certain items. Toggled on or off."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(stat == DEAD || has_status(STAT_PARALYZED) || has_status(STAT_WEAKENED) || has_status(STAT_STUNNED) || restrained() || src?.buckled_to() || LAZYLEN(src?.grabbed_by_list()) || has_buckled_mobs()) //VORE EDIT: Check for has_buckled_mobs() (taur riding)
		return

	if(status_flags & HIDING)
		reveal(FALSE, span_notice("You have stopped hiding."))
	else
		set_status_flags(status_flags | HIDING)
		layer = HIDING_LAYER //Just above cables with their 2.44
		plane = OBJ_PLANE
		to_chat(src,span_notice("You are now hiding."))

/mob/living/proc/toggle_selfsurgery()
	set name = "Allow Self Surgery"
	set desc = "Toggles the 'safeties' on self-surgery, allowing you to do so."
	set category = VERB_CAT_OBJECT

	allow_self_surgery = !allow_self_surgery

	to_chat(src, span_notice("You will [allow_self_surgery ? "now" : "no longer"] attempt to operate upon yourself."))
	log_admin("DEBUG \[[world.timeofday]\]: [src.ckey ? "[src.name]:([src.ckey])" : "[src.name]"] has [allow_self_surgery ? "Enabled" : "Disabled"] self surgery.")

/mob/living/proc/toggle_patting_defence()
	set name = "Toggle Reflexive Biting"
	set desc = "Toggles the automatic biting for if someone pats you on the head or boops your nose."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(touch_reaction_flags & SPECIES_TRAIT_PATTING_DEFENCE)
		touch_reaction_flags &= ~(SPECIES_TRAIT_PATTING_DEFENCE)
		to_chat(src,span_notice("You will no longer bite hands who pat or boop you."))
	else
		touch_reaction_flags |= SPECIES_TRAIT_PATTING_DEFENCE
		to_chat(src,span_notice("You will now bite hands who pat or boop you."))

/mob/living/proc/toggle_personal_space()
	set name = "Toggle Personal Space"
	set desc = "Toggles dodging any attempts to hug or pat you."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(touch_reaction_flags & SPECIES_TRAIT_PERSONAL_BUBBLE)
		touch_reaction_flags &= ~(SPECIES_TRAIT_PERSONAL_BUBBLE)
		to_chat(src,span_notice("You will no longer dodge all attempts at hugging, patting, booping, licking, smelling and hand shaking."))
	else
		touch_reaction_flags |= SPECIES_TRAIT_PERSONAL_BUBBLE
		to_chat(src,span_notice("You will now dodge all attempts at hugging, patting, booping, licking, smelling and hand shaking."))

/mob/living/proc/toggle_pickup_dodge()
	set name = "Toggle Pickup Dodge"
	set desc = "Toggles dodging any attempts to pick you up."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(touch_reaction_flags & SPECIES_TRAIT_PICKUP_DODGE)
		touch_reaction_flags &= ~(SPECIES_TRAIT_PICKUP_DODGE)
		to_chat(src, span_notice("You will no longer dodge pickup attempts."))
		return
	touch_reaction_flags |= SPECIES_TRAIT_PICKUP_DODGE
	to_chat(src, span_notice("You will now dodge pickup attempts."))

/mob/living/proc/toggle_thorns()
	set name = "Toggle Thorns"
	set desc = "Toggles defensive thorns across your body."
	set category = VERB_CAT_ABILITIES_GENERAL

	if(touch_reaction_flags & SPECIES_TRAIT_THORNS)
		touch_reaction_flags &= ~(SPECIES_TRAIT_THORNS)
		to_chat(src,span_notice("You will no longer be covered in defensive thorns."))
	else
		touch_reaction_flags |= SPECIES_TRAIT_THORNS
		to_chat(src,span_notice("You will now be covered in defensive thorns that may hurt those who touch you."))

/mob/living/proc/toggle_sparkles()
	set name = "Toggle Sparkles"
	set desc = "Toggle fancy glowing sparkles!"
	set category = VERB_CAT_ABILITIES_SPARKLEDOG

	if(!glow_toggle)
		set_glow_range(3)
		set_glow_intensity(2)
		set_glow_color("#FFFFFF")
		set_glow_toggle(TRUE)
		apply_body_effect(/datum/body_effect/sparkle, null, src)
	else
		set_glow_toggle(FALSE)

/datum/body_effect/sparkle
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = "sparkling"
	desc = "You are sparkling, woo!"
	mob_overlay_state = "cyan_sparkles"
	on_created_text = span_notice("You begin to sparkle!")
	on_expired_text = span_notice("Your sparkling fades away...")

/datum/body_effect/sparkle/on_tick(mob/living/L)
	if(!L.glow_toggle || L.stat)
		L.end_body_effect(type)

/mob/living/proc/healing_rainbows()
	set name = "Firin Mah Lazor"
	set desc = "Fire a glowing beam of rainbows at another person to heal them!"
	set category = VERB_CAT_ABILITIES_SPARKLEDOG

	if(src.stat)
		to_chat(src, span_warning("You can't vomit rainbows in this condition!"))

	var/list/targets = list()
	for(var/mob/living/carbon/human/M in oview(7,src))
		if(M.z != src.z || get_dist(src,M) > 7)
			continue
		if(src == M)
			continue
		targets |= M

	if(!targets)
		to_chat(src, span_warning("There is nobody next to you."))
		return

	open_request(src, /datum/prompt/choice/rainbow_target, PROC_REF(rainbow_target_chosen), answerer = src, choices = targets)
	return TRUE

/// Re-checked on the answer: still conscious, and next to the one picked.
/datum/prompt/choice/rainbow_target
	title = "Rainbow"
	question = "Who do you wish to shoot rainbows at?"
	timeout = 0
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/rainbow_target/recheck_extra()
	. = ..()
	if(.)
		return
	if(isnull(value))
		return null
	var/mob/living/carbon/human/selected = value
	if(!istype(selected) || QDELETED(selected) || QDELETED(answerer))
		return "gone"
	return answerer.Adjacent(selected) ? null : "too far away"

/mob/living/proc/rainbow_target_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return apply_rainbow_target_chosen(A)

/mob/living/proc/apply_rainbow_target_chosen(datum/act/request/A)
	var/mob/living/carbon/human/chosen_target = A.answer.value

	act_message(src, null, others = span_warning("%U% begins chargin' their lazor!"))
	task_timed(src, 5 SECONDS, target = chosen_target, receiver = src, on_done = PROC_REF(healing_rainbows_living_done), done_args = list(chosen_target))
	return TRUE

/mob/living/proc/healing_rainbows_living_done(mob/living/carbon/human/chosen_target)
	if(chosen_target.z != src.z || get_dist(src,chosen_target) > 7)
		return
	act_message(src, chosen_target, others = span_warning("%U% fires their lazor at %T%!"))
	var/obj/item/projectile/P = new /obj/item/projectile/beam/sparkledog(get_turf(src))
	play_sfx(src, SFX_WEAPONS_SPARKLE)
	P.launch_projectile(chosen_target, BP_TORSO, src)

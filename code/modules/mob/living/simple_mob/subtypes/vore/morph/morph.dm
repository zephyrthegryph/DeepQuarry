#define MORPH_COOLDOWN 50

/mob/living/simple_mob/vore/morph
	name = "morph"
	real_name = "morph"
	desc = "A revolting, pulsating pile of flesh."
	tt_desc = "morphus shapeshiftus"
	icon = 'icons/mob/animal_vr.dmi'
	icon_state = "new_morph"
	icon_living = "new_morph"
	icon_dead = "new_morph_dead"
	icon_rest = null
	color = "#658a62"
	movement_cooldown = -1
	status_flags = CANPUSH
	pass_flags = PASSTABLE
	mob_bump_flag = SLIME

	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0

	minbodytemp = 0
	endurance = 50
	taser_kill = TRUE
	melee_damage_lower = 15
	melee_damage_upper = 20
	see_in_dark = 8

	response_help = "touches"
	response_disarm = "pushes"
	response_harm = "hits"
	attacktext = "glomped"
	attack_sound = SFX_EFFECTS_BLOBATTACK

	meat_amount = 0

	vore_active = 1
	vore_default_mode = DM_HOLD

	var/morphed = FALSE
	var/tooltip = TRUE
	var/melee_damage_disguised = 0
	var/eat_while_disguised = FALSE
	var/atom/movable/form = null
	var/morph_time = 0
	var/our_size_multiplier = 1
	/// The morph's own mind while it wears a prey's body.
	var/datum/mind/original_mind
	var/chosen_color
	var/static/list/blacklist_typecache = typecacheof(list(
	/atom/movable/screen,
	/obj/singularity,
	/mob/living/simple_mob/vore/morph,
	/obj/effect))

CAPABILITIES(/mob/living/simple_mob/vore/morph)
	immune_to_incapacitation()
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/simple_mob/vore/morph/proc/take_over_prey)
	verb_entry(/mob/living/simple_mob/vore/morph/proc/morph_color)

CAPABILITIES(/mob/living/simple_mob/vore/morph/dominated_prey)
	verb_entry(/mob/living/simple_mob/vore/morph/proc/morph_color, hidden = TRUE)
	param(nameof(prey_mind), pos = 1)
	param(nameof(parent_morph), pos = 2)
	param(nameof(prey_body), pos = 3, apply = PROC_REF(swap_made))
	after_init(0, then(PROC_REF(end_if_no_prey)))

/// A node made with no prey ends when its init is complete: ending it from the param's apply would delete it while the init above it still writes owned refs.
/mob/living/simple_mob/vore/morph/dominated_prey/proc/end_if_no_prey(datum/act/timer/A)
	if(!prey_mind)
		spent(src)

/mob/living/simple_mob/vore/morph/proc/allowed(atom/movable/A)
	return !is_type_in_typecache(A, blacklist_typecache) && (isobj(A) || ismob(A))

/mob/living/simple_mob/vore/morph/examine(mob/user)
	if(morphed)
		. = form.examine(user)
		if(get_dist(user, src) <= 3 && !resting)
			. += span_warning("[form] doesn't look quite right...")
	else
		. = ..()

/mob/living/simple_mob/vore/morph/action_inspect(atom/movable/A)
	if(Adjacent(A))
		if(COOLDOWN_FINISHED(src, morph_time) && !stat)
			if(A == src)
				restore()
				return
			if(istype(A) && allowed(A))
				assume(A)
		else
			to_chat(src, span_warning("Your chameleon skin is still repairing itself!"))
	else
		..()

/mob/living/simple_mob/vore/morph/proc/assume(atom/movable/target)
	var/mob/living/carbon/human/humantarget = target
	if(istype(humantarget) && !humantarget.allow_mimicry)
		to_chat(src, span_warning("[target] cannot be impersonated!"))
		return
	if(morphed)
		to_chat(src, span_warning("You must restore to your original form first!"))
		return
	set_morphed(TRUE)
	rel_set(src, nameof(form), target)

	act_message(src, target, null, MSG_OTHERS(span_warning("%U% suddenly twists and changes shape, becoming a copy of %T%!")))
	color = null
	name = target.name
	desc = target.desc
	icon = target.icon
	icon_state = target.icon_state
	alpha = max(target.alpha, 150)
	copy_overlays(target, TRUE)
	our_size_multiplier = size_multiplier

	pixel_x = initial(target.pixel_x)
	pixel_y = initial(target.pixel_y)

	set_density(target.density)

	if(isobj(target))
		size_multiplier = 1
		icon_scale_x = target.icon_scale_x
		icon_scale_y = target.icon_scale_y
		update_transform()

	else if(ismob(target))
		var/mob/living/M = target
		resize(M.size_multiplier, ignore_prefs = TRUE)

	//Morphed is weaker
	melee_damage_lower = melee_damage_disguised
	melee_damage_upper = melee_damage_disguised
	movement_cooldown = 1

	COOLDOWN_START(src, morph_time, MORPH_COOLDOWN)

	return

/mob/living/simple_mob/vore/morph/proc/restore(silent = FALSE)
	if(!morphed)
		to_chat(src, span_warning("You're already in your normal form!"))
		return
	set_morphed(FALSE)

	if(!silent)
		act_message(src, null, null, MSG_OTHERS(span_warning("%U% suddenly collapses in on itself, dissolving into a pile of flesh!")))

	rel_clear(src, nameof(form))
	name = initial(name)
	desc = initial(desc)

	icon = initial(icon)
	icon_state = initial(icon_state)

	alpha = initial(alpha)
	if(chosen_color)
		color = chosen_color
	else
		color = initial(color)
	plane = initial(plane)
	layer = initial(layer)

	pixel_x = initial(pixel_x)
	pixel_y = initial(pixel_y)
	icon_scale_x = initial(icon_scale_x)
	icon_scale_y = initial(icon_scale_y)

	set_density(initial(density))

	cut_overlays(TRUE) //ALL of zem

	maptext = null

	size_multiplier = our_size_multiplier
	resize(size_multiplier, ignore_prefs = TRUE)

	//Baseline stats
	melee_damage_lower = initial(melee_damage_lower)
	melee_damage_upper = initial(melee_damage_upper)
	movement_cooldown = initial(movement_cooldown)

	COOLDOWN_START(src, morph_time, MORPH_COOLDOWN)

/mob/living/simple_mob/vore/morph/on_death(gibbed)
	if(morphed)
		act_message(src, null, null, MSG_OTHERS(span_warning("%U% twists and dissolves into a pile of flesh!")))
		restore(TRUE)
	..()

/mob/living/simple_mob/vore/morph/will_show_tooltip()
	return (!morphed)

/mob/living/simple_mob/vore/morph/resize(new_size, animate = TRUE, uncapped = FALSE, ignore_prefs = FALSE, aura_animation = FALSE, allow_stripping = FALSE) // Disable aura_animation. Too expensive for something you can't even see.
	if(morphed && !ismob(form))
		return
	return ..()

/mob/living/simple_mob/vore/morph/lay_down()
	if(morphed)
		var/temp_state = icon_state
		..()
		icon_state = temp_state
		//Stolen from protean blobs, ambush noms from resting! Doesn't hide you any better, but makes noms sneakier.
		if(resting)
			plane = ABOVE_OBJ_PLANE
			to_chat(src,span_notice("Your form settles in, appearing more 'normal'... laying in wait."))
		else
			plane = MOB_PLANE
			to_chat(src,span_notice("Your form quivers back to life, allowing you to move again!"))
			if(can_be_drop_pred) //Toggleable in vore panel
				var/list/potentials = living_mobs(0)
				if(potentials.len)
					var/mob/living/target = pick(potentials)
					if(can_spontaneous_vore(src, target))
						if(target?.buckled_to())
							var/atom/movable/_tmp_buck_27 = target?.buckled_to()
							_tmp_buck_27.unbuckle_mob(target, force = TRUE)
						vore_selected.nom_atom(target)
						to_chat(target,span_vwarning("\The [src] quickly engulfs you, [vore_selected.vore_verb]ing you into their [vore_selected.get_belly_name()]!"))
	else
		..()

TRACKED(/mob/living/simple_mob/vore/morph, morphed)

/// A morphed mob wears its copied form's appearance, so it draws nothing (the look stays untouched); in its own form it is an ordinary simple mob.
/mob/living/simple_mob/vore/morph/draw(datum/look/look)
	if(morphed)
		return
	..()

/mob/living/simple_mob/vore/morph/update_icons()
	if(morphed)
		return
	return ..()

/mob/living/simple_mob/vore/morph/update_transform()
	if(morphed)
		var/matrix/M = matrix()
		M.Scale(icon_scale_x, icon_scale_y)
		M.Turn(icon_rotation)
		src.transform = M
	else
		..()

/mob/living/simple_mob/vore/morph/proc/morph_color()
	set name = "Pick Color"
	set category = VERB_CAT_ABILITIES_SETTINGS
	set desc = "You can set your color!"
	open_request(src, /datum/prompt/color, PROC_REF(morph_color_picked), answerer = src, question = "Choose a color.", default = color, timeout = 0)

/mob/living/simple_mob/vore/morph/proc/morph_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		color = A.answer.value
		chosen_color = A.answer.value

/mob/living/simple_mob/vore/morph/proc/take_over_prey()
	set name = "Take Over Prey"
	set category = VERB_CAT_ABILITIES_MORPH
	set desc = "Take command of your prey's body."
	if(morphed)
		to_chat(src, span_warning("You must restore to your original form first!"))
		return
	var/list/possible_mobs = list()
	for(var/obj/belly/B in src.vore_organs)
		for(var/mob/living/H in B)
			if((ishuman(H) || isrobot(H)) && H.ckey)
				possible_mobs += H
			else
				continue
	var/datum/control_transfer_review/morph_takeover/review = new
	rel_set(review, nameof(review.actor), src)
	review.choices = possible_mobs
	review.start()

/datum/control_transfer_review/morph_takeover
	var/mob/living/prey
	var/prey_selected = FALSE
	var/list/choices

CAPABILITIES(/datum/control_transfer_review/morph_takeover)
	ref_one(nameof(prey), /mob/living)

/datum/prompt/choice/control_transfer_target/morph_takeover
	title = "Take Over Prey"
	question = "Select a mob to take over:"

/datum/control_transfer_review/morph_takeover/why_not()
	. = ..()
	if(.)
		return
	return prey_selected && QDELETED(prey) ? "gone" : null

/datum/control_transfer_review/morph_takeover/start_step(datum/act/request/A)
	open_request(src, /datum/prompt/choice/control_transfer_target/morph_takeover, PROC_REF(target_entered), answerer = actor, asker = actor, choices = choices)

/datum/control_transfer_review/morph_takeover/proc/target_entered(datum/act/request/A)
	if(!A.answer)
		retire()
		return
	run_step(PROC_REF(target_step), A)

/datum/control_transfer_review/morph_takeover/proc/target_step(datum/act/request/A)
	var/mob/living/selected = A.answer.value
	if(!istype(selected) || QDELETED(selected))
		retire()
		return
	rel_set(src, nameof(prey), selected)
	prey_selected = TRUE
	if(QDELETED(prey))
		retire()
		return
	if(!prey.allow_mimicry)
		to_chat(actor, span_warning("\The [prey] cannot be impersonated!"))
		retire()
		return
	ask(PROC_REF(sure_entered), "Take Over Prey", "You selected [prey] to attempt to take over. Are you sure?")

/datum/control_transfer_review/morph_takeover/proc/sure_entered(datum/act/request/A)
	confirmed(A, PROC_REF(offer_step))

/datum/control_transfer_review/morph_takeover/proc/offer_step(datum/act/request/A)
	log_admin("[key_name_admin(actor)] offered [prey] to swap bodies as a morph.")
	ask(PROC_REF(offer_entered), "Allow Morph To Take Over", "\The [actor] has elected to attempt to take over your body and control you. Is this something you will allow to happen?", prey, "declined your request for control.")

/datum/control_transfer_review/morph_takeover/proc/offer_entered(datum/act/request/A)
	confirmed(A, PROC_REF(final_offer_step))

/datum/control_transfer_review/morph_takeover/proc/final_offer_step(datum/act/request/A)
	ask(PROC_REF(final_entered), "Allow Morph To Take Over", "Are you sure? The only way to undo this on your own is to OOC Escape.", prey, "declined your request for control.")

/datum/control_transfer_review/morph_takeover/proc/final_entered(datum/act/request/A)
	confirmed(A, PROC_REF(finish_step))

/datum/control_transfer_review/morph_takeover/proc/finish_step(datum/act/request/A)
	var/mob/living/simple_mob/vore/morph/operator = actor
	operator.take_over_agreed(src)
	retire()

/mob/living/simple_mob/vore/morph/proc/take_over_agreed(datum/control_transfer_review/morph_takeover/seq)
	var/mob/living/L = seq.prey
	if(morphed || !isbelly(L.loc) || L.loc.loc != src)
		return
	var/obj/buckled = src?.buckled_to()
	if(buckled)
		buckled.unbuckle_mob()
	if(L?.buckled_to())
		var/atom/movable/_tmp_buck_28 = L?.buckled_to()
		_tmp_buck_28.unbuckle_mob()
	if(LAZYLEN(src?.buckled_mob_list()))
		for(var/buckledmob in src?.buckled_mob_list())
			riding_datum.force_dismount(buckledmob)
	if(LAZYLEN(L?.buckled_mob_list()))
		for(var/p_buckledmob in L?.buckled_mob_list())
			L.riding_datum.force_dismount(p_buckledmob)
	var/mob/self_puller = src?.pulled_by_mob()
	if(self_puller)
		self_puller.stop_pulling()
	var/mob/L_puller = L?.pulled_by_mob()
	if(L_puller)
		L_puller.stop_pulling()
	stop_pulling()
	rel_set(src, nameof(original_mind), ensure_mind())
	log_and_message_admins("has swapped bodies with [key_name_admin(L)] as a morph at [get_area(src)] - [COORD(src)].", src)
	new /mob/living/simple_mob/vore/morph/dominated_prey(L.vore_selected, L.ensure_mind(), src, L)


/mob/living/simple_mob/vore/morph/dominated_prey
	name = "subservient node"
	color = "#171717"
	digestable = 0
	devourable = 0
	var/mob/living/simple_mob/vore/morph/parent_morph
	var/mob/living/carbon/human/prey_body
	/// The prey's mind, held in this node while the morph wears the prey.
	var/datum/mind/prey_mind
	vore_active = FALSE

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The morph and its prey swap seats.
/mob/living/simple_mob/vore/morph/dominated_prey/proc/swap_made(prey)
	if(!prey_mind)
		return
	prey_body.forceMove(get_turf(parent_morph))
	prey_body.muffled = FALSE
	prey_body.absorbed = FALSE
	set_absorbed(TRUE)
	// Both keep their own identity while in the other's seat.
	move_player_mind(prey_mind, src, "taken over by morph [parent_morph]", share = TRUE)
	move_player_mind(parent_morph.original_mind, prey_body, "morph took over [prey_body]", share = TRUE)
	parent_morph.forceMove(src)
	name = "[prey_body.name]"
	to_chat(prey_body, span_notice("You have completely assumed the form of [prey_body]. Your form is now unable to change anymore until you restore control back to them. You can do this by 'ejecting' them from your [prey_body.vore_selected]. This will not actually release them from your body in this state, but instead return control to them, and restore you to your original form."))

/mob/living/simple_mob/vore/morph/dominated_prey/on_death(gibbed)
	. = ..()
	undo_prey_takeover(FALSE)

/mob/living/simple_mob/vore/morph/dominated_prey/proc/undo_prey_takeover(ooc_escape)
	var/obj/buckled = src?.buckled_to()
	if(buckled)
		buckled.unbuckle_mob()
	if(prey_body?.buckled_to())
		var/atom/movable/_tmp_buck_29 = prey_body?.buckled_to()
		_tmp_buck_29.unbuckle_mob()
	if(LAZYLEN(src?.buckled_mob_list()))
		for(var/buckledmob in src?.buckled_mob_list())
			riding_datum.force_dismount(buckledmob)
	if(LAZYLEN(prey_body?.buckled_mob_list()))
		for(var/p_buckledmob in prey_body?.buckled_mob_list())
			prey_body.riding_datum.force_dismount(p_buckledmob)
	var/mob/self_puller = src?.pulled_by_mob()
	if(self_puller)
		self_puller.stop_pulling()
	var/mob/prey_puller = prey_body?.pulled_by_mob()
	if(prey_puller)
		prey_puller.stop_pulling()
	stop_pulling()

	if(ooc_escape)
		prey_body.forceMove(get_turf(src))
		parent_morph.forceMove(get_turf(src))
		return_bodies()
		log_and_message_admins("used the OOC escape button to get out of [key_name_admin(parent_morph)]. They have been returned to their original bodies. [ADMIN_FLW(src)]", prey_body)
	else
		parent_morph.forceMove(get_turf(prey_body))
		return_bodies()
		parent_morph.vore_selected.nom_atom(prey_body)
		log_and_message_admins("and [key_name_admin(parent_morph)] have been returned to their original bodies. [get_area(src)] - [COORD(src)].", prey_body)
	dissolved(src)

/// Each mind goes home: the morph's into the morph, the prey's into its body.
/mob/living/simple_mob/vore/morph/dominated_prey/proc/return_bodies()
	move_player_mind(parent_morph.original_mind, parent_morph, "morph released [prey_body]")
	move_player_mind(prey_mind, prey_body, "returned to own body from morph [parent_morph]")
	rel_clear(parent_morph, nameof(parent_morph.original_mind))

#undef MORPH_COOLDOWN


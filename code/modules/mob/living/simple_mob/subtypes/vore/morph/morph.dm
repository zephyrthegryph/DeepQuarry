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
	attack_sound = 'sound/effects/blobattack.ogg'

	meat_amount = 0

	showvoreprefs = 0
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

/mob/living/simple_mob/vore/morph/Initialize(mapload)
	add_verb(src, /mob/living/proc/ventcrawl)
	add_verb(src, /mob/living/simple_mob/vore/morph/proc/take_over_prey)
	if(!istype(src, /mob/living/simple_mob/vore/morph/dominated_prey))
		add_verb(src, /mob/living/simple_mob/vore/morph/proc/morph_color)

	return ..()

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
	morphed = TRUE
	form = target

	visible_message(span_warning("[src] suddenly twists and changes shape, becoming a copy of [target]!"))
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

	density = target.density

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
	morphed = FALSE

	if(!silent)
		visible_message(span_warning("[src] suddenly collapses in on itself, dissolving into a pile of flesh!"))

	form = null
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

	density = initial(density)

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
		visible_message(span_warning("[src] twists and dissolves into a pile of flesh!"))
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

/mob/living/simple_mob/vore/morph/update_icon()
	if(morphed)
		return
	return ..()

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
	set category = "Abilities.Settings"
	set desc = "You can set your color!"
	om_ask(src, /datum/om/prompt/color, PROC_REF(morph_color_picked), message = "Choose a color.", default = color)

/mob/living/simple_mob/vore/morph/proc/morph_color_picked(datum/om/prompt/color/ask)
	if(ask.picked_color)
		color = ask.picked_color
		chosen_color = ask.picked_color

/mob/living/simple_mob/vore/morph/proc/take_over_prey()
	set name = "Take Over Prey"
	set category = "Abilities.Morph"
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
	om_ask_sequence(/datum/om/flow/ask_sequence/morph_takeover, src, null, on_done = PROC_REF(take_over_agreed), steps = list(
		new /datum/om/prompt/choice/morph_takeover_target(possible_mobs),
		PROC_REF(take_over_ask_sure),
		PROC_REF(take_over_ask_consent),
		PROC_REF(take_over_ask_consent_again),
	))

/datum/om/flow/ask_sequence/morph_takeover
	/// The answer of the prompt keyed "prey".
	var/mob/living/prey

/datum/om/prompt/choice/morph_takeover_target
	key = "prey"
	title = "Take Over Prey"
	message = "Select a mob to take over:"

/datum/om/prompt/choice/morph_takeover_target/New(list/possible_mobs)
	..()
	choices = possible_mobs

/datum/om/prompt/confirm/morph_takeover_sure
	key = "sure"
	title = "Take Over Prey"
	no_first = TRUE

/// The prey's consent, asked of the prey; a no tells the morph (the asker).
/datum/om/prompt/confirm/morph_takeover_consent
	key = "allow"
	title = "Allow Morph To Take Over"
	no_first = TRUE

/datum/om/prompt/confirm/morph_takeover_consent/prepare()
	message = "\The [asker] has elected to attempt to take over your body and control you. Is this something you will allow to happen?"
	return TRUE

/datum/om/prompt/confirm/morph_takeover_consent/declined()
	to_chat(asker, span_warning("\The [answerer] declined your request for control."))
	..()

/datum/om/prompt/confirm/morph_takeover_consent/again
	key = "allow2"

/datum/om/prompt/confirm/morph_takeover_consent/again/prepare()
	message = "Are you sure? The only way to undo this on your own is to OOC Escape."
	return TRUE

/mob/living/simple_mob/vore/morph/proc/take_over_ask_sure(datum/om/flow/ask_sequence/morph_takeover/seq)
	var/mob/living/L = seq.prey
	if(!L.allow_mimicry)
		to_chat(src, span_warning("\The [L] cannot be impersonated!"))
		return ASK_STOP
	var/datum/om/prompt/confirm/morph_takeover_sure/ask = new
	ask.message = "You selected [L] to attempt to take over. Are you sure?"
	return ask

/mob/living/simple_mob/vore/morph/proc/take_over_ask_consent(datum/om/flow/ask_sequence/morph_takeover/seq)
	var/mob/living/L = seq.prey
	log_admin("[key_name_admin(src)] offered [L] to swap bodies as a morph.")
	var/datum/om/prompt/confirm/morph_takeover_consent/ask = new
	ask.answerer = L
	return ask

/mob/living/simple_mob/vore/morph/proc/take_over_ask_consent_again(datum/om/flow/ask_sequence/morph_takeover/seq)
	var/datum/om/prompt/confirm/morph_takeover_consent/again/ask = new
	ask.answerer = seq.prey
	return ask

/mob/living/simple_mob/vore/morph/proc/take_over_agreed(datum/om/flow/ask_sequence/morph_takeover/seq)
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
	original_mind = ensure_mind()
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

/mob/living/simple_mob/vore/morph/dominated_prey/Initialize(mapload, datum/mind/pmind, parent, prey)
	. = ..()
	if(!pmind)
		return INITIALIZE_HINT_QDEL
	prey_mind = pmind
	parent_morph = parent
	prey_body = prey
	prey_body.forceMove(get_turf(parent_morph))
	prey_body.muffled = FALSE
	prey_body.absorbed = FALSE
	absorbed = TRUE
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
	qdel(src)

/// Each mind goes home: the morph's into the morph, the prey's into its body.
/mob/living/simple_mob/vore/morph/dominated_prey/proc/return_bodies()
	move_player_mind(parent_morph.original_mind, parent_morph, "morph released [prey_body]")
	move_player_mind(prey_mind, prey_body, "returned to own body from morph [parent_morph]")
	parent_morph.original_mind = null

#undef MORPH_COOLDOWN

REF_HELD(/mob/living/simple_mob/vore/morph, list("form", "original_mind"))
REF_HELD(/mob/living/simple_mob/vore/morph/dominated_prey, list("parent_morph", "prey_body", "prey_mind"))

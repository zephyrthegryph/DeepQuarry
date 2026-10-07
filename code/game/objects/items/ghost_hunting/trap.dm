/obj/item/ghost_trap
	name = "spectral trap"
	desc = "A mechanically activated 'ghost trap'."
	description_fluff = "A 'ghost trap' created by Krow Enterprise's Spectral Division. Used by self proclaimed ghost-hunters and \
	paranormal investigators to supposedly capture spirits and specters."
	throw_speed = 5
	throw_range = 7
	gender = PLURAL
	icon = 'icons/obj/ghost_trap.dmi'
	icon_state = "item"
	randpixel = 0
	center_of_mass_x = 0
	center_of_mass_y = 0
	throwforce = 0
	w_class = ITEMSIZE_NORMAL
	var/deployed = FALSE
	var/obj/item/radio/intercom/science/ghost_reporter

CAPABILITIES(/obj/item/ghost_trap)
	// Watches its catch every 2 s while it holds one; empty, it sleeps.
	every(2 SECONDS, then(PROC_REF(ghost_trap_step)), when = nameof(captured_entity))
	owns_one(nameof(ghost_reporter), /obj/item/radio/intercom/science)
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("self", in_hand(), label("Use"), then(PROC_REF(interaction_self)))
	op("release_occupant_effect", menu(), label("Relase Entity"), needs(req_adjacent(), req_capable()), then(PROC_REF(release_occupant_effect)))
	op("ghost_trap_hidden_vore_effect", menu(), label("Eat Entity"), needs(req_adjacent(), req_capable()), then(PROC_REF(ghost_trap_hidden_vore_effect)))

///The entity we currently have captured (a relation view).
OM_FIELD_VIEW(/obj/item/ghost_trap, mob, captured_entity, CHANGE_EXPLICIT)

/obj/item/ghost_trap/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(ghost_reporter), new /obj/item/radio/intercom/science(null)) // ALLOW(decl): made in nullspace, not in src

	var/static/list/ghost_events = list(
		/datum/notice/world_ghost_captured = TYPE_PROC_REF(/datum/experiment_handler, try_run_spectral_experiment),
		/datum/notice/world_wight_captured = TYPE_PROC_REF(/datum/experiment_handler, try_run_spectral_experiment),
	)

	new /datum/experiment_handler(src, \
		allowed_experiments = list(/datum/experiment/ghost_capture), \
		config_mode = EXPERIMENT_CONFIG_UI, \
		config_flags = EXPERIMENT_CONFIG_ALWAYS_ACTIVE, \
		experiment_events = ghost_events)


// a captured entity is released onto the turf.
/obj/item/ghost_trap/on_destroy(force)
	var/mob/our_entity = captured_entity
	if(our_entity)
		remove_trait(our_entity, TRAIT_NO_TRANSFORM, src)
		our_entity.forceMove(get_turf(src))
	..()

/obj/item/ghost_trap/proc/release_occupant_effect(datum/act/op/A)
	var/mob/user = A.actor
	release_entity(user)

/obj/item/ghost_trap/proc/release_entity(mob/living/user)
	if(!isliving(user)) //no ghosts
		return

	if((user.loc == src))
		to_chat(user, span_warning("You need to be outside \the [src] to do this."))
		return

	if(captured_entity)
		var/mob/our_entity = captured_entity
		if(our_entity && (our_entity.loc == src))
			remove_trait(our_entity, TRAIT_NO_TRANSFORM, src)
			rel_clear(src, nameof(captured_entity))
			our_entity.forceMove(get_turf(src))
			changed(src)
			return

	to_chat(user, span_info("There appears to be nothing in the trap!"))
	return

/obj/item/ghost_trap/draw(datum/look/look)
	..()

	if(deployed)
		look.state("on")
		return

	if(captured_entity)
		var/mob/our_entity = captured_entity
		if(our_entity)
			look.state("item_captured")
			return

		look.state(initial(icon_state))
		return
	look.state(initial(icon_state))

/obj/item/ghost_trap/start_active
	deployed = TRUE

/// Watches its catch every 2 s while it holds one (declared above); empty, it sleeps.
/obj/item/ghost_trap/proc/ghost_trap_step(datum/act/timer/A)
	if(captured_entity)
		var/mob/our_entity = captured_entity
		if(our_entity && our_entity.loc != src)
			remove_trait(our_entity, TRAIT_NO_TRANSFORM, src)
			rel_clear(src, nameof(captured_entity))
			announce_escape(our_entity)
			changed(src)

/obj/item/ghost_trap/proc/announce_escape(mob/our_entity)
	var/area/our_area = get_area(src)
	log_and_message_admins("[our_entity] escaped \the [name] at \the [our_area]", our_entity)
	ghost_reporter.autosay("Attention: Spectral event detected. Captured entity at [our_area] has breached containment.", "Spectral Trap", "Science", using_map.get_map_levels(z))

/obj/item/ghost_trap/proc/can_use(mob/user)
	return (user.IsAdvancedToolUser() && !isAI(user) && !user.stat && !user.restrained())

/// Old attack_self.
/obj/item/ghost_trap/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor

	if(captured_entity)
		var/mob/our_entity = captured_entity
		if(our_entity)
			to_chat(user, "You are unable to use \the [src]! It beeps that it an entity contained inside!")
			return TRUE

	if(!deployed && can_use(user))
		act_message(user, src, MSG_SELF(span_danger("You begin deploying %T%!")), \
			MSG_OTHERS(span_danger("%U% starts to deploy %T%.")))

		task_timed(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(user))
	return TRUE

/obj/item/ghost_trap/proc/attack_self_timed_done(mob/user)
	act_message(user, src, MSG_SELF(span_danger("You have deployed %T%!")), \
		MSG_OTHERS(span_danger("%U% has deployed %T%.")))
	play_sfx(src, SFX_MACHINES_CLICK, 1.4)

	deployed = TRUE
	user.drop_from_inventory(src)
	changed(src)
	set_anchored(TRUE)
	log_and_message_admins("has set up a [name] at \the [get_area(loc)]", user)

/obj/item/ghost_trap/container_resist(mob/living/escapee)
	if(!ismob(escapee))
		return
	visible_message(span_danger("Lights flicker and buzzers beep from \the [src], alerting that a containment breach is imminent!"))
	task_timed(escapee, 2 MINUTES, target = src, receiver = src, on_done = PROC_REF(container_resist_timed_done), done_args = list(escapee))

/obj/item/ghost_trap/proc/container_resist_timed_done(mob/living/escapee)
	remove_trait(escapee, TRAIT_NO_TRANSFORM, src)
	rel_clear(src, nameof(captured_entity))
	escapee.forceMove(get_turf(src))
	announce_escape(escapee)
	visible_message(span_danger("A loud buzzer rings out as \the [src] suddenly opens, alerting that a containment breach has ocurred!"))
	changed(src)

/// Old attack_hand.
/obj/item/ghost_trap/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(has_buckled_mobs() && can_use(user))
		act_message(user, src, MSG_SELF(span_notice("You carefully begin to free something from %T%.")), \
			MSG_OTHERS(span_notice("%U% begins freeing something from %T%.")))
		task_timed(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user))
	else if(deployed && can_use(user))
		act_message(user, src, MSG_SELF(span_notice("You begin deactivate %T%!")), \
			MSG_OTHERS(span_danger("%U% starts to deactivate %T%.")))
		play_sfx(src, SFX_MACHINES_CLICK)

		task_timed(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done2), done_args = list(user))
	else
		return OP_DECLINE
	return TRUE

/obj/item/ghost_trap/proc/attack_hand_timed_done(mob/user)
	act_message(user, src, others = span_notice("Something has been freed from %T% by %U%."))
	for(var/A in src?.buckled_mob_list())
		unbuckle_mob(A)
	set_anchored(FALSE)
	deployed = FALSE
/obj/item/ghost_trap/proc/attack_hand_timed_done2(mob/user)
	act_message(user, src, MSG_SELF(span_notice("You have deactivated %T%!")), \
		MSG_OTHERS(span_danger("%U% has deactivated %T%.")))
	deployed = FALSE
	set_anchored(FALSE)
	changed(src)

/obj/item/ghost_trap/proc/catch_ghost(mob/passing_entity)
	if(!ismob(passing_entity)) //wtf did you do
		return
	rel_set(src, nameof(captured_entity), passing_entity)

	if(isliving(passing_entity))
		var/mob/living/living_entity = passing_entity
		var/datum/shadekin/SK = living_entity.get_shadekin_state()
		living_entity.phase_in(get_turf(src), SK)

	passing_entity.forceMove(src)
	var/area/our_area = get_area(src)
	ghost_reporter.autosay("Attention: Spectral event detected. Trap activated at [our_area.name]", "Spectral Trap", "Science", using_map.get_map_levels(z))
	add_trait(passing_entity, TRAIT_NO_TRANSFORM, src)

	to_chat(passing_entity, span_danger("You feel a sudden sensation pulling you into \the [src]!"))
	if(isobserver(passing_entity))
		to_chat(passing_entity, span_info("((You are incapable of moving or 'jumping' to turf by clicking, but can still escape via teleport or orbit!))"))

	PUBLISH_LEGACY(src, /datum/notice/world_ghost_captured, passing_entity)

/obj/item/ghost_trap/Crossed(atom/movable/AM)

	if(istype(AM, /obj/effect/shadow_wight))
		PUBLISH_LEGACY(src, /datum/notice/world_wight_captured, AM)
		visible_message(span_danger("A flurry of beams shoot into the air from \the [src] and into [AM], capturing and disintegrating it!"))
		return

	if(!ismob(AM)) //Only affects mobs!
		return

	//Ghost catching.
	var/mob/passing_entity = AM
	if(isobserver(passing_entity))
		var/mob/observer/dead/ghost = AM
		if(ghost.admin_ghosted || !ghost.interact_with_world)
			return

	//Catching phasers.
	if(!passing_entity.is_incorporeal())
		return

	if(deployed)
		visible_message(span_danger("A flurry of beams shoot into the air from \the [src]!"))
		SSmotiontracker.ping(src,100) // Clunk!
		catch_ghost(passing_entity)
		deployed = FALSE
		set_anchored(FALSE)
		changed(src)
		log_and_message_admins("has been captured at \the [get_area(loc)] by the [name], last touched by [forensic_data?.get_lastprint()]", passing_entity)

/obj/item/ghost_trap/proc/ghost_trap_hidden_vore_effect(datum/act/op/A)
	var/mob/user = A.actor
	eat_entity(user)

/obj/item/ghost_trap/proc/eat_entity(mob/living/user)
	if(!isliving(user)) //no ghosts
		return

	if((user in contents))
		to_chat(user, span_warning("You need to be inside \the [src] to do this."))
		return

	if(captured_entity)
		var/mob/our_entity = captured_entity
		if(our_entity && (our_entity.loc == src) && our_entity.devourable)
			remove_trait(our_entity, TRAIT_NO_TRANSFORM, src)
			rel_clear(src, nameof(captured_entity))
			user.begin_instant_nom(user, our_entity, user, user.vore_selected)
			return

	to_chat(user, span_info("There appears to be nothing in the trap to eat!"))
	return

/// Old object verbs.

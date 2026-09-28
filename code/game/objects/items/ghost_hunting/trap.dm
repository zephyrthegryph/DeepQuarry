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
	///The entity we currently have captured.
	var/captured_entity
	var/obj/item/radio/intercom/science/ghost_reporter

/obj/item/ghost_trap/Initialize(mapload)
	. = ..()
	if(deployed)
		update_icon()
	ghost_reporter = new(null)

	var/static/list/ghost_events = list(
		/datum/om/event/world_ghost_captured = TYPE_PROC_REF(/datum/experiment_handler, try_run_spectral_experiment),
		/datum/om/event/world_wight_captured = TYPE_PROC_REF(/datum/experiment_handler, try_run_spectral_experiment),
	)

	new /datum/experiment_handler(src, \
		allowed_experiments = list(/datum/experiment/ghost_capture), \
		config_mode = EXPERIMENT_CONFIG_UI, \
		config_flags = EXPERIMENT_CONFIG_ALWAYS_ACTIVE, \
		experiment_events = ghost_events)

REF_OWNED(/obj/item/ghost_trap, "ghost_reporter")

// ALLOW(lifecycle): a captured entity is released onto the turf.
/obj/item/ghost_trap/Destroy()
	var/mob/our_entity = om_resolve(captured_entity)
	if(our_entity)
		REMOVE_TRAIT(our_entity, TRAIT_NO_TRANSFORM, src)
		our_entity.forceMove(get_turf(src))
	. = ..()

/obj/item/ghost_trap/proc/release_occupant_effect(mob/user, obj/item/held, datum/interaction/interaction)
	release_entity(user)

/obj/item/ghost_trap/proc/release_entity(mob/living/user)
	if(!isliving(user)) //no ghosts
		return

	if((user.loc == src))
		to_chat(user, span_warning("You need to be outside \the [src] to do this."))
		return

	if(captured_entity)
		var/mob/our_entity = om_resolve(captured_entity)
		if(our_entity && (our_entity.loc == src))
			REMOVE_TRAIT(our_entity, TRAIT_NO_TRANSFORM, src)
			captured_entity = null
			our_entity.forceMove(get_turf(src))
			update_icon()
			return

	to_chat(user, span_info("There appears to be nothing in the trap!"))
	return

/obj/item/ghost_trap/update_icon()
	..()

	if(deployed)
		icon_state = "on"
		return

	if(captured_entity)
		var/mob/our_entity = om_resolve(captured_entity)
		if(our_entity)
			icon_state = "item_captured"
			return

		icon_state = initial(icon_state)
		return
	icon_state = initial(icon_state)

/obj/item/ghost_trap/start_active
	deployed = TRUE

/// Watches its catch every 2 s while it holds one (catch_ghost() starts it); empty, it sleeps.
/obj/item/ghost_trap/periodic_step()
	if(!captured_entity)
		return PROCESS_KILL
	if(captured_entity)
		var/mob/our_entity = om_resolve(captured_entity)
		if(our_entity && our_entity.loc != src)
			REMOVE_TRAIT(our_entity, TRAIT_NO_TRANSFORM, src)
			captured_entity = null
			announce_escape(our_entity)
			update_icon()

/obj/item/ghost_trap/proc/announce_escape(mob/our_entity)
	var/area/our_area = get_area(src)
	log_and_message_admins("[our_entity] escaped \the [name] at \the [our_area]", our_entity)
	ghost_reporter.autosay("Attention: Spectral event detected. Captured entity at [our_area] has breached containment.", "Spectral Trap", "Science", using_map.get_map_levels(z))

/obj/item/ghost_trap/proc/can_use(mob/user)
	return (user.IsAdvancedToolUser() && !isAI(user) && !user.stat && !user.restrained())

/// Old attack_self.
/obj/item/ghost_trap/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)

	if(captured_entity)
		var/mob/our_entity = om_resolve(captured_entity)
		if(our_entity)
			to_chat(user, "You are unable to use \the [src]! It beeps that it an entity contained inside!")
			return TRUE

	if(!deployed && can_use(user))
		user.visible_message(
			span_danger("[user] starts to deploy \the [src]."),
			span_danger("You begin deploying \the [src]!")
			)

		om_do_after(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(user))
	return TRUE

/obj/item/ghost_trap/proc/attack_self_timed_done(mob/user)
	user.visible_message(
		span_danger("[user] has deployed \the [src]."),
		span_danger("You have deployed \the [src]!")
		)
	playsound(src, 'sound/machines/click.ogg', 70, 1)

	deployed = TRUE
	user.drop_from_inventory(src)
	update_icon()
	anchored = TRUE
	log_and_message_admins("has set up a [name] at \the [get_area(loc)]", user)

/obj/item/ghost_trap/container_resist(mob/living/escapee)
	if(!ismob(escapee))
		return
	visible_message(span_danger("Lights flicker and buzzers beep from \the [src], alerting that a containment breach is imminent!"))
	om_do_after(escapee, 2 MINUTES, target = src, receiver = src, on_done = PROC_REF(container_resist_timed_done), done_args = list(escapee))

/obj/item/ghost_trap/proc/container_resist_timed_done(mob/living/escapee)
	REMOVE_TRAIT(escapee, TRAIT_NO_TRANSFORM, src)
	captured_entity = null
	escapee.forceMove(get_turf(src))
	announce_escape(escapee)
	visible_message(span_danger("A loud buzzer rings out as \the [src] suddenly opens, alerting that a containment breach has ocurred!"))
	update_icon()

DECLARE_INTERACTIONS(/obj/item/ghost_trap, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
)

/// Old attack_hand.
/obj/item/ghost_trap/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(has_buckled_mobs() && can_use(user))
		user.visible_message(
			span_notice("[user] begins freeing something from \the [src]."),
			span_notice("You carefully begin to free something from \the [src]."),
			)
		om_do_after(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user))
	else if(deployed && can_use(user))
		user.visible_message(
			span_danger("[user] starts to deactivate \the [src]."),
			span_notice("You begin deactivate \the [src]!")
			)
		playsound(src, 'sound/machines/click.ogg', 50, 1)

		om_do_after(user, 6 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done2), done_args = list(user))
	else
		return FALSE
	return TRUE

/obj/item/ghost_trap/proc/attack_hand_timed_done(mob/user)
	user.visible_message(span_notice("Something has been freed from \the [src] by [user]."))
	for(var/A in src?.buckled_mob_list())
		unbuckle_mob(A)
	anchored = FALSE
	deployed = FALSE
/obj/item/ghost_trap/proc/attack_hand_timed_done2(mob/user)
	user.visible_message(
		span_danger("[user] has deactivated \the [src]."),
		span_notice("You have deactivated \the [src]!")
		)
	deployed = FALSE
	anchored = FALSE
	update_icon()

/obj/item/ghost_trap/proc/catch_ghost(mob/passing_entity)
	if(!ismob(passing_entity)) //wtf did you do
		return
	captured_entity = om_handle(passing_entity)
	PERIODIC_START(src, PERIODIC_SLOW) // watches for an escape while it holds something

	if(isliving(passing_entity))
		var/mob/living/living_entity = passing_entity
		var/datum/shadekin/SK = living_entity.get_shadekin_state()
		living_entity.phase_in(get_turf(src), SK)

	passing_entity.forceMove(src)
	var/area/our_area = get_area(src)
	ghost_reporter.autosay("Attention: Spectral event detected. Trap activated at [our_area.name]", "Spectral Trap", "Science", using_map.get_map_levels(z))
	ADD_TRAIT(passing_entity, TRAIT_NO_TRANSFORM, src)

	to_chat(passing_entity, span_danger("You feel a sudden sensation pulling you into \the [src]!"))
	if(isobserver(passing_entity))
		to_chat(passing_entity, span_info("((You are incapable of moving or 'jumping' to turf by clicking, but can still escape via teleport or orbit!))"))

	OM_EMIT(src, /datum/om/event/world_ghost_captured, passing_entity)

/obj/item/ghost_trap/Crossed(atom/movable/AM)

	if(istype(AM, /obj/effect/shadow_wight))
		OM_EMIT(src, /datum/om/event/world_wight_captured, AM)
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
		GLOB.motiontracker_service.ping(src,100) // Clunk!
		catch_ghost(passing_entity)
		deployed = FALSE
		anchored = FALSE
		update_icon()
		log_and_message_admins("has been captured at \the [get_area(loc)] by the [name], last touched by [forensic_data?.get_lastprint()]", passing_entity)

/obj/item/ghost_trap/proc/ghost_trap_hidden_vore_effect(mob/user, obj/item/held, datum/interaction/interaction)
	eat_entity(user)

/obj/item/ghost_trap/proc/eat_entity(mob/living/user)
	if(!isliving(user)) //no ghosts
		return

	if((user in contents))
		to_chat(user, span_warning("You need to be inside \the [src] to do this."))
		return

	if(captured_entity)
		var/mob/our_entity = om_resolve(captured_entity)
		if(our_entity && (our_entity.loc == src) && our_entity.devourable)
			REMOVE_TRAIT(our_entity, TRAIT_NO_TRANSFORM, src)
			captured_entity = null
			user.begin_instant_nom(user, our_entity, user, user.vore_selected)
			return

	to_chat(user, span_info("There appears to be nothing in the trap to eat!"))
	return

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/ghost_trap, \
	INTERACT_VERB("Relase Entity", PROC_REF(release_occupant_effect)), \
	INTERACT_VERB("Eat Entity", PROC_REF(ghost_trap_hidden_vore_effect)), \
)

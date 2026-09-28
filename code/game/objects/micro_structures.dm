
/obj/structure/micro_tunnel
	name = "mouse hole"
	desc = "A tiny little hole... where does it go?"
	icon = 'icons/obj/structures/micro_structures.dmi'
	icon_state = "mouse_hole"

	anchored = TRUE
	density = FALSE

	var/random = FALSE //For random tummels- spits the micro out at a random location.
	var/magic = FALSE	//For events and stuff, if true, this tunnel will show up in the list regardless of whether it's in valid range, of if you're in a tunnel with this var, all tunnels of the same faction will show up redardless of range
	micro_target = TRUE

	var/static/non_micro_types = list(
		/mob/living/simple_mob/vore/squirrel,
		/mob/living/simple_mob/vore/alienanimals/catslug,
		/mob/living/simple_mob/vore/morph,
		/mob/living/simple_mob/slime
	)

REGISTRY_MEMBERSHIP(/obj/structure/micro_tunnel, REGISTRY_MICRO_TUNNELS)

/obj/structure/micro_tunnel/Initialize(mapload)
	. = ..()
	if(name == initial(name))
		var/area/our_area = get_area(src)
		name = "[our_area.name] [name]"
	if(pixel_x || pixel_y)
		return
	offset_tunnel()

// ALLOW(lifecycle): the tunnel collapses and spits out the micros inside it.
/obj/structure/micro_tunnel/Destroy()
	visible_message(span_warning("\The [src] collapses!"))
	for(var/mob/thing in src.contents)
		visible_message(span_warning("\The [thing] tumbles out!"))
		thing.forceMove(get_turf(src.loc))
		thing.cancel_camera()

	return ..()

/obj/structure/micro_tunnel/set_dir(new_dir)
	. = ..()
	offset_tunnel()

/obj/structure/micro_tunnel/proc/offset_tunnel()

	pixel_x = 0
	pixel_y = 0

	switch(dir)
		if(1)
			pixel_y = 32
		if(2)
			pixel_y = -32
		if(4)
			pixel_x = 32
		if(8)
			pixel_x = -32

/obj/structure/micro_tunnel/proc/find_destinations()
	var/list/destinations = list()
	var/turf/myturf = get_turf(src.loc)
	var/datum/planet/planet
	for(var/datum/planet/P in SSplanets.planets)
		if(myturf.z in P.expected_z_levels)
			planet = P
	for(var/obj/structure/micro_tunnel/t in REGISTRY_MEMBERS(REGISTRY_MICRO_TUNNELS))
		if(t == src)
			continue
		if(magic || t.magic)
			destinations |= t
			continue
		if(t.z == z)
			destinations |= t
			continue
		var/turf/targetturf = get_turf(t.loc)
		if(planet)
			if(targetturf.z in planet.expected_z_levels)
				destinations |= t
				continue
		var/above = GetAbove(myturf)
		if(above && t.z == z + 1)
			destinations |= t
			continue
		var/below = GetBelow(myturf)
		if(below && t.z == z - 1)
			destinations |= t
	return destinations

/obj/structure/micro_tunnel/attack_hand(mob/living/user)
	tunnel_interact(user)
	return ..()

/obj/structure/micro_tunnel/attack_generic(mob/user, damage, attack_verb)
	tunnel_interact(user)
	return ..()

/obj/structure/micro_tunnel/attack_robot(mob/living/user)
	var/turf/hole = get_turf(src)	//Borgs can click stuff from far away, let's make sure they're next to the hole
	var/turf/borg = get_turf(user)
	if(hole.AdjacentQuick(borg))
		tunnel_interact(user)
		return ..()

/obj/structure/micro_tunnel/proc/tunnel_interact(mob/living/user)
	if(!isliving(user))
		return
	if(user.loc == src)
		var/list/our_options = list("Exit", "Move")

		if(is_type_in_list(user, non_micro_types))
			if(src.contents.len > 1)
				our_options |= "Eat"

		our_options |= "Cancel"

		om_prompt(src, user, list("message" = "It's dark and gloomy in here. What would you like to do?", "title" = "Tunnel", "choices" = our_options, "requires" = list(/datum/om/check/inside_target)), PROC_REF(tunnel_action_chosen))
		return

	if(!can_enter(user))
		if(may_choose_to_enter(user))
			om_prompt(src, user, list("message" = "Would you like to enter the tunnel, or reach inside it?", "title" = "Enter or reach", "choices" = list("Enter","Reach"), "requires" = PROMPT_ADJACENT, "data" = list("dropped" = FALSE)), PROC_REF(enter_or_reach_chosen))
			return
		tunnel_reach(user)
		return

	tunnel_climb(user)
	return TRUE

/obj/structure/micro_tunnel/proc/tunnel_reach(mob/living/user)
	user.visible_message(span_warning("\The [user] reaches into \the [src]. . ."),span_warning("You reach into \the [src]. . ."))
	om_task_start(/datum/om/task/timed/micro_reach/tunnel, user, src)

/obj/structure/micro_tunnel/proc/tunnel_climb(mob/living/user)
	user.visible_message(span_notice("\The [user] begins climbing into \the [src]!"))
	om_do_after(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(tunnel_interact_timed_done2), done_args = list(user), on_fail = PROC_REF(tunnel_interact_timed_failed2), fail_args = list(user))

/obj/structure/micro_tunnel/proc/enter_or_reach_chosen(mob/living/user, choice, datum/om/prompt/ask)
	if(ask.get("dropped"))
		if(choice == "Enter")
			mouse_drop_climb(user)
		return
	if(choice == "Enter")
		tunnel_climb(user)
	else
		tunnel_reach(user)

/obj/structure/micro_tunnel/proc/tunnel_action_chosen(mob/living/user, choice, datum/om/prompt/ask)
	switch(choice)
		if("Exit")
			user.forceMove(get_turf(src.loc))
			user.cancel_camera()
			user.visible_message(span_notice("\The [user] climbs out of \the [src]!"))
		if("Move")
			var/list/destinations = find_destinations()
			if(!destinations.len)
				to_chat(user, span_warning("There are no other tunnels connected to this one!"))
				return
			if(destinations.len == 1 || random)
				tunnel_move_chosen(user, pick(destinations), ask)
				return
			om_prompt_chain(ask, list("kind" = "list", "message" = "Where would you like to go?", "title" = "Pick a tunnel", "choices" = destinations), PROC_REF(tunnel_move_chosen))
		if("Eat")
			var/list/our_targets = list()
			for(var/mob/living/L in src.contents)
				if(L == user)
					continue
				our_targets |= L
			if(!our_targets.len)
				to_chat(user, span_warning("There is no one in here except for you!"))
				return
			if(our_targets.len == 1)
				tunnel_eat_chosen(user, pick(our_targets), ask)
				return
			om_prompt_chain(ask, list("kind" = "list", "message" = "Who would you like to eat?", "title" = "Pick a target to eat", "choices" = our_targets), PROC_REF(tunnel_eat_chosen))

/obj/structure/micro_tunnel/proc/tunnel_move_chosen(mob/living/user, choice, datum/om/prompt/ask)
	to_chat(user,span_notice("You begin moving..."))
	om_do_after(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(tunnel_interact_timed_done), done_args = list(user, choice))

/obj/structure/micro_tunnel/proc/tunnel_eat_chosen(mob/living/user, mob/our_choice, datum/om/prompt/ask)
	if(our_choice.loc != src)
		to_chat(user, span_warning("\The [our_choice] is no longer inside \the [src], and so cannot be eaten."))
		return
	user.feed_grabbed_to_self(user,our_choice)

/obj/structure/micro_tunnel/proc/tunnel_interact_timed_done(mob/living/user, choice)
	user.forceMove(choice)
	user.cancel_camera()
	var/obj/structure/micro_tunnel/da_oddawun = choice
	da_oddawun.tunnel_notify(user)
	return
/obj/structure/micro_tunnel/proc/tunnel_interact_timed_done2(mob/living/user)

	enter_tunnel(user)

/obj/structure/micro_tunnel/proc/tunnel_interact_timed_failed2(mob/living/user)
	to_chat(user, span_warning("You didn't go into \the [src]!"))
	return

/// Reached into the tunnel: pull whatever is inside out.
/obj/structure/micro_tunnel/proc/tunnel_reach_done(datum/om/task/timed/micro_reach/tunnel/task)
	var/mob/living/user = task.actor
	if(!src.contents.len)
		to_chat(user, span_warning("There was nothing inside."))
		user.visible_message(span_notice("\The [user] pulls their hand out of \the [src]."),span_warning("You pull your hand out of \the [src]"))
		return
	var/grabbed = pick(src.contents)
	if(!grabbed)
		to_chat(user, span_warning("There was nothing inside."))
		user.visible_message(span_notice("\The [user] pulls their hand out of \the [src]."),span_warning("You pull your hand out of \the [src]"))
		return

	if(ishuman(user))
		var/mob/living/carbon/human/h = user
		var/mob/living/l = grabbed
		if(isliving(grabbed))
			if(!l.attempt_to_scoop(h))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))

		user.visible_message(span_warning("\The [user] pulls \the [grabbed] out of \the [src]! ! !"))
		return

	else if(isanimal(user))
		var/mob/living/simple_mob/a = user
		var/mob/living/l = grabbed
		if(!a.has_hands || isliving(grabbed))
			if(!l.attempt_to_scoop(a))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))
		user.visible_message(span_warning("\The [user] pulls \the [grabbed] out of \the [src]! ! !"))
		return

/obj/structure/micro_tunnel/proc/can_enter(mob/living/user)
	if(user.mob_size <= MOB_TINY || user.get_effective_size(TRUE) <= micro_accepted_scale)
		return TRUE

	return FALSE

/// Big enough to reach in, but allowed to squeeze inside instead (they're asked which).
/obj/structure/micro_tunnel/proc/may_choose_to_enter(mob/living/user)
	return is_type_in_list(user, non_micro_types)

/obj/structure/micro_tunnel/MouseDrop_T(mob/living/M, mob/living/user)
	. = ..()
	if(M != user)
		return

	if(!can_enter(user))
		if(may_choose_to_enter(user))
			om_prompt(src, user, list("message" = "Would you like to enter the tunnel, or reach inside it?", "title" = "Enter or reach", "choices" = list("Enter","Reach"), "requires" = PROMPT_ADJACENT, "data" = list("dropped" = TRUE)), PROC_REF(enter_or_reach_chosen))
		return

	mouse_drop_climb(M)
	return TRUE

/obj/structure/micro_tunnel/proc/mouse_drop_climb(mob/living/k)
	k.visible_message(span_notice("\The [k] begins climbing into \the [src]!"))
	om_do_after(k, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(MouseDrop_T_timed_done), done_args = list(k), on_fail = PROC_REF(MouseDrop_T_timed_failed), fail_args = list(k))

/obj/structure/micro_tunnel/proc/MouseDrop_T_timed_done(mob/living/k)

	enter_tunnel(k)

/obj/structure/micro_tunnel/proc/MouseDrop_T_timed_failed(mob/living/k)
	to_chat(k, span_warning("You didn't go into \the [src]!"))
	return

/obj/structure/micro_tunnel/proc/enter_tunnel(mob/living/k)
	k.visible_message(span_notice("\The [k] climbs into \the [src]!"))
	k.forceMove(src)
	k.cancel_camera()
	to_chat(k,span_notice("You are inside of \the [src]. It's dark and gloomy inside of here. You can click upon the tunnel to exit, or travel to another tunnel if there are other tunnels linked to it."))
	tunnel_notify(k)

/obj/structure/micro_tunnel/proc/tunnel_notify(mob/living/user)
	to_chat(user, span_notice("You arrive inside \the [src]."))
	var/our_message = "You can see "
	var/found_stuff = FALSE
	for(var/thing in src.contents)
		if(thing == user)
			continue
		found_stuff = TRUE
		our_message = "[our_message] [thing], "
		if(isliving(thing))
			var/mob/living/t = thing
			to_chat(t, span_notice("\The [user] enters \the [src]!"))
	if(found_stuff)
		to_chat(user, span_notice("[our_message]inside of \the [src]!"))
	if(prob(25))
		visible_message(span_warning("Something moves inside of \the [src]. . ."))

/obj/structure/micro_tunnel/magic
	magic = TRUE

/obj/structure/micro_tunnel/random
	random = TRUE

/obj/Initialize(mapload)
	. = ..()
	intern_access_lists()
	if(micro_target)
		verbs += /obj/proc/micro_interact

/obj/proc/micro_action_chosen(mob/living/user, choice, datum/om/prompt/ask)
	switch(choice)
		if("Exit")
			user.forceMove(get_turf(src.loc))
			user.cancel_camera()
			user.visible_message(span_notice("\The [user] climbs out of \the [src]!"))
		if("Move")
			var/list/destinations = list()
			if(istype(src,/obj/structure/micro_tunnel))	//If we're in a tunnel let's also get the tunnel's destinations
				var/obj/structure/micro_tunnel/t = src
				destinations = t.find_destinations()
			var/turf/myturf = get_turf(src.loc)
			for(var/obj/o in range(1,myturf))
				if(o == src)
					continue
				if(o.micro_target)
					destinations |= o
			if(!destinations.len)
				to_chat(user, span_warning("There is nowhere to move to!"))
				return
			if(destinations.len == 1)
				micro_move_chosen(user, pick(destinations), ask)
				return
			om_prompt_chain(ask, list("kind" = "list", "message" = "Where would you like to go?", "title" = "Pick a destination", "choices" = destinations), PROC_REF(micro_move_chosen))

/obj/proc/micro_move_chosen(mob/living/user, choice, datum/om/prompt/ask)
	var/list/contained_mobs = list()
	for(var/mob/living/issamob in src.contents)
		contained_mobs |= issamob
	to_chat(user,span_notice("You begin moving..."))
	om_task_start(/datum/om/task/timed/obj_micro_interact, user, src, contained_mobs = contained_mobs, choice = choice)

/obj/proc/micro_interact()
	set name = "Micro Interact"
	set desc = "Micros can enter, or move between objects with this! Non-micros can reach into objects to search for micros!"
	set category = "Object"
	set src in oview(1)

	if(!isliving(usr))
		return

	var/list/contained_mobs = list()
	for(var/mob/living/issamob in src.contents)
		if(isliving(issamob))
			contained_mobs |= issamob

	if(usr.loc == src)
		om_prompt(src, usr, list("message" = "What would you like to do?", "title" = "[src]", "choices" = list("Exit", "Move", "Cancel"), "requires" = list(/datum/om/check/inside_target)), PROC_REF(micro_action_chosen))
		return

	if(!(usr.mob_size <= MOB_TINY || usr.get_effective_size(TRUE) <= micro_accepted_scale))
		usr.visible_message(span_warning("\The [usr] reaches into \the [src]. . ."),span_warning("You reach into \the [src]. . ."))
		om_task_start(/datum/om/task/timed/micro_reach, usr, src, contained_mobs = contained_mobs)
		return

	usr.visible_message(span_notice("\The [usr] begins climbing into \the [src]!"))
	om_task_start(/datum/om/task/timed/obj_micro_interact2, usr, src, contained_mobs = contained_mobs)
	return TRUE

/// Reaching into something small for whoever is inside.
/datum/om/task/timed/micro_reach
	duration = 3 SECONDS
	complete_proc = /obj/proc/micro_reach_done
	cancel_proc = /obj/proc/micro_reach_failed
	var/list/contained_mobs

/datum/om/task/timed/micro_reach/tunnel
	complete_proc = /obj/structure/micro_tunnel/proc/tunnel_reach_done

/obj/proc/micro_reach_failed(datum/om/task/timed/micro_reach/task)
	var/mob/usr_mob = task.actor
	usr_mob.visible_message(span_notice("\The [usr_mob] pulls their hand out of \the [src]."),span_warning("You pull your hand out of \the [src]"))

/// Reached into the tunnel: pull a random occupant out.
/obj/proc/micro_reach_done(datum/om/task/timed/micro_reach/task)
	var/list/contained_mobs = task.contained_mobs
	var/mob/usr_mob = task.actor

	if(!contained_mobs.len)
		to_chat(usr_mob, span_warning("There was nothing inside."))
		usr_mob.visible_message(span_notice("\The [usr_mob] pulls their hand out of \the [src]."),span_warning("You pull your hand out of \the [src]"))
		return
	var/grabbed = pick(contained_mobs)
	if(!grabbed)
		to_chat(usr_mob, span_warning("There was nothing inside."))
		usr_mob.visible_message(span_notice("\The [usr_mob] pulls their hand out of \the [src]."),span_warning("You pull your hand out of \the [src]"))
		return

	if(ishuman(usr_mob))
		var/mob/living/carbon/human/h = usr_mob
		var/mob/living/l = grabbed
		if(isliving(grabbed))
			l.attempt_to_scoop(h)
			if(!l.attempt_to_scoop(h))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))

		usr_mob.visible_message(span_warning("\The [usr_mob] pulls \the [grabbed] out of \the [src]! ! !"))
		return

	else if(isanimal(usr_mob))
		var/mob/living/simple_mob/a = usr_mob
		var/mob/living/l = grabbed
		if(!a.has_hands || isliving(grabbed))
			if(!l.attempt_to_scoop(a))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))
		usr_mob.visible_message(span_warning("\The [usr_mob] pulls \the [grabbed] out of \the [src]! ! !"))
		return

/datum/om/task/timed/obj_micro_interact
	duration = 10 SECONDS
	complete_proc = /obj/proc/micro_interact_timed_done
	var/list/contained_mobs
	var/choice

/obj/proc/micro_interact_timed_done(datum/om/task/timed/obj_micro_interact/task)
	var/list/contained_mobs = task.contained_mobs
	var/choice = task.choice
	var/mob/usr_mob = task.actor
	if(QDELETED(src))
		return
	if(usr_mob.loc != src)
		return
	var/obj/our_choice = choice

	var/list/new_contained_mobs = list()
	for(var/mob/living/issamob in src.contents)
		if(isliving(issamob))
			contained_mobs |= issamob

	usr_mob.forceMove(our_choice)
	usr_mob.cancel_camera()

	to_chat(usr_mob,span_notice("You are inside of \the [our_choice]. You can click upon the thing you are in to exit, or travel to a nearby thing if there are other tunnels linked to it."))

	var/our_message = "You can see "
	var/found_stuff = FALSE
	for(var/thing in new_contained_mobs)
		if(thing == usr_mob)
			continue
		found_stuff = TRUE
		our_message = "[our_message] [thing], "
		if(isliving(thing))
			var/mob/living/t = thing
			to_chat(t, span_notice("\The [usr_mob] enters \the [src]!"))
	if(found_stuff)
		to_chat(usr_mob, span_notice("[our_message]inside of \the [src]!"))
	if(prob(25))
		our_choice.visible_message(span_warning("Something moves inside of \the [our_choice]. . ."))
	return
/datum/om/task/timed/obj_micro_interact2
	duration = 10 SECONDS
	complete_proc = /obj/proc/micro_interact_timed_done2
	cancel_proc = /obj/proc/micro_interact_timed_failed2
	var/list/contained_mobs

/obj/proc/micro_interact_timed_done2(datum/om/task/timed/obj_micro_interact2/task)
	var/list/contained_mobs = task.contained_mobs
	var/mob/usr_mob = task.actor

	usr_mob.visible_message(span_notice("\The [usr_mob] climbs into \the [src]!"))
	usr_mob.forceMove(src)
	usr_mob.cancel_camera()
	to_chat(usr_mob,span_notice("You are inside of \the [src]. You can click upon the tunnel to exit, or travel to another tunnel if there are other tunnels linked to it."))

	var/our_message = "You can see "
	var/found_stuff = FALSE
	for(var/thing in contained_mobs)
		if(thing == usr_mob)
			continue
		found_stuff = TRUE
		our_message = "[our_message] [thing], "
		if(isliving(thing))
			var/mob/living/t = thing
			to_chat(t, span_notice("\The [usr_mob] enters \the [src]!"))
	if(found_stuff)
		to_chat(usr_mob, span_notice("[our_message]inside of \the [src]!"))
	if(prob(25))
		visible_message(span_warning("Something moves inside of \the [src]. . ."))

/obj/proc/micro_interact_timed_failed2(datum/om/task/timed/obj_micro_interact2/task)
	var/mob/usr_mob = task.actor
	to_chat(usr_mob, span_warning("You didn't go into \the [src]!"))
	return

/obj/effect/mouse_hole_spawner
	name = "mouse hole spawner"
	icon = 'icons/obj/landmark_vr.dmi'
	icon_state = "blue-x"
	invisibility = INVISIBILITY_ABSTRACT

	var/chance_to_spawn = 25

/obj/effect/mouse_hole_spawner/Initialize(mapload)
	. = ..()

	if(prob(chance_to_spawn))
		var/obj/structure/micro_tunnel/tunnel = new (get_turf(src.loc))
		tunnel.set_dir(dir)

	return INITIALIZE_HINT_QDEL

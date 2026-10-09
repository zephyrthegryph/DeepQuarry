
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

TRACKED(/obj/structure/micro_tunnel, random)

CAPABILITIES(/obj/structure/micro_tunnel)
	// outside: climb in, or reach in (a creature that may squeeze in is asked which); a cyborg uses it from beside the hole
	op("use", inputs(hand(), remote()), label("Use"), when(PROC_REF(actor_outside)), needs(req_adjacent()),
		asks(/datum/prompt/choice, fields = list("title" = "Enter or reach", "question" = "Would you like to enter the tunnel, or reach inside it?", "choices" = list("Enter", "Reach"), "buttons" = TRUE, "timeout" = 0), step = "enter_or_reach", when = PROC_REF(asks_enter_or_reach)),
		then(PROC_REF(interaction_hand)))
	// inside: the tunnel's menu, then where to go or whom to eat when there is a choice
	op("inside_use", inside(), label("Use"), when(PROC_REF(actor_inside)),
		asks(/datum/prompt/choice, fields = list("title" = "Tunnel", "question" = "It's dark and gloomy in here. What would you like to do?", "choices" = computed(PROC_REF(inside_choices)), "buttons" = TRUE, "timeout" = 0), step = "action", keeps = TARGET_PRESENT),
		asks(/datum/prompt/choice, fields = list("title" = "Pick a tunnel", "question" = "Where would you like to go?", "choices" = computed(PROC_REF(move_choices)), "timeout" = 0), step = "move_to", keeps = TARGET_PRESENT, when = PROC_REF(picks_destination)),
		asks(/datum/prompt/choice, fields = list("title" = "Pick a target to eat", "question" = "Who would you like to eat?", "choices" = computed(PROC_REF(eat_choices)), "timeout" = 0), step = "eat", keeps = TARGET_PRESENT, when = PROC_REF(picks_meal)),
		then(PROC_REF(tunnel_action_chosen)))
	op("climb_in", item(/mob/living), gesture(GESTURE_DRAG), label("Climb in"), needs(req_bool(PROC_REF(self_drag), silent = TRUE)),
		asks(/datum/prompt/choice, fields = list("title" = "Enter or reach", "question" = "Would you like to enter the tunnel, or reach inside it?", "choices" = list("Enter", "Reach"), "buttons" = TRUE, "timeout" = 0), step = "enter_or_reach", when = PROC_REF(asks_enter_or_reach)),
		then(PROC_REF(interaction_drag)))

/obj/structure/micro_tunnel/Initialize(mapload)
	. = ..()
	if(name == initial(name))
		var/area/our_area = get_area(src)
		name = "[our_area.name] [name]"
	if(pixel_x || pixel_y)
		return
	offset_tunnel()

// the tunnel collapses and spits out the micros inside it.
/obj/structure/micro_tunnel/on_destroy(force)
	visible_message(span_warning("\The [src] collapses!"))
	for(var/mob/thing in contents_of(src))
		visible_message(span_warning("\The [thing] tumbles out!"))
		thing.forceMove(get_turf(src.loc))
		thing.cancel_camera()

	..()

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

/// Old attack_hand (and a cyborg's use beside the hole): inside, the tunnel's menu; outside, climb in when small enough, else reach in (a
/// creature that could squeeze in is asked which). The click goes on afterwards, as the old handler answered FALSE.
/obj/structure/micro_tunnel/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!isliving(user))
		return OP_PASS
	if(micro_tunnel_fits(src, user))
		tunnel_climb(user)
		return OP_PASS
	var/datum/prompt/R = A.step_answers?["enter_or_reach"]
	if(R)
		if(R.value == "Enter")
			tunnel_climb(user)
		else if(R.value == "Reach")
			tunnel_reach(user)
		return OP_PASS
	tunnel_reach(user)
	return OP_PASS

/// Is `user` small enough to climb into `tunnel`?
/proc/micro_tunnel_fits(obj/structure/micro_tunnel/tunnel, mob/living/user)
	READS_FROM() // a body's size is asked when the click lands
	return user.mob_size <= MOB_TINY || user.get_effective_size(TRUE) <= tunnel.micro_accepted_scale

/// A creature too big to fit but allowed to squeeze in (it is asked whether to enter or to reach in).
/proc/micro_tunnel_may_choose(obj/structure/micro_tunnel/tunnel, mob/living/user)
	READS_FROM() // the kinds of creature are fixed
	return !micro_tunnel_fits(tunnel, user) && is_type_in_list(user, tunnel.non_micro_types)

/// Is `user` inside `tunnel`?
/proc/micro_tunnel_holds(obj/structure/micro_tunnel/tunnel, mob/living/user)
	READS_FROM() // where the actor is, asked when the click lands
	return user?.loc == tunnel

/// The creature drags itself onto the hole.
/obj/structure/micro_tunnel/proc/self_drag(datum/act/op/A)
	return A.held == A.actor

/obj/structure/micro_tunnel/proc/actor_outside(datum/act/op/A)
	return !micro_tunnel_holds(src, A.actor)

/obj/structure/micro_tunnel/proc/actor_inside(datum/act/op/A)
	return micro_tunnel_holds(src, A.actor)

/obj/structure/micro_tunnel/proc/asks_enter_or_reach(datum/act/op/A)
	return micro_tunnel_may_choose(src, A.actor)

/// The tunnel's menu from inside: exit, move, and for a bigger creature, eat what else is in here.
/obj/structure/micro_tunnel/proc/inside_choices(datum/act/op/A)
	var/list/our_options = list("Exit", "Move")
	if(is_type_in_list(A.actor, non_micro_types) && contents_count(src) > 1)
		our_options |= "Eat"
	our_options |= "Cancel"
	return our_options

/obj/structure/micro_tunnel/proc/move_choices(datum/act/A)
	return find_destinations()

/obj/structure/micro_tunnel/proc/eat_choices(datum/act/op/A)
	var/list/our_targets = list()
	for(var/mob/living/L in contents_of(src))
		if(L != A.actor)
			our_targets |= L
	return our_targets

/// "Move" with more than one place to go (a random tunnel picks for you).
/obj/structure/micro_tunnel/proc/picks_destination(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["action"]
	return R?.value == "Move" && !random && micro_tunnel_destination_count(src) > 1

/// "Eat" with more than one other creature inside.
/obj/structure/micro_tunnel/proc/picks_meal(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["action"]
	return R?.value == "Eat" && micro_tunnel_other_count(src, A.actor) > 1

/proc/micro_tunnel_destination_count(obj/structure/micro_tunnel/tunnel)
	READS_FROM() // the linked tunnels are looked up when the choice is made
	return length(tunnel.find_destinations())

/proc/micro_tunnel_other_count(obj/structure/micro_tunnel/tunnel, mob/user)
	READS_FROM() // who else is inside is looked up when the choice is made
	. = 0
	for(var/mob/living/L in contents_of(tunnel))
		if(L != user)
			.++

/obj/structure/micro_tunnel/attack_generic(mob/user, damage, attack_verb)
	perform_op(user, src, micro_tunnel_holds(src, user) ? "inside_use" : "use", null, ORIGIN_SYSTEM)
	return ..()

/obj/structure/micro_tunnel/proc/tunnel_reach(mob/living/user)
	act_message(user, src, MSG_SELF(span_warning("You reach into %T%. . .")), MSG_OTHERS(span_warning("%U% reaches into %T%. . .")))
	task_start(/datum/task/timed/micro_reach/tunnel, user, src)

/obj/structure/micro_tunnel/proc/tunnel_climb(mob/living/user)
	act_message(user, src, others = span_notice("%U% begins climbing into %T%!"))
	task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(tunnel_interact_timed_done2), done_args = list(user), on_fail = PROC_REF(tunnel_interact_timed_failed2), fail_args = list(user))

/datum/prompt/choice/tunnel_enter_or_reach
	timeout = 0
	title = "Enter or reach"
	question = "Would you like to enter the tunnel, or reach inside it?"
	choices = list("Enter","Reach")
	buttons = TRUE
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE
	/// Asked from a mouse drop: only entering does anything.
	var/dropped = FALSE

/// From inside: the action picked (and, when there was a choice, where to go or whom to eat).
/obj/structure/micro_tunnel/proc/tunnel_action_chosen(datum/act/op/A)
	var/datum/prompt/R = A.step_answers?["action"]
	if(!R)
		return OP_OK
	var/mob/living/user = A.actor
	switch(R.value)
		if("Exit")
			user.forceMove(get_turf(src.loc))
			user.cancel_camera()
			act_message(user, src, others = span_notice("%U% climbs out of %T%!"))
		if("Move")
			var/list/destinations = find_destinations()
			if(!destinations.len)
				to_chat(user, span_warning("There are no other tunnels connected to this one!"))
				return OP_OK
			var/datum/prompt/where = A.step_answers?["move_to"]
			if(where)
				if(where.value in destinations)
					tunnel_move(user, where.value)
				return OP_OK
			tunnel_move(user, pick(destinations))
		if("Eat")
			var/list/our_targets = list()
			for(var/mob/living/L in contents_of(src))
				if(L == user)
					continue
				our_targets |= L
			if(!our_targets.len)
				to_chat(user, span_warning("There is no one in here except for you!"))
				return OP_OK
			var/datum/prompt/whom = A.step_answers?["eat"]
			if(whom)
				tunnel_eat(user, whom.value)
				return OP_OK
			tunnel_eat(user, pick(our_targets))
	return OP_OK

/obj/structure/micro_tunnel/proc/tunnel_move(mob/living/user, choice)
	to_chat(user,span_notice("You begin moving..."))
	task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(tunnel_interact_timed_done), done_args = list(user, choice))

/obj/structure/micro_tunnel/proc/tunnel_eat(mob/living/user, mob/our_choice)
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
/obj/structure/micro_tunnel/proc/tunnel_reach_done(datum/task/timed/micro_reach/tunnel/task)
	var/mob/living/user = task.actor
	if(!contents_count(src))
		to_chat(user, span_warning("There was nothing inside."))
		act_message(user, src, MSG_SELF(span_warning("You pull your hand out of %T%")), MSG_OTHERS(span_notice("%U% pulls their hand out of %T%.")))
		return
	var/grabbed = pick(src.contents)
	if(!grabbed)
		to_chat(user, span_warning("There was nothing inside."))
		act_message(user, src, MSG_SELF(span_warning("You pull your hand out of %T%")), MSG_OTHERS(span_notice("%U% pulls their hand out of %T%.")))
		return

	if(ishuman(user))
		var/mob/living/carbon/human/h = user
		var/mob/living/l = grabbed
		if(isliving(grabbed))
			if(!l.attempt_to_scoop(h, stance = (h.combat_mode ? I_HURT : I_HELP)))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))

		act_message(user, src, others = span_warning("%U% pulls \the [grabbed] out of %T%! ! !"))
		return

	else if(isanimal(user))
		var/mob/living/simple_mob/a = user
		var/mob/living/l = grabbed
		if(!a.has_hands || isliving(grabbed))
			if(!l.attempt_to_scoop(a, stance = (a.combat_mode ? I_HURT : I_HELP)))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))
		act_message(user, src, others = span_warning("%U% pulls \the [grabbed] out of %T%! ! !"))
		return

/obj/structure/micro_tunnel/proc/can_enter(mob/living/user)
	if(user.mob_size <= MOB_TINY || user.get_effective_size(TRUE) <= micro_accepted_scale)
		return TRUE

	return FALSE

/// Big enough to reach in, but allowed to squeeze inside instead (they're asked which).
/obj/structure/micro_tunnel/proc/may_choose_to_enter(mob/living/user)
	return is_type_in_list(user, non_micro_types)

/// Old MouseDrop_T: a creature dragging itself onto the hole climbs in when small enough; one that may squeeze in is asked, and enters on "Enter".
/obj/structure/micro_tunnel/proc/interaction_drag(datum/act/op/A)
	var/mob/living/M = A.held
	if(M != A.actor)
		return OP_PASS
	if(micro_tunnel_fits(src, M))
		mouse_drop_climb(M)
		return OP_OK
	var/datum/prompt/R = A.step_answers?["enter_or_reach"]
	if(R?.value == "Enter")
		mouse_drop_climb(M)
	return OP_PASS

/obj/structure/micro_tunnel/proc/mouse_drop_climb(mob/living/k)
	act_message(k, src, others = span_notice("%U% begins climbing into %T%!"))
	task_timed(k, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(MouseDrop_T_timed_done), done_args = list(k), on_fail = PROC_REF(MouseDrop_T_timed_failed), fail_args = list(k))

/obj/structure/micro_tunnel/proc/MouseDrop_T_timed_done(mob/living/k)

	enter_tunnel(k)

/obj/structure/micro_tunnel/proc/MouseDrop_T_timed_failed(mob/living/k)
	to_chat(k, span_warning("You didn't go into \the [src]!"))
	return

/obj/structure/micro_tunnel/proc/enter_tunnel(mob/living/k)
	act_message(k, src, others = span_notice("%U% climbs into %T%!"))
	k.forceMove(src)
	k.cancel_camera()
	to_chat(k,span_notice("You are inside of \the [src]. It's dark and gloomy inside of here. You can click upon the tunnel to exit, or travel to another tunnel if there are other tunnels linked to it."))
	tunnel_notify(k)

/obj/structure/micro_tunnel/proc/tunnel_notify(mob/living/user)
	to_chat(user, span_notice("You arrive inside \the [src]."))
	var/our_message = "You can see "
	var/found_stuff = FALSE
	for(var/thing in contents_of(src))
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
	obj_instance_setup()

/obj/table_initialize()
	..()
	obj_instance_setup()

/// The per-instance part of /obj/Initialize(), shared with table_initialize() (atom_type_table.dm).
/obj/proc/obj_instance_setup()
	PRIVATE_PROC(TRUE)
	intern_access_lists()
	if(micro_target)
		grant(src, granted_verb(/obj/proc/micro_interact), src)

/// Someone inside a micro-enterable object picks what to do. Re-checked: still inside.
/datum/prompt/choice/micro_action
	question = "What would you like to do?"
	choices = list("Exit", "Move", "Cancel")
	buttons = TRUE
	timeout = 0
	ask_flags = ASK_INSIDE

/obj/proc/micro_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/living/user = A.request.answerer
	switch(A.answer.value)
		if("Exit")
			user.forceMove(get_turf(src.loc))
			user.cancel_camera()
			act_message(user, src, others = span_notice("%U% climbs out of %T%!"))
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
				micro_move(user, pick(destinations))
				return
			open_request(src, /datum/prompt/choice, PROC_REF(micro_move_chosen), answerer = user, title = "Pick a destination", question = "Where would you like to go?", choices = destinations, ask_flags = ASK_INSIDE, timeout = 0)

/obj/proc/micro_move_chosen(datum/act/request/A)
	if(!A.answer)
		return
	micro_move(A.request.answerer, A.answer.value)

/obj/proc/micro_move(mob/living/user, choice)
	var/list/contained_mobs = list()
	for(var/mob/living/issamob in contents_of(src))
		contained_mobs |= issamob
	to_chat(user,span_notice("You begin moving..."))
	task_start(/datum/task/timed/obj_micro_interact, user, src, contained_mobs = contained_mobs, choice = choice)

/obj/proc/micro_interact()
	set name = "Micro Interact"
	set desc = "Micros can enter, or move between objects with this! Non-micros can reach into objects to search for micros!"
	set category = VERB_CAT_OBJECT
	set src in oview(1)

	if(!isliving(usr))
		return

	var/list/contained_mobs = list()
	for(var/mob/living/issamob in contents_of(src))
		if(isliving(issamob))
			contained_mobs |= issamob

	if(usr.loc == src)
		open_request(src, /datum/prompt/choice/micro_action, PROC_REF(micro_action_chosen), answerer = usr, title = "[src]")
		return

	if(!(usr.mob_size <= MOB_TINY || usr.get_effective_size(TRUE) <= micro_accepted_scale))
		act_message(usr, src, MSG_SELF(span_warning("You reach into %T%. . .")), MSG_OTHERS(span_warning("%U% reaches into %T%. . .")))
		task_start(/datum/task/timed/micro_reach, usr, src, contained_mobs = contained_mobs)
		return

	act_message(usr, src, others = span_notice("%U% begins climbing into %T%!"))
	task_start(/datum/task/timed/obj_micro_interact2, usr, src, contained_mobs = contained_mobs)
	return TRUE

/// Reaching into something small for whoever is inside.
/datum/task/timed/micro_reach
	duration = 3 SECONDS
	complete_proc = /obj/proc/micro_reach_done
	cancel_proc = /obj/proc/micro_reach_failed
	var/list/contained_mobs

/datum/task/timed/micro_reach/tunnel
	complete_proc = /obj/structure/micro_tunnel/proc/tunnel_reach_done

/obj/proc/micro_reach_failed(datum/task/timed/micro_reach/task)
	var/mob/usr_mob = task.actor
	act_message(usr_mob, src, MSG_SELF(span_warning("You pull your hand out of %T%")), MSG_OTHERS(span_notice("%U% pulls their hand out of %T%.")))

/// Reached into the tunnel: pull a random occupant out.
/obj/proc/micro_reach_done(datum/task/timed/micro_reach/task)
	var/list/contained_mobs = task.contained_mobs
	var/mob/usr_mob = task.actor

	if(!contained_mobs.len)
		to_chat(usr_mob, span_warning("There was nothing inside."))
		act_message(usr_mob, src, MSG_SELF(span_warning("You pull your hand out of %T%")), MSG_OTHERS(span_notice("%U% pulls their hand out of %T%.")))
		return
	var/grabbed = pick(contained_mobs)
	if(!grabbed)
		to_chat(usr_mob, span_warning("There was nothing inside."))
		act_message(usr_mob, src, MSG_SELF(span_warning("You pull your hand out of %T%")), MSG_OTHERS(span_notice("%U% pulls their hand out of %T%.")))
		return

	if(ishuman(usr_mob))
		var/mob/living/carbon/human/h = usr_mob
		var/mob/living/l = grabbed
		if(isliving(grabbed))
			l.attempt_to_scoop(h, stance = (h.combat_mode ? I_HURT : I_HELP))
			if(!l.attempt_to_scoop(h, stance = (h.combat_mode ? I_HURT : I_HELP)))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))

		act_message(usr_mob, src, others = span_warning("%U% pulls \the [grabbed] out of %T%! ! !"))
		return

	else if(isanimal(usr_mob))
		var/mob/living/simple_mob/a = usr_mob
		var/mob/living/l = grabbed
		if(!a.has_hands || isliving(grabbed))
			if(!l.attempt_to_scoop(a, stance = (a.combat_mode ? I_HURT : I_HELP)))
				l.forceMove(get_turf(src.loc))
		else
			var/atom/movable/whatever = grabbed
			whatever.forceMove(get_turf(src.loc))
		act_message(usr_mob, src, others = span_warning("%U% pulls \the [grabbed] out of %T%! ! !"))
		return

/datum/task/timed/obj_micro_interact
	duration = 10 SECONDS
	complete_proc = /obj/proc/micro_interact_timed_done
	var/list/contained_mobs
	var/choice

/obj/proc/micro_interact_timed_done(datum/task/timed/obj_micro_interact/task)
	var/list/contained_mobs = task.contained_mobs
	var/choice = task.choice
	var/mob/usr_mob = task.actor
	if(QDELETED(src))
		return
	if(usr_mob.loc != src)
		return
	var/obj/our_choice = choice

	var/list/new_contained_mobs = list()
	for(var/mob/living/issamob in contents_of(src))
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
/datum/task/timed/obj_micro_interact2
	duration = 10 SECONDS
	complete_proc = /obj/proc/micro_interact_timed_done2
	cancel_proc = /obj/proc/micro_interact_timed_failed2
	var/list/contained_mobs

/obj/proc/micro_interact_timed_done2(datum/task/timed/obj_micro_interact2/task)
	var/list/contained_mobs = task.contained_mobs
	var/mob/usr_mob = task.actor

	act_message(usr_mob, src, others = span_notice("%U% climbs into %T%!"))
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

/obj/proc/micro_interact_timed_failed2(datum/task/timed/obj_micro_interact2/task)
	var/mob/usr_mob = task.actor
	to_chat(usr_mob, span_warning("You didn't go into \the [src]!"))
	return

/obj/effect/mouse_hole_spawner
	name = "mouse hole spawner"
	icon = 'icons/obj/landmark_vr.dmi'
	icon_state = "blue-x"
	invisibility = INVISIBILITY_ABSTRACT

	var/chance_to_spawn = 25

CAPABILITIES(/obj/effect/mouse_hole_spawner)
	map_resolver(GLOBAL_PROC_REF(resolve_mouse_hole_spawner), vars = list("chance_to_spawn"))

/// The map resolver of mouse hole spawners: a tunnel, chance_to_spawn percent of the time.
/proc/resolve_mouse_hole_spawner(atom/loc, path, list/varedits)
	var/obj/effect/mouse_hole_spawner/P = path
	if(prob(MAP_VAR(P, varedits, chance_to_spawn)))
		var/obj/structure/micro_tunnel/tunnel = new (get_turf(loc))
		tunnel.set_dir(MAP_VAR(P, varedits, dir))
	return TRUE

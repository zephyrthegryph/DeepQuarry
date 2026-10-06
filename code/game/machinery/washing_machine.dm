#define EMPTY_OPEN 1
#define EMPTY_CLOSED 2
#define FULL_OPEN 3
#define FULL_CLOSED 4
#define RUNNING 5
#define BLOODY_OPEN 6 //Not actually used...
#define BLOODY_CLOSED 7
#define BLOODY_RUNNING 8

/obj/machinery/washing_machine
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 4 SECONDS
	name = "Washing Machine"
	desc = "Not a hiding place. Unfit for pets."
	icon = 'icons/obj/machines/washing_machine_vr.dmi'
	icon_state = "wm_1"
	density = TRUE
	anchored = TRUE
	clicksound = SFX_BUTTON
	clickvol = 40

	circuit = /obj/item/circuitboard/washing
	state = EMPTY_OPEN
	var/hacked = TRUE //Bleh, screw hacking, let's have it hacked by default.
	var/gibs_ready = FALSE
	var/obj/crayon
	var/list/washing
	var/static/list/disallowed_types = list(
		/obj/item/clothing/suit/space,
		/obj/item/clothing/head/helmet/space
		)

CAPABILITIES(/obj/machinery/washing_machine)
	owns_many(nameof(washing), on_destroy = ON_DESTROY_SPILL)
	climb()
	extend("machine_panel", needs(req(PROC_REF(idle_and_empty), silent = TRUE)))
	extend("machine_panel_close", needs(req(PROC_REF(idle_and_empty), silent = TRUE)))
	extend("machine_deconstruct", needs(req(PROC_REF(idle_and_empty), silent = TRUE)))
	extend("machine_anchor", needs(req(PROC_REF(idle_and_empty), silent = TRUE)))
	extend("machine_unanchor", needs(req(PROC_REF(idle_and_empty), silent = TRUE)))
	default_parts()



/obj/machinery/washing_machine/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/washing_machine_use_item,
		/datum/interaction/machine_alt/washing_machine_start,
		/datum/interaction/machine_verb/washing_machine_start_washing,
		/datum/interaction/machine_verb/washing_machine_climb_out,
		/datum/interaction/machine_hand/ungated/washing_machine_use,
	)
	..()

/// Both player entry points pass their actor into the cycle starter.
/datum/interaction/machine_alt/washing_machine_start
	id = "washing_machine_start"
	name = "Start"
	consumes_input = FALSE
	effect = /obj/machinery/washing_machine/proc/interaction_washing_machine_start

/obj/machinery/washing_machine/proc/interaction_washing_machine_start(mob/user, obj/item/held, datum/interaction/interaction)
	start(user = user)
	return TRUE

/datum/interaction/machine_verb/washing_machine_start_washing
	id = "washing_machine_start_washing"
	name = "Start Washing"
	effect = /obj/machinery/washing_machine/proc/interaction_washing_machine_start_washing

/obj/machinery/washing_machine/proc/interaction_washing_machine_start_washing(mob/user, obj/item/held, datum/interaction/interaction)
	start(user = user)
	return TRUE

/obj/machinery/washing_machine/proc/start(force, damage_modifier, mob/user)

	if(!isliving(user) && !force)
		return
	if(!damage_modifier)
		damage_modifier = 0.5
	if(state != FULL_CLOSED)
		visible_message("The washing machine buzzes - it can not run in this state!")
		return

	if(locate(/mob,washing))
		set_state(BLOODY_RUNNING)
	else
		set_state(RUNNING)
	visible_message("The washing machine starts a cycle.")
	play_sfx(src, SFX_ITEMS_WASHINGMACHINE)

	after(src, 2 SECONDS, PROC_REF(finish_wash), with = list(damage_modifier))

/obj/machinery/washing_machine/proc/finish_wash(damage_modifier)
	for(var/atom/A in washing)
		A.wash(CLEAN_ALL)

	//Tanning!
	for(var/obj/item/stack/hairlesshide/HH in washing)
		var/obj/item/stack/wetleather/WL = new(src, HH.get_amount())
		own_take_member(src, nameof(washing), HH)
		HH.forceMove(get_turf(src))
		HH.use(HH.get_amount())

		rel_add(src, nameof(washing), WL)
	var/has_mobs = FALSE
	for(var/mob/living/mobs in washing)
		has_mobs = TRUE
		if(ishuman(mobs))
			var/mob/living/carbon/human/our_human = mobs
			var/max_health_coefficient = (our_human.get_endurance() * 0.09) //9 for 100% hp human, 4.5 for 50% hp human (teshari), etc.
			for(var/i=0,i<10,i++)
				our_human.injure(INJURY_BLUNT, max_health_coefficient*damage_modifier, pick(BP_ALL), src) //Let's randomly do damage across the body. One limb might get hurt more than the others. At 100% damge mod, does 90% of max hp in damage.
			continue
		mobs.set_stat(DEAD) //Kill them so they can't interact anymore.

	if(has_mobs)
		set_state(BLOODY_CLOSED)
		gibs_ready = TRUE
	else
		set_state(FULL_CLOSED)

/datum/interaction/machine_verb/washing_machine_climb_out
	id = "washing_machine_climb_out"
	name = "Climb out"
	requires = list(REQ_ON(PRED_ACTOR, /obj/machinery/washing_machine/proc/actor_inside, "you aren't inside it"))
	effect = /obj/machinery/washing_machine/proc/interaction_washing_machine_climb_out

/obj/machinery/washing_machine/proc/actor_inside(mob/actor, atom/target, obj/item/held)
	return actor.loc == target

/obj/machinery/washing_machine/proc/interaction_washing_machine_climb_out(mob/user, obj/item/held, datum/interaction/interaction)
	user_climb_out(user)
	return TRUE

/obj/machinery/washing_machine/proc/user_climb_out(mob/user)
	if(user.loc != src) //Have to be in it to climb out of it.
		return
	if(state in list(EMPTY_OPEN, FULL_OPEN, BLOODY_OPEN)) //Door is open, we can climb out easily.
		visible_message("[user] begins to climb out of the [src]!")
		om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(user_climb_out_timed_done), done_args = list(user))
	else if(state in list(EMPTY_CLOSED, FULL_CLOSED, BLOODY_CLOSED)) //Door is shut.
		visible_message("[src] begins to rattle and shake!")
		om_task_timed(user, 60 SECONDS, target = src, receiver = src, on_done = PROC_REF(user_climb_out_timed_done2), done_args = list(user))

/obj/machinery/washing_machine/proc/user_climb_out_timed_done(mob/user)
	if(!(state in list(EMPTY_CLOSED, FULL_CLOSED, BLOODY_CLOSED))) //Someone shut the door while we were trying to climb out!
		user.forceMove(get_turf(src))
		act_message(user, src, others = "%U% climbs out of %T%!")
	else
		to_chat(user, "Someone shut the door on you!")
/obj/machinery/washing_machine/proc/user_climb_out_timed_done2(mob/user)
	act_message(user, src, others = "%U% climbs out of %T%!")
	interaction_washing_machine_use(user, null, null, force = TRUE)

/obj/machinery/washing_machine/container_resist(mob/living/escapee)
	user_climb_out(escapee)

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/washing_machine/draw(datum/look/look)
	..()
	look.state("wm_[state]")
	if(panel_open == 1)
		look.overlay("panel")

/datum/interaction/machine_item/washing_machine_use_item
	id = "washing_machine_use_item"
	name = "Use"
	effect = /obj/machinery/washing_machine/proc/interaction_washing_machine_use_item

// Where the old body called a bare ..() and fell through to update_icon() below it (rather
// than returning), the base attackby signal is approximated as a no-op: that fallback is a
// generic atom hook with no other behavior on this type, but note it as an approximation.
/obj/machinery/washing_machine/proc/interaction_washing_machine_use_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/pen/crayon) || istype(W,/obj/item/stamp))
		if(state in list (EMPTY_OPEN, FULL_OPEN, BLOODY_OPEN))
			if(!crayon())
				if(!own_bring_in(src, nameof(crayon), W, null, user, TRUE, null, FALSE))
					return TRUE
				rel_set(src, nameof(crayon), W)
			//else: old fell through to a bare ..() (approximated as a no-op)

		//else: old fell through to a bare ..() (approximated as a no-op)

	else if(istype(W,/obj/item/grab))
		if((state == EMPTY_OPEN) && hacked)
			var/obj/item/grab/G = W
			if(ishuman(G?.grab_assailant()) && (iscorgi(G?.grab_target()) || ishuman(G?.grab_target())))
				act_message(user, src, MSG_SELF("You begin stuffing [G?.grab_target()] into %T%!"), \
					MSG_OTHERS("%U% begins stuffing [G?.grab_target()] into %T%!"))
				om_task_timed(user, 5 SECONDS, target = src, receiver = src, on_done = PROC_REF(interaction_washing_machine_use_item_timed_done), done_args = list(user, G))
		//else: old fell through to a bare ..() (approximated as a no-op)

	else if(is_type_in_list(W, disallowed_types))
		to_chat(user, span_warning("You can't fit \the [W] inside."))
		return TRUE

	else if(istype(W, /obj/item/clothing) || istype(W, /obj/item/bedsheet) || istype(W, /obj/item/stack/hairlesshide))
		if(length(washing) < 5)
			if(state in list(EMPTY_OPEN, FULL_OPEN))
				if(!move_into(src, nameof(src.washing), W, user))
					return TRUE
				set_state(FULL_OPEN)
			else
				to_chat(user, span_notice("You can't put the item in right now."))
		else
			to_chat(user, span_notice("The washing machine is full."))
	//else: old fell through to a bare ..() (approximated as a no-op)
	return TRUE

/obj/machinery/washing_machine/proc/interaction_washing_machine_use_item_timed_done(mob/user, obj/item/grab/G)
	if(state == EMPTY_OPEN) //Checking to make sure nobody closed it before we shoved em in it.
		var/mob/grabbed = G?.grab_target()
		act_message(user, grabbed, MSG_SELF("You stuff %T% into the [src] and shut the door!"), MSG_OTHERS("%U% stuffs %T% into the [src] and shuts the door!"))
		move_into(src, nameof(src.washing), grabbed, user)
		consume(G, user)
		set_state(FULL_CLOSED)
	else
		to_chat(user, "You can't shove [G?.grab_target()] in unless the washer is empty and open!")

/// Maintenance only on an empty, shut machine (otherwise the tool's click is taken and nothing happens).
/obj/machinery/washing_machine/proc/idle_and_empty(datum/act/op/A)
	return state == EMPTY_CLOSED && !LAZYLEN(washing)

/datum/interaction/machine_hand/ungated/washing_machine_use
	id = "washing_machine_use"
	name = "Use"
	effect = /obj/machinery/washing_machine/proc/interaction_washing_machine_use

/obj/machinery/washing_machine/proc/interaction_washing_machine_use(mob/user, obj/item/held, datum/interaction/interaction, force = FALSE)
	if(user.loc == src && !force)
		return TRUE //No interacting with it from the inside!
	switch(state)
		if(EMPTY_OPEN)
			set_state(EMPTY_CLOSED)
		if(EMPTY_CLOSED)
			set_state(EMPTY_OPEN)
			eject_dye()
			for(var/atom/movable/O in washing)
				O.forceMove(get_turf(src))
			rel_take(src, nameof(washing))
		if(FULL_OPEN)
			set_state(FULL_CLOSED)
		if(FULL_CLOSED)
			for(var/atom/movable/O in washing)
				O.forceMove(get_turf(src))
			eject_dye()
			rel_take(src, nameof(washing))
			set_state(EMPTY_OPEN)
		if(RUNNING)
			if(user)
				to_chat(user, span_warning("The [src] is busy."))
		if(BLOODY_OPEN)
			set_state(BLOODY_CLOSED)
		if(BLOODY_CLOSED)
			if(gibs_ready)
				gibs_ready = FALSE
				for(var/mob/living/mobs in washing)
					if(ishuman(mobs)) //Humans have special handling.
						continue
					mobs.gib()
			for(var/atom/movable/O in washing)
				O.forceMove(get_turf(src))
			eject_dye()
			set_state(EMPTY_OPEN)
			rel_take(src, nameof(washing))

	return TRUE

#undef EMPTY_OPEN
#undef EMPTY_CLOSED
#undef FULL_OPEN
#undef FULL_CLOSED
#undef RUNNING
#undef BLOODY_OPEN
#undef BLOODY_CLOSED
#undef BLOODY_RUNNING

/// Return the separate dye item whenever the washer is opened.
/obj/machinery/washing_machine/proc/eject_dye()
	var/obj/dye = crayon()
	if(dye)
		dye.forceMove(get_turf(src))
	rel_clear(src, nameof(crayon))

/// crayon (a relation view: it reads null once the target is deleted).
/obj/machinery/washing_machine/proc/crayon() as /obj
	return crayon

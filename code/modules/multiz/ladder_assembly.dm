/obj/structure/ladder_assembly
	name = "ladder assembly"
	icon = 'icons/obj/structures_vr.dmi'
	icon_state = "ladder00"
	density = FALSE
	opacity = 0
	anchored = FALSE
	w_class = ITEMSIZE_HUGE

	var/state = 0
	var/created_name = null

CAPABILITIES(/obj/structure/ladder_assembly)
	op("name_ladder", item(/obj/item/pen),
		asks(/datum/prompt/text, fields = list("question" = "Enter the name for the ladder.", "title" = "Ladder Name", "default" = nameof(created_name), "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "encode" = FALSE, "timeout" = 0), step = "k15"),
		then(PROC_REF(interaction_item)))

/// Old attackby: a pen names the ladder (the click goes on).
/obj/structure/ladder_assembly/proc/interaction_item(datum/act/op/A)
	var/t = sanitizeSafe(A.step_value("k15"), MAX_NAME_LEN)
	if(in_range(src, A.actor))
		created_name = t
	return OP_PASS

/obj/structure/ladder_assembly/wrench_act(mob/user, obj/item/W)
	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("\The [src] cannot be constructed on a shuttle."))
		return ITEM_INTERACT_BLOCKING
	switch(state)
		if(LADDER_CONSTRUCTION_UNANCHORED)
			state = LADDER_CONSTRUCTION_WRENCHED
			play_sfx(src, SFX_ITEMS_RATCHET, 1.5)
			act_message(user, src, MSG_SELF("You secure the reinforcing bolts."), \
				MSG_OTHERS("%U% secures %T%'s reinforcing bolts."), \
				MSG_BLIND("You hear a ratchet"))
			set_anchored(TRUE)
		if(LADDER_CONSTRUCTION_WRENCHED)
			state = LADDER_CONSTRUCTION_UNANCHORED
			play_sfx(src, SFX_ITEMS_RATCHET, 1.5)
			act_message(user, src, MSG_SELF("You undo the reinforcing bolts."), \
				MSG_OTHERS("%U% unsecures %T%'s reinforcing bolts."), \
				MSG_BLIND("You hear a ratchet"))
			set_anchored(FALSE)
		if(LADDER_CONSTRUCTION_WELDED)
			to_chat(user, span_warning("\The [src] needs to be unwelded."))
	return ITEM_INTERACT_SUCCESS

/obj/structure/ladder_assembly/welder_act(mob/user, obj/item/W)
	if(istype(get_area(src), /area/shuttle))
		to_chat(user, span_warning("\The [src] cannot be constructed on a shuttle."))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/weldingtool/WT = W.get_welder()
	switch(state)
		if(LADDER_CONSTRUCTION_UNANCHORED)
			to_chat(user, span_warning("The reinforcing bolts need to be secured."))
		if(LADDER_CONSTRUCTION_WRENCHED)
			if(!WT.remove_fuel(0, user))
				to_chat(user, span_warning("You need more welding fuel to complete this task."))
				return ITEM_INTERACT_BLOCKING
			play_sfx(src, SFX_ITEMS_WELDER2)
			act_message(user, src, MSG_SELF("You start to weld %T% to the floor."), \
				MSG_OTHERS("%U% starts to weld %T% to the floor."), \
				MSG_BLIND("You hear welding"))
			task_start(/datum/task/timed/ladder_assembly_weld, user, src, receiver = src, WT = WT, from_state = LADDER_CONSTRUCTION_WRENCHED)
		if(LADDER_CONSTRUCTION_WELDED)
			if(!WT.remove_fuel(0, user))
				to_chat(user, span_warning("You need more welding fuel to complete this task."))
				return ITEM_INTERACT_BLOCKING
			play_sfx(src, SFX_ITEMS_WELDER2)
			act_message(user, src, MSG_SELF("You start to cut %T% free from the floor."), \
				MSG_OTHERS("%U% starts to cut %T% free from the floor."), \
				MSG_BLIND("You hear welding"))
			task_start(/datum/task/timed/ladder_assembly_weld, user, src, receiver = src, WT = WT, from_state = LADDER_CONSTRUCTION_WELDED)
	return ITEM_INTERACT_SUCCESS

/datum/task/timed/ladder_assembly_weld
	duration = 2 SECONDS
	complete_proc = /obj/structure/ladder_assembly/proc/weld_done
	var/obj/item/weldingtool/WT
	var/from_state

/obj/structure/ladder_assembly/proc/weld_done(datum/task/timed/ladder_assembly_weld/task)
	var/mob/user = task.actor
	var/obj/item/weldingtool/WT = task.WT
	var/from_state = task.from_state
	if(!WT.isOn() || state != from_state)
		return
	if(from_state == LADDER_CONSTRUCTION_WRENCHED)
		state = LADDER_CONSTRUCTION_WELDED
		to_chat(user, "You weld \the [src] to the floor.")
		try_construct(user)
	else
		state = LADDER_CONSTRUCTION_WRENCHED
		to_chat(user, "You cut \the [src] free from the floor.")

// Try to construct this into a real stairway.
// It must have a matching ladder assembly above and/or below, and both must be welded in place
// NOTE - Currently this design only supports three story tall ladders.  Its fine for our map tho.
// A better way would search upwards until finding the top, then call a proc on that to build the string.
/obj/structure/ladder_assembly/proc/try_construct(mob/user)
	var/obj/structure/ladder_assembly/below
	var/obj/structure/ladder_assembly/above

	for(var/direction in list(DOWN, UP))
		var/turf/T = get_zstep(src, direction)
		if(!T) continue
		var/obj/structure/ladder_assembly/LA = locate(/obj/structure/ladder_assembly, T)
		if(!LA) continue
		if(direction == DOWN && (src.z in using_map.below_blocked_levels)) continue
		if(direction == UP && (LA.z in using_map.below_blocked_levels)) continue
		if(LA.state != LADDER_CONSTRUCTION_WELDED)
			to_chat(user, span_warning("\The [LA] [direction == UP ? "above" : "below"] must be secured and welded."))
			return
		if(direction == UP)
			above = LA
		if(direction == DOWN)
			below = LA

	if(!above && !below)
		to_chat(user, span_notice("\The [src] is ready to be connected to from above or below."))
		return

	// Construct them from bottom to top, because they initialize from top to bottom.
	// If we made bottom last, nothing would initialize it.
	var/obj/structure/ladder_assembly/me = src
	src = null // So we can delete ourselves etc.

	if(below)
		var/obj/structure/ladder/L = new(get_turf(below))
		L.allowed_directions = UP
		if(below.created_name) L.name = below.created_name
		L.attempt_connection()
		spent(below, user)

	if(me)
		var/obj/structure/ladder/L = new(get_turf(me))
		L.allowed_directions = (below ? DOWN : 0) | (above ? UP : 0)
		if(me.created_name) L.name = me.created_name
		L.attempt_connection()
		spent(me, user)

	if(above)
		var/obj/structure/ladder/L = new(get_turf(above))
		L.allowed_directions = DOWN
		if(above.created_name) L.name = above.created_name
		L.attempt_connection()
		spent(above, user)

// Make them constructable in hand
/datum/material/steel/generate_recipes()
	var/list/recipes = ..()
	if(!islist(recipes))
		recipes = list()
	recipes += new /datum/stack_recipe("ladder assembly", /obj/structure/ladder_assembly, 4, time = 50, one_per_turf = 1, on_floor = 1)
	return recipes

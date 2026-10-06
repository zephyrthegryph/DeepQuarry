//Define all tape types in policetape.dm
/obj/item/taperoll
	name = "tape roll"
	icon = 'icons/policetape.dmi'
	icon_state = "tape"
	w_class = ITEMSIZE_SMALL

	toolspeed = 3 //You can use it in surgery. It's stupid, but you can.

	var/turf/start
	var/turf/end
	var/tape_type = /obj/item/tape
	var/icon_base = "tape"

	var/apply_tape = FALSE

/obj/item/taperoll/Initialize(mapload)
	. = ..()
	if(apply_tape)
		var/turf/T = get_turf(src)
		if(!T)
			return
		var/obj/machinery/door/door = locate_on(T, /obj/machinery/door)
		if(istype(door, /obj/machinery/door/airlock) || istype(door, /obj/machinery/door/firedoor))
			afterattack(door, null, TRUE)
		return INITIALIZE_HINT_QDEL


GLOBAL_LIST_INIT_TYPED(hazard_overlays, /image, list(
		"[NORTH]"	= new/image('icons/effects/warning_stripes.dmi', icon_state = "N"),
		"[EAST]"	= new/image('icons/effects/warning_stripes.dmi', icon_state = "E"),
		"[SOUTH]"	= new/image('icons/effects/warning_stripes.dmi', icon_state = "S"),
		"[WEST]"	= new/image('icons/effects/warning_stripes.dmi', icon_state = "W")
	))
GLOBAL_LIST_EMPTY(tape_roll_applications)

/obj/item/tape
	name = "tape"
	icon = 'icons/policetape.dmi'
	icon_state = "tape"
	anchored = TRUE
	layer = WINDOW_LAYER
	var/lifted = 0
	var/crumpled = 0
	var/tape_dir = 0
	var/icon_base = "tape"

/obj/item/tape/draw(datum/look/look)
	..()
	//Possible directional bitflags: 0 (AIRLOCK), 1 (NORTH), 2 (SOUTH), 4 (EAST), 8 (WEST), 3 (VERTICAL), 12 (HORIZONTAL)
	switch (tape_dir)
		if(0)  // AIRLOCK
			look.state("[icon_base]_door_[crumpled]")
		if(3)  // VERTICAL
			look.state("[icon_base]_v_[crumpled]")
		if(12) // HORIZONTAL
			look.state("[icon_base]_h_[crumpled]")
		else   // END POINT (1|2|4|8)
			look.state("[icon_base]_dir_[crumpled]")
			look.set_dir(tape_dir)

/obj/item/taperoll/medical
	name = "medical tape"
	desc = "A roll of medical tape used to block off patients from the public."
	tape_type = /obj/item/tape/medical
	color = COLOR_WHITE

/obj/item/tape/medical
	name = "medical tape"
	desc = "A length of medical tape.  Do not cross."
	req_access = list(ACCESS_MEDICAL)
	color = COLOR_WHITE

/obj/item/taperoll/police
	name = "police tape"
	desc = "A roll of police tape used to block off crime scenes from the public."
	tape_type = /obj/item/tape/police
	color = COLOR_RED_LIGHT

/obj/item/tape/police
	name = "police tape"
	desc = "A length of police tape.  Do not cross."
	req_access = list(ACCESS_SECURITY)
	color = COLOR_RED_LIGHT

/obj/item/taperoll/engineering
	name = "engineering tape"
	desc = "A roll of engineering tape used to block off working areas from the public."
	tape_type = /obj/item/tape/engineering
	color = COLOR_YELLOW

/obj/item/taperoll/engineering/applied
	apply_tape = TRUE

/obj/item/tape/engineering
	name = "engineering tape"
	desc = "A length of engineering tape. Better not cross it."
	req_one_access = list(ACCESS_ENGINE,ACCESS_ATMOSPHERICS)
	color = COLOR_YELLOW

/obj/item/taperoll/atmos
	name = "atmospherics tape"
	desc = "A roll of atmospherics tape used to block off working areas from the public."
	tape_type = /obj/item/tape/atmos
	color = COLOR_DEEP_SKY_BLUE

/obj/item/tape/atmos
	name = "atmospherics tape"
	desc = "A length of atmospherics tape. Better not cross it."
	req_one_access = list(ACCESS_ENGINE,ACCESS_ATMOSPHERICS)
	color = COLOR_DEEP_SKY_BLUE

/obj/item/taperoll/draw(datum/look/look)
	..()
	var/image/overlay = image(icon = src.icon)
	overlay.appearance_flags = RESET_COLOR
	if(ismob(loc))
		if(!get_start())
			overlay.icon_state = "start"
		else
			overlay.icon_state = "stop"
		look.overlay(overlay)


/obj/item/taperoll/dropped(mob/user, equipping, slot)
	return ..()

/obj/item/taperoll/pickup(mob/user)
	return ..()

/// Old attack_hand.
/obj/item/taperoll/proc/interaction_hand(datum/act/op/A)
	return OP_DECLINE

CAPABILITIES(/obj/item/taperoll)
	op("lay_tape", in_hand(), label("Lay tape"), then(PROC_REF(tape_laying_requested)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))

/obj/item/taperoll/proc/tape_laying_requested(datum/act/op/A)
	var/mob/user = A.actor
	if(!get_start())
		rel_set(src, nameof(start), get_turf(src))
		to_chat(user, span_notice("You place the first end of \the [src]."))
	else
		rel_set(src, nameof(end), get_turf(src))
		if(get_start().y != get_end().y && get_start().x != get_end().x || get_start().z != get_end().z)
			rel_clear(src, nameof(start))
			to_chat(user, span_notice("\The [src] can only be laid horizontally or vertically."))
			return OP_OK

		if(get_start() == get_end())
			// spread tape in all directions, provided there is a wall/window
			var/turf/T
			var/possible_dirs = 0
			for(var/dir in GLOB.cardinal)
				T = get_step(get_start(), dir)
				if(T && T.density)
					possible_dirs |= dir
				else
					for(var/obj/structure/window/W in contents_of(T))
						if(W.is_fulltile() || W.dir == GLOB.reverse_dir[dir])
							possible_dirs |= dir
			for(var/obj/structure/window/window in get_start())
				if(istype(window) && !window.is_fulltile())
					possible_dirs |= window.dir
			if(!possible_dirs)
				rel_clear(src, nameof(start))
				to_chat(user, span_notice("You can't place \the [src] here."))
				return OP_OK
			if(possible_dirs & (NORTH|SOUTH))
				var/obj/item/tape/TP = new tape_type(get_start())
				for(var/dir in list(NORTH, SOUTH))
					if (possible_dirs & dir)
						TP.tape_dir += dir
				changed(TP)
			if(possible_dirs & (EAST|WEST))
				var/obj/item/tape/TP = new tape_type(get_start())
				for(var/dir in list(EAST, WEST))
					if (possible_dirs & dir)
						TP.tape_dir += dir
				changed(TP)
			rel_clear(src, nameof(start))
			to_chat(user, span_notice("You finish placing \the [src]."))
			return OP_OK

		var/turf/cur = get_start()
		var/orientation = get_dir(get_start(), get_end())
		var/dir = 0
		switch(orientation)
			if(NORTH, SOUTH)	dir = NORTH|SOUTH	// North-South taping
			if(EAST,   WEST)	dir =  EAST|WEST	// East-West taping

		var/can_place = 1
		while (can_place)
			if(cur.density == 1)
				can_place = 0
			else if (istype(cur, /turf/space))
				can_place = 0
			else
				for(var/obj/O in turf_contents_of_type(cur, /obj))
					if(istype(O, /obj/structure/window))
						var/obj/structure/window/window = O
						if(window.is_fulltile())
							can_place = 0
							break
						if(cur == get_start())
							if(window.dir == orientation)
								can_place = 0
								break
							else
								continue
						else if(cur == get_end())
							if(window.dir == GLOB.reverse_dir[orientation])
								can_place = 0
								break
							else
								continue
						else if (window.dir == GLOB.reverse_dir[orientation] || window.dir == orientation)
							can_place = 0
							break
						else
							continue
					if(O.density)
						can_place = 0
						break
			if(cur == get_end())
				break
			cur = get_step_towards(cur,get_end())
		if (!can_place)
			rel_clear(src, nameof(start))
			to_chat(user, span_warning("You can't run \the [src] through that!"))
			return OP_OK

		cur = get_start()
		var/tapetest
		var/tape_dir
		while (1)
			tapetest = 0
			tape_dir = dir
			if(cur == get_start())
				var/turf/T = get_step(get_start(), GLOB.reverse_dir[orientation])
				if(T && !T.density)
					tape_dir = orientation
					for(var/obj/structure/window/W in turf_contents_of_type(T, /obj/structure/window))
						if(W.is_fulltile() || W.dir == orientation)
							tape_dir = dir
				for(var/obj/structure/window/window in turf_contents_of_type(cur, /obj/structure/window))
					if(istype(window) && !window.is_fulltile() && window.dir == GLOB.reverse_dir[orientation])
						tape_dir = dir
			else if(cur == get_end())
				var/turf/T = get_step(get_end(), orientation)
				if(T && !T.density)
					tape_dir = GLOB.reverse_dir[orientation]
					for(var/obj/structure/window/W in turf_contents_of_type(T, /obj/structure/window))
						if(W.is_fulltile() || W.dir == GLOB.reverse_dir[orientation])
							tape_dir = dir
				for(var/obj/structure/window/window in turf_contents_of_type(cur, /obj/structure/window))
					if(istype(window) && !window.is_fulltile() && window.dir == orientation)
						tape_dir = dir
			for(var/obj/item/tape/T in turf_contents_of_type(cur, /obj/item/tape))
				if((T.tape_dir == tape_dir) && (T.icon_base == icon_base))
					tapetest = 1
					break
			if(!tapetest)
				var/obj/item/tape/T = new tape_type(cur)
				T.tape_dir = tape_dir
				changed(T)
				if(tape_dir & SOUTH)
					T.layer += 0.1 // Must always show above other tapes
			if(cur == get_end())
				break
			cur = get_step_towards(cur,get_end())
		rel_clear(src, nameof(start))
		to_chat(user, span_notice("You finish placing \the [src]."))
		return OP_OK
	return OP_OK

/obj/item/taperoll/afterattack(atom/A, mob/user as mob, proximity)
	if(!proximity)
		return

	if (istype(A, /obj/machinery/door))
		var/turf/T = get_turf(A)
		if(locate(/obj/item/tape, A.loc))
			to_chat(user, "There's already tape over that door!")
		else
			var/obj/item/tape/P = new tape_type(T)
			changed(P)
			P.layer = WINDOW_LAYER
			to_chat(user, span_notice("You finish placing \the [src]."))

	if (istype(A, /turf/simulated/floor) ||istype(A, /turf/unsimulated/floor))
		var/turf/F = A
		var/direction = user.loc == F ? user.dir : turn(user.dir, 180)
		var/icon/hazard_overlay = GLOB.hazard_overlays["[direction]"]
		if(GLOB.tape_roll_applications[F] == null)
			GLOB.tape_roll_applications[F] = 0

		if(GLOB.tape_roll_applications[F] & direction) // hazard_overlay in F.overlays wouldn't work.
			act_message(user, src, MSG_SELF("You use the adhesive of %T% to remove area markings from \the [F]."), MSG_OTHERS("%U% uses the adhesive of %T% to remove area markings from \the [F]."))
			F.cut_overlay(hazard_overlay)
			GLOB.tape_roll_applications[F] &= ~direction
		else
			act_message(user, src, MSG_SELF("You apply %T% on \the [F] to create area markings."), MSG_OTHERS("%U% applied %T% on \the [F] to create area markings."))
			F.add_overlay(hazard_overlay)
			GLOB.tape_roll_applications[F] |= direction
		return

/obj/item/tape/proc/crumple()
	if(!crumpled)
		crumpled = 1
		changed(src)
		name = "crumpled [name]"

/obj/item/tape/CanPass(atom/movable/mover, turf/target)
	if(!lifted && ismob(mover))
		var/mob/M = mover
		add_fingerprint(M)
		if(!allowed(M))	//only select few learn art of not crumpling the tape
			to_chat(M, span_warning("You are not supposed to go past \the [src]..."))
			if(!M.combat_mode && !(isanimal(M)))
				return FALSE
			crumple()
	return ..()

/// Old attackby.
/obj/item/tape/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	breaktape(user, interaction.stance)
	return INTERACTION_HANDLED_PASS

DECLARE_INTERACTIONS(/obj/item/tape, \
	INTERACT_HAND_UNGATED_AS(I_HELP, "Lift", PROC_REF(interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_DISARM, "Break", PROC_REF(interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_GRAB, "Break", PROC_REF(interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_HURT, "Break", PROC_REF(interaction_hand)), \
	INTERACT_ITEM_AS(I_HELP, null, PROC_REF(interaction_item)), \
	INTERACT_ITEM_AS(I_DISARM, "Break", PROC_REF(interaction_item)), \
	INTERACT_ITEM_AS(I_GRAB, "Break", PROC_REF(interaction_item)), \
	INTERACT_ITEM_AS(I_HURT, "Break", PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/item/tape/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if (interaction.stance == I_HELP && src.allowed(user))
		user.show_viewers(span_infoplain(span_bold("\The [user]") + " lifts \the [src], allowing passage."))
		for(var/obj/item/tape/T in gettapeline())
			T.lift(10 SECONDS) //~10 seconds
	else
		breaktape(user, interaction.stance)
	return TRUE

/obj/item/tape/proc/lift(time)
	lifted = 1
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	after(src, time, PROC_REF(settle))

// Returns a list of all tape objects connected to src, including itself.
/obj/item/tape/proc/gettapeline()
	var/list/dirs = list()
	if(tape_dir & NORTH)
		dirs += NORTH
	if(tape_dir & SOUTH)
		dirs += SOUTH
	if(tape_dir & WEST)
		dirs += WEST
	if(tape_dir & EAST)
		dirs += EAST

	var/list/obj/item/tape/tapeline = list()
	for (var/obj/item/tape/T in get_turf(src))
		tapeline += T
	for(var/dir in dirs)
		var/turf/cur = get_step(src, dir)
		var/not_found = 0
		while (!not_found)
			not_found = 1
			for (var/obj/item/tape/T in turf_contents_of_type(cur, /obj/item/tape))
				tapeline += T
				not_found = 0
			cur = get_step(cur, dir)
	return tapeline

/obj/item/tape/proc/breaktape(mob/user, stance = I_HURT)
	if(stance == I_HELP)
		to_chat(user, span_warning("You refrain from breaking \the [src]."))
		return
	act_message(user, src, MSG_SELF(span_notice("You break %T%.")), MSG_OTHERS(span_bold("%U%") + " breaks %T%!"))

	for (var/obj/item/tape/T in gettapeline())
		if(T == src)
			continue
		if(T.tape_dir & get_dir(T, src))
			destroyed(T, user)

	consume(src, user) //TODO: Dropping a trash item holding fibers/fingerprints of all broken tape parts
	return

/obj/item/tape/proc/settle()
	lifted = 0
	reset_plane_and_layer()

/// Relation view: start (reads null once it is gone).
/obj/item/taperoll/proc/get_start() as /turf
	return start

/// Relation view: end (reads null once it is gone).
/obj/item/taperoll/proc/get_end() as /turf
	return end

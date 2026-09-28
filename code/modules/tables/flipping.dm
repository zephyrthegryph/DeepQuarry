
/obj/structure/table/proc/straight_table_check(direction)
	if(get_integrity() > 100)
		return 0
	var/obj/structure/table/T
	for(var/angle in list(-90,90))
		T = locate_within(get_step(src.loc,turn(direction,angle)), /obj/structure/table)
		if(T && T.flipped == 0 && T.material() && T.material().name == material().name)
			return 0
	T = locate_within(get_step(src.loc,direction), /obj/structure/table)
	if (!T || T.flipped == 1 || T.material() != material())
		return 1
	return T.straight_table_check(direction)

/// FALSE on tables that can never be flipped by hand (racks, fixed decorative tables): no Flip/Put back menu entries.
/obj/structure/table/var/can_flip_verb = TRUE

EXTEND_INTERACTIONS(/obj/structure/table, \
	INTERACT_VERB("Flip table", PROC_REF(table_verb_flip), REQ_ON(PRED_TARGET, /obj/structure/table/proc/pred_can_flip, "it is already flipped")), \
	INTERACT_VERB("Put table back", PROC_REF(table_verb_put_back), REQ_ON(PRED_TARGET, /obj/structure/table/proc/pred_can_put_back, "it is not flipped")), \
)

/// Requirement for Flip table: replaces the old verb that flip()/unflip() added and removed.
/obj/structure/table/proc/pred_can_flip(mob/actor, atom/target, obj/item/held)
	return can_flip_verb && flipped == 0

/// Requirement for Put table back: the old do_put verb was only present while flipped.
/obj/structure/table/proc/pred_can_put_back(mob/actor, atom/target, obj/item/held)
	return can_flip_verb && flipped == 1

/// Old Flip table verb: flips a non-reinforced table.
/obj/structure/table/proc/table_verb_flip(mob/user, obj/item/held, datum/interaction/interaction)
	if (!can_touch(user) || HAS_TRAIT(user, TRAIT_AMBIENT_PEST_MOB))
		return

	if(flipped < 0 || !flip(get_cardinal_dir(user,src)))
		to_chat(user, span_notice("It won't budge."))
		return

	user.visible_message(span_warning("[user] flips \the [src]!"))

	om_emit(src, new /datum/om/event/climb_shake(user))

/obj/structure/table/proc/unflipping_check(direction)

	for(var/mob/M in oview(src,0))
		return 0

	var/obj/occupied = can_climb_turf(src)
	if(occupied)
		to_chat(usr, span_filter_notice("There's \a [occupied] in the way."))
		return 0

	var/list/L = list()
	if(direction)
		L.Add(direction)
	else
		L.Add(turn(src.dir,-90))
		L.Add(turn(src.dir,90))
	for(var/new_dir in L)
		var/obj/structure/table/T = locate_within(get_step(src.loc,new_dir), /obj/structure/table)
		if(T && T.material() && T.material().name == material().name)
			if(T.flipped == 1 && T.dir == src.dir && !T.unflipping_check(new_dir))
				return 0
	return 1

/// Old Put table back verb: puts a flipped table back.
/obj/structure/table/proc/table_verb_put_back(mob/user, obj/item/held, datum/interaction/interaction)
	if (!can_touch(user))
		return

	if (!unflipping_check())
		to_chat(user, span_notice("It won't budge."))
		return
	unflip()

/obj/structure/table/proc/flip(direction)
	if( !straight_table_check(turn(direction,90)) || !straight_table_check(turn(direction,-90)) )
		return 0

	var/list/targets = list(get_step(src,dir),get_step(src,turn(dir, 45)),get_step(src,turn(dir, -45)))
	for (var/atom/movable/A in get_turf(src))
		if (!A.anchored)
			A.throw_at(pick(targets),1,1)

	set_dir(direction)
	if(dir != NORTH)
		plane = MOB_PLANE
		layer = ABOVE_MOB_LAYER
	//climbable = FALSE //flipping tables allows them to be used as makeshift barriers
	flipped = 1
	flags |= ON_BORDER
	for(var/D in list(turn(direction, 90), turn(direction, -90)))
		var/obj/structure/table/T = locate_within(get_step(src,D), /obj/structure/table)
		if(T && T.flipped == 0 && material() && T.material() && T.material().name == material().name)
			T.flip(direction)
	take_damage(rand(5, 10), BRUTE, MELEE)
	update_connections(1)
	update_icon()

	return 1

/obj/structure/table/proc/unflip()
	reset_plane_and_layer()
	flipped = 0
	flags &= ~ON_BORDER
	for(var/D in list(turn(dir, 90), turn(dir, -90)))
		var/obj/structure/table/T = locate_within(get_step(src.loc,D), /obj/structure/table)
		if(T && T.flipped == 1 && T.dir == src.dir && material() && T.material()&& T.material().name == material().name)
			T.unflip()

	update_connections(1)
	update_icon()

	return 1

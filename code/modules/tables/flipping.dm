// Flipping a table on its side (a makeshift barricade) and putting it back: the menu's two ops (tables.dm), their conditions, and the flip itself. The
// whole straight run of tables of the same material goes over together, loose things on it are thrown, and the table takes a knock.

/obj/structure/table/proc/straight_table_check(direction)
	if(get_integrity() > 100)
		return 0
	var/obj/structure/table/T
	for(var/angle in list(-90,90))
		T = locate_within(get_step(src,turn(direction,angle)), /obj/structure/table)
		if(T && T.flipped == 0 && T.material() && T.material().name == material().name)
			return 0
	T = locate_within(get_step(src,direction), /obj/structure/table)
	if (!T || T.flipped == 1 || T.material() != material())
		return 1
	return T.straight_table_check(direction)

/// FALSE on tables that can never be flipped by hand (racks, fixed decorative tables): no Flip or Put back menu entries.
/obj/structure/table/var/can_flip_verb = TRUE

/// The table is standing and of a kind that can be flipped.
/obj/structure/table/proc/is_flippable(datum/act/A)
	return (can_flip_verb && flipped == 0) ? null : /datum/msg/req_failed

/// The table is lying on its side and of a kind that can be put back.
/obj/structure/table/proc/is_flipped_up(datum/act/A)
	return (can_flip_verb && flipped == 1) ? null : /datum/msg/req_failed

/// The actor has their hands and legs free and can touch the table (the old can_touch(), which also scolded: here it only answers).
/obj/structure/table/proc/actor_can_touch(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return FALSE
	if(user.restrained() || user.buckled_to())
		return FALSE
	if(user.stat || user.has_status(STAT_PARALYZED) || user.has_status(STAT_SLEEPING) || user.lying || user.has_status(STAT_WEAKENED)) // ALLOW(reads): posture is read when the touch is tried; a cached menu entry is advisory
		return FALSE
	return TRUE

/// Flipping asks the same (a mob nobody wants flipping tables, an ambient pest, is turned away by the effect).
/obj/structure/table/proc/actor_can_flip(datum/act/op/A)
	return (actor_can_touch(A)) ? null : MSG(table/hands_busy)

/// Flip's own precondition: a straight run of unflipped tables, toward the user's side.
/obj/structure/table/proc/can_flip_away(datum/act/op/A)
	var/direction = get_cardinal_dir(A.actor, src)
	return (straight_table_check(turn(direction, 90)) && straight_table_check(turn(direction, -90))) ? null : MSG(table/wont_budge)

/// Put back's precondition: nothing is in the way of the flipped table (and the flipped tables in line with it) standing up.
/obj/structure/table/proc/can_put_back(datum/act/op/A)
	return unflipping_check() == 1 ? null : (can_climb_turf(src) ? /datum/msg/table/in_the_way : /datum/msg/table/wont_budge)

/// The Flip table entry: flips a table away from the person, and shakes off whoever was climbing it.
/obj/structure/table/proc/flip_over(datum/act/op/A)
	if(has_trait(A.actor, TRAIT_AMBIENT_PEST_MOB))
		return OP_REFUSED
	if(!flip(get_cardinal_dir(A.actor, src)))
		return OP_FAILED
	climb_shake_off(src, A.actor)
	return OP_OK

/// Where a climber ends up on a flipped table: one standing on its tile climbs out the side it faces (when it can go there), anyone else onto the tile.
/obj/structure/table/proc/flipped_landing(mob/living/climber)
	if(flipped == 1 && climber.loc == loc)
		var/turf/T = get_step(src, dir)
		if(T?.Enter(climber))
			return T
	return null

/// The Put table back entry.
/obj/structure/table/proc/put_back(datum/act/op/A)
	unflip()
	return OP_OK

/// TRUE if the flipped table (and the flipped tables in line with it) can be put back, else why not.
/obj/structure/table/proc/unflipping_check(direction)

	for(var/mob/M in oview(src,0))
		return "it won't budge"

	var/obj/occupied = can_climb_turf(src)
	if(occupied)
		return "there's \a [occupied] in the way"

	var/list/L = list()
	if(direction)
		L.Add(direction)
	else
		L.Add(turn(src.dir,-90))
		L.Add(turn(src.dir,90))
	for(var/new_dir in L)
		var/obj/structure/table/T = locate_within(get_step(src,new_dir), /obj/structure/table)
		if(T && T.material() && T.material().name == material().name)
			if(T.flipped == 1 && T.dir == src.dir && T.unflipping_check(new_dir) != TRUE)
				return T.unflipping_check(new_dir)
	return 1

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
	set_flipped(1)
	flags |= ON_BORDER
	for(var/D in list(turn(direction, 90), turn(direction, -90)))
		var/obj/structure/table/T = locate_within(get_step(src,D), /obj/structure/table)
		if(T && T.flipped == 0 && material() && T.material() && T.material().name == material().name)
			T.flip(direction)
	take_damage(rand(5, 10), BRUTE, MELEE)
	update_connections(1)

	return 1

/obj/structure/table/proc/unflip()
	reset_plane_and_layer()
	set_flipped(0)
	flags &= ~ON_BORDER
	for(var/D in list(turn(dir, 90), turn(dir, -90)))
		var/obj/structure/table/T = locate_within(get_step(src,D), /obj/structure/table)
		if(T && T.flipped == 1 && T.dir == src.dir && material() && T.material()&& T.material().name == material().name)
			T.unflip()

	update_connections(1)

	return 1

/// Bluespace connection. Makes lockers into
/// portals: close one with something inside and it comes out of a connected exit. A capability
/// hooked on the closet_closed and hitby notices; the exits live on the closet as a relation list
/// view, or, on the permanent network, are GLOB.bslockers.
/// Connect with C.connect_bluespace(exits) or C.join_bluespace_network().
CAPABILITY_TYPE(bluespace_connection, CAP_BLUESPACE_CONNECTION, /datum/capability/bluespace_connection, key = NONE)
/datum/capability/bluespace_connection

/datum/capability/bluespace_connection/entries()
	return list(
		on_notice(/datum/notice/closet_closed, then(CAP_PROC(bluespace_closed))),
		on_notice(/datum/notice/hitby, then(CAP_PROC(bluespace_hit))),
	)

#define BLUESPACE_EXIT_SOUND 'sound/effects/clang.ogg'
#define BLUESPACE_THROW_RANGE 3
#define BLUESPACE_THROW_RANGE_X 5
#define BLUESPACE_THROW_RANGE_Y 5

/obj/structure/closet
	/// The exits this closet's bluespace connection leads to: a relation list view (lazy).
	var/list/atom/bluespace_exit_points
	/// TRUE: the exits are the permanent network (GLOB.bslockers), never severed.
	var/bluespace_permanent = FALSE

/// Connects this closet to `exits` (closets or other atoms).
/obj/structure/closet/proc/connect_bluespace(list/exits)
	for(var/atom/exit_point as anything in exits)
		if(!QDELETED(exit_point))
			rel_add(src, nameof(bluespace_exit_points), exit_point)
	grant(src, /datum/capability/bluespace_connection, src)

/// Joins the permanent network of bluespace lockers (GLOB.bslockers).
/obj/structure/closet/proc/join_bluespace_network()
	bluespace_permanent = TRUE
	grant(src, /datum/capability/bluespace_connection, src)

/obj/structure/closet/proc/bluespace_exits()
	if(bluespace_permanent)
		return GLOB.bslockers.Copy()
	return bluespace_exit_points ? bluespace_exit_points.Copy() : list()

/datum/capability/bluespace_connection/proc/bluespace_closed(datum/act/A)
	var/obj/structure/closet/assigned_closet = A.holder
	if(isemptylist(assigned_closet.contents))
		return
	var/list/exits = assigned_closet.bluespace_exits()
	if(!length(exits))
		assigned_closet.sever_bluespace(null)
		return

	var/exit_point = pick(exits)

	if(exit_point == assigned_closet)
		assigned_closet.sever_bluespace(exit_point)
		return

	if(istype(exit_point, /obj/structure/closet))
		var/obj/structure/closet/exit_closet = exit_point
		exit_closet.visible_message(span_notice("\The [exit_closet] rumbles..."), span_notice("Something rumbles..."))
		exit_closet.animate_shake()
		after(exit_closet, 1 SECONDS, TYPE_PROC_REF(/obj/structure/closet, open))

	playsound(exit_point, BLUESPACE_EXIT_SOUND, 50, TRUE)
	after(assigned_closet, 1.3 SECONDS, TYPE_PROC_REF(/obj/structure/closet, bluespace_exit), with = list(exit_point, assigned_closet.contents.Copy()))

/obj/structure/closet/proc/bluespace_exit(atom/exit_point, list/moving)
	// Nope, must be closed.
	if(opened)
		return

	if(QDELETED(exit_point))
		sever_bluespace(exit_point)
		return

	// Now the fun begins
	if(istype(exit_point, /obj/structure/closet))
		var/obj/structure/closet/exit_closet = exit_point
		if(!exit_closet.can_open()) // Bwomp. You're locked now. :)
			for(var/atom/movable/AM in moving)
				do_teleport(AM, exit_closet, channel = TELEPORT_CHANNEL_BLUESPACE, no_effects = TRUE)
			return
		exit_closet.open()

	var/turf/target = get_offset_target_turf(get_turf(src), rand(BLUESPACE_THROW_RANGE_X)-rand(BLUESPACE_THROW_RANGE_X), rand(BLUESPACE_THROW_RANGE_Y)-rand(BLUESPACE_THROW_RANGE_Y))

	for(var/atom/movable/AM in moving)
		if(QDELETED(AM))
			continue
		do_teleport(AM, get_turf(exit_point), channel = TELEPORT_CHANNEL_BLUESPACE, no_effects = TRUE)
		if(!isbelly(exit_point))
			AM.throw_at(target, BLUESPACE_THROW_RANGE, 1)

/datum/capability/bluespace_connection/proc/bluespace_hit(datum/act/A)
	var/obj/structure/closet/assigned_closet = A.holder
	if(assigned_closet.opened)
		assigned_closet.close()

/// Drops `removed_exit`; with no exits left the connection is severed. The permanent network only sparks.
/obj/structure/closet/proc/sever_bluespace(removed_exit)
	bluespace_sparks()
	if(bluespace_permanent)
		return TRUE
	if(removed_exit)
		rel_remove(src, nameof(bluespace_exit_points), removed_exit)
	if(!length(bluespace_exits())) // No exit points left, bluespace connection severed.
		rel_clear(src, nameof(bluespace_exit_points))
		revoke(src, /datum/capability/bluespace_connection, src)
	return TRUE

/obj/structure/closet/proc/bluespace_sparks()
	play_sfx(src, SFX_EFFECTS_SPARKS6)
	fx_sparks(loc, 2)

#undef BLUESPACE_EXIT_SOUND
#undef BLUESPACE_THROW_RANGE
#undef BLUESPACE_THROW_RANGE_X
#undef BLUESPACE_THROW_RANGE_Y

/obj/structure/closet/relations()
	. = ..()
	. += rel_many(nameof(bluespace_exit_points))

/// Swarming. Movables sharing a turf with another swarmer
/// spread out by a random pixel offset; alone again, they return. A shared behaviour
/// singleton on the moved event: whoever moves leaves the swarmers of its old turf and
/// joins those of its new one, so both sides of every pair stay in step. State lives on
/// the movable. A capability hooked on the moved notice: AM.enable_swarming() grants it.
CAPABILITY_TYPE(swarming, CAP_SWARMING, /datum/capability/swarming, key = NONE)
/datum/capability/swarming

/datum/capability/swarming/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(swarm_moved))))

/atom/movable
	/// Pixel offset used while swarming (set by enable_swarming()).
	var/swarm_offset_x = 0
	var/swarm_offset_y = 0
	/// TRUE while offset by swarming.
	var/is_swarming = FALSE
	/// The swarmers sharing our turf: a relation list view (lazy).
	var/list/atom/movable/swarm_members

/atom/movable/proc/enable_swarming(max_x = 24, max_y = 24)
	swarm_offset_x = rand(-max_x, max_x)
	swarm_offset_y = rand(-max_y, max_y)
	grant(src, /datum/capability/swarming, src)

/// TRUE if `AM` swarms.
/proc/is_swarmer(atom/movable/AM)
	return istype(AM) && granted(AM, /datum/capability/swarming)

/datum/capability/swarming/on_activate(datum/activation/A)
	join_turf(A.holder)

/datum/capability/swarming/on_deactivate(datum/activation/A)
	leave_all(A.holder)

/datum/capability/swarming/proc/swarm_moved(datum/act/A)
	var/atom/movable/AM = A.holder
	leave_all(AM)
	join_turf(AM)

/// Pairs `AM` with every other swarmer on its turf.
/datum/capability/swarming/proc/join_turf(atom/movable/AM)
	var/turf/T = AM.loc
	if(!isturf(T))
		return
	for(var/atom/movable/other in turf_contents_of_type(T, /atom/movable))
		if(other == AM || !is_swarmer(other))
			continue
		pair(AM, other)
		pair(other, AM)

/datum/capability/swarming/proc/pair(atom/movable/AM, atom/movable/other)
	if(QDELETED(other))
		return
	rel_add(AM, nameof(AM.swarm_members), other)
	swarm(AM)

/// Unpairs `AM` from every swarm-mate; mates left alone stop swarming.
/datum/capability/swarming/proc/leave_all(atom/movable/AM)
	for(var/atom/movable/other as anything in AM.swarm_members?.Copy())
		rel_remove(other, nameof(other.swarm_members), AM)
		if(!length(other.swarm_members))
			unswarm(other)
	rel_clear(AM, nameof(AM.swarm_members))
	unswarm(AM)

/datum/capability/swarming/proc/swarm(atom/movable/owner)
	if(!owner.is_swarming)
		owner.is_swarming = TRUE
		animate(owner, pixel_x = owner.pixel_x + owner.swarm_offset_x, pixel_y = owner.pixel_y + owner.swarm_offset_y, time = 2)

/datum/capability/swarming/proc/unswarm(atom/movable/owner)
	if(owner.is_swarming)
		animate(owner, pixel_x = owner.pixel_x - owner.swarm_offset_x, pixel_y = owner.pixel_y - owner.swarm_offset_y, time = 2)
		owner.is_swarming = FALSE

/atom/movable/relations()
	. = ..()
	. += rel_many(nameof(swarm_members))

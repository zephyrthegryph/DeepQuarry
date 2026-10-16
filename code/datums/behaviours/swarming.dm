/// Swarming. Movables sharing a turf with another swarmer
/// spread out by a random pixel offset; alone again, they return. A shared behaviour
/// singleton on the moved event: whoever moves leaves the swarmers of its old turf and
/// joins those of its new one, so both sides of every pair stay in step. State lives on
/// the movable. A capability hooked on the moved notice: AM.enable_swarming() grants it.
//
/// A type that always swarms declares it (CAPABILITIES(T) swarming()): its offset is rolled and it pairs with its turf's swarmers at init.
/// enable_swarming() grants it to one instance.
CAPABILITY_TYPE(swarming, CAP_SWARMING, /datum/capability/swarming, key = NONE)
/datum/capability/swarming
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/swarming/on_holder_init(datum/act/eval/A)
	var/atom/movable/AM = A.holder
	if(!istype(AM))
		return
	sparse_set_or(AM, swarm_offset_x, rand(-24, 24), 0)
	sparse_set_or(AM, swarm_offset_y, rand(-24, 24), 0)
	join_turf(AM)

/datum/capability/swarming/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(swarm_moved))))

/// Rare pixel-state and a sparse reciprocal relation, absent from ordinary movables.
sparse(/atom/movable, swarm_offset_x, type = num)
sparse(/atom/movable, swarm_offset_y, type = num)
sparse(/atom/movable, is_swarming, type = num)

/atom/movable/proc/is_swarming()
	return sparse_get_or(src, is_swarming, FALSE)

/atom/movable/proc/enable_swarming(max_x = 24, max_y = 24)
	sparse_set_or(src, swarm_offset_x, rand(-max_x, max_x), 0)
	sparse_set_or(src, swarm_offset_y, rand(-max_y, max_y), 0)
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
	link_make(AM, LK_SWARM_MEMBERS, other)
	swarm(AM)

/// Unpairs `AM` from every swarm-mate; mates left alone stop swarming.
/datum/capability/swarming/proc/leave_all(atom/movable/AM)
	for(var/atom/movable/other as anything in link_list(AM, LK_SWARM_MEMBERS))
		link_break(AM, LK_SWARM_MEMBERS, other)
		if(!length(link_list(other, LK_SWARM_MEMBERS)))
			unswarm(other)
	link_break(AM, LK_SWARM_MEMBERS)
	unswarm(AM)

/datum/capability/swarming/proc/swarm(atom/movable/owner)
	if(!owner.is_swarming())
		sparse_set_or(owner, is_swarming, TRUE, 0)
		animate(owner, pixel_x = owner.pixel_x + sparse_get_or(owner, swarm_offset_x, 0), pixel_y = owner.pixel_y + sparse_get_or(owner, swarm_offset_y, 0), time = 2)

/datum/capability/swarming/proc/unswarm(atom/movable/owner)
	if(owner.is_swarming())
		animate(owner, pixel_x = owner.pixel_x - sparse_get_or(owner, swarm_offset_x, 0), pixel_y = owner.pixel_y - sparse_get_or(owner, swarm_offset_y, 0), time = 2)
		sparse_set_or(owner, is_swarming, FALSE, 0)


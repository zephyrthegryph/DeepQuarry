/// Swarming (was /datum/component/swarming). Movables sharing a turf with another swarmer
/// spread out by a random pixel offset; alone again, they return. A shared behaviour
/// singleton on the moved event: whoever moves leaves the swarmers of its old turf and
/// joins those of its new one, so both sides of every pair stay in step. State lives on
/// the movable. Attach with AM.enable_swarming().
/datum/om/behaviour/swarming
	handles = list(/datum/om/event/moved)

/atom/movable
	/// Pixel offset used while swarming (set by enable_swarming()).
	var/swarm_offset_x = 0
	var/swarm_offset_y = 0
	/// TRUE while offset by swarming.
	var/is_swarming = FALSE
	/// om_handle()s of the swarmers sharing our turf (lazy).
	var/list/swarm_member_handles

/atom/movable/proc/enable_swarming(max_x = 24, max_y = 24)
	swarm_offset_x = rand(-max_x, max_x)
	swarm_offset_y = rand(-max_y, max_y)
	om_attach(src, /datum/om/behaviour/swarming)

/// TRUE if `AM` swarms.
/proc/is_swarmer(atom/movable/AM)
	return istype(AM) && om_attached(AM, /datum/om/behaviour/swarming)

/datum/om/behaviour/swarming/on_start(atom/movable/AM)
	join_turf(AM)

/datum/om/behaviour/swarming/on_stop(atom/movable/AM)
	leave_all(AM)

/datum/om/behaviour/swarming/on_moved(atom/movable/AM, datum/om/event/moved/event)
	leave_all(AM)
	join_turf(AM)

/// Pairs `AM` with every other swarmer on its turf.
/datum/om/behaviour/swarming/proc/join_turf(atom/movable/AM)
	var/turf/T = AM.loc
	if(!isturf(T))
		return
	for(var/atom/movable/other in T)
		if(other == AM || !is_swarmer(other))
			continue
		pair(AM, other)
		pair(other, AM)

/datum/om/behaviour/swarming/proc/pair(atom/movable/AM, atom/movable/other)
	var/h = om_handle(other)
	if(!h)
		return
	LAZYOR(AM.swarm_member_handles, h)
	swarm(AM)

/// Unpairs `AM` from every swarm-mate; mates left alone stop swarming.
/datum/om/behaviour/swarming/proc/leave_all(atom/movable/AM)
	var/my_h = om_handle(AM)
	for(var/h in AM.swarm_member_handles)
		var/atom/movable/other = om_resolve(h)
		if(!other)
			continue
		if(my_h)
			LAZYREMOVE(other.swarm_member_handles, my_h)
		if(!length(other.swarm_member_handles))
			unswarm(other)
	AM.swarm_member_handles = null
	unswarm(AM)

/datum/om/behaviour/swarming/proc/swarm(atom/movable/owner)
	if(!owner.is_swarming)
		owner.is_swarming = TRUE
		animate(owner, pixel_x = owner.pixel_x + owner.swarm_offset_x, pixel_y = owner.pixel_y + owner.swarm_offset_y, time = 2)

/datum/om/behaviour/swarming/proc/unswarm(atom/movable/owner)
	if(owner.is_swarming)
		animate(owner, pixel_x = owner.pixel_x - owner.swarm_offset_x, pixel_y = owner.pixel_y - owner.swarm_offset_y, time = 2)
		owner.is_swarming = FALSE

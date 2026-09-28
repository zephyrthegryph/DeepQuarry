/// The overheating state (was /datum/component/overheating): while the object is
/// above its heat limit (the overheating rule attaches this and detaches it when it
/// cools), a thermal damage stream proportional to the excess, OVERHEAT_DAMAGE_PER_KELVIN
/// per second per kelvin, between OVERHEAT_DAMAGE_MIN and OVERHEAT_DAMAGE_MAX per second.
/// A shared OM behaviour ticking once a second; it has no state of its own.
/datum/om/behaviour/overheating
	every = 1 SECONDS

/datum/om/behaviour/overheating/on_start(obj/O)
	O.on_overheat()

/datum/om/behaviour/overheating/tick(obj/O, dt)
	// The periodic lane this replaced passed its delta in deciseconds (10 per 1 s frame);
	// keep that rate exactly.
	overheat_step(O, dt * 10)

/// TRUE while `O` overheats.
/proc/overheating_active(obj/O)
	return om_attached(O, /datum/om/behaviour/overheating)

/// One step of `O`'s overheating damage stream.
/proc/overheat_step(obj/O, seconds_per_tick)
	if(QDELETED(O))
		return
	var/limit = PROPERTY(O, PROP_MELTING_POINT)
	var/excess = O.get_temperature() - (isnull(limit) ? INFINITY : limit)
	if(!(excess > 0))
		return
	O.apply_heat_damage(clamp(excess * OVERHEAT_DAMAGE_PER_KELVIN, OVERHEAT_DAMAGE_MIN, OVERHEAT_DAMAGE_MAX) * seconds_per_tick)

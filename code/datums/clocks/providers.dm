/**
 * # Clock providers (doc/medical_frameworks.md §1.2)
 *
 * A holder that slows time for what it holds (a freezer crate, a freezer box, the organ
 * gripper, a morgue tray, a cryobag, the MMI's cradle) sets `clock_speed`. Its clock is made
 * lazily, the first time something inside resolves its holder clock, and composes with the
 * clock of the holder it sits in: a cryobag in a freezer runs at the product of the two.
 *
 * The clock is deleted by clock_teardown() when the provider is; its bound contents rebind to
 * the parent clock and keep their pending events.
 */

/atom/movable
	/// Clock seconds per world second for things held inside this atom, or null when this atom
	/// provides no clock.
	var/clock_speed = null
	/// The clock this atom provides (lazy; see provided_clock()).
	var/tmp/datum/clock/own_clock

/atom/movable/provided_clock()
	if(isnull(clock_speed))
		return null
	if(!own_clock)
		own_clock = new /datum/clock(CLOCK_KIND_HOLDER, clock_speed, holder_clock(), src)
		own_clock.tie(src)
		if(GLOB.clock_trace)
			log_runtime("CLOCK: [type] made its holder clock at speed [own_clock.speed]")
	return own_clock

/// Changes the speed this holder provides (a freezer losing power). Pending events inside move
/// through the clock's rearm; nothing inside reschedules.
/atom/movable/proc/set_clock_speed(new_speed, reason)
	clock_speed = new_speed
	if(!own_clock)
		return
	if(isnull(new_speed))
		// No longer a provider: contents fall back to the next clock up.
		var/datum/clock/C = own_clock
		own_clock = null
		C.provider = null
		qdel(C)
		return
	own_clock.set_own_speed(new_speed, reason)

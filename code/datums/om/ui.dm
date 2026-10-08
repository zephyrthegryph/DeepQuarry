// Object-model core: Rust-owned watches (A.6) and dt helpers (K). The window push and status wake hooks that lived here are the
// UI push system (code/modules/tgui/ui_push.dm) and the window status watch (code/modules/tgui/ui_status.dm).

// ---------------------------------------------------------------- native (Rust) watches

// The DM half of Rust-owned watches. A behaviour declares wake_on_native
// bits; when it attaches, om_native_watch() tells the bridge which bits this
// entity needs. The reactor's drain calls om_native_deliver(E, bits) once per
// tick per entity, which runs on_native(E, bits) on each started behaviour
// declaring any of those bits. The bridge procs below are the stub interface:
// the reactor track replaces their bodies with its generated bindings.

/// Stub: register interest in native `bits` for `E` (reactor binding goes here).
/proc/om_native_bridge_watch(datum/E, bits)
	return FALSE

/// Stub: tell the native side `E`'s relevance level (reactor binding goes here).
/proc/om_native_bridge_relevance(datum/E, level)
	return FALSE

/proc/om_native_watch(datum/om/rec/rec)
	var/bits = 0
	for(var/datum/om/behaviour/B as anything in rec.att)
		bits |= B.wake_on_native
	if(bits != rec.native_bits)
		rec.native_bits = bits
		om_native_bridge_watch(rec.owner, bits)

/// Called by the reactor drain.
/proc/om_native_deliver(datum/E, bits)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return
	for(var/i in 1 to length(rec.att))
		var/datum/om/behaviour/B = rec.att[i]
		if((B.wake_on_native & bits) && (rec.att_state[i] & OM_ATT_STARTED))
			rec.sched.call_hook(rec, B, OM_HOOK_NATIVE, B.wake_on_native & bits)

/proc/om_native_relevance(datum/E, level)
	if(E)
		om_native_bridge_relevance(E, level)

// ---------------------------------------------------------------- dt helpers

/// Exponential approach of `x` toward `target` with rate `k` per second over `dt` seconds.
/// Exact for any dt: two half-steps equal one full step.
/proc/approach(x, target, k, dt)
	return target + (x - target) * NUM_E ** (-k * dt)

/// Exponential decay of `x` at `rate` per second over `dt` seconds.
/proc/decay(x, rate, dt)
	return x * NUM_E ** (-rate * dt)

/// TRUE with the probability that an event of `p_per_second` (0-1) happens within `dt` seconds.
/proc/chance_over(p_per_second, dt)
	if(p_per_second <= 0 || dt <= 0)
		return FALSE
	if(p_per_second >= 1)
		return TRUE
	return rand() < 1 - (1 - p_per_second) ** dt

/// Linear move of `x` toward `target` by at most `speed * dt`.
/proc/move_toward(x, target, speed, dt)
	var/delta = speed * dt
	if(abs(target - x) <= delta)
		return target
	return x + (target > x ? delta : -delta)

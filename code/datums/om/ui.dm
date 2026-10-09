// Object-model core: Rust-owned watches (A.6) and dt helpers (K). The window push and status wake hooks that lived here are the
// UI push system (code/modules/tgui/ui_push.dm) and the window status watch (code/modules/tgui/ui_status.dm).




/proc/om_native_deliver(datum/E, bits)
	return entity_native_deliver(E, bits)


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

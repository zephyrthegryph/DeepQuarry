/// The legacy scheduler's real timing columns, detached from its private state.
/// Keep ticks and tick_overrun rather than substituting times_fired/zero: the
/// performance log retains those exact historical values and column order.
/datum/system/behaviours/proc/performance_snapshot()
	return list("fire_cost" = fire_cost, "ticks" = ticks, "tick_overrun" = tick_overrun)

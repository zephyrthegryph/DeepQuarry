/// One cooldown of a keyed table (an offer key, a trigger window): when it started and how long it lasts. The contracts system owns each one
/// (offer_cooldowns, opportunity_cooldowns).
/datum/contract_cooldown
	var/duration = 0
	EXPIRY_DECLARE(started_at)

/// Starts (or restarts) the cooldown under `key` in the system's `table` (a var name), lasting `delay` from now.
/proc/contract_cooldown_start(table, key, delay)
	var/datum/contract_cooldown/cooldown = new
	cooldown.duration = delay
	STAMP(cooldown, started_at, CLOCK_WORLD)
	rel_add(SScontracts, table, cooldown, key = key)

/// The cooldown under `key` in `table` while it is still running, else null.
/proc/contract_cooldown_running(list/table, key)
	var/datum/contract_cooldown/cooldown = LAZYACCESS(table, key)
	if(cooldown && ELAPSED(cooldown, started_at, CLOCK_WORLD) < cooldown.duration)
		return cooldown
	return null

/// How much of a running cooldown is left.
/proc/contract_cooldown_left(datum/contract_cooldown/cooldown)
	return max(0, cooldown.duration - ELAPSED(cooldown, started_at, CLOCK_WORLD))

/// One cooldown of a keyed table (an offer key, a trigger window): the time it ends is a var, so it reads with the expiry forms.
/datum/contract_cooldown
	EXPIRY_DECLARE(until)

/// Starts (or restarts) the cooldown under `key` in `table`, lasting `delay` from now.
/proc/contract_cooldown_start(list/table, key, delay)
	var/datum/contract_cooldown/cooldown = table[key]
	if(!cooldown)
		cooldown = new /datum/contract_cooldown
		table[key] = cooldown
	EXPIRY_SET(cooldown, until, delay, CLOCK_WORLD)

/// The cooldown under `key` in `table` while it is still running, else null.
/proc/contract_cooldown_running(list/table, key)
	var/datum/contract_cooldown/cooldown = table[key]
	if(cooldown && EXPIRY_ACTIVE(cooldown, until, CLOCK_WORLD))
		return cooldown
	return null

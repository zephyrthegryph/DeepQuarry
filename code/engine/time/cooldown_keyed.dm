/// Starts `key` in a keyed cooldown table for `duration` from now and returns the table (created on first use). Entries whose end is past are dropped
/// first, so the table never grows past the keys that are still running.
/proc/cooldown_keyed_started(list/table, key, duration)
	var/now = TIME_NOW(CLOCK_WORLD)
	for(var/stale in table)
		if(table[stale] < now)
			table -= stale
	LAZYSET(table, key, now + duration)
	return table

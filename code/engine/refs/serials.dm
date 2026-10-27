// Serial numbers (code/__defines/engine/serials.dm, doc/rewrite/proposals/relations.md D9a). One counter per declared kind.

GLOBAL_LIST_EMPTY(serial_counters)

/// A serial kind: declared with SERIAL_DEF(), one instance per kind (GLOB.serial_counters), holding its counter.
/datum/serial
	/// The first number the kind issues.
	var/first = 1
	/// TRUE when the kind counts on from saved data: it is seeded before it issues.
	var/persisted = FALSE
	/// The number the next take returns; null until the first take (or seed).
	var/next_number
	/// Per-key counters of a keyed take: key -> next number.
	var/list/keyed
	/// Numbers issued since the world started, for the log and the debug view.
	var/issued = 0

/// The counter of kind `kind` (a /datum/serial path), made on first use.
/proc/serial_for(kind)
	var/datum/serial/S = GLOB.serial_counters[kind]
	if(S)
		return S
	if(!ispath(kind, /datum/serial))
		stack_trace("serial_for: [kind] is not a SERIAL_DEF kind")
		return null
	S = new kind()
	GLOB.serial_counters[kind] = S
	log_world("serial: [kind] declared, first [S.first][S.persisted ? ", persisted (waiting for its seed)" : ""]")
	return S

/// The next number of `kind`, or of its run for `key` when a key is given. Null (reported) from a persisted kind nobody has seeded.
/proc/serial_issue(kind, key)
	var/datum/serial/S = serial_for(kind)
	if(!S)
		return null
	if(S.persisted && isnull(S.next_number))
		stack_trace("serial_issue: persisted kind [kind] was never seeded: seed it from its saved data first")
		return null
	S.issued++
	if(!isnull(key))
		LAZYINITLIST(S.keyed)
		var/value = S.keyed[key]
		if(isnull(value))
			value = S.first
		S.keyed[key] = value + 1
		return value
	if(isnull(S.next_number))
		S.next_number = S.first
	var/number = S.next_number
	S.next_number = number + 1
	return number

/// Seeds `kind` so the next number is last_issued + 1 (a persisted kind's start from the database or the save).
/proc/serial_seed_kind(kind, last_issued)
	var/datum/serial/S = serial_for(kind)
	if(!S)
		return null
	if(!isnum(last_issued))
		stack_trace("serial_seed: [kind] seeded with [last_issued], not a number")
		return null
	S.next_number = max(S.first, last_issued + 1)
	log_world("serial: [kind] seeded, next [S.next_number]")
	return last_issued

/// Starts `kind` again at its first number.
/proc/serial_reset_kind(kind)
	var/datum/serial/S = serial_for(kind)
	if(!S)
		return
	S.next_number = S.persisted ? null : S.first
	S.keyed = null
	log_world("serial: [kind] reset after [S.issued] issued")

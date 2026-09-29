// Shared helpers for the standard capability library (doc/rewrite/dx_conventions.md §2).

/// Takes the entry out of a one-entry wrapper built by hand()/tool()/use_on()/insert() and makes
/// src its capability, so a library capability builds its entries with the standard constructors.
/datum/capability/proc/adopt_entry(datum/capability/entry/wrapper)
	var/datum/interaction/capability/E = wrapper.entry
	E.cap = src
	wrapper.entry = null
	return E

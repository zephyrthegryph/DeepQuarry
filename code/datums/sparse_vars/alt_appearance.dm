// Per-atom alternate-appearance storage: lazy tmp lists on /atom. An unset var
// costs an instance nothing (BYOND stores only vars that differ from the type
// default). Global helpers are the one read/write API.
//
// An atom holding either list refuses serialization (see /atom/state_refusal()
// in code/datums/state/base_codecs.dm): the entries are live HUD references.

/atom
	/// Alternate appearances this atom owns, keyed by appearance key. Null when none.
	var/tmp/list/alt_appearances_owned
	/// Alternate appearances this atom (a mob) is currently viewing. Null when none.
	var/tmp/list/alt_appearances_viewing

/proc/dq_get_alt_appearances(atom/a, create = FALSE)
	if(!a.alt_appearances_owned && create)
		a.alt_appearances_owned = list()
	return a.alt_appearances_owned

/proc/dq_clear_alt_appearances_component(atom/a)
	a.alt_appearances_owned = null

/proc/dq_get_viewing_alt_appearances(atom/a, create = FALSE)
	if(!a.alt_appearances_viewing && create)
		a.alt_appearances_viewing = list()
	return a.alt_appearances_viewing

/proc/dq_clear_viewing_alt_appearances_component(atom/a)
	a.alt_appearances_viewing = null

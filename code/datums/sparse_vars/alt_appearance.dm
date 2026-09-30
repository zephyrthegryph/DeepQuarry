// Per-atom alternate-appearance storage: lazy tmp lists on /atom. An unset var
// costs an instance nothing (BYOND stores only vars that differ from the type
// default). Global helpers are the read API; writes go through the ownership accessors.
//
// An atom holding either list refuses serialization (see /atom/state_refusal()
// in code/datums/state/base_codecs.dm): the entries are live HUD references.

/atom
	/// Alternate appearances this atom owns, keyed by appearance key (owned values). Null when none.
	var/tmp/list/alt_appearances_owned
	/// Alternate appearances this atom (a mob) is currently viewing: the relation list partnered with
	/// /datum/alternate_appearance/var/viewers. Null when none.
	var/tmp/list/datum/alternate_appearance/alt_appearances_viewing

/proc/dq_get_alt_appearances(atom/a)
	return a.alt_appearances_owned

/proc/dq_get_viewing_alt_appearances(atom/a)
	return a.alt_appearances_viewing

// Viewing is two-sided: showing an appearance to a mob lists each in the other, and either end
// dying drops it from the other's list (the client image comes off in hide()).
/atom/relations()
	. = ..()
	. += rel_many(nameof(alt_appearances_viewing), back = nameof(/datum/alternate_appearance::viewers))
/datum/alternate_appearance/relations()
	. = ..()
	. += rel_many(nameof(viewers), back = nameof(/atom::alt_appearances_viewing))

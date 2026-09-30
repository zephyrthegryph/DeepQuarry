// Small helpers for the capability library: a draw order, and the offered_when clause that says an actor has hands.

/// Sets C's draw order (lower first: a later layer covers an earlier one).
/proc/cap_layer_order(datum/capability/C, order)
	C.layer_order = order
	return C

/// offered_when clause proc: the actor has hands (not a silicon).
/proc/cap_actor_has_hands(mob/actor, atom/target, obj/item/held)
	return !issilicon(actor)

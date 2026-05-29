// Behavior-grant declarations on existing item types.
//
// Items declare what AI behaviors they grant to a mob holding them. The brain
// aggregates these into effective_behaviors on each slow tick.
//
// Uses the static-list-in-proc pattern: each item subtype overrides
// get_dq_granted_behaviors() and returns a proc-local `var/static/list/L`.
// That gives us per-subtype shared template lists with zero per-instance cost.
// The base proc returns null so items that grant nothing pay nothing.

/obj/item/proc/get_dq_granted_behaviors()
	return null

// --- Concrete grants --------------------------------------------------------

/obj/item/grenade/get_dq_granted_behaviors()
	var/static/list/L = list(/datum/ai_behavior/throw_grenade)
	return L

/obj/item/gun/get_dq_granted_behaviors()
	var/static/list/L = list(/datum/ai_behavior/aimed_shot)
	return L

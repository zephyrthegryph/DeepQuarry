// Helpers for bespoke entries (cap_hand()/cap_tool()/cap_use_on()/cap_insert()) that need more than
// their constructor offers: a legacy input entry point, start messages and tool costs, a wait, a draw
// order. Each returns the capability it was given, so it wraps a constructor call in capabilities().

/**
 * Puts a bespoke entry on a legacy input proc (INTERACTION_ENTRY_HAND: attack_hand, reached by hands,
 * the AI and cyborgs through silicon_use; INTERACTION_ENTRY_ALT: click_alt; INTERACTION_ENTRY_ITEM:
 * attackby). Entry-point interactions are tried in priority order and the first the actor MEANT
 * answers, so a hand entry never answers a click with an item in hand. `gated`: the holder's
 * hand_gate() runs first (FALSE: it works broken and unpowered, as an ungated attack_hand).
 */
/proc/cap_entry_point(datum/capability/entry/C, entry, gated = TRUE, consumes_input = TRUE)
	var/datum/interaction/capability/E = C.entry
	E.entry = entry
	E.behind_gate = gated
	E.consumes_input = consumes_input
	if(entry == INTERACTION_ENTRY_ALT)
		E.default_action = INPUT_ACTION_ALTERNATE
	return C

/// Start message (a /datum/msg type shown when a timed entry starts), tool fuel/charge and tool volume.
/proc/cap_entry_costs(datum/capability/entry/C, start, amount, volume)
	var/datum/interaction/capability/E = C.entry
	if(start)
		E.start_feedback = start
	if(!isnull(amount))
		E.tool_amount = amount
	if(!isnull(volume))
		E.tool_volume = volume
	return C

/// A wait before a non-tool entry's handler (cap_use_on/cap_insert), paid like any timed interaction.
/proc/cap_entry_delay(datum/capability/entry/C, delay)
	C.entry.duration = delay
	return C

/// Sets C's draw order (lower first: a later layer covers an earlier one).
/proc/cap_layer_order(datum/capability/C, order)
	C.layer_order = order
	return C

/**
 * Tells user why the capability entry they meant with `held` is refused, from a catch-all item
 * handler: a blocked resolver-native use_on entry otherwise falls through silently. TRUE when told.
 */
/proc/cap_tell_blocked_for(mob/user, atom/holder, obj/item/held)
	var/datum/interaction_resolution/R = interactions_for(user, holder, held, null, null, INPUT_ACTION_USE, null, TRUE, TRUE)
	for(var/datum/interaction/capability/E in R.blocked)
		if(!E.held_type || E.tool || !E.is_meant(user, holder, held))
			continue
		E.tell_blocked(user, holder, R.blocked[E])
		return TRUE
	return FALSE

/// offered_when clause proc: the actor has hands (not a silicon).
/proc/cap_actor_has_hands(mob/actor, atom/target, obj/item/held)
	return !issilicon(actor)

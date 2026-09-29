// Shared helpers for the standard capability library (doc/rewrite/dx_conventions.md §2).
//
// Every library constructor takes the standard gating arguments (behind, blocked_by, locked_by,
// needs, else_say, works_broken, works_unpowered, log), stored with cap_gating() and merged onto each
// entry by cap_apply_gating(), plus `layer =`: the layer name it draws (CAP_NO_LAYER: nothing).
// Entries are built with the standard constructors (cap_hand()/cap_tool()/cap_use_on()/cap_insert())
// and taken out of their wrapper with adopt_entry(), the one entry-building helper (M12). An entry
// passes only its own gating; the capability's comes on top centrally.

/// Takes the entry out of a one-entry wrapper built by cap_hand()/cap_tool()/cap_use_on()/cap_insert(),
/// makes src its capability and, with `id`, gives it a stable id (the predicate cache key: it must
/// differ wherever the tool or held type differs).
/datum/capability/proc/adopt_entry(datum/capability/entry/wrapper, id)
	var/datum/interaction/capability/E = wrapper.entry
	E.cap = src
	wrapper.entry = null
	if(id)
		E.id = id
	return E

/// Draws this capability's layer while `when` holds, unless it draws nothing (CAP_NO_LAYER).
/datum/capability/proc/draw_layer(datum/look/look, when = TRUE)
	if(!layer_name || layer_name == CAP_NO_LAYER)
		return
	look.overlay(layer_name, when = when)

/// needs: the actor can reach the holder (adjacent, silicon remote use, or a legacy entry).
/atom/proc/cap_in_reach(mob/user, obj/item/held)
	return dq_interaction_reach(user, src, held) ? TRUE : "you're too far away"

/// needs: the holder (an item) is in one of the actor's hands.
/atom/proc/cap_in_hand(mob/user, obj/item/held)
	return dq_interaction_self_reach(user, src, held) ? TRUE : "it's not in your hand"

/proc/is_bolted(atom/A)
	return !!(A.cap_state & CAP_BOLTED)

/proc/is_welded(atom/A)
	return !!(A.cap_state & CAP_WELDED)

/**
 * A held item used on itself (attack_self, the Z key): the holder is the item and the handler gets
 * `held` = the item. It runs from attack_self() (INTERACTION_ENTRY_SELF), not from clicks on the item,
 * so an empty hand still picks the item up. `requires` replaces the default in-hand reach clause
 * (REQ_IN_INVENTORY lets a worn item's native verb reach the same entry).
 *
 *	/datum/capability/two_handed/interactions(atom/holder)
 *		return list(adopt_entry(self_use("Wield", TYPE_PROC_REF(/obj/item, cap_two_handed_toggle))))
 */
/proc/self_use(name, handler, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, list/requires, priority, name_proc)
	var/datum/capability/entry/C = cap_hand(name, handler, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log, priority = priority, name_proc = name_proc)
	var/datum/interaction/capability/E = C.entry
	E.id = "self:[name]:[handler]"
	E.entry = INTERACTION_ENTRY_SELF
	E.requires = requires || list(REQ_SELF_USE_REACH)
	C.key = E.id
	return C

/// Sets D's var to a capability's type default unless the instance already differs from its compiled
/// default (a map edit, an earlier write): a capability's arguments are type defaults, instance vars win.
/proc/cap_default_var(datum/D, var_name, value)
	if(isnull(value) || D.vars[var_name] != initial(D.vars[var_name]))
		return FALSE
	D.vars[var_name] = value
	return TRUE

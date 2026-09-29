// Shared helpers for the standard capability library (doc/rewrite/dx_conventions.md §2).

/// Takes the entry out of a one-entry wrapper built by hand()/tool()/use_on()/insert() and makes
/// src its capability, so a library capability builds its entries with the standard constructors.
/datum/capability/proc/adopt_entry(datum/capability/entry/wrapper)
	var/datum/interaction/capability/E = wrapper.entry
	E.cap = src
	wrapper.entry = null
	return E

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
	var/datum/capability/entry/C = hand(name, handler, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log, priority = priority, name_proc = name_proc)
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

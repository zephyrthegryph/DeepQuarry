// Shared by the library capabilities: builds an entry with the standard constructors
// (cap_hand()/cap_tool()/cap_use_on()/cap_insert()) and makes it the owner capability's own.

/// Takes the entry out of a one-entry wrapper built by cap_hand()/cap_tool()/cap_use_on()/cap_insert(), makes
/// `owner` its capability and gives it a stable id (menus, logs and the shared predicate key).
/// The id must name everything its selector depends on (the held type, the stance).
/// empty_handed: offered only to an empty hand, so a held item goes to the item entries instead.
/proc/cap_claim_entry(datum/capability/owner, datum/capability/entry/wrapper, id, category, empty_handed = FALSE)
	var/datum/interaction/capability/E = wrapper.entry
	wrapper.entry = null
	E.cap = owner
	E.passes_cap = TRUE // handlers take (..., cap): M15
	E.id = id
	if(category)
		E.category = category
	if(empty_handed)
		E.offered_when = list(REQ_EMPTY_HANDED)
	return E

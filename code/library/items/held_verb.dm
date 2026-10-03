// held_verb(verb_path, slots = SLOT_ANY_HELD) (doc/rewrite/final_api.html, section 13 "Verbs and abilities": a runtime verb is granted through the verb store for as long as
// its source lasts): the item has a verb of its own only while a mob carries it, so a thing lying on the floor has none and nothing is added at init.
//
//   CAPABILITIES(/obj/item/storage/wallet/poly, held_verb(/obj/item/storage/wallet/poly/proc/change_color, SLOT_ANY_CARRIED))
//
// It replaces DECLARE_VERB on an item whose verb is `set src in usr`. The verb itself only starts an op (perform_op() with ORIGIN_VERB), since a gameplay
// command is an op. `slots` is where the item has to sit for the verb to be there: SLOT_ANY_HELD (a hand), SLOT_ANY_CARRIED (a hand or anything worn, a pocket
// included), or a slot id or list of them. The grant is the carrier's: the verb store holds it with the carrying mob as source, and it ends the moment the item leaves
// that slot or either end is deleted.

CAPABILITY_TYPE(verb_grant, CAP_VERB_GRANT, /datum/capability/lib/verb_grant, key = verb_path, verb_path = null)

/// The capability a held_verb() grants the carrier: its activation is the item's time in the slot, and the verb it brings is on the item (the source).
/datum/capability/lib/verb_grant

/datum/capability/lib/verb_grant/on_activate(datum/activation/A)
	var/datum/item = A.source
	if(A.scope == SCOPE_TYPE || isnull(verb_path) || !isdatum(item) || QDELETED(item))
		return
	om_grant(item, GRANT_VERB, verb_path, A.holder)

/datum/capability/lib/verb_grant/on_deactivate(datum/activation/A)
	var/datum/item = A.source
	if(A.scope == SCOPE_TYPE || isnull(verb_path) || !isdatum(item) || QDELETED(item))
		return
	om_revoke(item, GRANT_VERB, verb_path, A.holder)

/proc/held_verb(verb_path, slots = SLOT_ANY_HELD)
	return while_slotted(slots, verb_grant(verb_path), on = ON_HOLDER)

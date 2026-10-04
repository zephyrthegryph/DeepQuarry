// held_verb(verb_path, slots = SLOT_ANY_HELD) (doc/rewrite/final_api.html, section 13 "Verbs and abilities": a runtime verb is granted through the verb store for as long as
// its source lasts): the item has a verb of its own only while a mob carries it, so a thing lying on the floor has none and nothing is added at init.
//
//   CAPABILITIES(/obj/item/storage/wallet/poly, held_verb(/obj/item/storage/wallet/poly/proc/change_color, SLOT_ANY_CARRIED))
//
// It replaces DECLARE_VERB on an item whose verb is `set src in usr`. The verb itself only starts an op (perform_op() with ORIGIN_VERB), since a gameplay
// command is an op. `slots` is where the item has to sit for the verb to be there: SLOT_ANY_HELD (a hand), SLOT_ANY_CARRIED (a hand or anything worn, a pocket
// included), or a slot id or list of them. The grant is the carrier's: it is a granted_verb(on = ON_SOURCE) (code/engine/present/verbs.dm): the verb is on the item and the verb store holds it
// with the carrying mob as source, and it ends the moment the item leaves that slot or either end is deleted.

/proc/held_verb(verb_path, slots = SLOT_ANY_HELD)
	return while_slotted(slots, granted_verb(verb_path, on = ON_SOURCE), on = ON_HOLDER)

// Non-materializing reads for UI data and examine text (doc/rewrite/systems.md section 18).

/// The first thing in `slot_id` (null: the default slot) *if the ledger already exists*: never
/// builds the ledger, resolves the latent generator or materializes an entry. A holder without a
/// ledger has nothing real in its slots. The read for tgui_data()/examine(); slot_item() is for
/// actions.
/atom/proc/slot_item_real(slot_id)
	var/datum/ledger/L = containment_ledger()
	if(!L)
		return null
	var/list/things = L.slots[slot_id || L.default_id]
	return length(things) ? things[1] : null

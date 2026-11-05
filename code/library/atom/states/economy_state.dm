// economy: lazy state of /obj (storage contract, doc/rewrite/storage_contract.md): a row of an engine table keyed by the holder's slot, no var on the holder.
// read a field with STATE_PEEK(A, economy, field), write with STATE_SET(A, economy, field, value), end it with economy_clear(A).

/datum/economy_state
	parent_type = /datum/lazy_state
	var/economic_department
	var/economic_export_value = 0
	var/economic_producer_account = 0
	var/economic_sale_invoice_id = 0

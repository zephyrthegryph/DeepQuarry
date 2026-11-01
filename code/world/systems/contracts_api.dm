/// Contract lookup preserves the registered datum's identity.
/datum/system/contracts/proc/contract_by_id(id)
	return contracts_by_id[id]

/// Consoles walk detached keys, never a mutable reference to the owner's registry.
/datum/system/contracts/proc/contract_ids()
	var/list/ids = list()
	for(var/id in contracts_by_id)
		ids += id
	return ids

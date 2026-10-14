// Contract-system operations moved from code/modules/contracts/agent_fieldwork.dm.

/datum/system/contracts/proc/agent_contract_for_market_key(reservation_key) as /datum/contract/faction_agent
	if(!reservation_key)
		return null
	for(var/datum/contract/faction_agent/contract in active_contracts + grace_contracts)
		if(contract.offer_key == reservation_key)
			return contract
	return null

/datum/system/contracts/proc/agent_contact_contract(account_number, faction_id, reservation_key) as /datum/contract/faction_agent
	if(!account_number)
		return null
	for(var/datum/contract/faction_agent/contract in active_contracts + grace_contracts)
		if(contract.contact_cooperated || contract.contact_account_number != account_number || (faction_id && contract.agent_faction != faction_id) || (reservation_key && contract.offer_key != reservation_key))
			continue
		return contract
	return null

// Contract-system operations moved from code/modules/contracts/faction_agent_contracts.dm.

/datum/system/contracts/proc/agent_contract_definition_ids(datum/faction_agent_record/record) as /list
	var/static/list/base_definition_ids = list(
		"agent_cross_department_portfolio",
		"agent_reciprocal_trade",
		"agent_rush_brokerage",
		"agent_confidential_brokerage",
		"agent_department_endorsement",
	)
	var/list/definition_ids = base_definition_ids.Copy()
	if(record?.tier >= FACTION_AGENT_TIER_TRUSTED)
		definition_ids += "agent_red_exfiltration"
	return definition_ids

/datum/system/contracts/proc/queue_agent_vetting(account_number, faction_id)
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(account_number)
	if(!record || record.faction_id != faction_id || record.tier != FACTION_AGENT_TIER_CANDIDATE)
		return FALSE
	for(var/datum/contract/faction_agent/contract in offered_contracts + active_contracts + grace_contracts)
		if(contract.owner_account_number == account_number)
			return FALSE
	var/sequence = record.next_offer_sequence++
	return queue_offer("agent_vetting", list(
		"owner_account" = account_number,
		"agent_faction" = faction_id,
		"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
	), "Authenticated candidate vetting", "agent-vetting:[faction_id]:[account_number]:[sequence]", 120)

/datum/system/contracts/proc/queue_agent_offers(account_number, faction_id)
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(account_number)
	if(!record || record.faction_id != faction_id || record.tier < FACTION_AGENT_TIER_ACCREDITED)
		return FALSE
	for(var/datum/contract/faction_agent/active_contract in active_contracts)
		if(active_contract.owner_account_number == account_number)
			return FALSE
	for(var/datum/contract/faction_agent/grace_contract in grace_contracts)
		if(grace_contract.owner_account_number == account_number)
			return FALSE
	var/live_offers = 0
	var/list/live_definitions = list()
	for(var/datum/contract/faction_agent/offered_contract in offered_contracts)
		if(offered_contract.owner_account_number != account_number)
			continue
		live_offers++
		live_definitions |= offered_contract.definition_id
	var/list/available_definitions = agent_contract_definition_ids(record)
	available_definitions -= live_definitions
	var/offers_to_create = min(CARGO_MARKET_AGENT_OFFERS - live_offers, length(available_definitions))
	for(var/offer_index in 1 to offers_to_create)
		var/definition_id = pick_n_take(available_definitions)
		var/sequence = record.next_offer_sequence++
		queue_offer(definition_id, list(
			"owner_account" = account_number,
			"agent_faction" = faction_id,
			"profile_id" = agent_target_profile(faction_id),
			"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
		), "Confidential commission for an accredited faction agent", "agent:[faction_id]:[account_number]:[sequence]", 100)
	return TRUE

/datum/system/contracts/proc/queue_covert_market_investigation(suspect_account)
	if(!suspect_account)
		return FALSE
	for(var/datum/contract/contract in offered_contracts + active_contracts + grace_contracts)
		if(contract.definition_id == "covert_market_investigation" && contract.offer_context?["suspect_account"] == suspect_account)
			return TRUE
	return queue_offer("covert_market_investigation", list(
		"department" = DEPARTMENT_SECURITY,
		"suspect_account" = suspect_account,
		"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
	), "Forensic threshold reached in encrypted market telemetry", "covert-investigation:[suspect_account]", 90)

/datum/system/contracts/proc/handle_covert_market_investigation_closed(datum/contract/contract)
	var/suspect_account = contract.offer_context?["suspect_account"]
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(suspect_account)
	if(!record)
		return
	record.counter_offer_queued = FALSE
	if(contract.closure_code == CONTRACT_CLOSE_COMPLETED)
		record.exposure = max(0, record.exposure - FACTION_AGENT_INVESTIGATION_THRESHOLD)
		adjust_personal_faction_reputation(record.account_number, record.faction_id, -AGENT_INVESTIGATION_REPUTATION_PENALTY)
		for(var/datum/contract/faction_agent/agent_contract in active_contracts.Copy())
			if(agent_contract.owner_account_number != record.account_number)
				continue
			if(agent_contract.contact_account_number)
				adjust_personal_faction_reputation(agent_contract.contact_account_number, record.faction_id, -round(AGENT_INVESTIGATION_REPUTATION_PENALTY / 2))
			agent_contract.advance_discovery(AGENT_DISCOVERY_PROVEN, "Security completed a correlated investigation and burned the route.", 20)
			agent_contract.fail("Security correlated the principal and freight contact, burning the authenticated market route.")

/datum/system/contracts/proc/handle_agent_contract_closed(datum/contract/faction_agent/contract)
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(contract.owner_account_number)
	if(!record || record.faction_id != contract.agent_faction)
		return
	SSsupply?.release_agent_contract_market(contract)
	if(contract.red_contract)
		GLOB.station_faction_relations.deactivate_contract_operative(contract.owner_account_number, contract.id)
	if(contract.definition_id == "agent_vetting")
		if(contract.closure_code == CONTRACT_CLOSE_COMPLETED)
			GLOB.station_faction_relations.accredit_agent(contract.owner_account_number)
		else
			if(contract.closure_code == CONTRACT_CLOSE_FAILED)
				record.contracts_failed++
			after(src, CARGO_MARKET_AGENT_OFFER_DELAY, PROC_REF(queue_agent_vetting), with = list(contract.owner_account_number, contract.agent_faction))
		return
	if(contract.closure_code == CONTRACT_CLOSE_COMPLETED)
		record.contracts_completed++
	else if(contract.closure_code == CONTRACT_CLOSE_FAILED)
		record.contracts_failed++
	GLOB.station_faction_relations.refresh_agent_tier(record)
	after(src, CARGO_MARKET_AGENT_OFFER_DELAY, PROC_REF(queue_agent_offers), with = list(contract.owner_account_number, contract.agent_faction))

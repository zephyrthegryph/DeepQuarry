/datum/contract_definition/personal_outcome/research_internal_access
	id = "research_internal_access"
	title = "Open Technology Cooperative"
	description = "The Workers' Union offers a personal honorarium for keeping useful Research output aboard the station and selling it affordably to several crewmembers instead of exporting every prototype."
	issuer_name = "Workers' Union Technology Cooperative"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 800

/datum/contract_definition/personal_outcome/research_internal_access/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	contract.personal_reputation_reward = 15
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("department" = DEPARTMENT_RESEARCH, "rollup" = "staff"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	settlement.name = "Settled internal Research market"
	settlement.description = "Close one accounting period with 500 eligible Thalers in Research sales to at least three crew accounts under your staff identity."
	settlement.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 500)
	settlement.require_number("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_item_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_type_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 2)
	contract.add_requirement(settlement)

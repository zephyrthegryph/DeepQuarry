/datum/contract_definition/personal_outcome/cargo_local_priority
	id = "cargo_local_priority"
	title = "Local Supply Priority"
	description = "The Workers' Union offers a personal honorarium for retaining useful Cargo inventory for direct crew purchase while the Guild seeks outbound freight."
	issuer_name = "Workers' Union Local Supply Desk"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 750

/datum/contract_definition/personal_outcome/cargo_local_priority/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	contract.personal_reputation_reward = 13
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("department" = DEPARTMENT_CARGO, "rollup" = "staff"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	settlement.name = "Settled local Cargo market"
	settlement.description = "Close one accounting period with 600 eligible Thalers in Cargo sales to at least three crew accounts under your staff identity."
	settlement.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 600)
	settlement.require_number("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_item_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3)
	settlement.require_number("verified_type_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 2)
	contract.add_requirement(settlement)

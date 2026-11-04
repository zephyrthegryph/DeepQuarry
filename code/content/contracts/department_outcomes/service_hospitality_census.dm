/datum/contract_definition/outcome/service_hospitality_census
	initial_offers = 0
	auto_replace = FALSE
	id = "service_hospitality_census"
	title = "Station Hospitality Census"
	description = "The Interstellar Traders' Guild requests a live market sample from paid station hospitality. Completed register and scanner invoices provide the census without disclosing purchases beyond the receipts customers already receive."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "Interstellar Traders' Guild Hospitality Bureau"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 1900

/datum/contract_definition/outcome/service_hospitality_census/configure_contract(datum/contract/outcome/contract, list/context)
	contract.primary_target = context?["revenue_target"] || pick(800, 1000, 1200, 1500)
	contract.secondary_target = context?["customer_target"] || pick(4, 5, 6)
	contract.description = "Close one 15-minute accounting period with at least [contract.primary_target] Thalers in paid Civilian services for [contract.secondary_target] distinct customers. Refunded, anonymous, and self-paid invoices do not qualify."
	contract.station_reputation_reward = 7
	contract.department_reputation_reward = 22
	contract.personal_reputation_reward = 12
	configure_outcome_negotiations(contract, 45 MINUTES)
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("rollup" = "department"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	settlement.name = "Closed hospitality ledger"
	settlement.description = "Close an accounting period with [contract.primary_target] Thalers in qualifying sales to [contract.secondary_target] distinct customers."
	settlement.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
	settlement.require_number("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
	contract.add_requirement(settlement)
	contract.personal_side_definitions = list("service_gratuity_drive")

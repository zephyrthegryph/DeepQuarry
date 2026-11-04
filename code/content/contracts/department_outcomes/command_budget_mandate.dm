/datum/contract_definition/outcome/command_budget_mandate
	initial_offers = 0
	auto_replace = FALSE
	id = "command_budget_mandate"
	title = "Interdepartmental Capital Mandate"
	description = "NanoTrasen Finance requests a diversified monthly operating plan entered through the station's Department Management console."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Station Finance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2600

/datum/contract_definition/outcome/command_budget_mandate/configure_contract(datum/contract/outcome/contract, list/context)
	contract.primary_target = context?["allocation_target"] || pick(14000, 16000, 18000, 20000)
	contract.secondary_target = context?["department_target"] || pick(4, 5)
	contract.minimum_allocation = context?["minimum_allocation"] || 2000
	contract.description = "Complete one monthly budget and payroll cycle that actually funds at least [contract.primary_target] Thalers among [contract.secondary_target] station departments, with no qualifying department below [contract.minimum_allocation] Thalers and at least 75% of wages paid. Exploration is excluded and Command may retain no more than 3,000 Thalers under the diversified mandate."
	contract.station_reputation_reward = 14
	contract.department_reputation_reward = 20
	contract.personal_reputation_reward = 6
	configure_outcome_negotiations(contract, 30 MINUTES)
	var/datum/contract_requirement/event_count/settlement = new(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, list("rollup" = "station"))
	settlement.name = "Funded monthly mandate"
	settlement.description = "Close one cycle with [contract.primary_target] funded Thalers across [contract.secondary_target] qualifying departments while keeping Command's allocation at or below 3,000."
	settlement.require_number("funded_allocation_total", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
	settlement.require_number("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
	settlement.require_number("command_allocation", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 3000)
	settlement.require_number("payroll_coverage", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 0.75)
	contract.add_requirement(settlement)
	contract.personal_side_definitions = list("command_executive_reserve")

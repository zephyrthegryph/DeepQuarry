/datum/contract_definition/personal_outcome/command_executive_reserve
	id = "command_executive_reserve"
	title = "Executive Reserve Advisory"
	description = "Eclipse offers a private advisory fee for ensuring Command retains a conspicuous monthly allocation while NanoTrasen's public diversification mandate is active."
	issuer_name = "Eclipse Executive Advisory"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 900

/datum/contract_definition/personal_outcome/command_executive_reserve/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context, 20 MINUTES)
	contract.personal_reputation_reward = 16
	var/datum/contract_requirement/event_count/reserve = new(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, list("rollup" = "station"))
	reserve.name = "Command reserve allocation"
	reserve.description = "Close a funded budget cycle with at least 6,000 Thalers retained for Command. This directly conflicts with the public diversification mandate."
	reserve.require_number("command_allocation", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 6000)
	contract.add_requirement(reserve)

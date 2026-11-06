/datum/contract_definition/personal_outcome/service_gratuity_drive
	id = "service_gratuity_drive"
	title = "Premium Hospitality Trial"
	description = "The Traders' Guild offers a personal market-testing premium for voluntary gratuities recorded on station service invoices."
	issuer_name = "Interstellar Traders' Guild Hospitality Bureau"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 650

/datum/contract_definition/personal_outcome/service_gratuity_drive/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	contract.personal_reputation_reward = 12
	var/datum/contract_requirement/event_count/tips = new(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1, list("department" = DEPARTMENT_CIVILIAN, "rollup" = "staff"), null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	tips.name = "Settled voluntary gratuities"
	tips.description = "Close one accounting period with at least 150 eligible Thalers in voluntary gratuities under your staff identity."
	tips.require_number("tip", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 150)
	contract.add_requirement(tips)

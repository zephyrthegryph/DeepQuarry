/datum/contract_definition/social/program/station_festival
	id = "station_catering_commission"
	title = "Station Catering Commission"
	description = "TALON Cultural Exchange requests a paid catering service for a broad group of station personnel."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "TALON Cultural Exchange"
	issuer_faction = REPUTATION_FACTION_TALON
	reward = 3000
	expected_duration = 45 MINUTES

/datum/contract_definition/social/program/station_festival/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/customer_target = contract_scaled_participant_target(10, 3, 2)
	add_social_role(contract, "caterer", "Catering lead", "Plans, prepares, prices, and serves the commission.", list(DEPARTMENT_CIVILIAN), 1, 4)
	add_social_role(contract, "customer", "Catering customer", "Purchases and consumes a meal or drink from the commissioned service.", null, 3, 10)
	contract.personal_side_definitions = list("service_gratuity_drive")
	var/list/paid_checks = list(list("key" = "sale_invoice_id", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1))
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, customer_target, "Customers served", "Serve invoiced food or drink to [customer_target] distinct station customers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id", null, paid_checks)
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, min(5, customer_target), "Menu choice", "Serve [min(5, customer_target)] different prepared dishes or drinks as part of the order.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "item_type", null, paid_checks)

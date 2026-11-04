/datum/contract_definition/social/program/applied_chemistry
	id = "research_equipment_commission"
	title = "Station Equipment Commission"
	description = "Eclipse will subsidize useful Research equipment purchased by station departments for real operational use."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Applied Technologies"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 3200

/datum/contract_definition/social/program/applied_chemistry/configure_contract(datum/contract/social/contract, list/context)
	..()
	contract.description = "Build useful equipment, sell it through the Research checkout, and have several departments put it into operational use. Eclipse pays for equipment that leaves the shelf and gets used."
	add_social_role(contract, "designer", "Equipment designer", "Builds and prices equipment for an identified station need.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "customer", "Operational customer", "Purchases equipment for use in their department.", null, 2, 8)
	contract.personal_side_definitions = list("research_exclusive_export")
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 900, "Equipment in service", "Put 900 Thalers of purchased Research equipment into operational use.", "value", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 3, "Departments equipped", "Have purchased equipment used by three distinct station departments.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "customer_department")
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 4, "Useful deliveries", "Have four distinct purchased items used by their customers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "physical_item_id")

/datum/contract_definition/social/program/mutual_aid
	id = "interdepartmental_mutual_aid_compact"
	title = "Interdepartmental Mutual-Aid Compact"
	description = "The Worker's Union requests real resource transfers paired with useful cross-department outcomes."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "Worker's Union Mutual-Aid Council"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 3200

/datum/contract_definition/social/program/mutual_aid/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "coordinator", "Mutual-aid coordinator", "Allocates resources and resolves interdepartmental priorities.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "recipient", "Funded department lead", "Accepts funding and delivers a useful project for station operation.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 3, 7)
	var/datum/contract_requirement/paired_facts/projects = add_program_paired_facts(contract, CONTRACT_EVENT_MONEY_TRANSFERRED, CONTRACT_EVENT_ITEM_PRODUCED, "target_department", 3, "Funded station projects", "Fund three departments from the station account, then have each funded department produce useful equipment.", CONTRACT_EVIDENCE_SCOPE_ANY, "department")
	projects.first_filter.require_value("source_is_station", TRUE)
	projects.first_filter.require_value("target_is_department", TRUE)
	projects.first_filter.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 1000)
	projects.second_filter.require_number("value", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 100)

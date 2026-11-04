/datum/contract_definition/outcome/security_case_resolution
	initial_offers = 0
	auto_replace = FALSE
	id = "security_case_resolution"
	title = "Custodial Resolution Audit"
	description = "SolGov Justice Administration offers an audit award for documented custodial cases that conclude through release or parole after a meaningful detention period. Security-record transitions provide the audit trail."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "SolGov Justice Administration"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 2100

/datum/contract_definition/outcome/security_case_resolution/configure_contract(datum/contract/outcome/contract, list/context)
	contract.primary_target = context?["case_target"] || pick(2, 3, 4)
	contract.outcome_duration = context?["custody_duration"] || pick(2 MINUTES, 3 MINUTES, 4 MINUTES)
	contract.description = "Resolve [contract.primary_target] distinct Security cases through release or parole after at least [DisplayTimeText(contract.outcome_duration)] in recorded custody. Repeated edits to one record count only once."
	contract.station_reputation_reward = 10
	contract.department_reputation_reward = 25
	contract.personal_reputation_reward = 10
	configure_outcome_negotiations(contract, 45 MINUTES)
	var/datum/contract_requirement/event_count/cases = new(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, contract.primary_target, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	cases.name = "Properly resolved cases"
	cases.description = "Record [contract.primary_target] distinct releases or paroles after [DisplayTimeText(contract.outcome_duration)] in custody."
	cases.unique_field = "physical_subject_id"
	cases.require_tag("custody_resolution")
	cases.require_value("previous_status", "Incarcerated")
	cases.require_value("physical_custody_verified", TRUE)
	cases.require_number("custody_duration", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.outcome_duration)
	contract.add_requirement(cases)
	contract.personal_side_definitions = list("security_record_suppression")

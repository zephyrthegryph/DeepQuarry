/datum/contract_opportunity_rule/security_caseload
	id = "security_caseload"
	definition_id = "opportunity_case_review"
	description = "A varied docket of physically grounded cases created an independent review commission."
	window_duration = 15 MINUTES

/datum/contract_opportunity_rule/security_caseload/configure()
	var/datum/contract_opportunity_signal/cases = add_signal(new /datum/contract_opportunity_signal("cases", CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 4))
	cases.minimum_facts = 4
	cases.require_value("physical_custody_verified", TRUE)
	cases.require_diversity("record_id", 4)
	cases.require_diversity("physical_subject_id", 3)

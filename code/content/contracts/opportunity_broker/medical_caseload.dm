/datum/contract_opportunity_rule/medical_caseload
	id = "medical_caseload"
	definition_id = "opportunity_clinical_aftercare"
	description = "A diverse clinical caseload created a sponsored aftercare opportunity."
	window_duration = 12 MINUTES

/datum/contract_opportunity_rule/medical_caseload/configure()
	var/datum/contract_opportunity_signal/outcomes = add_signal(new /datum/contract_opportunity_signal("outcomes", CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 150, "improvement"))
	outcomes.minimum_facts = 4
	outcomes.maximum_fact_value = 50
	outcomes.maximum_actor_value = 75
	outcomes.require_station_source = TRUE
	outcomes.require_number("improvement", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 5)
	outcomes.require_diversity("subject_id", 3)
	outcomes.require_diversity("condition_type", 2)

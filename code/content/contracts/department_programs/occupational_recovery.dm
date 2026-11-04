// --------------------------------------------------------------------------
// Medical
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/occupational_recovery
	id = "occupational_recovery_program"
	title = "Occupational Recovery Program"
	description = "The Worker's Union requests measurable treatment of work-related conditions across the station workforce."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "Worker's Union Health Trust"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 2900

/datum/contract_definition/social/program/occupational_recovery/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/patient_target = contract_scaled_participant_target(6, 2)
	add_social_role(contract, "clinician", "Occupational clinician", "Coordinates diagnosis, treatment, and follow-up records.", list(DEPARTMENT_MEDICAL), 1, 4)
	add_social_role(contract, "patient", "Participating worker", "Participates in care and outcome follow-up.", null, 4, 12)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, patient_target * 50, "Clinical improvement", "Deliver substantial, measurable improvement across participating workers.", "improvement", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_paired_facts(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, CONTRACT_EVENT_MEDICAL_SCAN_CREATED, "subject_id", patient_target, "Documented recovery", "Improve and produce a follow-up body scan for the same [patient_target] participating workers.")

// Contract-system operations moved from code/modules/contracts/medical_trial.dm.

/// affliction_severity_changed event: republish trial eligibility and emit
/// the measured treatment outcome when a condition improves.
/datum/system/contracts/proc/on_affliction_severity_changed(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/carbon/human/patient = N.target
	var/datum/notice/affliction_severity_changed/event = N
	var/datum/affliction/A = event.affliction
	var/old_severity = event.old_severity
	if(!istype(patient) || !affliction_reports_clinical_outcomes(A))
		return
	A.update_contract_eligibility()
	var/improvement = old_severity - A.severity
	if(improvement < 1 || old_severity < MEDICAL_TRIAL_MINIMUM_BASELINE)
		return
	var/datum/contract_subject_identity/identity = subject_identity(patient)
	if(!identity)
		return
	emit_contract_event(CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, list(
		"department" = DEPARTMENT_MEDICAL,
		"subject_id" = identity.id,
		"subject_name" = patient.real_name,
		"condition_type" = A.type,
		"condition_name" = A.name,
		"metrics" = list(
			"improvement" = improvement,
			"initial_severity" = old_severity,
			"final_severity" = A.severity,
		),
		"detail" = "[patient.real_name]'s [A.name] improved by [round(improvement, 0.1)] severity.",
	), "medical-treatment:[REF(A)]:[world.time]:[A.severity]", patient, null, patient)

/// body_afflictions_changed event: an affliction can join or leave a body
/// without a severity change (an organ carrying afflictions is reattached, an
/// affliction is cured or cleared outright). Keep eligibility in step.
/datum/system/contracts/proc/on_body_afflictions_changed(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/carbon/human/patient = N.target
	var/datum/notice/body_afflictions_changed/event = N
	var/datum/affliction/A = event.affliction
	var/added = event.added
	if(!affliction_reports_clinical_outcomes(A))
		return
	if(added)
		A.update_contract_eligibility()
		return
	if(A.contract_eligibility_qualifying || A.contract_rare_eligibility_qualifying)
		A.contract_eligibility_qualifying = FALSE
		A.contract_rare_eligibility_qualifying = FALSE
		PUBLISH_LEGACY(patient, /datum/notice/mob_medical_issues_changed)

// Contract-system operations moved from code/modules/contracts/medical_case_report.dm.

/datum/system/contracts/proc/consider_rare_medical_case(mob/living/carbon/human/subject)
	if(!subject || subject.stat == DEAD || !subject.mind?.assigned_role)
		withdraw_rare_case_offers(subject)
		return
	var/list/qualifying_types = list()
	var/subject_id = subject_identity(subject)?.id
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		if(medical_rare_case_condition(condition))
			qualifying_types |= condition.type
	for(var/datum/contract/medical_case_report/report in offered_contracts.Copy())
		if(report.target_ref == subject_id && !(report.target_condition_type in qualifying_types))
			report.withdraw("The qualifying condition resolved before acceptance.")
	for(var/datum/contract/medical_case_report/report in active_contracts.Copy())
		if(report.target_ref == subject_id && !report.consent_time && !(report.target_condition_type in qualifying_types))
			report.withdraw("The qualifying presentation resolved before consent; no penalty was assessed.")
	for(var/datum/affliction/condition as anything in subject.get_afflictions())
		if(!medical_rare_case_condition(condition) || rare_case_contract_exists(subject_id, condition.type))
			continue
		queue_offer("medical_rare_case_report", list(
			"target_ref" = subject_id,
			"target_name" = subject.real_name,
			"condition_type" = condition.type,
			"condition_name" = condition.name,
		), "A qualifying rare clinical presentation was detected", "medical_rare_case_report:[subject_id]:[condition.type]", 90)

/datum/system/contracts/proc/rare_case_contract_exists(subject_ref, condition_type)
	for(var/datum/contract/medical_case_report/report in offered_contracts)
		if(report.target_ref == subject_ref && report.target_condition_type == condition_type)
			return TRUE
	for(var/datum/contract/medical_case_report/report in active_contracts)
		if(report.target_ref == subject_ref && report.target_condition_type == condition_type)
			return TRUE
	if(find_candidate("medical_rare_case_report:[subject_ref]:[condition_type]"))
		return TRUE
	return FALSE

/datum/system/contracts/proc/withdraw_rare_case_offers(mob/living/carbon/human/subject)
	if(!subject)
		return
	for(var/datum/contract/medical_case_report/report in offered_contracts.Copy())
		if(report.target_ref == subject_identity(subject)?.id)
			report.withdraw("The patient is no longer available for this report.")
	var/subject_ref = subject_identity(subject)?.id
	for(var/datum/contract_offer_candidate/candidate in offer_candidates.Copy())
		if(candidate.definition_id == "medical_rare_case_report" && candidate.context["target_ref"] == subject_ref)
			withdraw_candidate(candidate, "The patient is no longer available for this report.")

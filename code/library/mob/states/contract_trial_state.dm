// contract_trial: lazy owned state of /mob/living/carbon/human (storage contract, doc/rewrite/storage_contract.md). It does not exist until the first write;
// read a field with STATE_GET(M, contract_trial, field), write with STATE_SET(M, contract_trial, field, value), end it with contract_trial_clear(M).

/datum/contract_trial_state
	var/list/clinical_exposure_history
	var/list/contract_medical_indications

/mob/living/carbon/human
	var/datum/contract_trial_state/contract_trial

/datum/contract_definition/social/program/blood_reserve
	id = "blood_reserve_campaign"
	title = "Blood Reserve Campaign"
	description = "VeyMed requests a diverse, traceable blood reserve collected under Medical supervision."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "VeyMed Transfusion Services"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 2600

/datum/contract_definition/social/program/blood_reserve/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/donor_target = contract_scaled_participant_target(4, 2, 3)
	add_social_role(contract, "clinician", "Transfusion coordinator", "Screens donors and manages safe blood collection.", list(DEPARTMENT_MEDICAL), 1, 3)
	add_social_role(contract, "donor", "Registered donor", "Contributes to the station reserve under Medical supervision.", null, 4, 12)
	add_program_count(contract, CONTRACT_EVENT_BLOOD_DONATED, donor_target * 150, "Reserve volume", "Collect [donor_target * 150] units of blood into the station reserve.", "amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_BLOOD_DONATED, donor_target, "Donor participation", "Collect from [donor_target] distinct donors.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")

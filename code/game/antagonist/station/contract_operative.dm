/// Applied only after a trusted faction agent explicitly accepts a red
/// contract. Accreditation and ordinary grey-market work never grant
/// antagonist status by themselves.
/datum/antagonist/contract_operative
	id = CONTRACT_OPERATIVE_ANTAG_ID
	role_type = BE_RENEGADE
	role_text = "Contract Operative"
	role_text_plural = "Contract Operatives"
	bantype = "renegade"
	avoid_silicons = TRUE
	welcome_text = "You accepted an explicitly antagonistic red contract. Your authority is bounded by its written objective and the server rules."
	antag_text = "You are a contract antagonist. Pursue the red contract you knowingly accepted, keep the conflict roleplay-focused, and do not treat this status as unrestricted permission to grief or escalate beyond the objective. All server rules still apply."
	flags = ANTAG_SUSPICIOUS | ANTAG_IMPLANT_IMMUNE
	can_speak_aooc = FALSE

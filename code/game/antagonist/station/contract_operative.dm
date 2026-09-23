GLOBAL_DATUM(contract_operatives, /datum/antagonist/contract_operative)

/**
 * A bounded antagonist role granted only while a trusted faction agent is
 * carrying an accepted red contract. The contract owns both enrollment and
 * removal; this datum must never recruit roundstart or latejoin candidates.
 */
/datum/antagonist/contract_operative
	id = CONTRACT_OPERATIVE_ANTAG_ID
	role_text = "Contract Operative"
	role_text_plural = "Contract Operatives"
	bantype = "operative"
	feedback_tag = "contract_operative_objective"
	avoid_silicons = TRUE
	can_speak_aooc = FALSE
	flags = ANTAG_SUSPICIOUS
	antaghud_indicator = "hudoperative"
	welcome_text = "You have accepted a high-risk faction contract. Your authorization lasts only while that contract remains active. Pursue its written objective within the server rules and preserve other players' opportunities for roleplay."
	antag_text = "You are a contract operative for one accepted assignment. This status authorizes the conduct described by that contract; it is not permission for unrelated antagonism."

/datum/antagonist/contract_operative/New()
	..()
	GLOB.contract_operatives = src

/datum/antagonist/contract_operative/get_candidates(ghosts_only)
	return list()

/datum/antagonist/contract_operative/attempt_random_spawn()
	return FALSE

/datum/antagonist/contract_operative/can_late_spawn()
	return FALSE

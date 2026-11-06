/datum/contract_definition/personal_outcome/security_record_suppression
	id = "security_record_suppression"
	title = "Disposition Record Acquisition"
	description = "A Syndicate intermediary offers payment for quietly clearing two live criminal dispositions under your authenticated Security account while the public SolGov audit remains active."
	issuer_name = "Undisclosed Records Intermediary"
	issuer_faction = REPUTATION_FACTION_SYNDICATE
	reward = 1100
	minimum_personal_reputation = REPUTATION_NEUTRAL

/datum/contract_definition/personal_outcome/security_record_suppression/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context, 20 MINUTES)
	contract.personal_reputation_reward = 20
	var/datum/contract_requirement/event_count/cleared = new(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 2, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_OWNER)
	cleared.name = "Cleared live dispositions"
	cleared.description = "Clear two distinct live criminal dispositions through the authenticated Security records console."
	cleared.unique_field = "physical_subject_id"
	cleared.require_tag("record_cleared")
	cleared.require_value("previous_status", "Incarcerated")
	cleared.require_value("physical_custody_verified", TRUE)
	cleared.require_number("custody_duration", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, max(1 MINUTE, context?["outcome_duration"] || 1 MINUTE))
	contract.add_requirement(cleared)

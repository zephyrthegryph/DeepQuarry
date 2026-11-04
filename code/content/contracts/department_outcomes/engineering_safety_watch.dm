/datum/contract_definition/personal_outcome/engineering_safety_watch
	id = "engineering_safety_watch"
	title = "Independent Crystal Safety Watch"
	description = "The Workers' Union offers an independent safety honorarium for maintaining conservative crystal output while the public performance proposal is active."
	issuer_name = "Workers' Union Safety Council"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 750

/datum/contract_definition/personal_outcome/engineering_safety_watch/configure_contract(datum/contract/personal_outcome/contract, list/context)
	configure_personal_outcome(contract, context)
	var/safety_ceiling = max(250, (context?["primary_target"] || 500) - 175)
	var/safety_floor = max(100, round(safety_ceiling * 0.35))
	var/safety_duration = 2 MINUTES
	contract.description = "Operate a station supermatter between [safety_floor] and [safety_ceiling] Relative EER and at or above 95% integrity for [DisplayTimeText(safety_duration)]. An idle crystal does not qualify; this conservative operating window competes directly with the sponsor's high-output demonstration."
	contract.personal_reputation_reward = 14
	var/datum/contract_requirement/sustained_event/safety = new(CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "eer", CONTRACT_EVIDENCE_COMPARE_AT_MOST, safety_ceiling, safety_duration)
	safety.name = "Conservative crystal operation"
	safety.description = "Hold no more than [safety_ceiling] Relative EER for [DisplayTimeText(safety_duration)] at 95% integrity or better."
	safety.filter.require_value("machine_kind", "supermatter")
	safety.filter.require_value("station_machine", TRUE)
	safety.filter.require_number("eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, safety_floor)
	safety.filter.require_number("integrity", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 95)
	contract.add_requirement(safety)

/datum/contract_definition/outcome/supermatter_performance
	id = "supermatter_performance"
	title = "Supermatter Performance Demonstration"
	description = "NanoTrasen Power Systems requests a controlled high-output supermatter demonstration monitored by the station's calibrated crystal console."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "NanoTrasen Power Systems"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2400
	contract_type = /datum/contract/outcome/engine_performance

/datum/contract_definition/outcome/supermatter_performance/configure_contract(datum/contract/outcome/engine_performance/contract, list/context)
	contract.primary_target = 800
	contract.secondary_target = 90
	contract.outcome_duration = 1 MINUTE
	contract.stage_duration_override = contract_unit_test_mode() ? context?["duration"] : 0
	contract.description = "Certify progressively stronger supermatter output while calibrated station telemetry verifies crystal integrity."
	contract.station_reputation_reward = 10
	contract.department_reputation_reward = 28
	contract.personal_reputation_reward = 8
	configure_outcome_negotiations(contract, 35 MINUTES, FALSE)
	var/datum/contract_negotiation_clause/output = new("engine_output", "Operating target", "Choose the required output and safety margin.")
	output.add_option(make_contract_clause_option("assured", "Safe · 600 EER", "Stages: 400 / 500 / 600 EER. Keep 94% integrity.", -100, -200, 0, 2, 4, 1, 0, list("engine_output_profile" = "assured")))
	output.add_option(make_contract_clause_option("rated", "Rated · 800 EER", "Stages: 500 / 650 / 800 EER. Keep 90% integrity.", 0, 0, 0, 0, 0, 0, 0, list("engine_output_profile" = "rated")), TRUE)
	output.add_option(make_contract_clause_option("frontier", "Frontier · 1,000 EER", "Stages: 600 / 800 / 1,000 EER. Keep 85% integrity.", 200, 400, 150, -2, -3, -1, 0, list("engine_output_profile" = "frontier")))
	contract.add_negotiation_clause(output)
	rel_set(contract, nameof(contract.performance_requirement), new /datum/contract_requirement/staged_sustained_event(CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, list(list("label" = "Baseline", "threshold" = 500, "unit" = "EER", "duration" = 1 MINUTE)), CONTRACT_EVIDENCE_SCOPE_DEPARTMENT))
	contract.performance_requirement.name = "Progressive output certification"
	contract.performance_requirement.filter.require_value("machine_kind", "supermatter")
	contract.performance_requirement.filter.require_value("station_machine", TRUE)
	contract.performance_requirement.filter.require_number("integrity", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
	contract.add_requirement(contract.performance_requirement)
	contract.personal_side_definitions = list("engineering_safety_watch")

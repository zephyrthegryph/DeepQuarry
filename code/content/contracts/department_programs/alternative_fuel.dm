/datum/contract_definition/social/program/alternative_fuel
	id = "alternative_fuel_demonstration"
	title = "Alternative Fuel Demonstration"
	description = "Focal Point Energetics requests a stable high-output engine run using a diverse, low-phoron chamber mixture."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "Focal Point Energetics"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3400
	expected_duration = 90 MINUTES
	contract_type = /datum/contract/social/alternative_fuel_trial

/datum/contract_definition/social/program/alternative_fuel/configure_contract(datum/contract/social/alternative_fuel_trial/contract, list/context)
	..()
	add_social_role(contract, "operator", "Engine operator", "Designs and operates the alternative chamber mixture.", list(DEPARTMENT_ENGINEERING), 1, 3)
	add_social_role(contract, "observer", "Independent technical observer", "Reviews safety and performance on behalf of another department.", list(DEPARTMENT_RESEARCH, DEPARTMENT_COMMAND), 1, 3)
	contract.personal_side_definitions = list("engineering_safety_watch")
	var/datum/contract_negotiation_clause/fuel_protocol = new("fuel_protocol", "Fuel protocol", "Choose the chamber mixture and required output stages.")
	fuel_protocol.add_option(make_contract_clause_option("conservative", "Safe · 450 EER", "Stages: 250 / 350 / 450 EER. Under 10% phoron, 4,000 K, and above 92% integrity.", -100, -150, 50, 2, 4, 2, 0, list("fuel_certification_profile" = "conservative")))
	fuel_protocol.add_option(make_contract_clause_option("balanced", "Mixed gas · 650 EER", "Stages: 300 / 450 / 650 EER. Under 15% phoron, 4,500 K, and above 85% integrity.", 0, 0, 0, 0, 0, 0, 0, list("fuel_certification_profile" = "balanced")), TRUE)
	fuel_protocol.add_option(make_contract_clause_option("phoron_free", "No phoron · 500 EER", "Stages: 200 / 325 / 500 EER with effectively no phoron.", 100, 250, 50, 2, 5, 2, 5 MINUTES, list("fuel_certification_profile" = "phoron_free")))
	contract.add_negotiation_clause(fuel_protocol)
	var/static/list/output_checks = list(
		list("key" = "station_machine", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1),
		list("key" = "gas_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 2),
		list("key" = "plasma_fraction", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 0.15),
		list("key" = "integrity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 85),
	)
	rel_set(contract, nameof(contract.output_requirement), new /datum/contract_requirement/staged_sustained_event(CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, list(list("label" = "Pilot output", "threshold" = 300, "unit" = "EER", "duration" = 45 SECONDS)), CONTRACT_EVIDENCE_SCOPE_DEPARTMENT))
	contract.output_requirement.name = "Alternative-fuel output stages"
	for(var/list/check as anything in output_checks)
		contract.output_requirement.filter.require_number(check["key"], check["comparator"], check["expected"])
	contract.output_requirement.filter.require_value("machine_kind", "supermatter")
	contract.add_requirement(contract.output_requirement)
	rel_set(contract, nameof(contract.thermal_requirement), add_program_sustained(contract, CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "temperature", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 4500, 2 MINUTES, 1, "Thermal control", "Keep the qualifying engine below 4,500 K for the full demonstration.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, list("machine_kind" = "supermatter"), list(list("key" = "eer", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 300))))
	add_program_sustained(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, "service_id", "powered_channels", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3, 3 MINUTES, 4, "Commissioned station service", "After the engine trial, hold four APC service zones at full power for three minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	var/datum/contract_negotiation_clause/commissioning = new("commissioning_priority", "Commissioning priority", "Choose what the station must protect while pursuing the performance award.")
	commissioning.add_option(make_contract_clause_option("reserve", "Protect reserve", "Keep the safer operating margin; Engineering receives more of the award.", -100, 250, -50, 1, 3, 0, 10 MINUTES, list("requirement_floors" = list("Alternative-fuel output stages" = 0.75))))
	commissioning.add_option(make_contract_clause_option("balanced", "Service first", "Use the standard limits and prove useful station service.", 0, 0, 0), TRUE)
	commissioning.add_option(make_contract_clause_option("sponsor", "Peak demonstration", "Pursue the full output envelope on a shorter schedule for a larger shared award.", 200, 150, 150, 0, 0, 0, -10 MINUTES))
	contract.add_negotiation_clause(commissioning)

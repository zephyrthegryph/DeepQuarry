/// Declarative authoring helpers for the broad departmental contract catalog.
/// These only compose the generic event requirements; gameplay facts continue
/// to come from their authoritative power, atmos, medicine, research, economy,
/// service, security, and automation systems.

/proc/add_program_count(datum/contract/social/contract, event_type, target, name, description, value_field = null, scope_mode = CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, unique_field = null, list/exact_values, list/numeric_checks) as /datum/contract_requirement/event_count
	var/datum/contract_requirement/event_count/requirement = new(event_type, target, exact_values, value_field, TRUE, scope_mode)
	requirement.name = name
	requirement.description = description
	requirement.unique_field = unique_field
	for(var/list/check as anything in numeric_checks)
		requirement.require_number(check["key"], check["comparator"], check["expected"])
	contract.add_requirement(requirement)
	return requirement

/proc/add_program_portfolio(datum/contract/social/contract, event_type, target, category_field, value_field, category_target, name, description, scope_mode = CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, list/exact_values, list/numeric_checks, maximum_fact_value = INFINITY, maximum_category_value = INFINITY) as /datum/contract_requirement/fact_portfolio
	var/datum/contract_requirement/fact_portfolio/requirement = new(event_type, target, category_field, value_field, category_target, scope_mode)
	requirement.name = name
	requirement.description = description
	requirement.maximum_fact_value = maximum_fact_value
	requirement.maximum_category_value = maximum_category_value
	for(var/key in exact_values)
		requirement.require_value(key, exact_values[key])
	for(var/list/check as anything in numeric_checks)
		requirement.require_number(check["key"], check["comparator"], check["expected"])
	contract.add_requirement(requirement)
	return requirement

/proc/add_program_sustained(datum/contract/social/contract, event_type, entity_field, numeric_field, comparator, threshold, duration, target, name, description, scope_mode = CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, list/exact_values, list/numeric_checks) as /datum/contract_requirement/sustained_event
	var/datum/contract_requirement/sustained_event/requirement = new(event_type, entity_field, numeric_field, comparator, threshold, duration, target, scope_mode)
	requirement.name = name
	requirement.description = description
	for(var/key in exact_values)
		requirement.filter.require_value(key, exact_values[key])
	for(var/list/check as anything in numeric_checks)
		requirement.filter.require_number(check["key"], check["comparator"], check["expected"])
	contract.add_requirement(requirement)
	return requirement

/// A physical stock order is complete only when one batch first passes its
/// assay and that same fingerprint subsequently leaves on the cargo shuttle.
/datum/contract_requirement/qualified_material_delivery
	name = "Qualified material delivery"
	var/datum/contract_event_filter/assay_filter
	var/minimum_amount = 1
	var/list/qualified_lots
	var/source_department

/datum/contract_requirement/qualified_material_delivery/New(list/checks, amount = 1, _source_department)
	. = ..()
	source_department = _source_department
	assay_filter = new(source_department ? CONTRACT_EVIDENCE_SCOPE_ANY : CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	if(source_department)
		assay_filter.require_value("department", source_department)
	minimum_amount = max(1, amount)
	qualified_lots = list()
	for(var/list/check as anything in checks)
		assay_filter.require_number(check["key"], check["comparator"], check["expected"])
	assay_filter.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, minimum_amount)
	event_types = list(CONTRACT_EVENT_MATERIAL_CERTIFIED, CONTRACT_EVENT_ITEM_EXPORTED)

/datum/contract_requirement/qualified_material_delivery/Destroy()
	QDEL_NULL(assay_filter)
	qualified_lots = null
	return ..()

/datum/contract_requirement/qualified_material_delivery/handle_event(datum/contract_event/event)
	if(state != CONTRACT_REQUIREMENT_PENDING)
		return FALSE
	if(event.event_type == CONTRACT_EVENT_MATERIAL_CERTIFIED)
		if(!assay_filter.matches(event, contract))
			return FALSE
		var/lot_id = event.value("material_lot_id")
		if(!lot_id)
			return FALSE
		qualified_lots["[lot_id]"] = event.value("contributor_account")
		contract.audit(CONTRACT_AUDIT_PROGRESS, "[name]: lot [lot_id] passed assay and awaits Cargo shipment.")
		return TRUE
	if(event.event_type != CONTRACT_EVENT_ITEM_EXPORTED || event.value("origin_department") != (source_department || contract.department) || event.value("handling_department") != DEPARTMENT_CARGO || event.value("material_amount") < minimum_amount)
		return FALSE
	var/lot_id = "[event.value("material_lot_id")]"
	if(!(lot_id in qualified_lots))
		return FALSE
	return add_progress(1, qualified_lots[lot_id], "Assayed material lot [lot_id] was accepted as Cargo freight.")

/datum/contract_requirement/qualified_material_delivery/progress_text()
	if(state == CONTRACT_REQUIREMENT_COMPLETE)
		return "Assay and delivery complete"
	return length(qualified_lots) ? "Qualified lot awaiting Cargo shipment" : "Batch awaiting assay"

/proc/add_material_delivery(datum/contract/social/contract, list/checks, amount, name, description, source_department)
	var/datum/contract_requirement/qualified_material_delivery/requirement = new(checks, amount, source_department)
	requirement.name = name
	requirement.description = description
	contract.add_requirement(requirement)
	return requirement

/proc/add_program_paired_facts(datum/contract/social/contract, first_event_type, second_event_type, join_field, target, name, description, scope_mode = CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, second_join_field) as /datum/contract_requirement/paired_facts
	var/datum/contract_requirement/paired_facts/requirement = new(first_event_type, second_event_type, join_field, target, scope_mode, second_join_field)
	requirement.name = name
	requirement.description = description
	contract.add_requirement(requirement)
	return requirement

/// Keep social breadth meaningful without making low-population offers impossible.
/proc/contract_scaled_participant_target(desired, minimum = 2, crew_per_participant = 2)
	var/active_crew = 0
	for(var/mob/living/player in GLOB.player_list)
		if(player.client && player.stat != DEAD)
			active_crew++
	return min(desired, max(minimum, CEILING(active_crew / crew_per_participant, 1)))

/datum/contract_definition/social/program
	abstract_type = /datum/contract_definition/social/program
	expected_duration = 25 MINUTES
	max_simultaneous = 1
	var/station_reputation = 8
	var/department_reputation = 24
	var/staff_reputation = 12

/datum/contract_definition/social/program/configure_contract(datum/contract/social/contract, list/context)
	..()
	contract.deadline_duration = expected_duration
	configure_social_identity(contract, station_reputation, department_reputation, staff_reputation)

// --------------------------------------------------------------------------
// Engineering
// --------------------------------------------------------------------------

/datum/contract/social/alternative_fuel_trial
	var/datum/contract_requirement/staged_sustained_event/output_requirement
	var/datum/contract_requirement/sustained_event/thermal_requirement

/datum/contract/social/alternative_fuel_trial/Destroy()
	output_requirement = null
	thermal_requirement = null
	return ..()

/datum/contract/social/alternative_fuel_trial/on_negotiated_terms_changed()
	..()
	if(!output_requirement)
		return
	var/profile = negotiated_effect("fuel_certification_profile", "balanced")
	var/max_plasma_fraction = 0.15
	var/integrity_floor = 85
	var/thermal_ceiling = 4500
	var/list/stages
	switch(profile)
		if("conservative")
			max_plasma_fraction = 0.1
			integrity_floor = 92
			thermal_ceiling = 4000
			stages = list(
				list("label" = "Pilot output", "threshold" = 250, "unit" = "EER", "duration" = 45 SECONDS),
				list("label" = "Stable output", "threshold" = 350, "unit" = "EER", "duration" = 1 MINUTE),
				list("label" = "Assured output", "threshold" = 450, "unit" = "EER", "duration" = 75 SECONDS),
			)
		if("phoron_free")
			max_plasma_fraction = 0.001
			integrity_floor = 88
			thermal_ceiling = 4250
			stages = list(
				list("label" = "Phoron-free ignition", "threshold" = 200, "unit" = "EER", "duration" = 45 SECONDS),
				list("label" = "Phoron-free generation", "threshold" = 325, "unit" = "EER", "duration" = 1 MINUTE),
				list("label" = "Phoron-free maximum", "threshold" = 500, "unit" = "EER", "duration" = 75 SECONDS),
			)
		else
			stages = list(
				list("label" = "Pilot output", "threshold" = 300, "unit" = "EER", "duration" = 45 SECONDS),
				list("label" = "Commercial output", "threshold" = 450, "unit" = "EER", "duration" = 1 MINUTE),
				list("label" = "High output", "threshold" = 650, "unit" = "EER", "duration" = 75 SECONDS),
			)
	output_requirement.set_stages(stages)
	output_requirement.filter.set_number_requirement("plasma_fraction", CONTRACT_EVIDENCE_COMPARE_AT_MOST, max_plasma_fraction)
	output_requirement.filter.set_number_requirement("integrity", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, integrity_floor)
	output_requirement.description = "Certify three increasingly strong [profile] output stages using at least two chamber gases, no more than [round(max_plasma_fraction * 100, 0.1)]% phoron, and at least [integrity_floor]% integrity."
	if(thermal_requirement)
		thermal_requirement.threshold = thermal_ceiling
		thermal_requirement.filter.set_number_requirement("eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, stages[1]["threshold"])
		thermal_requirement.description = "Hold the qualifying alternative-fuel engine below [thermal_ceiling] K for two minutes."
	description = "Certify progressively stronger output under the negotiated [profile] alternative-fuel protocol while controlling temperature and crystal integrity."

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
	var/list/output_checks = list(
		list("key" = "station_machine", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1),
		list("key" = "gas_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 2),
		list("key" = "plasma_fraction", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 0.15),
		list("key" = "integrity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 85),
	)
	contract.output_requirement = new(CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, list(list("label" = "Pilot output", "threshold" = 300, "unit" = "EER", "duration" = 45 SECONDS)), CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	contract.output_requirement.name = "Alternative-fuel output stages"
	for(var/list/check as anything in output_checks)
		contract.output_requirement.filter.require_number(check["key"], check["comparator"], check["expected"])
	contract.output_requirement.filter.require_value("machine_kind", "supermatter")
	contract.add_requirement(contract.output_requirement)
	contract.thermal_requirement = add_program_sustained(contract, CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "temperature", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 4500, 2 MINUTES, 1, "Thermal control", "Keep the qualifying engine below 4,500 K for the full demonstration.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, list("machine_kind" = "supermatter"), list(list("key" = "eer", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 300)))
	add_program_sustained(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, "service_id", "powered_channels", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3, 3 MINUTES, 4, "Commissioned station service", "After the engine trial, hold four APC service zones at full power for three minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	var/datum/contract_negotiation_clause/commissioning = new("commissioning_priority", "Commissioning priority", "Choose what the station must protect while pursuing the performance award.")
	commissioning.add_option(make_contract_clause_option("reserve", "Protect reserve", "Keep the safer operating margin; Engineering receives more of the award.", -100, 250, -50, 1, 3, 0, 10 MINUTES, list("requirement_floors" = list("Alternative-fuel output stages" = 0.75))))
	commissioning.add_option(make_contract_clause_option("balanced", "Service first", "Use the standard limits and prove useful station service.", 0, 0, 0), TRUE)
	commissioning.add_option(make_contract_clause_option("sponsor", "Peak demonstration", "Pursue the full output envelope on a shorter schedule for a larger shared award.", 200, 150, 150, 0, 0, 0, -10 MINUTES))
	contract.add_negotiation_clause(commissioning)

// --------------------------------------------------------------------------
// Medical
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/occupational_recovery
	id = "occupational_recovery_program"
	title = "Occupational Recovery Program"
	description = "The Worker's Union requests measurable treatment of work-related conditions across the station workforce."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "Worker's Union Health Trust"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 2900

/datum/contract_definition/social/program/occupational_recovery/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/patient_target = contract_scaled_participant_target(6, 2)
	add_social_role(contract, "clinician", "Occupational clinician", "Coordinates diagnosis, treatment, and follow-up records.", list(DEPARTMENT_MEDICAL), 1, 4)
	add_social_role(contract, "patient", "Participating worker", "Participates in care and outcome follow-up.", null, 4, 12)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, patient_target * 50, "Clinical improvement", "Deliver substantial, measurable improvement across participating workers.", "improvement", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_paired_facts(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, CONTRACT_EVENT_MEDICAL_SCAN_CREATED, "subject_id", patient_target, "Documented recovery", "Improve and produce a follow-up body scan for the same [patient_target] participating workers.")

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

/datum/contract_definition/social/program/advanced_alloy_trial
	id = "advanced_alloy_trial"
	title = "Advanced Alloy Trial"
	description = "Chimera Applied Materials requests a traceable multi-component alloy with balanced performance, prepared and qualified aboard the station."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Chimera Applied Materials"
	issuer_faction = REPUTATION_FACTION_CHIMERA
	reward = 3400
	expected_duration = 90 MINUTES

/datum/contract_definition/social/program/advanced_alloy_trial/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/list/profiles = list(
		list("name" = "Surgical Instrument Stock", "purpose" = "corrosion-safe, tough stock for reusable surgical tools", "checks" = list(list("key" = "toughness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 62), list("key" = "corrosion_resistance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 70), list("key" = "hardness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 72))),
		list("name" = "Pressure Vessel Stock", "purpose" = "low-defect, corrosion-resistant pressure containment", "checks" = list(list("key" = "toughness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 65), list("key" = "corrosion_resistance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 60), list("key" = "defect_fraction", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 15))),
		list("name" = "Disposable Cutter Stock", "purpose" = "extreme hardness at an economical unit cost", "checks" = list(list("key" = "hardness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 76), list("key" = "unit_cost", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 45), list("key" = "brittleness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 70))),
		list("name" = "Light Armor Plate", "purpose" = "balanced armor stock with practical production yield", "checks" = list(list("key" = "hardness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 62), list("key" = "toughness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 55), list("key" = "yield", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 78))),
	)
	var/list/profile = pick(profiles)
	contract.title = profile["name"]
	contract.description = "Produce [profile["purpose"]] and submit a qualified batch for Chimera's materials trial. Composition and treatment are at Research's discretion."
	add_social_role(contract, "metallurgist", "Process metallurgist", "Selects feedstock and develops a reproducible treatment route.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "evaluator", "Operational evaluator", "Examines the physical workpiece and proposes a station use for the alloy.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_CARGO, DEPARTMENT_SECURITY), 1, 4)
	var/list/checks = profile["checks"]
	checks += list(list("key" = "composition_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 2))
	add_material_delivery(contract, checks, 1, "Application stock order", "Assay a batch meeting the application envelope, then ship that exact stock through Cargo.")

/datum/contract_definition/social/program/extreme_service_material
	id = "extreme_service_material"
	title = "Extreme-Service Material Qualification"
	description = "NanoTrasen Engineering requests finished material for harsh thermal and electrical service."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "NanoTrasen Engineering Assurance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3600

/datum/contract_definition/social/program/extreme_service_material/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/list/profiles = list(
		list("name" = "Reactor Liner Qualification", "purpose" = "high-temperature corrosion service without excessive heat conduction", "checks" = list(list("key" = "heat_resistance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 68), list("key" = "corrosion_resistance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 64), list("key" = "conductivity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 48))),
		list("name" = "High-Temperature Power Bus", "purpose" = "conductive stock that retains useful thermal performance", "checks" = list(list("key" = "conductivity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 68), list("key" = "heat_resistance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 52), list("key" = "oxidation", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 12))),
		list("name" = "Precision Sensor Crystal", "purpose" = "low-defect stock inside a narrow conductivity window", "checks" = list(list("key" = "conductivity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 42), list("key" = "conductivity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 62), list("key" = "defect_fraction", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 10))),
	)
	var/list/profile = pick(profiles)
	contract.title = profile["name"]
	contract.description = "Develop [profile["purpose"]] from available station feedstock and deliver a qualified batch."
	add_social_role(contract, "scientist", "Materials scientist", "Develops the composition and documents the process history.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "engineer", "Service engineer", "Reviews whether the observed properties suit a credible station application.", list(DEPARTMENT_ENGINEERING), 1, 4)
	var/list/checks = profile["checks"]
	checks += list(list("key" = "purity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 84), list("key" = "amount", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 4))
	add_material_delivery(contract, checks, 4, "Extreme-service stock order", "Assay at least four sheets meeting the complete envelope, then ship that exact batch through Cargo.")

/datum/contract_definition/social/program/applied_chemistry
	id = "research_equipment_commission"
	title = "Station Equipment Commission"
	description = "Eclipse will subsidize useful Research equipment purchased by station departments for real operational use."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Applied Technologies"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 3200

/datum/contract_definition/social/program/applied_chemistry/configure_contract(datum/contract/social/contract, list/context)
	..()
	contract.description = "Build useful equipment, sell it through the Research checkout, and have several departments put it into operational use. Eclipse pays for equipment that leaves the shelf and gets used."
	add_social_role(contract, "designer", "Equipment designer", "Builds and prices equipment for an identified station need.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "customer", "Operational customer", "Purchases equipment for use in their department.", null, 2, 8)
	contract.personal_side_definitions = list("research_exclusive_export")
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 900, "Equipment in service", "Put 900 Thalers of purchased Research equipment into operational use.", "value", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 3, "Departments equipped", "Have purchased equipment used by three distinct station departments.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "customer_department")
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 4, "Useful deliveries", "Have four distinct purchased items used by their customers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "physical_item_id")

/datum/contract_definition/social/program/station_festival
	id = "station_catering_commission"
	title = "Station Catering Commission"
	description = "TALON Cultural Exchange requests a paid catering service for a broad group of station personnel."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "TALON Cultural Exchange"
	issuer_faction = REPUTATION_FACTION_TALON
	reward = 3000
	expected_duration = 45 MINUTES

/datum/contract_definition/social/program/station_festival/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/customer_target = contract_scaled_participant_target(10, 3, 2)
	add_social_role(contract, "caterer", "Catering lead", "Plans, prepares, prices, and serves the commission.", list(DEPARTMENT_CIVILIAN), 1, 4)
	add_social_role(contract, "customer", "Catering customer", "Purchases and consumes a meal or drink from the commissioned service.", null, 3, 10)
	contract.personal_side_definitions = list("service_gratuity_drive")
	var/list/paid_checks = list(list("key" = "sale_invoice_id", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1))
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, customer_target, "Customers served", "Serve invoiced food or drink to [customer_target] distinct station customers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id", null, paid_checks)
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, min(5, customer_target), "Menu choice", "Serve [min(5, customer_target)] different prepared dishes or drinks as part of the order.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "item_type", null, paid_checks)

// --------------------------------------------------------------------------
// Command
// --------------------------------------------------------------------------

/datum/contract/social/balanced_operations
	var/datum/contract_requirement/event_count/cycle_requirement

/datum/contract/social/balanced_operations/Destroy()
	cycle_requirement = null
	return ..()

/datum/contract/social/balanced_operations/on_negotiated_terms_changed()
	..()
	if(!cycle_requirement)
		return
	var/profile = negotiated_effect("budget_profile", "balanced")
	var/payroll_floor = profile == "staff" ? 0.98 : 0.9
	var/department_floor = profile == "departments" ? 7 : 6
	var/reserve_floor = profile == "reserve" ? 5000 : 0
	cycle_requirement.filter.set_number_requirement("payroll_coverage", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, payroll_floor)
	cycle_requirement.filter.set_number_requirement("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, department_floor)
	cycle_requirement.filter.set_number_requirement("station_balance", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, reserve_floor)
	cycle_requirement.description = "Close two station budget cycles with at least [round(payroll_floor * 100)]% payroll coverage, [department_floor] funded departments[reserve_floor ? ", and [reserve_floor] Thalers retained in station reserve" : ""]."

/datum/contract_definition/social/program/balanced_operations
	id = "balanced_operations_charter"
	title = "Balanced Operations Charter"
	description = "NanoTrasen requests a funded, diversified budget cycle with sustainable payroll coverage."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Corporate Finance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3400
	expected_duration = 120 MINUTES
	contract_type = /datum/contract/social/balanced_operations

/datum/contract_definition/social/program/balanced_operations/configure_contract(datum/contract/social/balanced_operations/contract, list/context)
	..()
	add_social_role(contract, "executive", "Executive budget sponsor", "Sets allocations and accepts accountability for the closed cycle.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "delegate", "Department budget delegate", "Represents operating and workforce needs.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 5, 9)
	contract.personal_side_definitions = list("command_executive_reserve")
	contract.cycle_requirement = add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 2, "Sustained operating agreement", "Close two distinct station budget cycles with payroll paid first, at least six funded departments, and at least 90% payroll coverage.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "accounting_period", list("rollup" = "station"), list(list("key" = "funded_department_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 6), list("key" = "payroll_coverage", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0.9), list("key" = "station_balance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0)))
	var/datum/contract_negotiation_clause/operating_policy = new("operating_policy", "Operating policy", "Choose the station's priority for both covered budget cycles.")
	operating_policy.add_option(make_contract_clause_option("staff", "Staffing first", "Requires 98% payroll coverage across both cycles.", -100, -100, 200, 2, 1, 3, 0, list("budget_profile" = "staff")), TRUE)
	operating_policy.add_option(make_contract_clause_option("departments", "Operations first", "Requires all seven operating departments to receive funding.", -50, 250, -100, 1, 3, 0, 0, list("budget_profile" = "departments")))
	operating_policy.add_option(make_contract_clause_option("reserve", "Reserve first", "Requires a 5,000 Thaler station reserve at settlement.", 250, -100, -150, 2, -1, -1, 0, list("budget_profile" = "reserve")))
	contract.add_negotiation_clause(operating_policy)

/datum/contract_definition/social/program/mutual_aid
	id = "interdepartmental_mutual_aid_compact"
	title = "Interdepartmental Mutual-Aid Compact"
	description = "The Worker's Union requests real resource transfers paired with useful cross-department outcomes."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "Worker's Union Mutual-Aid Council"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 3200

/datum/contract_definition/social/program/mutual_aid/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "coordinator", "Mutual-aid coordinator", "Allocates resources and resolves interdepartmental priorities.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "recipient", "Funded department lead", "Accepts funding and delivers a useful project for station operation.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 3, 7)
	var/datum/contract_requirement/paired_facts/projects = add_program_paired_facts(contract, CONTRACT_EVENT_MONEY_TRANSFERRED, CONTRACT_EVENT_ITEM_PRODUCED, "target_department", 3, "Funded station projects", "Fund three departments from the station account, then have each funded department produce useful equipment.", CONTRACT_EVIDENCE_SCOPE_ANY, "department")
	projects.first_filter.require_value("source_is_station", TRUE)
	projects.first_filter.require_value("target_is_department", TRUE)
	projects.first_filter.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 1000)
	projects.second_filter.require_number("value", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 100)

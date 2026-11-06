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

CAPABILITIES(/datum/contract_requirement/qualified_material_delivery)
	owns_one(nameof(assay_filter), /datum/contract_event_filter)

/datum/contract_requirement/qualified_material_delivery/New(list/checks, amount = 1, _source_department)
	. = ..()
	source_department = _source_department
	rel_set(src, nameof(assay_filter), new /datum/contract_event_filter(source_department ? CONTRACT_EVIDENCE_SCOPE_ANY : CONTRACT_EVIDENCE_SCOPE_DEPARTMENT))
	if(source_department)
		assay_filter.require_value("department", source_department)
	minimum_amount = max(1, amount)
	qualified_lots = list()
	for(var/list/check as anything in checks)
		assay_filter.require_number(check["key"], check["comparator"], check["expected"])
	assay_filter.require_number("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, minimum_amount)
	event_types = list(CONTRACT_EVENT_MATERIAL_CERTIFIED, CONTRACT_EVENT_ITEM_EXPORTED)

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
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player.client && player.stat != DEAD)
			active_crew++
	return min(desired, max(minimum, CEILING(active_crew / crew_per_participant, 1)))

// --------------------------------------------------------------------------
// Engineering
// --------------------------------------------------------------------------

/datum/contract/social/alternative_fuel_trial
	var/datum/contract_requirement/staged_sustained_event/output_requirement
	var/tmp/datum/contract_requirement/sustained_event/thermal_requirement

CAPABILITIES(/datum/contract/social/alternative_fuel_trial)
	ref_one(nameof(output_requirement), /datum/contract_requirement/staged_sustained_event)
	ref_one(nameof(thermal_requirement), /datum/contract_requirement/sustained_event)

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
	if(thermal_requirement())
		thermal_requirement().threshold = thermal_ceiling
		thermal_requirement().filter.set_number_requirement("eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, stages[1]["threshold"])
		thermal_requirement().description = "Hold the qualifying alternative-fuel engine below [thermal_ceiling] K for two minutes."
	description = "Certify progressively stronger output under the negotiated [profile] alternative-fuel protocol while controlling temperature and crystal integrity."

// --------------------------------------------------------------------------
// Command
// --------------------------------------------------------------------------

/datum/contract/social/balanced_operations
	var/tmp/datum/contract_requirement/event_count/cycle_requirement

CAPABILITIES(/datum/contract/social/balanced_operations)
	ref_one(nameof(cycle_requirement), /datum/contract_requirement/event_count)

/datum/contract/social/balanced_operations/on_negotiated_terms_changed()
	..()
	if(!cycle_requirement())
		return
	var/profile = negotiated_effect("budget_profile", "balanced")
	var/payroll_floor = profile == "staff" ? 0.98 : 0.9
	var/department_floor = profile == "departments" ? 7 : 6
	var/reserve_floor = profile == "reserve" ? 5000 : 0
	cycle_requirement().filter.set_number_requirement("payroll_coverage", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, payroll_floor)
	cycle_requirement().filter.set_number_requirement("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, department_floor)
	cycle_requirement().filter.set_number_requirement("station_balance", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, reserve_floor)
	cycle_requirement().description = "Close two station budget cycles with at least [round(payroll_floor * 100)]% payroll coverage, [department_floor] funded departments[reserve_floor ? ", and [reserve_floor] Thalers retained in station reserve" : ""]."

/// the thermal_requirement this refers to (a relation view: null once it is deleted).
/datum/contract/social/alternative_fuel_trial/proc/thermal_requirement() as /datum/contract_requirement/sustained_event
	return thermal_requirement

/// the cycle_requirement this refers to (a relation view: null once it is deleted).
/datum/contract/social/balanced_operations/proc/cycle_requirement() as /datum/contract_requirement/event_count
	return cycle_requirement

/// Measurement qualifications use immutable instrument records carried on
/// ordinary paper. No machine-specific submission gadget or certification UI.
/proc/process_engineering_measurement_fax(obj/item/paper/paper, sender_account, mob/living/sender)
	var/evidence_id = paper.medical_scan_evidence?["evidence_id"]
	var/datum/contract_evidence/evidence = SScontracts.evidence_by_id[evidence_id]
	if(!evidence || evidence.kind != CONTRACT_EVIDENCE_ENGINEERING || evidence.void_reason || evidence.consumed_by || !sender_account)
		return FALSE
	var/list/payload = evidence.payload.Copy()
	payload["measurement_id"] = evidence_id
	payload["actor_account"] = sender_account
	payload["contributor_account"] = evidence.creator_account
	payload["destination"] = CONTRACT_FAX_ENGINEERING
	payload["evidence_ids"] = list(evidence_id)
	emit_contract_event(CONTRACT_EVENT_FAX_ACCEPTED, payload, "engineering-fax:[evidence_id]", paper, sender)
	return TRUE

/// Reusable staged *recorded interval* requirement. Unlike live-state timers,
/// a submitted document must already prove the entire operating interval.
/datum/contract_requirement/recorded_stages
	var/datum/contract_event_filter/filter
	var/list/stages
	var/last_interval_end = 0
	var/measurement_field
	var/unit

/datum/contract_requirement/recorded_stages/New(kind, field, _unit, list/thresholds)
	..()
	filter = new(CONTRACT_EVIDENCE_SCOPE_ANY)
	filter.require_value("kind", kind)
	filter.require_value("destination", CONTRACT_FAX_ENGINEERING)
	filter.require_number("duration", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 45)
	filter.require_number("efficiency", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 0.5)
	stages = thresholds.Copy()
	target = length(stages)
	measurement_field = field
	unit = _unit
	event_types += CONTRACT_EVENT_FAX_ACCEPTED

/datum/contract_requirement/recorded_stages/Destroy()
	QDEL_NULL(filter)
	stages = null
	return ..()

/datum/contract_requirement/recorded_stages/handle_event(datum/contract_event/event)
	if(state != CONTRACT_REQUIREMENT_PENDING || !filter.matches(event, contract))
		return FALSE
	var/start = event.value("started")
	var/end = event.value("ended")
	if(!isnum(start) || !isnum(end) || end > event.occurred_at || start < max(contract.accepted_at, last_interval_end) || end - start < 45 SECONDS || abs(event.value("duration") - (end - start) / 10) > 0.1)
		return FALSE
	var/value = event.value(measurement_field)
	if(!isnum(value) || value < stages[progress + 1])
		return FALSE
	var/list/evidence_ids = event.value("evidence_ids")
	if(!SScontracts.evidence_available(evidence_ids) || !SScontracts.consume_evidence(evidence_ids, contract.id))
		return FALSE
	last_interval_end = end
	return add_progress(1, event.value("contributor_account"), "Qualified [value] [unit] over a complete observed interval.")

/datum/contract_requirement/recorded_stages/progress_text()
	return target == 1 ? (progress ? "Operating qualification complete" : "Operating qualification awaiting evidence") : "[progress] / [target] operating stages"

/datum/contract_requirement/recorded_stages/ui_stage_rows()
	var/list/result = list()
	for(var/index in 1 to length(stages))
		result += list(list("index" = index, "label" = "Operating qualification", "threshold" = stages[index], "unit" = unit, "duration" = "45 seconds", "status" = index <= progress ? "Complete" : "Waiting"))
	return result

/datum/contract_definition/social/program/engineering_qualification
	id = "power_assembly_qualification"
	title = "Low-Loss Power Assembly"
	description = "Demonstrate a power cell or cable assembly sustaining a useful load without overheating. Observe it with a multitool, then print the reading at a photocopier and fax it to NanoTrasen Engineering Assurance."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = CONTRACT_FAX_ENGINEERING
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 4000
	var/measurement_kind = "power"
	var/measurement_field = "minimum_output_watts"
	var/measurement_unit = "W delivered"
	var/list/thresholds = list(3500)

/datum/contract_definition/social/program/engineering_qualification/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "designer", "Assembly designer", "Chooses and fabricates the functional parts.", list(DEPARTMENT_RESEARCH), 1, 3)
	add_social_role(contract, "operator", "Operating engineer", "Builds the test circuit and records delivered operation.", list(DEPARTMENT_ENGINEERING), 1, 3)
	var/datum/contract_requirement/recorded_stages/requirement = new(measurement_kind, measurement_field, measurement_unit, thresholds)
	requirement.name = "Observed operating envelope"
	requirement.description = "Fax one 45-second operating record. It must sustain the stated output with at least 50% conversion efficiency and remain below 400 K."
	requirement.filter.require_number("maximum_temperature_k", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 400)
	contract.add_requirement(requirement)

/datum/contract_definition/social/program/engineering_qualification/gas
	id = "gas_assembly_qualification"
	title = "Contained Gas Transfer Trial"
	description = "Develop a pump and containment assembly that sustains useful gas transfer into a pressurized receiver. Record the run with a multitool, print it at a photocopier, and fax the reading to NanoTrasen Engineering Assurance."
	measurement_kind = "gas"
	measurement_field = "minimum_flow_moles"
	measurement_unit = "mol/s delivered"
	thresholds = list(3)

/datum/contract_definition/social/program/engineering_qualification/gas/configure_contract(datum/contract/social/contract, list/context)
	..()
	for(var/datum/contract_requirement/recorded_stages/requirement in contract.requirements)
		requirement.filter.require_number("minimum_pressure_kpa", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 500)
		requirement.description += " The receiver must remain at or above 500 kPa."

/datum/contract_definition/social/program/engineering_qualification/beam
	id = "emitter_assembly_qualification"
	title = "Sustained Emitter Trial"
	description = "Build an emitter that sustains useful beam output without exceeding 400 K. Arrange a safe target and power supply, record the run with a multitool, and fax the photocopied reading to NanoTrasen Engineering Assurance."
	measurement_kind = "beam"
	thresholds = list(15000)

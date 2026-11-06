/// Incident- and demand-driven work. Offers only appear after authoritative
/// station events identify a concrete reason for them.

/datum/contract_definition/social/program/opportunity
	abstract_type = /datum/contract_definition/social/program/opportunity
	initial_offers = 0
	offer_kind = CONTRACT_OFFER_OPPORTUNITY
	auto_replace = FALSE
	offer_duration = 12 MINUTES
	candidate_duration = 10 MINUTES
	offer_cooldown = 8 MINUTES
	repeat_cooldown = 25 MINUTES

/datum/contract_definition/social/program/opportunity/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/trigger_area = context?["trigger_area"]
	if(trigger_area)
		contract.description += " The originating report identifies [trigger_area]."

/proc/opportunity_bound_values(list/context, field)
	var/list/trigger_values = context?["trigger_values"]
	var/list/values = trigger_values?[field]
	return values?.Copy()

/datum/contract_definition/social/program/opportunity/grid_restoration
	id = "opportunity_grid_restoration"
	title = "Distributed Grid Restoration Call"
	description = "NanoTrasen Utilities requests measured restoration of services named in a recent interruption report."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "NanoTrasen Utilities Dispatch"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3200

/datum/contract_definition/social/program/opportunity/grid_restoration/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "grid_lead", "Grid restoration lead", "Coordinates generation, distribution, and repairs.", list(DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "service_owner", "Affected service owner", "Provides access and confirms restored operation.", null, 1, 8)
	var/list/services = opportunity_bound_values(context, "service_id")
	var/datum/contract_requirement/sustained_event/stability = add_program_sustained(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, "service_id", "powered_channels", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3, 2 MINUTES, min(4, max(1, length(services))), "Stable restored service", "Hold the reported APC services at full power for two minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	if(length(services))
		stability.require_any_value("service_id", services)

/datum/contract_definition/social/program/opportunity/atmos_containment
	id = "opportunity_atmos_containment"
	title = "Atmospheric Containment Recertification"
	description = "SolGov habitat inspectors request recertification of alarm zones named in a recent containment report."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "SolGov Habitat Safety Office"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3300

/datum/contract_definition/social/program/opportunity/atmos_containment/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "atmos_lead", "Containment lead", "Finds breaches and restores safe atmospheric service.", list(DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "occupant", "Habitat representative", "Provides access and confirms the space is usable.", null, 1, 8)
	var/list/services = opportunity_bound_values(context, "service_id")
	var/datum/contract_requirement/sustained_event/stability = add_program_sustained(contract, CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, "service_id", "danger_level", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 0, 2 MINUTES, min(4, max(1, length(services))), "Stable containment", "Hold the reported alarm zones above 80 kPa at safe status for two minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list(list("key" = "pressure", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 80)))
	if(length(services))
		stability.require_any_value("service_id", services)

/datum/contract_definition/social/program/opportunity/clinical_aftercare
	id = "opportunity_clinical_aftercare"
	title = "Clinical Aftercare Partnership"
	description = "VeyMed offers follow-up funding for patients named in a recent clinical caseload report."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "VeyMed Continuity of Care"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 3100

/datum/contract_definition/social/program/opportunity/clinical_aftercare/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/list/subjects = opportunity_bound_values(context, "subject_id")
	var/target = min(4, max(1, length(subjects)))
	add_social_role(contract, "clinician", "Aftercare clinician", "Coordinates continued treatment and follow-up scanning.", list(DEPARTMENT_MEDICAL), 1, 5)
	add_social_role(contract, "patient", "Aftercare participant", "Returns for treatment and a follow-up scan.", null, 1, 8)
	var/datum/contract_requirement/paired_facts/followups = add_program_paired_facts(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, CONTRACT_EVENT_MEDICAL_SCAN_CREATED, "subject_id", target, "Documented aftercare", "Improve and then scan the same patients named in the originating report.")
	if(length(subjects))
		followups.first_filter.require_any_value("subject_id", subjects)
		followups.second_filter.require_any_value("subject_id", subjects)

/datum/contract_definition/social/program/opportunity/breakthrough_translation
	id = "opportunity_equipment_deployment"
	title = "Research Equipment Deployment"
	description = "Eclipse offers follow-on funding to place newly available station technology with real departmental customers."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Applied Research"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 3400

/datum/contract_definition/social/program/opportunity/breakthrough_translation/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "developer", "Equipment developer", "Builds and prices equipment using newly available technology.", list(DEPARTMENT_RESEARCH), 1, 5)
	add_social_role(contract, "customer", "Operational customer", "Purchases equipment for a real station use.", null, 2, 8)
	contract.personal_side_definitions = list("research_exclusive_export")
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 1200, "Equipment deployed", "Put 1,200 Thalers of purchased Research equipment into operational use.", "value", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 4, "Department adoption", "Have purchased equipment used by four distinct station departments.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "customer_department")
	add_program_count(contract, CONTRACT_EVENT_EQUIPMENT_ADOPTED, 5, "Useful deliveries", "Have five distinct purchased items used by their customers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "physical_item_id")

/datum/contract_definition/social/program/opportunity/case_review
	id = "opportunity_case_review"
	title = "Independent Case Review Docket"
	description = "SolGov oversight requests review and disposition of records named in a recent Security caseload."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "SolGov Justice Standards Office"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3000

/datum/contract_definition/social/program/opportunity/case_review/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/list/records = opportunity_bound_values(context, "record_id")
	var/target = min(4, max(1, length(records)))
	add_social_role(contract, "reviewer", "Case reviewer", "Reviews evidence and records a proportionate disposition.", list(DEPARTMENT_SECURITY), 1, 4)
	add_social_role(contract, "observer", "Independent observer", "Represents affected crew during review.", list(DEPARTMENT_COMMAND, DEPARTMENT_MEDICAL, DEPARTMENT_CIVILIAN), 1, 6)
	contract.personal_side_definitions = list("security_record_suppression")
	var/datum/contract_requirement/event_count/reviews = add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, target, "Named records reviewed", "Resolve records named in the originating docket; unrelated arrests do not count.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "record_id")
	if(length(records))
		reviews.require_any_value("record_id", records)

/datum/contract_definition/social/program/opportunity/operational_dividend
	id = "opportunity_operational_dividend"
	title = "Operational Dividend Mandate"
	description = "NanoTrasen Finance offers a dividend for one genuinely funded station budget and payroll cycle."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Corporate Finance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3500

/datum/contract_definition/social/program/opportunity/operational_dividend/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "executive", "Budget executive", "Sets allocations and accepts accountability for the closed cycle.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "delegate", "Department delegate", "Represents workforce and operating requirements.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 3, 10)
	contract.personal_side_definitions = list("command_executive_reserve")
	add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, "Funded operating cycle", "Close the next station cycle with at least 98% payroll coverage, seven funded departments, and 25,000 funded Thalers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "accounting_period", list("rollup" = "station"), list(list("key" = "payroll_coverage", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0.98), list("key" = "funded_department_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 7), list("key" = "funded_allocation_total", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 25000)))

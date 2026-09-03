/// Context-triggered departmental commissions. Unlike the rotating standing
/// catalog, these definitions have no initial offer and are materialized only
/// by the generic opportunity broker after a meaningful pattern of gameplay.

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
		contract.description += " The originating telemetry was last localized to [trigger_area]; the required work begins only after acceptance."

/proc/opportunity_bound_values(list/context, field)
	var/list/trigger_values = context?["trigger_values"]
	var/list/values = trigger_values?[field]
	return values?.Copy()

// --------------------------------------------------------------------------
// Engineering incident response
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/opportunity/grid_restoration
	id = "opportunity_grid_restoration"
	title = "Distributed Grid Restoration Call"
	description = "NanoTrasen Utilities requests a fresh, independently measured restoration after a multi-zone electrical interruption."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "NanoTrasen Utilities Dispatch"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3200

/datum/contract_definition/social/program/opportunity/grid_restoration/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "grid_lead", "Grid restoration lead", "Coordinates generation, distribution, and repair work after the interruption.", list(DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "service_owner", "Affected service owner", "Represents an operating department and verifies restored service.", null, 2, 8)
	var/list/affected_services = opportunity_bound_values(context, "service_id")
	var/datum/contract_requirement/event_count/restorations = add_program_count(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, min(6, max(1, length(affected_services))), "Affected service restorations", "After acceptance, restore the APC zones identified by the originating interruption.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "service_id", null, list(list("key" = "powered_channels", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 3)))
	var/datum/contract_requirement/sustained_event/stability = add_program_sustained(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, "service_id", "powered_channels", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3, 2 MINUTES, min(4, max(1, length(affected_services))), "Verified grid stability", "Hold the affected service zones at full power for two minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	if(length(affected_services))
		restorations.require_any_value("service_id", affected_services)
		stability.require_any_value("service_id", affected_services)

/datum/contract_definition/social/program/opportunity/atmos_containment
	id = "opportunity_atmos_containment"
	title = "Atmospheric Containment Recertification"
	description = "SolGov safety underwriters request a fresh containment and service demonstration after correlated air-alarm warnings."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "SolGov Habitat Safety Office"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3300

/datum/contract_definition/social/program/opportunity/atmos_containment/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "atmos_lead", "Containment lead", "Locates breaches and restores safe, stable atmospheric service.", list(DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "occupant", "Habitat representative", "Coordinates access and verifies that restored spaces serve their occupants.", null, 2, 8)
	var/list/affected_services = opportunity_bound_values(context, "service_id")
	var/datum/contract_requirement/event_count/recoveries = add_program_count(contract, CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, min(5, max(1, length(affected_services))), "Affected alarm recoveries", "After acceptance, return the alarm zones identified by the originating incident to safe pressure.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "service_id", null, list(list("key" = "danger_level", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 0), list("key" = "pressure", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 80)))
	var/datum/contract_requirement/sustained_event/stability = add_program_sustained(contract, CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, "service_id", "danger_level", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 0, 2 MINUTES, min(4, max(1, length(affected_services))), "Stable containment", "Hold the affected zones at safe status for two minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list(list("key" = "pressure", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 80)))
	if(length(affected_services))
		recoveries.require_any_value("service_id", affected_services)
		stability.require_any_value("service_id", affected_services)

// --------------------------------------------------------------------------
// Medical and Research follow-through
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/opportunity/clinical_aftercare
	id = "opportunity_clinical_aftercare"
	title = "Clinical Aftercare Partnership"
	description = "VeyMed offers follow-through funding after station telemetry demonstrated a varied, substantive clinical caseload."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "VeyMed Continuity of Care"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 3100

/datum/contract_definition/social/program/opportunity/clinical_aftercare/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/patient_target = contract_scaled_participant_target(5, 2)
	var/condition_target = min(4, max(2, CEILING(patient_target / 2, 1)))
	add_social_role(contract, "clinician", "Aftercare clinician", "Coordinates continued condition-based treatment and documents outcomes.", list(DEPARTMENT_MEDICAL), 1, 5)
	add_social_role(contract, "patient", "Aftercare participant", "Participates in treatment, follow-up scanning, or recovery planning.", null, 3, 10)
	contract.personal_side_definitions = list("clinical_priority_coordinator")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, patient_target * 44, "Continued clinical improvement", "Deliver substantial new improvement across the follow-up caseload.", "improvement", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, patient_target, "Patient breadth", "Record new outcomes for [patient_target] distinct patients.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, condition_target, "Condition breadth", "Treat at least [condition_target] distinct diagnosed conditions.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "condition_type")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_SCAN_CREATED, patient_target, "Follow-up records", "File body-scanner follow-ups for [patient_target] distinct patients.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")

/datum/contract_definition/social/program/opportunity/breakthrough_translation
	id = "opportunity_breakthrough_translation"
	title = "Breakthrough Translation Grant"
	description = "Eclipse offers a commercialization grant after detecting a credible cluster of unrelated station research milestones."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Applied Research"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 3400

/datum/contract_definition/social/program/opportunity/breakthrough_translation/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "developer", "Translation developer", "Turns newly available theory into useful, attributable station products.", list(DEPARTMENT_RESEARCH), 1, 5)
	add_social_role(contract, "evaluator", "Operational evaluator", "Purchases, deploys, or evaluates resulting products in another department.", null, 3, 9)
	contract.personal_side_definitions = list("research_exclusive_export")
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_PRODUCED, 2500, "item_type", "value", 7, "Translated product suite", "Produce 2,500 Thalers of fresh station equipment across seven product classes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, null, 500, 700)
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_EXPORTED, 1400, "item_type", "value", 4, "External validation portfolio", "Export 1,400 Thalers of Research-origin products across four classes.", CONTRACT_EVIDENCE_SCOPE_ANY, list("origin_department" = DEPARTMENT_RESEARCH), null, 500, 700)
	add_program_count(contract, CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 450, "Crew adoption", "Settle 450 verified Thalers of Research sales to station personnel.", "verified_amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "department"))

/datum/contract_definition/social/program/opportunity/process_scaleup
	id = "opportunity_process_scaleup"
	title = "Synthesis Process Scale-Up"
	description = "Chimera Genetics offers process-development funding after observing a diverse run of substantive station syntheses."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Chimera Genetics Process Development"
	issuer_faction = REPUTATION_FACTION_CHIMERA
	reward = 3150

/datum/contract_definition/social/program/opportunity/process_scaleup/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "chemist", "Process chemist", "Develops a varied, reproducible synthesis portfolio.", list(DEPARTMENT_RESEARCH, DEPARTMENT_MEDICAL), 1, 5)
	add_social_role(contract, "consumer", "Process customer", "Defines an operational use and receives resulting materials or products.", null, 2, 8)
	add_program_count(contract, CONTRACT_EVENT_CHEMISTRY_RESULT, 120, "Scaled synthesis volume", "Produce 120 fresh units through qualifying reactions.", "amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_CHEMISTRY_RESULT, 7, "Reaction breadth", "Complete seven distinct reaction types after accepting the commission.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "reaction_id")
	add_program_count(contract, CONTRACT_EVENT_CHEMISTRY_RESULT, 5, "Complex processes", "Complete five distinct syntheses using at least three reactants.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "reaction_id", null, list(list("key" = "reactant_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 3)))
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_PRODUCED, 1000, "item_type", "value", 4, "Applied outputs", "Produce 1,000 Thalers of useful equipment across four product classes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, null, 350, 500)

// --------------------------------------------------------------------------
// Security and trade response
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/opportunity/case_review
	id = "opportunity_case_review"
	title = "Independent Case Review Docket"
	description = "SolGov oversight offers a review commission after a concentrated run of varied cases involving identifiable station personnel."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "SolGov Justice Standards Office"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3000

/datum/contract_definition/social/program/opportunity/case_review/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "reviewer", "Case review officer", "Develops and closes fresh records linked to physical subjects.", list(DEPARTMENT_SECURITY), 1, 4)
	add_social_role(contract, "observer", "Independent observer", "Reviews proportionality and represents affected departments or crew.", list(DEPARTMENT_COMMAND, DEPARTMENT_MEDICAL, DEPARTMENT_CIVILIAN), 2, 6)
	contract.personal_side_definitions = list("security_record_suppression")
	add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 5, "Fresh reviewed cases", "Resolve five new custodial case records concerning identifiable station personnel.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "record_id", list("physical_custody_verified" = TRUE))
	add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 4, "Subject breadth", "Resolve custodial records concerning four distinct people.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "physical_subject_id", list("physical_custody_verified" = TRUE))
	add_program_count(contract, CONTRACT_EVENT_CUSTODY_CHANGED, 3, "Documented custody episodes", "Document three distinct custodial episodes involving different people.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")

/datum/contract_definition/social/program/opportunity/supplier_option
	id = "opportunity_supplier_option"
	title = "Preferred Supplier Option"
	description = "The Interstellar Traders' Guild offers a larger follow-on option after observing broad station export capability."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "Interstellar Traders' Guild"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 3400

/datum/contract_definition/social/program/opportunity/supplier_option/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "broker", "Preferred-supplier broker", "Coordinates valuation, provenance, and outbound freight.", list(DEPARTMENT_CARGO), 1, 4)
	add_social_role(contract, "supplier", "Department supplier", "Provides attributable station products for the new option.", null, 4, 12)
	contract.personal_side_definitions = list("cargo_local_priority")
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_EXPORTED, 5000, "origin_department", "value", 4, "Fresh supplier portfolio", "Export 5,000 new Thalers of goods sourced from four departments.", CONTRACT_EVIDENCE_SCOPE_ANY, null, null, 900, 1500)
	add_program_count(contract, CONTRACT_EVENT_ITEM_EXPORTED, 9, "Product breadth", "Export nine distinct product classes under the option.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "item_type")
	add_program_count(contract, CONTRACT_EVENT_ITEM_PRODUCED, 6, "Station production base", "Produce six distinct station-made product classes after acceptance.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "item_type")

/datum/contract_definition/social/program/opportunity/procurement_rebate
	id = "opportunity_procurement_rebate"
	title = "Cooperative Procurement Rebate"
	description = "NanoTrasen Purchasing offers a volume rebate after several departments demonstrated varied procurement demand."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "NanoTrasen Cooperative Purchasing"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3200

/datum/contract_definition/social/program/opportunity/procurement_rebate/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "buyer", "Cooperative buyer", "Consolidates legitimate department needs without concentrating the order book.", list(DEPARTMENT_CARGO), 1, 4)
	add_social_role(contract, "requester", "Department requester", "Defines, funds, and receives equipment needed for departmental work.", null, 4, 10)
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 6000, "Fresh procured value", "Deliver 6,000 Thalers of new departmental supply orders.", "value", CONTRACT_EVIDENCE_SCOPE_ANY)
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 8, "Catalog breadth", "Receive eight distinct supply-pack types.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "pack_type")
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 4, "Funding breadth", "Serve four distinct funding departments.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "funding_department")

// --------------------------------------------------------------------------
// Civilian demand and station services
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/opportunity/hospitality_expansion
	id = "opportunity_hospitality_expansion"
	title = "Hospitality Capacity Expansion"
	description = "TALON Cultural Exchange offers an expanded service commission after verified station demand exceeded routine trade."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "TALON Cultural Exchange"
	issuer_faction = REPUTATION_FACTION_TALON
	reward = 3100

/datum/contract_definition/social/program/opportunity/hospitality_expansion/configure_contract(datum/contract/social/contract, list/context)
	..()
	var/customer_target = contract_scaled_participant_target(18, 5, 1)
	add_social_role(contract, "host", "Expansion host", "Coordinates pricing, menu breadth, and accessible service.", list(DEPARTMENT_CIVILIAN), 1, 5)
	add_social_role(contract, "patron", "Station patron", "Patronizes the expanded food and drink service.", null, 6, 16)
	contract.personal_side_definitions = list("service_gratuity_drive")
	add_program_count(contract, CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, customer_target * 75, "Expanded revenue", "Settle [customer_target * 75] Thalers of new Civilian service sales.", "verified_amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "department"))
	var/list/paid_checks = list(list("key" = "sale_invoice_id", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1))
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, customer_target, "Customer reach", "Serve invoiced food or drink to [customer_target] distinct consumers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id", null, paid_checks)
	var/menu_target = min(10, max(4, CEILING(customer_target * 0.6, 1)))
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, menu_target, "Menu breadth", "Serve [menu_target] distinct invoiced meal or drink types.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "item_type", null, paid_checks)

/datum/contract_definition/social/program/opportunity/crop_forward_order
	id = "opportunity_crop_forward_order"
	title = "Agricultural Forward Order"
	description = "The Worker's Union cooperative offers a forward order after a varied station harvest demonstrated sustainable capacity."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "Worker's Union Agricultural Exchange"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 2950

/datum/contract_definition/social/program/opportunity/crop_forward_order/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "grower", "Forward-order grower", "Plans and delivers a varied fresh harvest.", list(DEPARTMENT_CIVILIAN), 1, 5)
	add_social_role(contract, "buyer", "Kitchen or crew buyer", "Purchases the cooperative's harvest for station use.", null, 3, 10)
	add_program_count(contract, CONTRACT_EVENT_CROP_HARVESTED, 80, "Fresh contracted yield", "Harvest eighty new units of station produce.", "yield", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_CROP_HARVESTED, 9, "Crop breadth", "Harvest nine distinct crop lines.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "crop_id")
	add_program_count(contract, CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 800, "Crew market demand", "Settle 800 verified Thalers of Civilian sales after acceptance.", "verified_amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "department"))

// --------------------------------------------------------------------------
// Synthetic and Command capacity
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/opportunity/automation_expansion
	id = "opportunity_automation_expansion"
	title = "Automation Capacity Expansion"
	description = "Kusanagi field support offers expanded capacity after diverse station bots completed a meaningful operating workload."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_SYNTHETIC
	issuer_name = "Kusanagi Robotics Field Support"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3100

/datum/contract_definition/social/program/opportunity/automation_expansion/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "coordinator", "Automation coordinator", "Configures bots and coordinates service priorities.", list(DEPARTMENT_SYNTHETIC, DEPARTMENT_CARGO), 1, 4)
	add_social_role(contract, "recipient", "Automation-service recipient", "Provides real work and supervises outcomes in an operating department.", null, 3, 10)
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 20, "New automated workload", "Complete twenty successful bot assignments after acceptance.", "work_units", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("successful" = TRUE))
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 3, "Task breadth", "Complete three distinct automation task classes.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "task_kind", list("successful" = TRUE))
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 8, "Service breadth", "Complete useful work for eight distinct recipients or locations.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "target_id", list("successful" = TRUE))

/datum/contract_definition/social/program/opportunity/operational_dividend
	id = "opportunity_operational_dividend"
	title = "Operational Dividend Mandate"
	description = "NanoTrasen Finance offers a one-cycle dividend after the station demonstrated broad payroll and operating coverage."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Corporate Finance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3500

/datum/contract_definition/social/program/opportunity/operational_dividend/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "executive", "Dividend executive", "Sets the next cycle's allocations and accepts accountability for payroll coverage.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "delegate", "Department budget delegate", "Represents workforce and operating requirements in the funded cycle.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 5, 10)
	contract.personal_side_definitions = list("command_executive_reserve")
	add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, "Fresh dividend cycle", "Close the next station cycle with at least 98% payroll coverage, seven funded departments, and 25,000 funded Thalers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "station"), list(list("key" = "payroll_coverage", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0.98), list("key" = "funded_department_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 7), list("key" = "funded_allocation_total", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 25000)))
	add_program_count(contract, CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED, 5, "Participating budgets", "Set allocations for five distinct department accounts before settlement.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "target_department", null, list(list("key" = "amount", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1000)))

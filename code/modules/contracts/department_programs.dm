/// Declarative authoring helpers for the broad departmental contract catalog.
/// These only compose the generic event requirements; gameplay facts continue
/// to come from their authoritative power, atmos, medicine, research, economy,
/// service, security, and automation systems.

/proc/add_program_count(datum/contract/social/contract, event_type, target, name, description, value_field = null, scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY, unique_field = null, list/exact_values, list/numeric_checks) as /datum/contract_requirement/event_count
	var/datum/contract_requirement/event_count/requirement = new(event_type, target, exact_values, value_field, TRUE, scope_mode)
	requirement.name = name
	requirement.description = description
	requirement.unique_field = unique_field
	for(var/list/check as anything in numeric_checks)
		requirement.require_number(check["key"], check["comparator"], check["expected"])
	contract.add_requirement(requirement)
	return requirement

/proc/add_program_portfolio(datum/contract/social/contract, event_type, target, category_field, value_field, category_target, name, description, scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY, list/exact_values, list/numeric_checks, maximum_fact_value = INFINITY, maximum_category_value = INFINITY) as /datum/contract_requirement/fact_portfolio
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

/proc/add_program_sustained(datum/contract/social/contract, event_type, entity_field, numeric_field, comparator, threshold, duration, target, name, description, scope_mode = CONTRACT_EVIDENCE_SCOPE_ANY, list/exact_values, list/numeric_checks) as /datum/contract_requirement/sustained_event
	var/datum/contract_requirement/sustained_event/requirement = new(event_type, entity_field, numeric_field, comparator, threshold, duration, target, scope_mode)
	requirement.name = name
	requirement.description = description
	for(var/key in exact_values)
		requirement.filter.require_value(key, exact_values[key])
	for(var/list/check as anything in numeric_checks)
		requirement.filter.require_number(check["key"], check["comparator"], check["expected"])
	contract.add_requirement(requirement)
	return requirement

/datum/contract_definition/social/program
	abstract_type = /datum/contract_definition/social/program
	max_simultaneous = 1
	max_round_completions = 2
	round_reward_budget = 7000
	repeat_reward_decay_percent = 25
	var/station_reputation = 8
	var/department_reputation = 24
	var/staff_reputation = 12

/datum/contract_definition/social/program/configure_contract(datum/contract/social/contract, list/context)
	..()
	configure_social_identity(contract, station_reputation, department_reputation, staff_reputation)

// --------------------------------------------------------------------------
// Engineering
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/grid_recovery
	id = "grid_recovery_indemnity"
	title = "Grid Recovery Indemnity"
	description = "NanoTrasen Utilities will underwrite a documented recovery of distributed station electrical service."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "NanoTrasen Utilities Assurance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3000

/datum/contract_definition/social/program/grid_recovery/configure_contract(datum/contract/social/contract, list/context)
	..()
	contract.description = "Restore and hold full electrical service at several independently monitored APCs, while completing meaningful physical repairs. Partial recovery qualifies for a reduced graded settlement."
	add_social_role(contract, "engineer", "Grid recovery engineer", "Restores generation, distribution, and damaged electrical assets.", list(DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "liaison", "Service-area liaison", "Confirms operational needs and coordinates safe access in affected departments.", null, 2, 8)
	contract.personal_side_definitions = list("engineering_safety_watch")
	add_program_count(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, 5, "Restored APC coverage", "Return five distinct APC service zones to all three powered channels.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "service_id", null, list(list("key" = "powered_channels", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 3)))
	add_program_sustained(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, "service_id", "powered_channels", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3, 3 MINUTES, 3, "Stable restored grid", "Hold three restored APC service zones at full power for three minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 300, "Physical restoration", "Complete 300 integrity points of genuine station infrastructure repairs.", "repair_amount")

/datum/contract_definition/social/program/atmos_recovery
	id = "atmospheric_recovery_bond"
	title = "Atmospheric Recovery Bond"
	description = "Osiris underwriters request a verified recovery of multiple unsafe station atmosphere zones."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "Osiris Atmospherics Underwriting"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3100

/datum/contract_definition/social/program/atmos_recovery/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "atmos", "Atmospheric recovery lead", "Repairs containment and restores safe pressure and temperature.", list(DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "occupant", "Affected-area representative", "Coordinates evacuation, access, and operational acceptance.", null, 2, 8)
	add_program_count(contract, CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, 5, "Recovered alarm zones", "Return five distinct air-alarm zones to a safe state above 80 kPa.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "service_id", null, list(list("key" = "danger_level", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 0), list("key" = "pressure", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 80)))
	add_program_sustained(contract, CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, "service_id", "danger_level", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 0, 3 MINUTES, 3, "Sustained atmosphere", "Hold three recovered zones at safe alarm status for three minutes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list(list("key" = "pressure", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 80)))
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 200, "Containment repairs", "Complete 200 integrity points of station repairs associated with the recovery.", "repair_amount")

/datum/contract_definition/social/program/alternative_fuel
	id = "alternative_fuel_demonstration"
	title = "Alternative Fuel Demonstration"
	description = "Focal Point Energetics requests a stable high-output engine run using a diverse, low-phoron chamber mixture."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "Focal Point Energetics"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3400

/datum/contract_definition/social/program/alternative_fuel/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "operator", "Engine operator", "Designs and operates the alternative chamber mixture.", list(DEPARTMENT_ENGINEERING), 1, 3)
	add_social_role(contract, "observer", "Independent technical observer", "Reviews safety and performance on behalf of another department.", list(DEPARTMENT_RESEARCH, DEPARTMENT_COMMAND), 1, 3)
	contract.personal_side_definitions = list("engineering_safety_watch")
	var/list/output_checks = list(
		list("key" = "station_machine", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 1),
		list("key" = "gas_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 2),
		list("key" = "plasma_fraction", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 0.15),
		list("key" = "integrity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 80),
	)
	add_program_sustained(contract, CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "eer", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 350, 2 MINUTES, 1, "Alternative-fuel output", "Hold at least 350 Relative EER for two minutes with two or more chamber gases, no more than 15% phoron, and at least 80% integrity.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, list("machine_kind" = "supermatter"), output_checks)
	add_program_sustained(contract, CONTRACT_EVENT_MACHINE_RESULT, "machine_id", "temperature", CONTRACT_EVIDENCE_COMPARE_AT_MOST, 4500, 2 MINUTES, 1, "Thermal control", "Keep the qualifying engine below 4,500 K for the full demonstration.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, list("machine_kind" = "supermatter"), list(list("key" = "eer", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 350)))

/datum/contract_definition/social/program/preventative_maintenance
	id = "preventative_maintenance_portfolio"
	title = "Preventative Maintenance Portfolio"
	description = "Ward-Takahashi requests a broad portfolio of authentic station infrastructure maintenance."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_ENGINEERING
	issuer_name = "Ward-Takahashi Reliability Office"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2700

/datum/contract_definition/social/program/preventative_maintenance/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "maintainer", "Maintenance lead", "Plans and performs the preventative work portfolio.", list(DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "owner", "Asset-area representative", "Identifies operational assets and verifies that work does not disrupt service.", null, 2, 8)
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 600, "Restored integrity", "Complete 600 integrity points of real station infrastructure repair.", "repair_amount")
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 7, "Asset diversity", "Repair seven distinct infrastructure classes.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "atom_type")
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 5, "Area coverage", "Perform qualifying work in five distinct station areas.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "area_name")

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
	add_social_role(contract, "clinician", "Occupational clinician", "Coordinates diagnosis, treatment, and ordinary medical records.", list(DEPARTMENT_MEDICAL), 1, 4)
	add_social_role(contract, "patient", "Participating worker", "Participates in care and outcome follow-up.", null, 4, 12)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 300, "Clinical improvement", "Record 300 points of genuine condition-severity improvement.", "improvement", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 6, "Workers recovered", "Improve six distinct patients.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_SCAN_CREATED, 6, "Documented follow-up", "Produce ordinary medical scans for six distinct patients.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "subject_id")

/datum/contract_definition/social/program/blood_reserve
	id = "blood_reserve_campaign"
	title = "Blood Reserve Campaign"
	description = "VeyMed requests a diverse, traceable reserve collected through ordinary IV equipment."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "VeyMed Transfusion Services"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 2600

/datum/contract_definition/social/program/blood_reserve/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "clinician", "Transfusion coordinator", "Screens donors and manages ordinary blood collection.", list(DEPARTMENT_MEDICAL), 1, 3)
	add_social_role(contract, "donor", "Registered donor", "Contributes to the station reserve under Medical supervision.", null, 4, 12)
	add_program_count(contract, CONTRACT_EVENT_BLOOD_DONATED, 600, "Reserve volume", "Collect 600 units of blood through ordinary IV drips.", "amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_BLOOD_DONATED, 4, "Donor participation", "Collect from four distinct donors.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_BLOOD_DONATED, 3, "Blood-type breadth", "Represent three distinct blood types in the campaign.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "blood_type")

/datum/contract_definition/social/program/rehabilitation
	id = "rehabilitation_return_to_duty"
	title = "Rehabilitation and Return-to-Duty"
	description = "NanoTrasen Personnel requests documented recovery of multiple injured crew members."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "NanoTrasen Occupational Health"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2800

/datum/contract_definition/social/program/rehabilitation/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "rehab", "Rehabilitation clinician", "Coordinates treatment and confirms durable recovery.", list(DEPARTMENT_MEDICAL), 1, 4)
	add_social_role(contract, "worker", "Returning crew member", "Completes treatment and follow-up assessment.", null, 4, 10)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 240, "Condition recovery", "Record 240 points of genuine condition improvement.", "improvement", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 5, "Returned crew", "Improve five distinct crew members.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_SCAN_CREATED, 5, "Return-to-duty scans", "Produce follow-up scans for five distinct patients.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "subject_id")

/datum/contract_definition/social/program/public_health
	id = "public_health_response"
	title = "Public Health Response"
	description = "SolGov Health requests a broad, evidence-led response to varied station medical conditions."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_MEDICAL
	issuer_name = "SolGov Public Health Service"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3200

/datum/contract_definition/social/program/public_health/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "coordinator", "Public-health coordinator", "Coordinates case finding, treatment, and follow-up.", list(DEPARTMENT_MEDICAL), 1, 3)
	add_social_role(contract, "liaison", "Department health liaison", "Brings department-specific risks and affected staff into the response.", null, 3, 8)
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 8, "Cases improved", "Improve eight distinct patients through the full medical condition system.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 4, "Condition breadth", "Treat four distinct condition classes.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "condition_type")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_SCAN_CREATED, 8, "Case surveillance", "Create medical scans for eight distinct patients.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "subject_id")

// --------------------------------------------------------------------------
// Research
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/materials_qualification
	id = "materials_qualification_board"
	title = "Materials Qualification Board"
	description = "Chimera Genetics requests a varied portfolio of station-manufactured material applications."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Chimera Applied Materials Board"
	issuer_faction = REPUTATION_FACTION_CHIMERA
	reward = 3000

/datum/contract_definition/social/program/materials_qualification/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "researcher", "Materials researcher", "Produces and documents the qualification portfolio.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "user", "Operational evaluator", "Purchases, uses, or exports qualified station products.", null, 3, 8)
	contract.personal_side_definitions = list("research_exclusive_export")
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_PRODUCED, 2200, "item_type", "value", 7, "Qualified production", "Produce 2,200 Thalers of station equipment across seven product classes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, null, 500, 700)
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_EXPORTED, 1200, "item_type", "value", 4, "External qualification", "Export 1,200 Thalers across four qualified product classes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, null, 400, 500)

/datum/contract_definition/social/program/advanced_alloy_trial
	id = "advanced_alloy_trial"
	title = "Advanced Alloy Trial"
	description = "Chimera Applied Materials requests a traceable multi-component alloy with balanced mechanical performance, qualified through ordinary station equipment."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Chimera Applied Materials"
	issuer_faction = REPUTATION_FACTION_CHIMERA
	reward = 3400

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
	contract.description = "Produce and certify [profile["purpose"]]. The issuer evaluates outcomes rather than prescribing ingredients or a process route."
	add_social_role(contract, "metallurgist", "Process metallurgist", "Selects feedstock and develops a reproducible treatment route.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "evaluator", "Operational evaluator", "Reviews the physical certificate and proposes a station use for the alloy.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_CARGO, DEPARTMENT_SECURITY), 1, 4)
	add_program_count(contract, CONTRACT_EVENT_MATERIAL_PROCESSED, 4, "Controlled processing", "Complete four distinct physical processing stages on station material.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "process")
	var/list/checks = profile["checks"]
	checks += list(list("key" = "composition_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 2))
	add_program_count(contract, CONTRACT_EVENT_MATERIAL_CERTIFIED, 1, "Application qualification", "Certify a batch meeting the complete application envelope shown above.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "fingerprint", null, checks)

/datum/contract_definition/social/program/extreme_service_material
	id = "extreme_service_material"
	title = "Extreme-Service Material Qualification"
	description = "NanoTrasen Engineering requests a certified material for harsh thermal and electrical service."
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
	add_social_role(contract, "engineer", "Service engineer", "Reviews whether the certified properties suit a credible station application.", list(DEPARTMENT_ENGINEERING), 1, 4)
	var/list/checks = profile["checks"]
	checks += list(list("key" = "purity", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 84), list("key" = "amount", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 4))
	add_program_count(contract, CONTRACT_EVENT_MATERIAL_CERTIFIED, 1, "Extreme-service certificate", "Certify at least four sheets meeting the complete application envelope.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "fingerprint", null, checks)

/datum/contract_definition/social/program/replication_study
	id = "independent_replication_study"
	title = "Independent Replication Study"
	description = "SolGov Science requests independent reproduction of multiple station research results."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "SolGov Open Science Directorate"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3100

/datum/contract_definition/social/program/replication_study/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "author", "Primary investigator", "Selects research milestones and produces the initial results.", list(DEPARTMENT_RESEARCH), 1, 3)
	add_social_role(contract, "replicator", "Independent replicator", "Reproduces outputs without relying on the primary investigator alone.", list(DEPARTMENT_RESEARCH, DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL), 2, 6)
	add_program_count(contract, CONTRACT_EVENT_RESEARCH_MILESTONE, 4, "Research milestones", "Unlock four distinct techweb nodes.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "node_id")
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_PRODUCED, 1800, "item_type", "value", 6, "Replicated outputs", "Produce a varied 1,800-Thaler portfolio across six product types.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, null, 400, 500)

/datum/contract_definition/social/program/applied_chemistry
	id = "applied_chemistry_brief"
	title = "Applied Chemistry Brief"
	description = "VeyMed requests varied, nontrivial chemistry synthesis through ordinary reagent systems."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "VeyMed Applied Chemistry"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 2800

/datum/contract_definition/social/program/applied_chemistry/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "chemist", "Applied chemist", "Plans and performs the synthesis portfolio.", list(DEPARTMENT_RESEARCH, DEPARTMENT_MEDICAL), 1, 4)
	add_social_role(contract, "customer", "Operational customer", "Defines practical needs and evaluates delivered results.", null, 2, 6)
	add_program_count(contract, CONTRACT_EVENT_CHEMISTRY_RESULT, 100, "Synthesized volume", "Produce 100 units through genuine chemical reactions.", "amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_CHEMISTRY_RESULT, 8, "Product breadth", "Produce eight distinct reaction products.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "product_id")
	add_program_count(contract, CONTRACT_EVENT_CHEMISTRY_RESULT, 5, "Complex synthesis", "Complete five distinct reactions requiring at least three reactants.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "reaction_id", null, list(list("key" = "reactant_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 3)))

/datum/contract_definition/social/program/publication_consortium
	id = "publication_consortium"
	title = "Publication Consortium"
	description = "A multi-institution consortium requests research milestones, useful outputs, and genuine station adoption."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Vir Scientific Publication Consortium"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3300

/datum/contract_definition/social/program/publication_consortium/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "author", "Consortium author", "Coordinates milestones and attributes contributors.", list(DEPARTMENT_RESEARCH), 2, 5)
	add_social_role(contract, "licensee", "Station licensee", "Purchases or evaluates resulting Research goods.", null, 3, 10)
	contract.personal_side_definitions = list("research_exclusive_export")
	add_program_count(contract, CONTRACT_EVENT_RESEARCH_MILESTONE, 5, "Published milestones", "Unlock five distinct research nodes.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "node_id")
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_PRODUCED, 2000, "item_type", "value", 7, "Publication outputs", "Produce 2,000 Thalers across seven output classes.", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, null, 450, 600)
	add_program_count(contract, CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 700, "Station adoption", "Settle 700 Thalers of verified Research sales to crew.", "verified_amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "department"))

// --------------------------------------------------------------------------
// Security
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/contraband_buyback
	id = "contraband_buyback_program"
	title = "Contraband Buyback Program"
	description = "SolGov offers a restorative buyback award for resolving custody cases with documented compensation."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "SolGov Community Safety Office"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 2700

/datum/contract_definition/social/program/contraband_buyback/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "officer", "Buyback coordinator", "Records surrendered cases and verifies lawful disposition.", list(DEPARTMENT_SECURITY), 1, 4)
	add_social_role(contract, "participant", "Program participant", "Participates in a documented voluntary resolution.", null, 3, 10)
	contract.personal_side_definitions = list("security_record_suppression")
	add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 5, "Resolved participants", "Close five distinct physical-subject cases.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_MONEY_TRANSFERRED, 1000, "Documented consideration", "Transfer 1,000 Thalers in genuine participant compensation or restitution.", "amount", CONTRACT_EVIDENCE_SCOPE_ANY, "target_account", null, list(list("key" = "amount", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 50)))

/datum/contract_definition/social/program/forensic_portfolio
	id = "forensic_case_portfolio"
	title = "Forensic Case Portfolio"
	description = "NanoTrasen Legal requests a varied portfolio of physically grounded case resolutions."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "NanoTrasen Legal Assurance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2900

/datum/contract_definition/social/program/forensic_portfolio/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "investigator", "Case investigator", "Develops records and links them to physical subjects.", list(DEPARTMENT_SECURITY), 1, 4)
	add_social_role(contract, "reviewer", "Independent case reviewer", "Reviews proportionality and record completeness.", list(DEPARTMENT_COMMAND, DEPARTMENT_MEDICAL), 1, 3)
	add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 7, "Case portfolio", "Resolve seven distinct security records linked to physical subjects.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "record_id")
	add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 5, "Subject breadth", "Resolve cases for five distinct physical subjects.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "physical_subject_id")
	add_program_count(contract, CONTRACT_EVENT_CUSTODY_CHANGED, 3, "Verified custody", "Record three distinct physically verified custody episodes.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")

/datum/contract_definition/social/program/community_resolution
	id = "community_resolution_docket"
	title = "Community Resolution Docket"
	description = "The Worker's Union requests negotiated, restorative closure of station disputes."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "Worker's Union Mediation Board"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 2600

/datum/contract_definition/social/program/community_resolution/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "mediator", "Security mediator", "Facilitates documented case closure without predetermining the outcome.", list(DEPARTMENT_SECURITY), 1, 3)
	add_social_role(contract, "party", "Community participant", "Represents an affected party, guarantor, or department.", null, 4, 12)
	add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 5, "Resolved docket", "Close five distinct case records.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "record_id")
	add_program_count(contract, CONTRACT_EVENT_MONEY_TRANSFERRED, 800, "Restitution and guarantees", "Record 800 Thalers of genuine transfers among distinct recipients.", "amount", CONTRACT_EVIDENCE_SCOPE_ANY, "target_account", null, list(list("key" = "amount", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 50)))

/datum/contract_definition/social/program/emergency_response
	id = "emergency_response_accreditation"
	title = "Emergency Response Accreditation"
	description = "SolGov Emergency Management requests a multi-department response portfolio grounded in real incidents."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_SECURITY
	issuer_name = "SolGov Emergency Management"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3200

/datum/contract_definition/social/program/emergency_response/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "commander", "Response commander", "Coordinates scene safety and cross-department priorities.", list(DEPARTMENT_SECURITY, DEPARTMENT_COMMAND), 1, 3)
	add_social_role(contract, "responder", "Specialist responder", "Provides Engineering or Medical response capacity.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL), 2, 6)
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 350, "Scene restoration", "Complete 350 integrity points of genuine station repairs.", "repair_amount")
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 4, "Casualty recovery", "Improve four distinct patients through the condition system.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, 3, "Incident closure", "Close three distinct incident records.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "record_id")

// --------------------------------------------------------------------------
// Cargo
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/budget_procurement
	id = "budget_procurement_challenge"
	title = "Budget Procurement Challenge"
	description = "The Traders' Guild requests broad purchasing value without relying on a single catalog line."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "Interstellar Traders' Guild"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 2900

/datum/contract_definition/social/program/budget_procurement/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "buyer", "Cargo procurement lead", "Coordinates approvals, timing, and budget use.", list(DEPARTMENT_CARGO), 1, 3)
	add_social_role(contract, "requester", "Department requester", "Defines a genuine operational need and receives the order.", null, 3, 8)
	contract.personal_side_definitions = list("cargo_local_priority")
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 5000, "Procured value", "Fulfill 5,000 Thalers of ordinary supply orders.", "value", CONTRACT_EVIDENCE_SCOPE_ANY)
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 9, "Catalog breadth", "Fulfill nine distinct supply-pack types.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "pack_type")
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 4, "Department participation", "Fulfill orders funded by four distinct departments.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "funding_department")

/datum/contract_definition/social/program/local_supplier
	id = "local_supplier_cooperative"
	title = "Local Supplier Cooperative"
	description = "The Traders' Guild requests a diversified export portfolio sourced from station departments."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "Interstellar Traders' Guild Cooperative Desk"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 3000

/datum/contract_definition/social/program/local_supplier/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "broker", "Cargo cooperative broker", "Values, manifests, and exports station products.", list(DEPARTMENT_CARGO), 1, 3)
	add_social_role(contract, "supplier", "Department supplier", "Contributes locally produced goods to the cooperative.", null, 4, 12)
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_EXPORTED, 4000, "origin_department", "value", 4, "Local export value", "Export 4,000 Thalers sourced from four station departments.", CONTRACT_EVIDENCE_SCOPE_ANY, null, null, 700, 1400)
	add_program_count(contract, CONTRACT_EVENT_ITEM_EXPORTED, 9, "Product breadth", "Export nine distinct product classes.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "item_type")

/datum/contract_definition/social/program/materials_recovery
	id = "materials_recovery_initiative"
	title = "Materials Recovery Initiative"
	description = "NanoTrasen Circular Logistics requests varied recovered value returned through ordinary freight."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "NanoTrasen Circular Logistics"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2850

/datum/contract_definition/social/program/materials_recovery/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "recovery", "Materials recovery lead", "Organizes collection, valuation, and outbound processing.", list(DEPARTMENT_CARGO), 1, 4)
	add_social_role(contract, "supplier", "Recovery contributor", "Supplies salvage, surplus, raw material, or fabricated goods.", null, 3, 10)
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_EXPORTED, 5000, "item_type", "value", 10, "Recovered freight", "Export 5,000 Thalers across ten product classes.", CONTRACT_EVIDENCE_SCOPE_ANY, null, null, 600, 900)
	add_program_portfolio(contract, CONTRACT_EVENT_ITEM_PRODUCED, 1200, "department", "value", 3, "Station reclamation use", "Produce 1,200 Thalers of equipment across three departments.", CONTRACT_EVIDENCE_SCOPE_ANY, null, null, 400, 600)

/datum/contract_definition/social/program/cold_chain
	id = "cold_chain_logistics"
	title = "Cold-Chain Logistics"
	description = "VeyMed requests diverse temperature-controlled supply deliveries through ordinary freezer crates."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "VeyMed Cold-Chain Operations"
	issuer_faction = REPUTATION_FACTION_VEYMED
	reward = 2800

/datum/contract_definition/social/program/cold_chain/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "logistics", "Cold-chain coordinator", "Schedules and receives temperature-controlled Cargo orders.", list(DEPARTMENT_CARGO), 1, 3)
	add_social_role(contract, "recipient", "Clinical or food-service recipient", "Defines need and accepts freezer-crate deliveries.", list(DEPARTMENT_MEDICAL, DEPARTMENT_CIVILIAN), 2, 6)
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 6, "Cold-chain deliveries", "Fulfill six distinct supply packs delivered in freezer crates.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "pack_type", list("cold_chain" = TRUE))
	add_program_count(contract, CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED, 2400, "Protected cargo value", "Deliver 2,400 Thalers of freezer-crated goods.", "value", CONTRACT_EVIDENCE_SCOPE_ANY, null, list("cold_chain" = TRUE))

// --------------------------------------------------------------------------
// Civilian
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/station_festival
	id = "station_festival_commission"
	title = "Station Festival Commission"
	description = "TALON Cultural Exchange requests a paid station event with broad participation and varied service."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "TALON Cultural Exchange"
	issuer_faction = REPUTATION_FACTION_TALON
	reward = 3000

/datum/contract_definition/social/program/station_festival/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "host", "Festival host", "Coordinates food, drink, pricing, and participation.", list(DEPARTMENT_CIVILIAN), 2, 6)
	add_social_role(contract, "patron", "Registered patron", "Participates as a genuine customer or sponsor.", null, 6, 16)
	contract.personal_side_definitions = list("service_gratuity_drive")
	add_program_count(contract, CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 1200, "Festival revenue", "Settle 1,200 Thalers of verified Civilian service sales.", "verified_amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "department"))
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, 16, "Festival attendance", "Serve food or drink to sixteen distinct consumers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, 10, "Menu breadth", "Serve ten distinct meal or drink types.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "item_type")

/datum/contract_definition/social/program/nutritional_services
	id = "nutritional_services_campaign"
	title = "Nutritional Services Campaign"
	description = "NanoTrasen Personnel requests broad, measurable crew participation in paid station food service."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "NanoTrasen Personnel Services"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2700

/datum/contract_definition/social/program/nutritional_services/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "provider", "Nutrition-service provider", "Prepares and sells a varied menu through ordinary service checkout.", list(DEPARTMENT_CIVILIAN), 1, 5)
	add_social_role(contract, "participant", "Crew participant", "Purchases and consumes station food or drink.", null, 5, 14)
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, 20, "Crew reached", "Serve twenty distinct consumers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "subject_id")
	add_program_count(contract, CONTRACT_EVENT_FOOD_CONSUMED, 12, "Menu diversity", "Serve twelve distinct food or drink types.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "item_type")
	add_program_count(contract, CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 900, "Sustainable service", "Settle 900 Thalers of verified Civilian sales.", "verified_amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "department"))

/datum/contract_definition/social/program/agricultural_cooperative
	id = "agricultural_cooperative"
	title = "Agricultural Cooperative"
	description = "The Worker's Union requests a varied harvest tied to genuine station food-service demand."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "Worker's Union Agricultural Cooperative"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 2800

/datum/contract_definition/social/program/agricultural_cooperative/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "grower", "Cooperative grower", "Raises and harvests a varied station crop portfolio.", list(DEPARTMENT_CIVILIAN), 1, 5)
	add_social_role(contract, "buyer", "Kitchen or crew buyer", "Creates real demand for the cooperative's output.", null, 3, 10)
	add_program_count(contract, CONTRACT_EVENT_CROP_HARVESTED, 60, "Cooperative yield", "Harvest sixty units of station produce.", "yield", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_CROP_HARVESTED, 8, "Crop diversity", "Harvest eight distinct crop lines.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "crop_id")
	add_program_count(contract, CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, 700, "Market demand", "Settle 700 Thalers of verified Civilian sales.", "verified_amount", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "department"))

/datum/contract_definition/social/program/sanitation_recovery
	id = "sanitation_recovery_award"
	title = "Sanitation Recovery Award"
	description = "NanoTrasen Facilities requests broad manual and automated sanitation of station spaces."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CIVILIAN
	issuer_name = "NanoTrasen Facilities Assurance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2500

/datum/contract_definition/social/program/sanitation_recovery/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "sanitation", "Sanitation lead", "Coordinates safe cleanup and verifies affected areas.", list(DEPARTMENT_CIVILIAN), 1, 4)
	add_social_role(contract, "liaison", "Area representative", "Provides access and identifies operational cleanup priorities.", null, 2, 8)
	add_program_count(contract, CONTRACT_EVENT_SANITATION_COMPLETED, 24, "Sanitized locations", "Clean twenty-four distinct station targets.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "target_id")
	add_program_count(contract, CONTRACT_EVENT_SANITATION_COMPLETED, 2, "Method breadth", "Use both manual and automated sanitation methods.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "method")
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 6, "Automated assistance", "Complete six cleanbot sanitation tasks.", "work_units", CONTRACT_EVIDENCE_SCOPE_ANY, null, list("task_kind" = "sanitation"))

// --------------------------------------------------------------------------
// Command
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/balanced_operations
	id = "balanced_operations_charter"
	title = "Balanced Operations Charter"
	description = "NanoTrasen requests a funded, diversified budget cycle with sustainable payroll coverage."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "NanoTrasen Corporate Finance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3400

/datum/contract_definition/social/program/balanced_operations/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "executive", "Executive budget sponsor", "Sets allocations and accepts accountability for the closed cycle.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "delegate", "Department budget delegate", "Represents operating and workforce needs.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 5, 9)
	contract.personal_side_definitions = list("command_executive_reserve")
	add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, "Balanced cycle", "Close a station budget cycle funding at least six departments and 20,000 Thalers.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "station"), list(list("key" = "funded_department_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 6), list("key" = "funded_allocation_total", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 20000)))
	add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, "Payroll coverage", "Fund at least 90% of due station payroll in the same closed cycle.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "station"), list(list("key" = "payroll_coverage", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0.9)))

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
	add_social_role(contract, "delegate", "Department compact delegate", "Commits a department to provide or receive meaningful aid.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 4, 9)
	add_program_count(contract, CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED, 10000, "Committed aid", "Allocate 10,000 Thalers through ordinary department budgeting.", "amount")
	add_program_count(contract, CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED, 5, "Recipient breadth", "Fund five distinct departments.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "target_department")
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 250, "Delivered aid outcome", "Complete 250 integrity points of station repairs after the compact is active.", "repair_amount")

/datum/contract_definition/social/program/emergency_continuity
	id = "emergency_continuity_award"
	title = "Emergency Continuity Award"
	description = "SolGov requests restoration of essential electrical, atmospheric, and medical service after disruption."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "SolGov Continuity Directorate"
	issuer_faction = REPUTATION_FACTION_SOLGOV
	reward = 3500

/datum/contract_definition/social/program/emergency_continuity/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "command", "Continuity commander", "Coordinates priorities and interdepartmental access.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "specialist", "Continuity specialist", "Restores one essential service domain.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_SECURITY), 3, 8)
	add_program_count(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, 5, "Electrical continuity", "Return five distinct APC zones to full service.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "service_id", null, list(list("key" = "powered_channels", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 3)))
	add_program_count(contract, CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, 5, "Atmospheric continuity", "Return five distinct alarm zones to safe status.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "service_id", null, list(list("key" = "danger_level", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 0)))
	add_program_count(contract, CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME, 4, "Medical continuity", "Improve four distinct patients through the ordinary condition system.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "subject_id")

/datum/contract_definition/social/program/workforce_retention
	id = "workforce_retention_agreement"
	title = "Workforce Retention Agreement"
	description = "The Worker's Union requests a funded payroll cycle and broad employee participation."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_COMMAND
	issuer_name = "Worker's Union Bargaining Council"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 3300

/datum/contract_definition/social/program/workforce_retention/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "executive", "Station bargaining representative", "Commits Command to the selected compensation terms.", list(DEPARTMENT_COMMAND), 1, 2)
	add_social_role(contract, "delegate", "Workforce delegate", "Represents one department's staff and operating needs.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_SYNTHETIC), 5, 10)
	add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 1, "Funded payroll", "Close a cycle paying at least 95% of due payroll.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "station"), list(list("key" = "payroll_coverage", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 0.95)))
	add_program_count(contract, CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, 6, "Funded departments", "Fund at least six operating departments in the closed cycle.", "funded_department_count", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, null, list("rollup" = "station"))

// --------------------------------------------------------------------------
// Synthetic
// --------------------------------------------------------------------------

/datum/contract_definition/social/program/systems_uptime
	id = "systems_uptime_accord"
	title = "Systems Uptime Accord"
	description = "Kusanagi field support requests distributed service stability verified by ordinary station controllers."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_SYNTHETIC
	issuer_name = "Kusanagi Robotics Field Support"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2900

/datum/contract_definition/social/program/systems_uptime/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "systems", "Synthetic systems coordinator", "Monitors service continuity and directs automated support.", list(DEPARTMENT_SYNTHETIC), 0, 4)
	add_social_role(contract, "liaison", "Department systems liaison", "Provides operational priorities and verifies restored service.", null, 3, 8)
	add_program_count(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, 8, "Distributed uptime", "Return eight distinct APC service zones to full power.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "service_id", null, list(list("key" = "powered_channels", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 3)))
	add_program_sustained(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, "service_id", "powered_channels", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 3, 3 MINUTES, 5, "Sustained uptime", "Hold five service zones at full power for three minutes.", CONTRACT_EVIDENCE_SCOPE_ANY)

/datum/contract_definition/social/program/automation_logistics
	id = "automation_logistics_trial"
	title = "Automation Logistics Trial"
	description = "Kusanagi Robotics requests a varied portfolio of successful ordinary station-bot tasks."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_SYNTHETIC
	issuer_name = "Kusanagi Robotics Applications Group"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 3000

/datum/contract_definition/social/program/automation_logistics/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "automation", "Automation coordinator", "Configures and supervises ordinary station bots.", list(DEPARTMENT_SYNTHETIC, DEPARTMENT_CARGO), 1, 4)
	add_social_role(contract, "recipient", "Automation-service recipient", "Provides real tasks and confirms operational results.", null, 3, 10)
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 15, "Automated workload", "Complete fifteen units of successful automated work.", "work_units", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 3, "Task diversity", "Complete three distinct automation task classes.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "task_kind")
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 5, "Destination breadth", "Serve five distinct task targets.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "target_id")

/datum/contract_definition/social/program/access_safety_audit
	id = "access_safety_audit"
	title = "Access and Safety Audit"
	description = "NanoTrasen Systems Assurance requests cross-system verification backed by actual service transitions and repairs."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_SYNTHETIC
	issuer_name = "NanoTrasen Systems Assurance"
	issuer_faction = REPUTATION_FACTION_NANOTRASEN
	reward = 2800

/datum/contract_definition/social/program/access_safety_audit/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "auditor", "Systems auditor", "Coordinates automated checks and identifies unsafe dependencies.", list(DEPARTMENT_SYNTHETIC, DEPARTMENT_ENGINEERING), 1, 4)
	add_social_role(contract, "owner", "Department asset owner", "Provides access and accepts the resulting service state.", null, 3, 8)
	add_program_count(contract, CONTRACT_EVENT_POWER_SERVICE_CHANGED, 6, "Electrical audit", "Verify six distinct APC zones in full service.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "service_id", null, list(list("key" = "powered_channels", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 3)))
	add_program_count(contract, CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, 6, "Atmospheric audit", "Verify six distinct air-alarm zones at safe status.", null, CONTRACT_EVIDENCE_SCOPE_ANY, "service_id", null, list(list("key" = "danger_level", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 0)))
	add_program_count(contract, CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED, 200, "Corrective work", "Complete 200 integrity points of corrective station repair.", "repair_amount")

/datum/contract_definition/social/program/human_synthetic_compact
	id = "human_synthetic_service_compact"
	title = "Human-Synthetic Service Compact"
	description = "The Worker's Union and Kusanagi Robotics jointly request accountable automation serving varied crew needs."
	scope = CONTRACT_SCOPE_STATION
	department = DEPARTMENT_SYNTHETIC
	issuer_name = "Human-Synthetic Service Council"
	issuer_faction = REPUTATION_FACTION_WORKERS_UNION
	reward = 3200

/datum/contract_definition/social/program/human_synthetic_compact/configure_contract(datum/contract/social/contract, list/context)
	..()
	add_social_role(contract, "synthetic", "Synthetic service coordinator", "Coordinates automated work and reports service constraints.", list(DEPARTMENT_SYNTHETIC), 0, 4)
	add_social_role(contract, "delegate", "Crew service delegate", "Represents a department receiving or supervising automated assistance.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_MEDICAL, DEPARTMENT_RESEARCH, DEPARTMENT_SECURITY, DEPARTMENT_CARGO, DEPARTMENT_CIVILIAN, DEPARTMENT_COMMAND), 4, 10)
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 18, "Shared automated work", "Complete eighteen units of successful station-bot work.", "work_units", CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 3, "Service breadth", "Complete three distinct automation task classes.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "task_kind")
	add_program_count(contract, CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, 8, "Crew needs served", "Serve eight distinct task targets.", null, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT, "target_id")

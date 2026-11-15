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
		list("name" = "Surgical Instrument Stock", "purpose" = "corrosion-safe, tough stock for reusable surgical tools", "checks" = list(list("key" = "toughness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 31), list("key" = "corrosion_resistance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 70), list("key" = "strength", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 72))),
		list("name" = "Pressure Vessel Stock", "purpose" = "low-flaw, corrosion-resistant pressure containment", "checks" = list(list("key" = "toughness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 33), list("key" = "corrosion_resistance", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 60), list("key" = "flaws", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 25))),
		list("name" = "Disposable Cutter Stock", "purpose" = "extreme hardness at an economical unit cost", "checks" = list(list("key" = "strength", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 76), list("key" = "unit_cost", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 45), list("key" = "brittleness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_MOST, "expected" = 70))),
		list("name" = "Light Armor Plate", "purpose" = "balanced armor stock with practical production quality", "checks" = list(list("key" = "strength", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 62), list("key" = "toughness", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 28), list("key" = "quality", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 70))),
	)
	var/list/profile = pick(profiles)
	contract.title = profile["name"]
	contract.description = "Produce [profile["purpose"]] and submit a qualified batch for Chimera's materials trial. Composition and treatment are at Research's discretion."
	add_social_role(contract, "metallurgist", "Process metallurgist", "Selects feedstock and develops a reproducible treatment route.", list(DEPARTMENT_RESEARCH), 1, 4)
	add_social_role(contract, "evaluator", "Operational evaluator", "Examines the physical workpiece and proposes a station use for the alloy.", list(DEPARTMENT_ENGINEERING, DEPARTMENT_CARGO, DEPARTMENT_SECURITY), 1, 4)
	var/list/checks = profile["checks"]
	checks += list(list("key" = "composition_count", "comparator" = CONTRACT_EVIDENCE_COMPARE_AT_LEAST, "expected" = 2))
	add_material_delivery(contract, checks, 1, "Application stock order", "Assay a batch meeting the application envelope, then ship that exact stock through Cargo.")

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

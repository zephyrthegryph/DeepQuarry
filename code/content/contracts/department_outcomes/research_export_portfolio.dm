/datum/contract_definition/outcome/research_export_portfolio
	initial_offers = 0
	auto_replace = FALSE
	id = "research_export_portfolio"
	title = "Applied Prototype Portfolio"
	description = "Eclipse Corporation requests a commercially useful portfolio of station-fabricated Research products, accompanied by freight records establishing their value and station provenance."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_RESEARCH
	issuer_name = "Eclipse Applied Technologies"
	issuer_faction = REPUTATION_FACTION_ECLIPSE
	reward = 2300

/datum/contract_definition/outcome/research_export_portfolio/configure_contract(datum/contract/outcome/contract, list/context)
	contract.outcome_variant = context?["portfolio_variant"] || (context?["value_target"] ? "balanced" : pick("breadth", "balanced", "premium"))
	var/default_value = contract.outcome_variant == "breadth" ? pick(1300, 1500) : (contract.outcome_variant == "premium" ? pick(1900, 2200) : pick(1500, 1700, 1900))
	var/default_variety = contract.outcome_variant == "breadth" ? pick(5, 6) : (contract.outcome_variant == "premium" ? 3 : pick(4, 5))
	contract.primary_target = context?["value_target"] || default_value
	contract.secondary_target = context?["variety_target"] || default_variety
	contract.description = "Complete a [contract.outcome_variant] Research portfolio: export at least [contract.primary_target] Thalers of Research-produced equipment across [contract.secondary_target] distinct product designs. The freight ledger recognizes items fabricated by Research machinery and records the responsible producer."
	contract.station_reputation_reward = 8
	contract.department_reputation_reward = 26
	contract.personal_reputation_reward = 10
	configure_outcome_negotiations(contract)
	var/datum/contract_requirement/fact_portfolio/portfolio = new(CONTRACT_EVENT_ITEM_EXPORTED, contract.primary_target, "item_type", "value", contract.secondary_target, CONTRACT_EVIDENCE_SCOPE_DEPARTMENT)
	portfolio.name = "Commercial prototype portfolio"
	portfolio.description = "Export [contract.primary_target] Thalers across [contract.secondary_target] distinct Research-produced designs. No one item contributes more than 500 Thalers and no repeated design contributes more than 750."
	portfolio.minimum_fact_value = contract.outcome_variant == "premium" ? 150 : 50
	portfolio.maximum_fact_value = 500
	portfolio.maximum_category_value = contract.outcome_variant == "breadth" ? 600 : 750
	contract.add_requirement(portfolio)
	contract.personal_side_definitions = list("research_internal_access")

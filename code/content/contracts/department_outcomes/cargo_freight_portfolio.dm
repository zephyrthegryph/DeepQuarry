/datum/contract_definition/outcome/cargo_freight_portfolio
	initial_offers = 0
	auto_replace = FALSE
	id = "cargo_freight_portfolio"
	title = "Guild Freight Portfolio"
	description = "The Interstellar Traders' Guild offers a throughput award for valuable, varied Cargo-origin freight accepted aboard the supply shuttle."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = DEPARTMENT_CARGO
	issuer_name = "Interstellar Traders' Guild Freight Exchange"
	issuer_faction = REPUTATION_FACTION_TRADERS_GUILD
	reward = 2200

/datum/contract_definition/outcome/cargo_freight_portfolio/configure_contract(datum/contract/outcome/contract, list/context)
	contract.outcome_variant = context?["portfolio_variant"] || (context?["value_target"] ? "balanced" : pick("salvage", "balanced", "diversified"))
	var/default_value = contract.outcome_variant == "salvage" ? pick(3000, 3400) : (contract.outcome_variant == "diversified" ? pick(2100, 2400) : pick(2500, 2800, 3100))
	var/default_variety = contract.outcome_variant == "salvage" ? 3 : (contract.outcome_variant == "diversified" ? pick(6, 7) : pick(4, 5))
	contract.primary_target = context?["value_target"] || default_value
	contract.secondary_target = context?["variety_target"] || default_variety
	contract.description = "Complete a [contract.outcome_variant] Cargo portfolio by processing [contract.primary_target] Thalers of accepted outbound freight across at least [contract.secondary_target] distinct product types. Raw materials, salvage, crates, and goods consigned by other departments are all eligible."
	contract.station_reputation_reward = 8
	contract.department_reputation_reward = 24
	contract.personal_reputation_reward = 10
	configure_outcome_negotiations(contract)
	var/datum/contract_requirement/fact_portfolio/portfolio = new(CONTRACT_EVENT_ITEM_EXPORTED, contract.primary_target, "item_type", "value", contract.secondary_target, CONTRACT_EVIDENCE_SCOPE_ANY)
	portfolio.name = "Diversified freight portfolio"
	portfolio.description = "Process [contract.primary_target] Thalers across [contract.secondary_target] distinct accepted freight types. No one item contributes more than 650 Thalers and no repeated type contributes more than 900."
	portfolio.filter.require_value("handling_department", DEPARTMENT_CARGO)
	portfolio.minimum_fact_value = 25
	portfolio.maximum_fact_value = contract.outcome_variant == "salvage" ? 900 : 650
	portfolio.maximum_category_value = contract.outcome_variant == "salvage" ? 1400 : (contract.outcome_variant == "diversified" ? 700 : 900)
	contract.add_requirement(portfolio)
	contract.personal_side_definitions = list("cargo_local_priority")

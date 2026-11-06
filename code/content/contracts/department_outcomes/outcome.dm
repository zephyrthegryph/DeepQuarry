/datum/contract_definition/outcome
	abstract_type = /datum/contract_definition/outcome
	initial_offers = 1
	offer_kind = CONTRACT_OFFER_STANDING
	auto_replace = TRUE
	max_simultaneous = 2
	var/followup_reputation_threshold = REPUTATION_ALLIED
	contract_type = /datum/contract/outcome

/datum/contract_definition/outcome/prepare_accept(datum/contract/outcome/contract, datum/money_account/accepting_account, mob/living/user, atom/source)
	var/live_crew = 0
	for(var/mob/living/player in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(player.client && player.stat != DEAD && contract_account_for_mob(player))
			live_crew++
	switch(id)
		if("supermatter_performance")
			if(user)
				var/has_station_crystal = FALSE
				for(var/obj/machinery/power/supermatter/crystal in REGISTRY_MEMBERS(REGISTRY_MACHINES))
					if(crystal.stationcrystal && (crystal.z in using_map.station_levels))
						has_station_crystal = TRUE
						break
				if(!has_station_crystal)
					to_chat(user, span_warning("No station supermatter telemetry source is currently available."))
					return FALSE
		if("service_hospitality_census")
			contract.secondary_target = min(contract.secondary_target, max(1, live_crew - 1))
			contract.primary_target = min(contract.primary_target, contract.secondary_target * 400)
			for(var/datum/contract_requirement/event_count/requirement in contract.requirements)
				requirement.filter.set_number_requirement("amount", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
				requirement.filter.set_number_requirement("customer_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
				requirement.description = "Close an accounting period with [contract.primary_target] Thalers in qualifying sales to [contract.secondary_target] distinct customers."
		if("security_case_resolution")
			contract.primary_target = min(contract.primary_target, max(1, live_crew - 1))
			for(var/datum/contract_requirement/event_count/requirement in contract.requirements)
				requirement.target = contract.primary_target
				requirement.description = "Record [contract.primary_target] distinct releases or paroles after [DisplayTimeText(contract.outcome_duration)] in custody."
		if("command_budget_mandate")
			var/available_departments = 0
			for(var/department_name in GLOB.department_accounts)
				if(department_name != DEPARTMENT_PLANET && department_name != "Vendor")
					available_departments++
			var/minimum_allocation = max(1, contract.minimum_allocation)
			var/funding_capacity = SSsupply.projected_station_budget_capacity()
			var/fundable_departments = min(available_departments, FLOOR(funding_capacity / minimum_allocation, 1))
			if(fundable_departments < 1)
				if(user)
					to_chat(user, span_warning("The station lacks enough current funds and committed payroll support to accept this capital mandate."))
				return FALSE
			contract.secondary_target = min(contract.secondary_target, fundable_departments)
			contract.primary_target = max(contract.secondary_target * minimum_allocation, min(contract.primary_target, funding_capacity, contract.secondary_target * 4000))
			contract.description = "Complete one monthly budget and payroll cycle that actually funds at least [contract.primary_target] Thalers among [contract.secondary_target] station departments, with no qualifying department below [minimum_allocation] Thalers and at least 75% of wages paid. Exploration is excluded and Command may retain no more than 3,000 Thalers under the diversified mandate."
			for(var/datum/contract_requirement/event_count/requirement in contract.requirements)
				requirement.filter.set_number_requirement("funded_allocation_total", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.primary_target)
				requirement.filter.set_number_requirement("funded_department_count", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, contract.secondary_target)
				requirement.description = "Close one cycle with [contract.primary_target] funded Thalers across [contract.secondary_target] qualifying departments while keeping Command's allocation at or below 3,000."
	return TRUE

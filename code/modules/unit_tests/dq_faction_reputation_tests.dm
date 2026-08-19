/datum/unit_test/dq_faction_registry

/datum/unit_test/dq_faction_registry/Run()
	TEST_ASSERT_EQUAL(length(GLOB.reputation_factions), 9, "reputation faction registry must contain all nine configured factions")
	for(var/faction_id in list(
		REPUTATION_FACTION_NANOTRASEN,
		REPUTATION_FACTION_SOLGOV,
		REPUTATION_FACTION_CHIMERA,
		REPUTATION_FACTION_ECLIPSE,
		REPUTATION_FACTION_SYNDICATE,
		REPUTATION_FACTION_TRADERS_GUILD,
		REPUTATION_FACTION_TALON,
		REPUTATION_FACTION_WORKERS_UNION,
		REPUTATION_FACTION_VEYMED,
	))
		var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
		TEST_ASSERT_NOTNULL(faction, "missing reputation faction [faction_id]")
		TEST_ASSERT(length(faction.name), "faction [faction_id] has no name")
		TEST_ASSERT(length(faction.description), "faction [faction_id] has no lore description")

/datum/unit_test/dq_faction_ledger_scopes

/datum/unit_test/dq_faction_ledger_scopes/Run()
	var/datum/faction_reputation_ledger/first = new()
	var/datum/faction_reputation_ledger/second = new()
	TEST_ASSERT(first.adjust_reputation(REPUTATION_FACTION_VEYMED, 125), "valid reputation adjustment was rejected")
	TEST_ASSERT_EQUAL(first.get_reputation(REPUTATION_FACTION_VEYMED), 125, "adjustment was not retained")
	TEST_ASSERT_EQUAL(second.get_reputation(REPUTATION_FACTION_VEYMED), 0, "independent reputation ledgers leaked state")
	first.set_reputation(REPUTATION_FACTION_VEYMED, REPUTATION_MAXIMUM + 500)
	TEST_ASSERT_EQUAL(first.get_reputation(REPUTATION_FACTION_VEYMED), REPUTATION_MAXIMUM, "positive reputation was not clamped")
	first.set_reputation(REPUTATION_FACTION_VEYMED, REPUTATION_MINIMUM - 500)
	TEST_ASSERT_EQUAL(first.get_reputation(REPUTATION_FACTION_VEYMED), REPUTATION_MINIMUM, "negative reputation was not clamped")
	TEST_ASSERT(!first.adjust_reputation("not_a_faction", 1), "unknown faction adjustment was accepted")
	qdel(first)
	qdel(second)

/datum/unit_test/dq_faction_affiliation_preference

/datum/unit_test/dq_faction_affiliation_preference/Run()
	var/datum/preference/faction_affiliations/preference = GLOB.preference_entries[/datum/preference/faction_affiliations]
	TEST_ASSERT_NOTNULL(preference, "faction affiliation preference was not registered")
	var/list/defaults = preference.create_default_value()
	TEST_ASSERT(preference.is_valid(defaults), "default faction affiliations are invalid")
	defaults[REPUTATION_FACTION_TALON] = AFFILIATION_MEMBER
	TEST_ASSERT(!preference.is_valid(defaults), "unfunded positive affiliation was accepted")
	defaults[REPUTATION_FACTION_SYNDICATE] = AFFILIATION_HOSTILE
	TEST_ASSERT(preference.is_valid(defaults), "funded member affiliation was rejected")
	defaults[REPUTATION_FACTION_TALON] = "Owner"
	TEST_ASSERT(!preference.is_valid(defaults), "unknown affiliation was accepted")
	var/list/sanitized = preference.pref_deserialize(defaults, null)
	TEST_ASSERT_EQUAL(sanitized[REPUTATION_FACTION_TALON], AFFILIATION_NEUTRAL, "invalid affiliation was not neutralized")
	for(var/preference_type in GLOB.preference_entries)
		var/datum/preference/registered_preference = GLOB.preference_entries[preference_type]
		TEST_ASSERT(registered_preference.savefile_key != "faction", "legacy single-faction preference is still registered")

/datum/unit_test/dq_faction_affiliation_budget

/datum/unit_test/dq_faction_affiliation_budget/Run()
	var/list/affiliations = list()
	for(var/faction_id in GLOB.reputation_factions)
		affiliations[faction_id] = AFFILIATION_NEUTRAL
	TEST_ASSERT_EQUAL(reputation_affiliation_total(affiliations), 0, "neutral affiliations should have a zero total")
	affiliations[REPUTATION_FACTION_NANOTRASEN] = AFFILIATION_FRIENDLY
	TEST_ASSERT(reputation_affiliation_total(affiliations) > REPUTATION_AFFILIATION_NET_CAP, "unfunded positive affiliation should exceed the cap")
	affiliations[REPUTATION_FACTION_SYNDICATE] = AFFILIATION_OPPOSED
	TEST_ASSERT_EQUAL(reputation_affiliation_total(affiliations), REPUTATION_AFFILIATION_NET_CAP, "equal negative reputation should fund positive reputation")
	TEST_ASSERT_EQUAL(affiliations[REPUTATION_FACTION_WORKERS_UNION], AFFILIATION_NEUTRAL, "changing one affiliation unexpectedly changed another")

/datum/unit_test/dq_faction_reputation_stable_identity

/datum/unit_test/dq_faction_reputation_stable_identity/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/account = new
	account.account_number = 9654321
	account.owner_name = "Stable Reputation Tester"
	GLOB.all_money_accounts += account
	var/datum/mind/test_mind = new("stable_reputation_tester")
	test_mind.initial_account = account
	var/mob/living/carbon/human/first_body = new(test_turf)
	test_mind.transfer_to(first_body)
	var/list/affiliations = list()
	for(var/faction_id in GLOB.reputation_factions)
		affiliations[faction_id] = AFFILIATION_NEUTRAL
	first_body.set_faction_affiliations(affiliations)
	TEST_ASSERT(first_body.adjust_faction_reputation(REPUTATION_FACTION_VEYMED, 35), "first body could not earn personal reputation")

	var/mob/living/carbon/human/second_body = new(test_turf)
	test_mind.transfer_to(second_body)
	// Character preferences may be applied to a replacement body; they must not
	// reset standing already earned by the account this round.
	second_body.set_faction_affiliations(affiliations)
	TEST_ASSERT_EQUAL(second_body.get_faction_reputation(REPUTATION_FACTION_VEYMED), 35, "mind transfer or preference application reset earned reputation")
	TEST_ASSERT(adjust_personal_faction_reputation(account.account_number, REPUTATION_FACTION_VEYMED, 5), "offline/account-directed reputation adjustment failed")
	TEST_ASSERT_EQUAL(second_body.get_faction_reputation(REPUTATION_FACTION_VEYMED), 40, "account-directed reputation did not reach the current body")

	var/personal_key = "[account.account_number]"
	var/datum/faction_reputation_ledger/personal_ledger = GLOB.station_faction_relations.personal_ledgers[personal_key]
	GLOB.station_faction_relations.personal_ledgers -= personal_key
	GLOB.all_money_accounts -= account
	qdel(second_body)
	qdel(first_body)
	qdel(test_mind)
	qdel(personal_ledger)
	qdel(account)

/datum/unit_test/dq_faction_agent_earned_eligibility

/datum/unit_test/dq_faction_agent_earned_eligibility/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/account = new
	account.account_number = 9654330
	account.owner_name = "Agency Tester"
	GLOB.all_money_accounts += account
	var/datum/mind/test_mind = new("agency_tester")
	test_mind.initial_account = account
	var/mob/living/carbon/human/test_agent = new(test_turf)
	test_mind.transfer_to(test_agent)
	var/datum/faction_reputation_ledger/ledger = GLOB.station_faction_relations.get_personal_ledger(account.account_number)
	ledger.set_reputation(REPUTATION_FACTION_TRADERS_GUILD, CARGO_MARKET_AGENT_REPUTATION)
	TEST_ASSERT(!GLOB.station_faction_relations.account_agent_eligibility(account.account_number, REPUTATION_FACTION_TRADERS_GUILD), "character-setup standing alone incorrectly granted agency")
	TEST_ASSERT(ledger.adjust_reputation(REPUTATION_FACTION_TRADERS_GUILD, CARGO_MARKET_AGENT_EARNED_REPUTATION), "in-round reputation gain was rejected")
	TEST_ASSERT_EQUAL(ledger.positive_earned(REPUTATION_FACTION_TRADERS_GUILD), CARGO_MARKET_AGENT_EARNED_REPUTATION, "positive in-round reputation was not tracked")
	TEST_ASSERT(GLOB.station_faction_relations.account_agent_eligibility(account.account_number, REPUTATION_FACTION_TRADERS_GUILD), "earned Allied standing did not unlock agency")
	TEST_ASSERT(GLOB.station_faction_relations.begin_agent_vetting(test_agent, REPUTATION_FACTION_TRADERS_GUILD), "eligible player could not begin faction vetting")
	TEST_ASSERT(GLOB.station_faction_relations.account_has_principal_access(account.account_number, REPUTATION_FACTION_TRADERS_GUILD), "candidate relationship was not retained by stable account identity")
	TEST_ASSERT(!GLOB.station_faction_relations.account_is_agent(account.account_number, REPUTATION_FACTION_TRADERS_GUILD), "candidate incorrectly bypassed authenticated trade vetting")
	TEST_ASSERT(!GLOB.station_faction_relations.account_agent_eligibility(account.account_number, REPUTATION_FACTION_VEYMED), "an appointed agent could select a second principal")
	var/vetting_offers = 0
	for(var/datum/contract/faction_agent/offer in SScontracts.offered_contracts.Copy())
		if(offer.owner_account_number != account.account_number)
			continue
		TEST_ASSERT_EQUAL(offer.definition_id, "agent_vetting", "candidate received an accredited commission before vetting")
		vetting_offers++
		qdel(offer)
	TEST_ASSERT_EQUAL(vetting_offers, 1, "candidate did not receive exactly one authenticated vetting offer")
	TEST_ASSERT(GLOB.station_faction_relations.accredit_agent(account.account_number), "completed vetting could not accredit the stable account")
	TEST_ASSERT(GLOB.station_faction_relations.account_is_agent(account.account_number, REPUTATION_FACTION_TRADERS_GUILD), "accreditation did not unlock ordinary agency")
	var/agent_offers = 0
	for(var/datum/contract/faction_agent/offer in SScontracts.offered_contracts.Copy())
		if(offer.owner_account_number != account.account_number)
			continue
		agent_offers++
		qdel(offer)
	for(var/datum/contract_offer_candidate/candidate in SScontracts.offer_candidates.Copy())
		if(candidate.context?["owner_account"] == account.account_number)
			SScontracts.withdraw_candidate(candidate, "Agency test cleanup")
	TEST_ASSERT_EQUAL(agent_offers, CARGO_MARKET_AGENT_OFFERS, "agency did not publish the expected private offer choice")
	var/datum/faction_agent_record/record = GLOB.station_faction_relations.get_agent_record(account.account_number)
	record.contracts_completed = FACTION_AGENT_TRUSTED_COMPLETIONS
	TEST_ASSERT(GLOB.station_faction_relations.refresh_agent_tier(record), "qualified accredited agent did not reach trusted status")
	TEST_ASSERT("agent_red_exfiltration" in SScontracts.agent_contract_definition_ids(record), "trusted non-Syndicate agent was not offered a faction-appropriate red mandate")
	var/personal_key = "[account.account_number]"
	GLOB.station_faction_relations.agent_records -= personal_key
	GLOB.station_faction_relations.personal_ledgers -= personal_key
	GLOB.all_money_accounts -= account
	qdel(record)
	qdel(test_agent)
	qdel(test_mind)
	qdel(ledger)
	qdel(account)

/datum/unit_test/dq_faction_operation_composition

/datum/unit_test/dq_faction_operation_composition/Run()
	var/list/factions = list(
		REPUTATION_FACTION_NANOTRASEN,
		REPUTATION_FACTION_SOLGOV,
		REPUTATION_FACTION_CHIMERA,
		REPUTATION_FACTION_ECLIPSE,
		REPUTATION_FACTION_SYNDICATE,
		REPUTATION_FACTION_TRADERS_GUILD,
		REPUTATION_FACTION_TALON,
		REPUTATION_FACTION_WORKERS_UNION,
		REPUTATION_FACTION_VEYMED,
	)
	var/list/operation_definitions = list(
		"agent_cross_department_portfolio",
		"agent_reciprocal_trade",
		"agent_rush_brokerage",
		"agent_confidential_brokerage",
		"agent_department_endorsement",
	)
	var/list/red_signatures = list()
	for(var/faction_id in factions)
		for(var/definition_id in operation_definitions)
			var/datum/contract_definition/faction_agent/definition = SScontracts.definitions[definition_id]
			TEST_ASSERT_NOTNULL(definition, "missing compositional agent definition [definition_id]")
			var/datum/contract/faction_agent/contract = new
			contract.reward = definition.reward
			contract.definition_id = definition_id
			contract.offer_key = "composition:[faction_id]:[definition_id]"
			contract.offer_context = list("owner_account" = 9000001, "agent_faction" = faction_id)
			definition.configure_contract(contract, contract.offer_context)
			TEST_ASSERT(contract.operation_kind in list(AGENT_OPERATION_SOURCING, AGENT_OPERATION_DEMONSTRATION, AGENT_OPERATION_SERVICE, AGENT_OPERATION_CUSTODY, AGENT_OPERATION_INFLUENCE), "[faction_id] [definition_id] had no operation family")
			TEST_ASSERT(length(contract.stakeholder_departments) >= 3, "[faction_id] [definition_id] did not involve a multi-department stakeholder set")
			TEST_ASSERT(length(contract.requirements) >= 3, "[faction_id] [definition_id] had no authoritative gameplay requirement beyond paperwork")
			qdel(contract)
		var/datum/contract_definition/faction_agent/red_definition = SScontracts.definitions["agent_red_exfiltration"]
		var/datum/contract/faction_agent/red_contract = new
		red_contract.reward = red_definition.reward
		red_contract.definition_id = red_definition.id
		red_contract.offer_key = "red-composition:[faction_id]"
		red_contract.offer_context = list("owner_account" = 9000001, "agent_faction" = faction_id)
		red_definition.configure_contract(red_contract, red_contract.offer_context)
		var/list/event_types = list()
		for(var/datum/contract_requirement/requirement in red_contract.requirements)
			for(var/event_type in requirement.event_types)
				if(!(event_type in list(CONTRACT_EVENT_AGENT_APPROACH_SIGNED, CONTRACT_EVENT_AGENT_CONTACT_SIGNED)))
					event_types |= event_type
		event_types = sortList(event_types)
		red_signatures[json_encode(event_types)] = TRUE
		TEST_ASSERT(length(event_types), "[faction_id] red operation had no gameplay-system integration")
		qdel(red_contract)
	TEST_ASSERT(length(red_signatures) >= 6, "nine faction red mandates collapsed into fewer than six mechanically distinct event profiles")
	var/datum/faction_agent_record/test_record = new
	test_record.tier = FACTION_AGENT_TIER_ACCREDITED
	var/list/live_pool = SScontracts.agent_contract_definition_ids(test_record)
	for(var/legacy_id in list("agent_export_diversion", "agent_preferred_supplier", "agent_targeted_acquisition", "agent_principal_directive"))
		TEST_ASSERT(!(legacy_id in live_pool), "repetitive legacy shipment contract [legacy_id] remained in the live agent offer pool")
	qdel(test_record)

/datum/unit_test/dq_agent_approach_and_discovery_tradeoffs

/datum/unit_test/dq_agent_approach_and_discovery_tradeoffs/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/account = new
	account.account_number = 9654360
	account.owner_name = "Operation Terms Tester"
	GLOB.all_money_accounts += account
	var/datum/mind/test_mind = new("operation_terms_tester")
	test_mind.initial_account = account
	var/mob/living/carbon/human/agent = new(test_turf)
	test_mind.transfer_to(agent)
	var/datum/contract/faction_agent/registered = new
	registered.state = CONTRACT_ACTIVE
	registered.owner_account_number = account.account_number
	registered.agent_faction = REPUTATION_FACTION_NANOTRASEN
	registered.department = DEPARTMENT_RESEARCH
	registered.base_reward = 1000
	registered.reward = 1000
	TEST_ASSERT(registered.select_operation_approach(null, agent, AGENT_APPROACH_REGISTERED, null), "agent could not select the lawful registered approach")
	TEST_ASSERT_EQUAL(registered.reward, 900, "registered approach did not exchange award value for institutional protection")
	TEST_ASSERT_EQUAL(registered.station_share, 0.2, "registered approach did not fund the station")
	TEST_ASSERT_EQUAL(registered.department_share, 0.2, "registered approach did not fund its lead department")
	TEST_ASSERT_EQUAL(registered.discovery_stage, AGENT_DISCOVERY_CLEAN, "registered approach generated covert suspicion")

	var/datum/contract/faction_agent/ordinary = new
	ordinary.state = CONTRACT_ACTIVE
	ordinary.owner_account_number = account.account_number
	ordinary.agent_faction = REPUTATION_FACTION_ECLIPSE
	ordinary.base_reward = 1000
	ordinary.reward = 1000
	TEST_ASSERT(!ordinary.select_operation_approach(null, agent, AGENT_APPROACH_HOSTILE, null), "ordinary commission allowed a hostile approach without explicit red authorization")
	var/datum/contract/faction_agent/hostile = new
	hostile.state = CONTRACT_ACTIVE
	hostile.owner_account_number = account.account_number
	hostile.agent_faction = REPUTATION_FACTION_ECLIPSE
	hostile.red_contract = TRUE
	hostile.base_reward = 1000
	hostile.reward = 1000
	TEST_ASSERT(hostile.select_operation_approach(null, agent, AGENT_APPROACH_HOSTILE, null), "red commission rejected its explicitly authorized hostile approach")
	TEST_ASSERT_EQUAL(hostile.reward, 1250, "hostile approach did not apply its risk premium")
	TEST_ASSERT_EQUAL(hostile.failure_reputation_factor, 1, "hostile approach did not retain full failure liability")
	TEST_ASSERT_EQUAL(hostile.discovery_stage, AGENT_DISCOVERY_SUSPECTED, "hostile charter did not create initial suspicion")
	TEST_ASSERT(hostile.advance_discovery(AGENT_DISCOVERY_TRACED, "test trace"), "operation discovery did not advance monotonically")
	TEST_ASSERT_EQUAL(hostile.discovery_reward_multiplier(), 0.85, "traced operation did not receive its graded exposure settlement")
	TEST_ASSERT(!hostile.advance_discovery(AGENT_DISCOVERY_SUSPECTED, "stale test"), "operation discovery regressed to a weaker stage")
	TEST_ASSERT_EQUAL(hostile.operation_grade_for_ratio(0.6), CONTRACT_OUTCOME_MINIMUM, "partial operation did not map to the minimum settlement grade")
	TEST_ASSERT_EQUAL(hostile.operation_grade_for_ratio(0.8), CONTRACT_OUTCOME_SUCCESSFUL, "substantial operation did not map to the successful settlement grade")
	TEST_ASSERT_EQUAL(hostile.operation_grade_for_ratio(1), CONTRACT_OUTCOME_EXCEPTIONAL, "complete operation did not map to the exceptional settlement grade")
	GLOB.all_money_accounts -= account
	qdel(hostile)
	qdel(ordinary)
	qdel(registered)
	qdel(agent)
	qdel(test_mind)
	qdel(account)

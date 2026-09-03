#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/proc/dq_contract_test_scan(obj/item/paper/paper, mob/living/carbon/human/subject, scan_time, contract_id)
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/list/markers = list()
	if(contract_id)
		markers[contract_id] = MEDICAL_TRIAL_MINIMUM_DOSE
	paper.medical_scan_evidence = list(
		"subject_ref" = identity.id,
		"subject_id" = identity.id,
		"subject_name" = subject.real_name,
		"scan_time" = scan_time,
		"snapshot" = medical_trial_snapshot(subject),
		"trial_markers" = markers,
	)
	var/evidence_id = SScontracts.register_evidence(CONTRACT_EVIDENCE_MEDICAL_SCAN, identity.id, null, paper, paper.medical_scan_evidence)
	paper.attach_contract_evidence(evidence_id)
	return SScontracts.authenticated_scan_payload(paper)

/datum/contract_definition/dq_offer_lifecycle_test
	id = "dq_offer_lifecycle_test"
	title = "Offer Lifecycle Test"
	description = "Exercises bounded offer publication."
	scope = CONTRACT_SCOPE_DEPARTMENT
	department = "DQ Lifecycle Test"
	reward = 0
	max_simultaneous = 16
	offer_duration = 10 MINUTES

/datum/contract_definition/dq_offer_lifecycle_test/configure_contract(datum/contract/contract, list/context)
	var/datum/contract_requirement/event_count/requirement = new("dq_offer_lifecycle_result", 1)
	requirement.name = "Lifecycle completion"
	contract.add_requirement(requirement)

/datum/contract_definition/dq_opportunity_guardrail_test
	id = "dq_opportunity_guardrail_test"
	title = "Opportunity Guardrail Test"
	description = "Exercises rolling broker anti-cheese behavior."
	scope = CONTRACT_SCOPE_STATION
	reward = 0
	max_simultaneous = 2
	offer_duration = 10 MINUTES

/datum/contract_definition/dq_opportunity_guardrail_test/configure_contract(datum/contract/contract, list/context)
	contract.add_requirement(new /datum/contract_requirement/event_count("dq_opportunity_completion", 1))

/datum/contract_opportunity_rule/dq_guardrail_test
	id = "dq_guardrail_test"
	definition_id = "dq_opportunity_guardrail_test"
	description = "Focused opportunity guardrail fixture."
	window_duration = 10 MINUTES
	cooldown = 10 MINUTES
	priority = 1000

/datum/contract_opportunity_rule/dq_guardrail_test/configure()
	var/datum/contract_opportunity_signal/signal = add_signal(new /datum/contract_opportunity_signal("work", "dq_opportunity_test", 100, "value"))
	signal.minimum_facts = 3
	signal.maximum_fact_value = 50
	signal.maximum_actor_value = 60
	signal.require_diversity("entity", 3)
	signal.require_diversity("category", 2)

/datum/unit_test/dq_contract_offer_lifecycle

/datum/unit_test/dq_contract_board_curation

/datum/unit_test/dq_contract_board_curation/Run()
	var/list/offers_by_board = list()
	for(var/datum/contract/contract in SScontracts.offered_contracts)
		if(contract.offer_kind != CONTRACT_OFFER_STANDING || contract.scope == CONTRACT_SCOPE_PERSONAL)
			continue
		var/list/board_offers = offers_by_board[contract.board_key]
		if(!board_offers)
			board_offers = list()
			offers_by_board[contract.board_key] = board_offers
		board_offers += contract
	for(var/board_key in offers_by_board)
		var/list/current_board_offers = offers_by_board[board_key]
		TEST_ASSERT(length(current_board_offers) <= 2, "standing board [board_key] published more than two choices")
		if(length(current_board_offers) < 2)
			continue
		var/datum/contract/first = current_board_offers[1]
		var/datum/contract/second = current_board_offers[2]
		var/datum/contract_definition/first_definition = SScontracts.definitions[first.definition_id]
		var/datum/contract_definition/second_definition = SScontracts.definitions[second.definition_id]
		TEST_ASSERT(SScontracts.definition_term_class(first_definition) != SScontracts.definition_term_class(second_definition), "standing board [board_key] did not mix short- and long-term work")
		if(first.issuer_faction && second.issuer_faction)
			TEST_ASSERT(first.issuer_faction != second.issuer_faction, "standing board [board_key] published duplicate sponsor factions")

/datum/unit_test/dq_contract_offer_lifecycle/Run()
	var/test_board = "[CONTRACT_SCOPE_DEPARTMENT]:DQ Lifecycle Test"
	var/preexisting_station_offers = 0
	var/datum/contract/held_station_offer
	for(var/datum/contract/existing in SScontracts.offered_contracts)
		if(existing.board_key == test_board && existing.definition_id != "dq_offer_lifecycle_test")
			preexisting_station_offers++
	var/expected_published = min(4, max(0, CONTRACT_BOARD_DEPARTMENT_LIMIT - preexisting_station_offers))
	if(expected_published <= 0)
		for(var/datum/contract/existing in SScontracts.offered_contracts)
			if(existing.board_key != test_board || existing.definition_id == "dq_offer_lifecycle_test")
				continue
			held_station_offer = existing
			break
		TEST_ASSERT(held_station_offer, "a full station board had no fixture offer to hold aside")
		SScontracts.offered_contracts -= held_station_offer
		preexisting_station_offers--
		expected_published = min(4, max(0, CONTRACT_BOARD_DEPARTMENT_LIMIT - preexisting_station_offers))
	TEST_ASSERT(expected_published > 0, "the lifecycle test could not obtain a station-board fixture slot")
	var/list/test_keys = list()
	for(var/index in 1 to 4)
		var/offer_key = "dq-lifecycle-[index]"
		test_keys += offer_key
		SScontracts.queue_offer("dq_offer_lifecycle_test", null, "Focused lifecycle test", offer_key, 50)
	var/list/published = list()
	for(var/datum/contract/contract in SScontracts.offered_contracts)
		if(contract.definition_id == "dq_offer_lifecycle_test")
			published += contract
	TEST_ASSERT_EQUAL(length(published), expected_published, "station board did not enforce its published-offer limit alongside existing offers")
	TEST_ASSERT(SScontracts.find_candidate("dq-lifecycle-4"), "the overflow opportunity was not retained as a lightweight candidate")
	var/datum/contract/declined = published[1]
	var/candidates_before_decline = 0
	for(var/datum/contract_offer_candidate/candidate in SScontracts.offer_candidates)
		if(candidate.definition_id == "dq_offer_lifecycle_test")
			candidates_before_decline++
	TEST_ASSERT(declined.decline(), "one-click decline did not close an offered contract")
	TEST_ASSERT_EQUAL(declined.closure_code, CONTRACT_CLOSE_DECLINED, "decline did not record its lifecycle outcome")
	TEST_ASSERT(SScontracts.offer_cooldowns[declined.offer_key] > world.time, "declined offer did not enter cooldown")
	var/candidates_after_decline = 0
	for(var/datum/contract_offer_candidate/candidate in SScontracts.offer_candidates)
		if(candidate.definition_id == "dq_offer_lifecycle_test")
			candidates_after_decline++
	TEST_ASSERT_EQUAL(candidates_after_decline, candidates_before_decline - 1, "freeing a board slot did not publish one queued opportunity")
	var/published_after_decline = 0
	for(var/datum/contract/contract in SScontracts.offered_contracts)
		if(contract.definition_id == "dq_offer_lifecycle_test")
			published_after_decline++
	TEST_ASSERT_EQUAL(published_after_decline, expected_published, "decline did not refill the bounded offer board")

	var/datum/contract/grace_contract = new
	grace_contract.title = "Evidence grace test"
	grace_contract.deadline_grace_duration = 10 SECONDS
	grace_contract.add_requirement(new /datum/contract_requirement/event_count("dq_offer_grace_result", 1))
	TEST_ASSERT(grace_contract.accept(), "grace test contract could not be accepted")
	grace_contract.deadline = world.time
	grace_contract.check_deadline()
	TEST_ASSERT_EQUAL(grace_contract.state, CONTRACT_GRACE, "deadline did not enter the evidence grace state")
	emit_contract_event("dq_offer_grace_result", list("contract_id" = grace_contract.id), "dq-offer-grace")
	TEST_ASSERT_EQUAL(grace_contract.state, CONTRACT_COMPLETED, "evidence arriving during grace did not complete the contract")
	qdel(grace_contract)

	for(var/id in SScontracts.contracts_by_id.Copy())
		var/datum/contract/contract = SScontracts.contracts_by_id[id]
		if(contract.definition_id == "dq_offer_lifecycle_test")
			qdel(contract)
	for(var/datum/contract_offer_candidate/candidate in SScontracts.offer_candidates.Copy())
		if(candidate.definition_id == "dq_offer_lifecycle_test")
			SScontracts.withdraw_candidate(candidate, "Lifecycle test cleanup")
	if(held_station_offer)
		SScontracts.offered_contracts |= held_station_offer
	for(var/offer_key in test_keys)
		SScontracts.offer_cooldowns -= offer_key

	var/list/priority_keys = list("dq-priority-standing-1", "dq-priority-standing-2", "dq-priority-standing-3", "dq-priority-urgent")
	for(var/index in 1 to 3)
		SScontracts.queue_offer("dq_offer_lifecycle_test", list("offer_kind" = CONTRACT_OFFER_STANDING), "Priority fixture", priority_keys[index], 10)
	SScontracts.queue_offer("dq_offer_lifecycle_test", list("offer_kind" = CONTRACT_OFFER_OPPORTUNITY), "Urgent priority fixture", priority_keys[4], 1000)
	TEST_ASSERT(SScontracts.find_live_offer(priority_keys[4]), "urgent opportunity did not displace a lower-priority standing offer")
	var/standing_after_displacement = 0
	for(var/datum/contract/contract in SScontracts.offered_contracts)
		if(contract.board_key == test_board && contract.offer_kind == CONTRACT_OFFER_STANDING)
			standing_after_displacement++
	TEST_ASSERT_EQUAL(standing_after_displacement, CONTRACT_BOARD_DEPARTMENT_LIMIT - 1, "priority displacement removed the wrong number of standing offers")
	for(var/datum/contract/contract in SScontracts.offered_contracts.Copy())
		if(contract.offer_key in priority_keys)
			qdel(contract)
	for(var/key in priority_keys)
		SScontracts.offer_cooldowns -= key

/datum/unit_test/dq_contract_event_lifecycle

/datum/unit_test/dq_contract_event_lifecycle/Run()
	var/datum/contract/contract = new
	contract.title = "Infrastructure test"
	contract.description = "Exercises event-driven completion."
	contract.reward = 0
	var/datum/contract_requirement/event_count/requirement = new("dq_test_event", 3)
	requirement.name = "Test progress"
	contract.add_requirement(requirement)
	TEST_ASSERT(!contract.validate(), "valid test contract failed validation")
	TEST_ASSERT(contract.accept(), "valid contract could not be accepted")
	TEST_ASSERT(contract in SScontracts.active_contracts, "accepted contract was not indexed as active")
	emit_contract_event("dq_test_event", list("contributor_account" = 123, "detail" = "test"))
	TEST_ASSERT_EQUAL(requirement.progress, 1, "event did not advance its subscribed requirement")
	emit_contract_event("dq_unrelated_event", list("contributor_account" = 123))
	TEST_ASSERT_EQUAL(requirement.progress, 1, "unrelated event advanced contract progress")
	emit_contract_event("dq_test_event", list("contributor_account" = 123))
	emit_contract_event("dq_test_event", list("contributor_account" = 123))
	TEST_ASSERT_EQUAL(contract.state, CONTRACT_COMPLETED, "completed requirements did not close the contract")
	TEST_ASSERT(contract in SScontracts.closed_contracts, "completed contract was not indexed in history")
	qdel(contract)

/datum/unit_test/dq_contract_evidence_routing

/datum/unit_test/dq_contract_evidence_routing/Run()
	var/deduplicated_before = SScontracts.events_deduplicated
	var/datum/contract/contract = new
	contract.title = "Typed evidence routing test"
	contract.department = DEPARTMENT_MEDICAL
	contract.reward = 0
	var/datum/contract_requirement/event_count/requirement = new("dq_typed_evidence", 2, null, null, TRUE, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
	requirement.name = "Two unique certified results"
	requirement.unique_field = "subject_id"
	requirement.require_tag("certified")
	requirement.require_number("quality", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 50)
	contract.add_requirement(requirement)
	TEST_ASSERT(contract.accept(), "typed-evidence contract could not be accepted")
	emit_contract_event("dq_typed_evidence", list("contract_id" = "wrong", "subject_id" = "A", "tags" = list("certified"), "metrics" = list("quality" = 100)))
	emit_contract_event("dq_typed_evidence", list("contract_id" = contract.id, "subject_id" = "A", "metrics" = list("quality" = 100)))
	emit_contract_event("dq_typed_evidence", list("contract_id" = contract.id, "subject_id" = "A", "tags" = list("certified"), "metrics" = list("quality" = 49)))
	TEST_ASSERT_EQUAL(requirement.progress, 0, "wrong-scope, untagged, or below-threshold evidence advanced progress")
	var/list/valid_a = list("contract_id" = contract.id, "subject_id" = "A", "contributor_account" = 101, "tags" = list("certified"), "metrics" = list("quality" = 50))
	TEST_ASSERT(emit_contract_event("dq_typed_evidence", valid_a, "typed-A"), "valid typed evidence was rejected")
	TEST_ASSERT(!emit_contract_event("dq_typed_evidence", valid_a, "typed-A"), "the producer occurrence ledger accepted a duplicate delivery")
	emit_contract_event("dq_typed_evidence", valid_a, "typed-A-retry")
	TEST_ASSERT_EQUAL(requirement.progress, 1, "duplicate occurrence or duplicate subject advanced typed evidence")
	emit_contract_event("dq_typed_evidence", list("contract_id" = contract.id, "subject_id" = "B", "contributor_account" = 102, "tags" = list("certified"), "metrics" = list("quality" = 75)), "typed-B")
	TEST_ASSERT_EQUAL(contract.state, CONTRACT_COMPLETED, "second unique qualifying evidence did not complete the contract")
	TEST_ASSERT_EQUAL(SScontracts.events_deduplicated, deduplicated_before + 1, "duplicate event was not visible in evidence-bus telemetry")
	qdel(contract)

/datum/unit_test/dq_contract_sustained_evidence

/datum/unit_test/dq_contract_sustained_evidence/Run()
	var/datum/contract/contract = new
	contract.title = "Sustained evidence test"
	contract.reward = 0
	var/datum/contract_requirement/sustained_event/requirement = new("dq_machine_measurement", "machine_id", "output", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 500, 1, 1, CONTRACT_EVIDENCE_SCOPE_CONTRACT)
	requirement.name = "Sustain machine output"
	requirement.filter.require_number("integrity", CONTRACT_EVIDENCE_COMPARE_AT_LEAST, 90)
	contract.add_requirement(requirement)
	TEST_ASSERT(contract.accept(), "sustained-evidence contract could not be accepted")
	emit_contract_event("dq_machine_measurement", list("contract_id" = contract.id, "machine_id" = "reactor-A", "metrics" = list("output" = 600, "integrity" = 95)), "reactor-A-high-1")
	emit_contract_event("dq_machine_measurement", list("contract_id" = contract.id, "machine_id" = "reactor-A", "metrics" = list("output" = 600, "integrity" = 50)), "reactor-A-low-integrity")
	sleep(2)
	TEST_ASSERT_EQUAL(requirement.progress, 0, "an auxiliary-filter state change did not cancel sustained evidence")
	emit_contract_event("dq_machine_measurement", list("contract_id" = contract.id, "machine_id" = "reactor-A", "contributor_account" = 103, "metrics" = list("output" = 600, "integrity" = 95)), "reactor-A-high-2")
	sleep(2)
	TEST_ASSERT_EQUAL(contract.state, CONTRACT_COMPLETED, "continuous qualifying evidence did not complete after its duration")
	qdel(contract)

/datum/unit_test/dq_contract_internal_escrow

/datum/unit_test/dq_contract_internal_escrow/Run()
	var/currency_created_before = SSsupply.currency_created
	var/currency_destroyed_before = SSsupply.currency_destroyed
	var/datum/money_account/funder = new
	funder.owner_name = "Test issuer"
	funder.money = 500
	var/datum/contract/contract = new
	contract.title = "Escrow test"
	contract.funding_mode = CONTRACT_FUNDING_INTERNAL
	contract.funding_account = funder
	contract.reward = 200
	contract.add_requirement(new /datum/contract_requirement/event_count("dq_escrow_event", 1))
	TEST_ASSERT(contract.accept(), "funded contract could not be accepted")
	TEST_ASSERT_EQUAL(funder.money, 300, "acceptance did not place the reward in escrow")
	TEST_ASSERT_EQUAL(contract.escrow_balance, 200, "contract escrow balance was incorrect")
	funder.suspended = TRUE
	TEST_ASSERT(contract.cancel("Test cancellation"), "active contract could not be cancelled")
	TEST_ASSERT_EQUAL(funder.money, 500, "suspended issuer lost its escrow refund")
	TEST_ASSERT_EQUAL(contract.escrow_balance, 0, "refunded escrow remained available")
	funder.suspended = FALSE
	TEST_ASSERT_EQUAL(SSsupply.currency_created, currency_created_before, "internal escrow refund was counted as newly created currency")
	TEST_ASSERT_EQUAL(SSsupply.currency_destroyed, currency_destroyed_before, "internal escrow funding was counted as destroyed currency")
	qdel(contract)
	var/station_money_before = GLOB.station_account.money
	var/datum/contract/completed_contract = new
	completed_contract.title = "Escrow payout test"
	completed_contract.funding_mode = CONTRACT_FUNDING_INTERNAL
	completed_contract.funding_account = funder
	completed_contract.reward = 200
	completed_contract.add_requirement(new /datum/contract_requirement/event_count("dq_escrow_payout_event", 1))
	TEST_ASSERT(completed_contract.accept(), "funded payout contract could not be accepted")
	emit_contract_event("dq_escrow_payout_event", list("contract_id" = completed_contract.id), "dq-escrow-payout:[REF(completed_contract)]")
	TEST_ASSERT_EQUAL(completed_contract.state, CONTRACT_COMPLETED, "funded payout contract did not complete")
	TEST_ASSERT_EQUAL(GLOB.station_account.money, station_money_before + 200, "internal escrow payout did not reach its recipient")
	TEST_ASSERT_EQUAL(SSsupply.currency_created, currency_created_before, "internal escrow payout was counted as newly created currency")
	TEST_ASSERT_EQUAL(SSsupply.currency_destroyed, currency_destroyed_before, "completed internal escrow was counted as destroyed currency")
	GLOB.station_account.money = station_money_before
	qdel(completed_contract)
	var/datum/money_account/contributor = new
	contributor.owner_name = "Suspended contributor"
	contributor.account_number = 880041
	GLOB.all_money_accounts += contributor
	var/datum/contract/deferred_contract = new
	deferred_contract.title = "Deferred escrow payout test"
	deferred_contract.funding_mode = CONTRACT_FUNDING_INTERNAL
	deferred_contract.funding_account = funder
	deferred_contract.reward = 200
	deferred_contract.station_share = 0
	deferred_contract.department_share = 0
	deferred_contract.contributor_share = 1
	deferred_contract.add_requirement(new /datum/contract_requirement/event_count("dq_deferred_escrow_event", 1))
	deferred_contract.record_contribution(contributor.account_number, 1, null, contributor.owner_name)
	TEST_ASSERT(deferred_contract.accept(), "deferred payout contract could not be accepted")
	contributor.suspended = TRUE
	emit_contract_event("dq_deferred_escrow_event", list("contract_id" = deferred_contract.id), "dq-deferred-escrow:[REF(deferred_contract)]")
	TEST_ASSERT_EQUAL(deferred_contract.state, CONTRACT_ACTIVE, "contract completed despite a rejected recipient credit")
	TEST_ASSERT_EQUAL(deferred_contract.escrow_balance, 200, "deferred payout discarded its escrow")
	TEST_ASSERT_EQUAL(contributor.money, 0, "suspended contributor was recorded as paid")
	contributor.suspended = FALSE
	TEST_ASSERT(deferred_contract.reconcile_completion(), "deferred payout did not retry after its recipient became available")
	TEST_ASSERT_EQUAL(deferred_contract.state, CONTRACT_COMPLETED, "retried payout did not complete the contract")
	TEST_ASSERT_EQUAL(contributor.money, 200, "retried payout did not reach the contributor")
	TEST_ASSERT_EQUAL(deferred_contract.escrow_balance, 0, "successful retried payout retained escrow")
	GLOB.all_money_accounts -= contributor
	qdel(deferred_contract)
	qdel(contributor)
	qdel(funder)

/datum/unit_test/dq_contract_identity_and_evidence

/datum/unit_test/dq_contract_identity_and_evidence/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/mob/living/carbon/human/unclaimed = new(test_turf)
	var/datum/contract_subject_identity/body_identity = SScontracts.subject_identity(unclaimed)
	var/body_key = "body:[REF(unclaimed)]"
	var/datum/mind/claiming_mind = new("contract_identity_claim_test")
	claiming_mind.transfer_to(unclaimed)
	var/datum/contract_subject_identity/claimed_identity = SScontracts.subject_identity(unclaimed)
	TEST_ASSERT_EQUAL(claimed_identity.id, body_identity.id, "assigning a mind minted a second identity for an already documented body")
	TEST_ASSERT(!SScontracts.subject_identities[body_key], "the obsolete body-key identity alias remained after mind assignment")
	var/mob/living/carbon/human/original = new(test_turf)
	var/mob/living/carbon/human/replacement = new(test_turf)
	var/datum/mind/mind = new("contract_identity_test")
	mind.transfer_to(original)
	var/datum/contract_subject_identity/first_identity = SScontracts.subject_identity(original)
	mind.transfer_to(replacement)
	var/datum/contract_subject_identity/second_identity = SScontracts.subject_identity(replacement)
	TEST_ASSERT_EQUAL(first_identity.id, second_identity.id, "contract subject identity did not follow a mind into a replacement body")
	TEST_ASSERT_EQUAL(first_identity.current_mob(), replacement, "stable subject identity did not resolve the mind's current body")
	var/first_evidence = SScontracts.register_evidence(CONTRACT_EVIDENCE_MEDICAL_SCAN, first_identity.id, null, null, list())
	var/second_evidence = SScontracts.register_evidence(CONTRACT_EVIDENCE_DOCUMENT, first_identity.id, null, null, list())
	TEST_ASSERT(SScontracts.consume_evidence(list(first_evidence), "DQ-TEST-A"), "fresh generic evidence could not be consumed")
	TEST_ASSERT(!SScontracts.consume_evidence(list(first_evidence), "DQ-TEST-B"), "one evidence record was accepted by two contracts")
	TEST_ASSERT(!SScontracts.consume_evidence(list(first_evidence, second_evidence), "DQ-TEST-C"), "atomic evidence consumption accepted a partly consumed set")
	TEST_ASSERT(SScontracts.evidence_available(list(second_evidence)), "failed atomic consumption incorrectly consumed the remaining evidence")
	var/obj/item/paper/scan = new(test_turf)
	var/list/authentic_payload = list("subject_id" = first_identity.id, "scan_time" = 10)
	var/scan_evidence_id = SScontracts.register_evidence(CONTRACT_EVIDENCE_MEDICAL_SCAN, first_identity.id, null, scan, authentic_payload)
	scan.medical_scan_evidence = list("evidence_id" = scan_evidence_id, "subject_id" = "forged", "scan_time" = 999)
	var/list/authenticated_payload = SScontracts.authenticated_scan_payload(scan)
	TEST_ASSERT_EQUAL(authenticated_payload["subject_id"], first_identity.id, "mutable paper metadata overrode the immutable evidence ledger")
	TEST_ASSERT_EQUAL(authenticated_payload["scan_time"], 10, "forged scan time overrode the immutable evidence ledger")
	qdel(scan)
	var/retained_evidence = SScontracts.register_evidence(CONTRACT_EVIDENCE_MEDICAL_SCAN, first_identity.id, null, null, list("scan_time" = 20))
	var/obj/item/paper/first_copy = new(test_turf)
	var/obj/item/paper/second_copy = new(test_turf)
	first_copy.attach_contract_evidence(retained_evidence)
	second_copy.attach_contract_evidence(retained_evidence)
	qdel(first_copy)
	TEST_ASSERT(SScontracts.evidence_by_id[retained_evidence], "deleting one physical copy discarded evidence still carried by another")
	qdel(second_copy)
	TEST_ASSERT(!SScontracts.evidence_by_id[retained_evidence], "orphaned unsubmitted evidence was not pruned when its final paper was destroyed")
	SScontracts.prune_contract_evidence("DQ-TEST-A")
	TEST_ASSERT(!SScontracts.evidence_by_id[first_evidence], "consumed evidence was not pruned after its contract retention window")
	qdel(original)
	qdel(replacement)
	qdel(mind)
	qdel(unclaimed)
	qdel(claiming_mind)

/datum/unit_test/dq_contract_economy_result

/datum/unit_test/dq_contract_economy_result/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/contributor_account = new
	contributor_account.account_number = 876543
	contributor_account.owner_name = "Contract Contributor"
	contributor_account.money = 50
	GLOB.all_money_accounts += contributor_account
	var/mob/living/carbon/human/contributor = new(test_turf)
	var/datum/mind/contributor_mind = new("contract_economy_test")
	contributor_mind.initial_account = contributor_account
	contributor_mind.transfer_to(contributor)
	GLOB.player_list |= contributor
	var/datum/money_account/medical_account = GLOB.department_accounts[DEPARTMENT_MEDICAL]
	var/station_before = GLOB.station_account.money
	var/medical_before = medical_account.money
	var/personal_before = contributor_account.money
	var/station_rep_before = get_station_faction_reputation(REPUTATION_FACTION_VEYMED)
	var/department_rep_before = get_department_faction_reputation(DEPARTMENT_MEDICAL, REPUTATION_FACTION_VEYMED)
	var/personal_rep_before = contributor.get_faction_reputation(REPUTATION_FACTION_VEYMED)
	var/datum/contract/contract = new
	contract.title = "Economy result test"
	contract.department = DEPARTMENT_MEDICAL
	contract.issuer_name = "VeyMed Test Accounting"
	contract.issuer_faction = REPUTATION_FACTION_VEYMED
	contract.reward = 1000
	contract.station_share = 0.2
	contract.department_share = 0.6
	contract.contributor_share = 0.2
	contract.station_reputation_reward = 3
	contract.department_reputation_reward = 4
	contract.personal_reputation_reward = 5
	var/datum/contract_negotiation_clause/economy_clause = new("distribution", "Distribution", "Economy integration terms")
	economy_clause.add_option(make_contract_clause_option("adjusted", "Adjusted", "Exercise all negotiated payout destinations", 50, -50, 100, 2, -1, 3), TRUE)
	contract.add_negotiation_clause(economy_clause)
	contract.add_requirement(new /datum/contract_requirement/event_count("dq_economy_result", 1))
	contract.record_contribution(contributor_account.account_number, 1, "Completed the test workflow")
	TEST_ASSERT(contract.accept(), "economy-result contract could not be accepted")
	emit_contract_event("dq_economy_result", list())
	TEST_ASSERT_EQUAL(contract.state, CONTRACT_COMPLETED, "economy-result contract did not complete")
	TEST_ASSERT_EQUAL(GLOB.station_account.money - station_before, 250, "negotiated station contract payout was incorrect")
	TEST_ASSERT_EQUAL(medical_account.money - medical_before, 550, "negotiated Medical contract payout was incorrect")
	TEST_ASSERT_EQUAL(contributor_account.money - personal_before, 300, "negotiated contributor contract payout was incorrect")
	TEST_ASSERT_EQUAL(get_station_faction_reputation(REPUTATION_FACTION_VEYMED) - station_rep_before, 7, "negotiated station reputation reward was incorrect")
	TEST_ASSERT_EQUAL(get_department_faction_reputation(DEPARTMENT_MEDICAL, REPUTATION_FACTION_VEYMED) - department_rep_before, 2, "negotiated department reputation reward was incorrect")
	TEST_ASSERT_EQUAL(contributor.get_faction_reputation(REPUTATION_FACTION_VEYMED) - personal_rep_before, 11, "negotiated personal reputation reward was incorrect")
	GLOB.station_account.money = station_before
	medical_account.money = medical_before
	contributor_account.money = personal_before
	GLOB.station_faction_relations.set_reputation(REPUTATION_FACTION_VEYMED, station_rep_before)
	var/datum/faction_reputation_ledger/medical_reputation = GLOB.station_faction_relations.get_department_ledger(DEPARTMENT_MEDICAL)
	medical_reputation.set_reputation(REPUTATION_FACTION_VEYMED, department_rep_before)
	contributor.ensure_faction_reputation().set_reputation(REPUTATION_FACTION_VEYMED, personal_rep_before)
	GLOB.player_list -= contributor
	GLOB.all_money_accounts -= contributor_account
	qdel(contract)
	qdel(contributor)
	qdel(contributor_mind)
	qdel(contributor_account)

/datum/unit_test/dq_contract_negotiation

/datum/unit_test/dq_contract_negotiation/Run()
	var/datum/contract/contract = new
	contract.title = "Negotiated infrastructure test"
	contract.department = DEPARTMENT_MEDICAL
	contract.reward = 1000
	contract.station_share = 0.2
	contract.department_share = 0.6
	contract.contributor_share = 0.2
	contract.station_reputation_reward = 2
	contract.department_reputation_reward = 3
	contract.personal_reputation_reward = 4
	contract.deadline_duration = 30 MINUTES
	contract.add_requirement(new /datum/contract_requirement/event_count("dq_negotiation_result", 1))
	var/datum/contract_negotiation_clause/clause = new("publication", "Publication", "Test clause")
	clause.add_option(make_contract_clause_option("standard", "Standard", "Base terms"), TRUE)
	clause.add_option(make_contract_clause_option("premium", "Premium", "Adjusted terms", 100, 50, 25, 2, -1, 3, -5 MINUTES))
	TEST_ASSERT(contract.add_negotiation_clause(clause), "generic negotiation clause could not be added")
	contract.finalize_offer(5 MINUTES)
	TEST_ASSERT(!contract.select_negotiation_option("publication", "missing", "Test Head"), "unknown clause option was accepted")
	TEST_ASSERT(contract.select_negotiation_option("publication", "premium", "Test Head"), "valid negotiated option was rejected")
	TEST_ASSERT_EQUAL(contract.reward, 1175, "negotiation did not update the total monetary reward")
	TEST_ASSERT_EQUAL(contract.negotiated_station_amount(), 300, "negotiation station reward was incorrect")
	TEST_ASSERT_EQUAL(contract.negotiated_department_amount(), 650, "negotiation department reward was incorrect")
	TEST_ASSERT_EQUAL(contract.negotiated_staff_amount(), 225, "negotiation staff reward was incorrect")
	TEST_ASSERT_EQUAL(contract.station_reputation_reward, 4, "negotiation station reputation was incorrect")
	TEST_ASSERT_EQUAL(contract.department_reputation_reward, 2, "negotiation department reputation was incorrect")
	TEST_ASSERT_EQUAL(contract.personal_reputation_reward, 7, "negotiation staff reputation was incorrect")
	TEST_ASSERT_EQUAL(contract.deadline_duration, 25 MINUTES, "negotiation deadline adjustment was incorrect")
	TEST_ASSERT(contract.accept(), "negotiated contract could not be accepted")
	TEST_ASSERT(contract.negotiation_locked, "accepted negotiation was not locked")
	TEST_ASSERT(!contract.select_negotiation_option("publication", "standard", "Test Head"), "accepted contract terms could still be changed")
	qdel(contract)

/datum/unit_test/dq_contract_definition_catalog

/datum/unit_test/dq_contract_definition_catalog/Run()
	TEST_ASSERT(SScontracts.definitions["experimental_medication_study"], "experimental medication definition was not registered")
	TEST_ASSERT(SScontracts.definitions["medical_trial_coverup"], "VeyMed cover-up definition was not registered")
	TEST_ASSERT(SScontracts.definitions["medical_trial_advocate"], "patient-advocate definition was not registered")
	TEST_ASSERT(SScontracts.definitions["medical_trial_espionage"], "industrial-espionage definition was not registered")
	TEST_ASSERT(SScontracts.definitions["medical_trial_autopsy"], "corpse-autopsy definition was not registered")
	TEST_ASSERT(SScontracts.definitions["medical_rare_case_report"], "rare-case report definition was not registered")
	var/datum/contract_definition/trial_terms_definition = SScontracts.definitions["experimental_medication_study"]
	var/datum/contract/medical_trial/negotiable_trial = trial_terms_definition.create_contract()
	TEST_ASSERT_EQUAL(length(negotiable_trial.negotiation_clauses), 6, "medical trial did not expose its full generic negotiation set")
	TEST_ASSERT(!negotiable_trial.validate(), "default medical negotiation terms were invalid")
	qdel(negotiable_trial)
	var/datum/contract_definition/social_definition = SScontracts.definitions["occupational_recovery_program"]
	var/datum/contract/social/social_offer = social_definition.create_contract()
	TEST_ASSERT(social_offer.negotiation_clauses["objective_focus"], "multi-objective social contract lacked an operational-emphasis clause")
	TEST_ASSERT(social_offer.select_negotiation_option("objective_focus", "primary", "Unit test"), "social objective emphasis could not be negotiated")
	var/list/negotiated_floors = social_offer.negotiated_effect("requirement_floors")
	var/datum/contract_requirement/primary_requirement = social_offer.requirements[1]
	var/datum/contract_requirement/supporting_requirement = social_offer.requirements[2]
	TEST_ASSERT_EQUAL(negotiated_floors[primary_requirement.name], 1, "primary emphasis weakened the named primary objective")
	TEST_ASSERT_EQUAL(negotiated_floors[supporting_requirement.name], 0.65, "primary emphasis did not relax a supporting objective")
	TEST_ASSERT(social_offer.select_negotiation_option("schedule", "accelerated", "Unit test"), "expedited social warranty could not be negotiated")
	TEST_ASSERT_EQUAL(social_offer.minimum_grade_ratio, 0.65, "expedited warranty did not strengthen the minimum outcome")
	qdel(social_offer)
	var/datum/contract_definition/fuel_definition = SScontracts.definitions["alternative_fuel_demonstration"]
	var/datum/contract/social/alternative_fuel_trial/fuel_offer = fuel_definition.create_contract()
	TEST_ASSERT(fuel_offer.negotiation_clauses["fuel_protocol"], "alternative-fuel contract lacked its certification protocol")
	TEST_ASSERT(fuel_offer.select_negotiation_option("fuel_protocol", "phoron_free", "Unit test"), "phoron-free certification could not be negotiated")
	TEST_ASSERT_EQUAL(fuel_offer.output_requirement.target, 3, "alternative-fuel protocol did not expose three output stages")
	TEST_ASSERT(findtext(fuel_offer.output_requirement.description, "0.1% phoron"), "phoron-free negotiation did not update its visible chamber restriction")
	qdel(fuel_offer)
	var/found_offer = FALSE
	for(var/datum/contract/medical_trial/trial in SScontracts.offered_contracts)
		found_offer = TRUE
		TEST_ASSERT(!trial.validate(), "generated medication study offer was invalid")
		TEST_ASSERT(trial.profile.cohort in list(MEDICAL_TRIAL_COHORT_HEALTHY, MEDICAL_TRIAL_COHORT_PREVENTATIVE), "normal medication offer unexpectedly required a pre-existing condition")
		break
	TEST_ASSERT(found_offer || SScontracts.find_candidate("experimental_medication_study:initial:1"), "round initialization did not place a medication study in the rotating catalog")
	var/datum/contract/medical_trial/original_routine
	for(var/datum/contract/medical_trial/trial in SScontracts.offered_contracts)
		if(!trial.conditional_offer)
			original_routine = trial
			break
	if(!original_routine)
		original_routine = trial_terms_definition.create_contract(list("offer_key" = "dq-medical-rotation-test", "board_key" = "[CONTRACT_SCOPE_DEPARTMENT]:[DEPARTMENT_MEDICAL]", "offer_kind" = CONTRACT_OFFER_STANDING))
	TEST_ASSERT(original_routine?.offer_timer, "routine medical offer had no expiry timer")
	original_routine.cancel("Lifecycle test")
	TEST_ASSERT(SScontracts.find_candidate(original_routine.offer_key), "closing a standing medical offer did not queue its cooldown-safe replacement")
	TEST_ASSERT(SScontracts.offer_cooldowns[original_routine.offer_key] > world.time, "closing a standing offer did not enforce its publication cooldown")

/datum/unit_test/dq_medical_trial_outcome_workflow

/datum/unit_test/dq_medical_trial_outcome_workflow/Run()
	var/datum/contract/medical_trial/trial = new
	trial.department = DEPARTMENT_MEDICAL
	trial.station_share = 1
	trial.department_share = 0
	trial.contributor_share = 0
	trial.initialize_trial()
	trial.profile.cohort = "affected-patient therapeutic"
	trial.profile.target_metric = "respiratory"
	trial.profile.adverse_metric = "heart damage"
	trial.profile.therapeutic_strength = 1
	trial.profile.adverse_strength = 1
	TEST_ASSERT(trial.accept(), "medical study could not be accepted")
	for(var/index in 1 to 3)
		var/mob/living/carbon/human/subject = new(run_loc_floor_bottom_left)
		subject.real_name = "Trial Subject [index]"
		var/obj/item/organ/host = subject.internal_organs_by_name[O_LUNGS]
		var/datum/medical_issue/condition/pulmonary_contusion/condition = new
		condition.owner = subject
		condition.affectedorgan = host
		condition.set_severity(30)
		host.add_medical_issue(condition, subject)
		TEST_ASSERT(trial.enroll(subject), "qualifying consenting subject could not be enrolled")
		var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
		var/list/baseline_evidence = list("subject_ref" = identity.id, "subject_id" = identity.id, "scan_time" = world.time, "snapshot" = medical_trial_snapshot(subject))
		var/datum/reagent/medicine/experimental_contract/test_drug = new
		test_drug.data = list("contract_id" = trial.id)
		test_drug.affect_blood(subject, null, 5)
		TEST_ASSERT(subject.medical_trial_marker_snapshot()[trial.id] > 0, "real trial medication did not leave its scanner-visible coded metabolite")
		qdel(test_drug)
		TEST_ASSERT(condition.severity < 30, "trial medication did not reduce authoritative respiratory-condition severity")
		var/obj/item/organ/heart = subject.internal_organs_by_name[O_HEART]
		var/found_adverse_condition = FALSE
		for(var/datum/medical_issue/condition/heart_damage/reaction in heart.medical_issues)
			found_adverse_condition = reaction.severity > 0 && length(reaction.active_symptoms)
		TEST_ASSERT(found_adverse_condition, "trial medication did not create a symptomatic vanilla organ-owned adverse condition")
		var/datum/medical_trial_participant/participant = trial.participants[identity.id]
		participant.exposure_time = world.time - 1 MINUTE
		baseline_evidence["scan_time"] = participant.exposure_time
		var/list/trial_markers = list()
		trial_markers[trial.id] = MEDICAL_TRIAL_MINIMUM_DOSE
		var/list/followup_evidence = list("subject_ref" = identity.id, "subject_id" = identity.id, "scan_time" = world.time, "snapshot" = medical_trial_snapshot(subject), "trial_markers" = trial_markers)
		TEST_ASSERT(trial.submit_subject_evidence(identity.id, baseline_evidence, followup_evidence, null), "scanner evidence submission was rejected")
		qdel(subject)
	TEST_ASSERT_EQUAL(trial.observation_requirement.progress, 3, "valid observations did not satisfy the study cohort")
	TEST_ASSERT(trial.submit_analysis(trial.profile.target_metric, trial.profile.adverse_metric, null), "correct clinical interpretation was rejected")
	TEST_ASSERT_EQUAL(trial.state, CONTRACT_COMPLETED, "completed medical study did not close")
	qdel(trial)

/datum/unit_test/dq_medical_trial_custody_chain

/datum/unit_test/dq_medical_trial_custody_chain/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/contract/medical_trial/first_trial = new
	first_trial.department = DEPARTMENT_MEDICAL
	first_trial.station_share = 1
	first_trial.department_share = 0
	first_trial.contributor_share = 0
	first_trial.initialize_trial()
	first_trial.profile.cohort = MEDICAL_TRIAL_COHORT_HEALTHY
	first_trial.profile.adverse_metric = "none"
	first_trial.profile.therapeutic_strength = 0
	var/datum/contract/medical_trial/second_trial = new
	second_trial.department = DEPARTMENT_MEDICAL
	second_trial.station_share = 1
	second_trial.department_share = 0
	second_trial.contributor_share = 0
	second_trial.initialize_trial()
	second_trial.profile.cohort = MEDICAL_TRIAL_COHORT_HEALTHY
	second_trial.profile.adverse_metric = "none"
	second_trial.profile.therapeutic_strength = 0
	TEST_ASSERT(first_trial.accept() && second_trial.accept(), "custody-chain trials could not be activated")
	var/mob/living/carbon/human/subject = new(test_turf)
	TEST_ASSERT(first_trial.enroll(subject) && second_trial.enroll(subject), "custody-chain subject could not be enrolled")
	var/obj/item/reagent_containers/glass/beaker/first_source = new(test_turf)
	var/obj/item/reagent_containers/glass/beaker/second_source = new(test_turf)
	var/obj/item/reagent_containers/glass/beaker/mixed = new(test_turf)
	var/obj/item/reagent_containers/syringe/injector = new(test_turf)
	first_source.reagents.add_reagent(MEDICAL_TRIAL_REAGENT_ID, 5, medical_trial_contract_data(first_trial.id))
	second_source.reagents.add_reagent(MEDICAL_TRIAL_REAGENT_ID, 5, medical_trial_contract_data(second_trial.id))
	first_source.reagents.trans_to_holder(mixed.reagents, 5)
	second_source.reagents.trans_to_holder(mixed.reagents, 5)
	TEST_ASSERT_EQUAL(medical_trial_reagent_amount(mixed.reagents, MEDICAL_TRIAL_REAGENT_ID, first_trial.id), 5, "mixing lost the first trial's proportional provenance")
	TEST_ASSERT_EQUAL(medical_trial_reagent_amount(mixed.reagents, MEDICAL_TRIAL_REAGENT_ID, second_trial.id), 5, "mixing lost the second trial's proportional provenance")
	mixed.reagents.trans_to_holder(injector.reagents, 4)
	TEST_ASSERT_EQUAL(medical_trial_reagent_amount(injector.reagents, MEDICAL_TRIAL_REAGENT_ID, first_trial.id), 2, "syringe transfer distorted first-trial provenance")
	TEST_ASSERT_EQUAL(medical_trial_reagent_amount(injector.reagents, MEDICAL_TRIAL_REAGENT_ID, second_trial.id), 2, "syringe transfer distorted second-trial provenance")
	injector.reagents.trans_to_mob(subject, 4, CHEM_BLOOD)
	var/datum/reagent/injected = subject.bloodstr.get_reagent(MEDICAL_TRIAL_REAGENT_ID)
	injected.affect_blood(subject, null, 4)
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/medical_trial_participant/first_participant = first_trial.participants[identity.id]
	var/datum/medical_trial_participant/second_participant = second_trial.participants[identity.id]
	TEST_ASSERT_EQUAL(first_participant.dose, 2, "mixed injection credited the wrong first-trial dose")
	TEST_ASSERT_EQUAL(second_participant.dose, 2, "mixed injection credited the wrong second-trial dose")
	var/list/markers = subject.medical_trial_marker_snapshot()
	TEST_ASSERT(markers[first_trial.id] > 0 && markers[second_trial.id] > 0, "mixed injection did not preserve both scanner-visible tracers")
	var/obj/item/reagent_containers/glass/beaker/dialysis_collection = new(test_turf)
	subject.bloodstr.trans_to_holder(dialysis_collection.reagents, 2)
	TEST_ASSERT(medical_trial_reagent_amount(dialysis_collection.reagents, MEDICAL_TRIAL_REAGENT_ID, first_trial.id) > 0, "blood extraction discarded first-trial provenance")
	TEST_ASSERT(medical_trial_reagent_amount(dialysis_collection.reagents, MEDICAL_TRIAL_REAGENT_ID, second_trial.id) > 0, "blood extraction discarded second-trial provenance")
	var/mob/living/carbon/human/oral_subject = new(test_turf)
	TEST_ASSERT(first_trial.enroll(oral_subject), "oral custody-chain subject could not be enrolled")
	var/obj/item/reagent_containers/glass/beaker/oral_source = new(test_turf)
	oral_source.reagents.add_reagent(MEDICAL_TRIAL_REAGENT_ID, 3, medical_trial_contract_data(first_trial.id))
	oral_source.reagents.trans_to_mob(oral_subject, 3, CHEM_INGEST)
	var/datum/reagent/oral_dose = oral_subject.ingested.get_reagent(MEDICAL_TRIAL_REAGENT_ID)
	oral_dose.affect_ingest(oral_subject, null, 3)
	TEST_ASSERT_EQUAL(medical_trial_reagent_amount(oral_subject.bloodstr, MEDICAL_TRIAL_REAGENT_ID, first_trial.id), 3, "ingestion discarded trial provenance before bloodstream absorption")
	var/datum/reagent/absorbed_dose = oral_subject.bloodstr.get_reagent(MEDICAL_TRIAL_REAGENT_ID)
	absorbed_dose.affect_blood(oral_subject, null, 3)
	var/datum/contract_subject_identity/oral_identity = SScontracts.subject_identity(oral_subject)
	var/datum/medical_trial_participant/oral_participant = first_trial.participants[oral_identity.id]
	TEST_ASSERT_EQUAL(oral_participant.dose, 3, "ingested medication did not credit its originating trial")
	qdel(first_source)
	qdel(second_source)
	qdel(mixed)
	qdel(injector)
	qdel(dialysis_collection)
	qdel(oral_source)
	qdel(subject)
	qdel(oral_subject)
	qdel(first_trial)
	qdel(second_trial)

/datum/unit_test/dq_medical_trial_cohort_protocols

/datum/unit_test/dq_medical_trial_cohort_protocols/Run()
	var/mob/living/carbon/human/healthy = new(run_loc_floor_bottom_left)
	var/mob/living/carbon/human/healthy_two = new(run_loc_floor_bottom_left)
	var/mob/living/carbon/human/affected = new(run_loc_floor_bottom_left)
	var/obj/item/organ/lungs = affected.internal_organs_by_name[O_LUNGS]
	var/datum/medical_issue/condition/pulmonary_contusion/illness = new
	illness.owner = affected
	illness.affectedorgan = lungs
	illness.set_severity(30)
	lungs.add_medical_issue(illness, affected)
	var/list/available_indications = medical_trial_qualifying_indications(list(healthy, affected), FALSE)
	TEST_ASSERT("respiratory" in available_indications, "an actually present qualifying respiratory condition did not enable its indication")
	TEST_ASSERT(!("neurological" in available_indications), "an absent neurological condition incorrectly enabled a conditional offer")
	TEST_ASSERT("respiratory" in affected.contract_medical_indications, "add_medical_issue did not publish eligibility through its mutation signal")
	illness.set_severity(10)
	TEST_ASSERT(!("respiratory" in affected.contract_medical_indications), "central severity mutation did not withdraw cohort eligibility below threshold")
	illness.set_severity(30)
	TEST_ASSERT("respiratory" in affected.contract_medical_indications, "central severity mutation did not republish cohort eligibility above threshold")
	var/list/one_case_availability = list(
		"indication_counts" = list("respiratory" = 1),
		"healthy_count" = 2,
	)
	TEST_ASSERT(!medical_trial_protocol_is_viable(MEDICAL_TRIAL_COHORT_THERAPEUTIC, "respiratory", one_case_availability), "one affected crewmember incorrectly made a three-patient therapeutic cohort viable")
	TEST_ASSERT(medical_trial_protocol_is_viable(MEDICAL_TRIAL_COHORT_MIXED, "respiratory", one_case_availability), "one affected crewmember plus two controls did not make a mixed cohort viable")
	var/list/three_case_availability = list(
		"indication_counts" = list("respiratory" = 3),
		"healthy_count" = 0,
	)
	TEST_ASSERT(medical_trial_protocol_is_viable(MEDICAL_TRIAL_COHORT_THERAPEUTIC, "respiratory", three_case_availability), "three affected crewmembers did not make a therapeutic cohort viable")
	SScontracts.reconcile_medical_trial_offers(one_case_availability)
	var/datum/contract/medical_trial/conditional_offer
	for(var/datum/contract/medical_trial/candidate in SScontracts.offered_contracts)
		if(candidate.profile.cohort in list(MEDICAL_TRIAL_COHORT_THERAPEUTIC, MEDICAL_TRIAL_COHORT_MIXED))
			conditional_offer = candidate
			break
	TEST_ASSERT(conditional_offer && conditional_offer.profile.target_metric == "respiratory" && conditional_offer.profile.cohort == MEDICAL_TRIAL_COHORT_MIXED, "availability counts did not create the only fulfillable mixed protocol")
	SScontracts.reconcile_medical_trial_offers(list("indication_counts" = list(), "healthy_count" = 2))
	TEST_ASSERT(!(conditional_offer in SScontracts.offered_contracts), "conditional offer was not withdrawn when its qualifying condition disappeared")
	var/datum/contract_definition/trial_definition = SScontracts.definitions["experimental_medication_study"]
	var/datum/contract/medical_trial/accepted_conditional = trial_definition.create_contract(list(
		"cohort" = MEDICAL_TRIAL_COHORT_MIXED,
		"target_metric" = "respiratory",
		"conditional_offer" = TRUE,
		"eligibility_confirmed" = TRUE,
		"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
	))
	TEST_ASSERT(accepted_conditional.accept(), "fulfillable conditional offer could not be accepted")
	SScontracts.reconcile_medical_trial_offers(list("indication_counts" = list(), "healthy_count" = 2))
	TEST_ASSERT_EQUAL(accepted_conditional.state, CONTRACT_CANCELLED, "unenrolled conditional study was not cancelled without penalty after its cohort disappeared")

	var/datum/contract/medical_trial/safety = new
	safety.initialize_trial()
	safety.profile.cohort = "healthy-volunteer safety"
	TEST_ASSERT(safety.accept(), "healthy-volunteer study could not be accepted")
	TEST_ASSERT(safety.enroll(healthy), "healthy volunteer was rejected from a safety cohort")
	TEST_ASSERT(!safety.enroll(affected), "affected patient was accepted into a healthy-only cohort")
	var/datum/contract/medical_trial/wrong_indication = new
	wrong_indication.initialize_trial()
	wrong_indication.profile.cohort = "affected-patient therapeutic"
	wrong_indication.profile.target_metric = "neurological"
	TEST_ASSERT(wrong_indication.accept(), "target-specific therapeutic study could not be accepted")
	TEST_ASSERT(!wrong_indication.enroll(affected), "a respiratory patient was accepted into an unrelated neurological therapeutic cohort")

	var/datum/contract/medical_trial/mixed = new
	mixed.initialize_trial()
	mixed.profile.cohort = "mixed controlled"
	mixed.profile.target_metric = "respiratory"
	TEST_ASSERT(mixed.accept(), "mixed study could not be accepted")
	TEST_ASSERT(mixed.enroll(healthy), "healthy control was rejected from mixed cohort")
	TEST_ASSERT(mixed.enroll(affected), "affected patient was rejected from mixed cohort")

	var/datum/contract/medical_trial/preventative = new
	preventative.initialize_trial()
	preventative.profile.cohort = "preventative challenge"
	preventative.profile.target_metric = "respiratory"
	TEST_ASSERT(preventative.accept(), "preventative study could not be accepted")
	var/mob/living/carbon/human/preventative_subject = new(run_loc_floor_bottom_left)
	TEST_ASSERT(preventative.enroll(preventative_subject), "healthy volunteer was rejected from preventative cohort")
	preventative.record_exposure(preventative_subject, 5)
	TEST_ASSERT(preventative.record_challenge(preventative_subject, 5), "controlled challenge was rejected after prophylaxis")
	preventative.apply_controlled_challenge(preventative_subject, 5)
	var/found_challenge = FALSE
	var/obj/item/organ/preventative_lungs = preventative_subject.internal_organs_by_name[O_LUNGS]
	for(var/datum/medical_issue/condition/pulmonary_contusion/challenge in preventative_lungs.medical_issues)
		found_challenge = challenge.severity > 0
	TEST_ASSERT(found_challenge, "preventative protocol did not produce an authoritative controlled condition")

	qdel(safety)
	qdel(wrong_indication)
	qdel(mixed)
	qdel(preventative)
	lungs.remove_medical_issue(illness)
	qdel(illness)
	TEST_ASSERT(!("respiratory" in affected.contract_medical_indications), "remove_medical_issue did not withdraw eligibility through its mutation signal")
	qdel(healthy)
	qdel(healthy_two)
	qdel(affected)
	qdel(preventative_subject)

/datum/unit_test/dq_medical_trial_deferred_availability

/datum/unit_test/dq_medical_trial_deferred_availability/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/list/subjects = list()
	var/list/minds = list()
	for(var/index in 1 to 3)
		var/mob/living/carbon/human/subject = new(test_turf)
		var/datum/mind/mind = new("contract_availability_[index]")
		mind.assigned_role = JOB_MEDICAL_DOCTOR
		mind.transfer_to(subject)
		var/obj/item/organ/lungs = subject.internal_organs_by_name[O_LUNGS]
		var/datum/medical_issue/condition/pulmonary_contusion/condition = new
		condition.set_severity(30)
		lungs.add_medical_issue(condition, subject)
		SScontracts.watch_contract_subject(subject)
		GLOB.player_list |= subject
		subjects += subject
		minds += mind
	var/datum/contract_definition/definition = SScontracts.definitions["experimental_medication_study"]
	var/datum/contract/medical_trial/conditional = definition.create_contract(list(
		"cohort" = MEDICAL_TRIAL_COHORT_THERAPEUTIC,
		"target_metric" = "respiratory",
		"conditional_offer" = TRUE,
		"eligibility_confirmed" = TRUE,
		"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
	))
	TEST_ASSERT(conditional in SScontracts.offered_contracts, "three-person therapeutic offer was not published")
	var/mob/living/carbon/human/departing = subjects[1]
	SEND_SIGNAL(departing, COMSIG_MOB_LOGOUT)
	GLOB.player_list -= departing
	sleep(1)
	TEST_ASSERT(QDELETED(conditional) || !(conditional in SScontracts.offered_contracts), "next-tick logout reconciliation retained an offer after the cohort left the player list")
	for(var/mob/living/carbon/human/subject in subjects)
		GLOB.player_list -= subject
		qdel(subject)
	for(var/datum/mind/mind in minds)
		qdel(mind)

/datum/unit_test/dq_medical_trial_side_contracts

/datum/unit_test/dq_medical_trial_side_contracts/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/owner = new
	owner.account_number = 987654
	GLOB.all_money_accounts += owner
	var/datum/contract/medical_trial/trial = new
	trial.department = DEPARTMENT_MEDICAL
	trial.station_share = 1
	trial.department_share = 0
	trial.contributor_share = 0
	trial.initialize_trial()
	trial.profile.cohort = "healthy-volunteer safety"
	TEST_ASSERT(trial.accept(), "fax-path test study could not be accepted")
	var/mob/living/carbon/human/subject = new(run_loc_floor_bottom_left)
	subject.real_name = "Test Subject"
	var/obj/item/paper/consent = create_contract_document(run_loc_floor_bottom_left, "test consent", "<b>Subject signature:</b> <span class=\"paper_field\"></span>", trial.id, CONTRACT_DOCUMENT_CLINICAL_CASE, CONTRACT_FAX_VEYMED, list("issuer_account" = owner.account_number))
	var/datum/component/contract_document/consent_component = consent.GetComponent(/datum/component/contract_document)
	consent.on_field_written(subject, 1, null)
	TEST_ASSERT(consent_component.payload["subject_ref"], "writing in the ordinary paper signature field did not register the signature")
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/medical_trial_participant/participant = trial.participants[identity.id]
	TEST_ASSERT_EQUAL(participant.consent_record, consent, "signed clinical record was not retained as the authoritative consent paper")
	TEST_ASSERT(trial.reissue_clinical_packet(test_turf, identity.id, owner.account_number), "lost clinical consent had no certified replacement path")
	var/consent_time = consent_component.payload["signature_time"]
	var/obj/item/paper/baseline_scan = new(run_loc_floor_bottom_left)
	baseline_scan.name = "Body Scan - Test Subject (baseline)"
	dq_contract_test_scan(baseline_scan, subject, consent_time, null)
	var/list/context = list(
		"owner_account" = owner.account_number,
		"trial_id" = trial.id,
		"target_ref" = identity.id,
		"target_name" = "Test Subject",
	)
	var/datum/contract_definition/advocate_definition = SScontracts.definitions["medical_trial_advocate"]
	var/datum/contract_definition/coverup_definition = SScontracts.definitions["medical_trial_coverup"]
	var/datum/contract/medical_trial_personal/advocate = advocate_definition.create_contract(context)
	var/datum/contract/medical_trial_personal/coverup = coverup_definition.create_contract(context)
	TEST_ASSERT(!advocate.validate() && !coverup.validate(), "linked personal contracts were invalid")
	TEST_ASSERT(advocate.accept(owner), "patient-advocate contract could not be accepted by its owner")
	TEST_ASSERT(coverup.accept(owner), "cover-up contract could not be accepted by its owner")
	TEST_ASSERT(process_contract_fax(participant.consent_record, "Worker's Union Advocacy", owner.account_number), "faxed consent did not satisfy patient advocacy")
	TEST_ASSERT_EQUAL(advocate.state, CONTRACT_COMPLETED, "patient-advocate contract remained active")
	TEST_ASSERT_EQUAL(coverup.state, CONTRACT_CANCELLED, "opposing cover-up contract was not cancelled")
	trial.record_exposure(subject, 5)
	participant.exposure_time = world.time - 1 MINUTE
	consent_component.payload["signature_time"] = participant.exposure_time
	dq_contract_test_scan(baseline_scan, subject, participant.exposure_time, null)
	var/obj/item/paper/followup_scan = new(run_loc_floor_bottom_left)
	followup_scan.name = "Body Scan - Test Subject (follow-up)"
	dq_contract_test_scan(followup_scan, subject, world.time, trial.id)
	var/obj/item/paper_bundle/evidence_packet = new(run_loc_floor_bottom_left)
	consent.forceMove(evidence_packet)
	baseline_scan.forceMove(evidence_packet)
	followup_scan.forceMove(evidence_packet)
	evidence_packet.pages = list(consent, baseline_scan, followup_scan)
	var/list/authenticated_baseline = SScontracts.authenticated_scan_payload(baseline_scan)
	var/list/authenticated_followup = SScontracts.authenticated_scan_payload(followup_scan)
	TEST_ASSERT(authenticated_baseline && authenticated_followup, "physical scanner pages lost their evidence-ledger records")
	TEST_ASSERT_EQUAL(authenticated_baseline["subject_id"], identity.id, "baseline ledger identity changed during paper handling")
	TEST_ASSERT_EQUAL(authenticated_followup["subject_id"], identity.id, "follow-up ledger identity changed during paper handling")
	TEST_ASSERT(authenticated_followup["trial_markers"]?[trial.id] > 0, "follow-up ledger lost the coded trial tracer")
	TEST_ASSERT(SScontracts.evidence_available(list(consent_component.evidence_id, authenticated_baseline["evidence_id"], authenticated_followup["evidence_id"])), "complete packet contained unavailable or duplicate evidence identities")
	TEST_ASSERT(process_contract_fax(evidence_packet, CONTRACT_FAX_VEYMED, owner.account_number), "complete physical evidence packet was rejected by VeyMed fax processing")
	TEST_ASSERT_EQUAL(trial.observation_requirement.progress, 1, "faxed signed observation did not advance the study")
	TEST_ASSERT(trial.print_consent_revocation(test_turf, identity.id, owner.account_number), "submitted participant could not obtain a withdrawal form")
	var/obj/item/paper/submitted_withdrawal
	for(var/obj/item/paper/page in test_turf)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.contract_id == trial.id && document.document_kind == CONTRACT_DOCUMENT_CONSENT_REVOCATION && document.payload["subject_id"] == identity.id)
			submitted_withdrawal = page
			break
	TEST_ASSERT(submitted_withdrawal, "submitted-participant withdrawal paper was not printed")
	submitted_withdrawal.on_field_written(subject, 1, null)
	TEST_ASSERT(process_contract_fax(submitted_withdrawal, CONTRACT_FAX_VEYMED, owner.account_number), "signed withdrawal was rejected by the normal fax path")
	TEST_ASSERT(participant.consent_withdrawn && trial.participants[identity.id] == participant, "post-submission withdrawal incorrectly erased already-received evidence")

	var/mob/living/carbon/human/withdrawing_subject = new(test_turf)
	withdrawing_subject.real_name = "Withdrawing Subject"
	var/obj/item/paper/withdrawing_consent = create_contract_document(test_turf, "withdrawal test consent", "<b>Subject signature:</b> <span class=\"paper_field\"></span>", trial.id, CONTRACT_DOCUMENT_CLINICAL_CASE, CONTRACT_FAX_VEYMED, list("issuer_account" = owner.account_number))
	withdrawing_consent.on_field_written(withdrawing_subject, 1, null)
	var/datum/contract_subject_identity/withdrawing_identity = SScontracts.subject_identity(withdrawing_subject)
	var/datum/medical_trial_participant/withdrawing_participant = trial.participants[withdrawing_identity.id]
	TEST_ASSERT(withdrawing_participant, "second consenting subject was not enrolled")
	TEST_ASSERT(trial.print_consent_revocation(test_turf, withdrawing_identity.id, owner.account_number), "unsubmitted participant could not obtain a withdrawal form")
	var/obj/item/paper/unsubmitted_withdrawal
	for(var/obj/item/paper/page in test_turf)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.contract_id == trial.id && document.document_kind == CONTRACT_DOCUMENT_CONSENT_REVOCATION && document.payload["subject_id"] == withdrawing_identity.id)
			unsubmitted_withdrawal = page
			break
	unsubmitted_withdrawal.on_field_written(withdrawing_subject, 1, null)
	var/consent_evidence_id = withdrawing_participant.consent_evidence_id
	TEST_ASSERT(process_contract_fax(unsubmitted_withdrawal, CONTRACT_FAX_VEYMED, owner.account_number), "unsubmitted consent withdrawal was rejected")
	TEST_ASSERT(!trial.participants[withdrawing_identity.id], "withdrawn unsubmitted participant still occupied a cohort slot")
	var/datum/contract_evidence/voided_consent = SScontracts.evidence_by_id[consent_evidence_id]
	TEST_ASSERT(voided_consent?.void_reason, "withdrawal did not void the prior consent evidence")

	var/mob/living/carbon/human/corpse = new(run_loc_floor_bottom_left)
	corpse.death()
	var/obj/item/organ/brain = corpse.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT(!medical_trial_corpse_irrecoverable(corpse), "fresh corpse was incorrectly eligible for irreversible transfer")
	brain.damage = brain.max_damage
	TEST_ASSERT(medical_trial_corpse_irrecoverable(corpse), "100% brain-damaged corpse was rejected from irreversible transfer")

	// A missing/offline original clinician must fall through to another live
	// Medical account instead of permanently consuming the one-shot offer.
	var/datum/money_account/fallback_account = new
	fallback_account.account_number = 987655
	fallback_account.owner_name = "Fallback Clinician"
	GLOB.all_money_accounts += fallback_account
	var/mob/living/carbon/human/fallback_clinician = new(test_turf)
	fallback_clinician.real_name = fallback_account.owner_name
	fallback_clinician.job = JOB_MEDICAL_DOCTOR
	var/datum/mind/fallback_mind = new("fallback_clinician")
	fallback_mind.initial_account = fallback_account
	fallback_mind.assigned_role = JOB_MEDICAL_DOCTOR
	fallback_mind.transfer_to(fallback_clinician)
	GLOB.player_list |= fallback_clinician
	var/datum/medical_trial_participant/fallback_participant = new(SScontracts.subject_identity(corpse).id, list(), FALSE, 123456789)
	var/datum/contract/medical_trial_personal/fallback_offer = medical_trial_offer_corpse_autopsy(trial, fallback_participant)
	TEST_ASSERT(fallback_offer, "corpse offer did not fall back from a missing clinician account")
	TEST_ASSERT_EQUAL(fallback_offer.owner_account_number, fallback_account.account_number, "corpse offer fallback selected the wrong Medical account")
	qdel(fallback_offer)
	qdel(fallback_participant)
	GLOB.player_list -= fallback_clinician
	GLOB.all_money_accounts -= fallback_account
	qdel(fallback_clinician)
	qdel(fallback_mind)
	qdel(fallback_account)

	var/datum/contract_definition/espionage_definition = SScontracts.definitions["medical_trial_espionage"]
	var/list/espionage_context = list(
		"owner_account" = owner.account_number,
		"trial_id" = trial.id,
		"target_name" = trial.profile.code_name,
	)
	var/datum/contract/medical_trial_personal/espionage = espionage_definition.create_contract(espionage_context)
	TEST_ASSERT(espionage.accept(owner), "industrial-espionage shipping contract could not be accepted")
	var/obj/structure/closet/crate/sample_crate = new(run_loc_floor_bottom_left)
	create_contract_document(sample_crate, "test sample manifest", "test", trial.id, CONTRACT_DOCUMENT_MANIFEST, espionage.issuer_name, list("side_contract_id" = espionage.id))
	var/obj/item/reagent_containers/glass/beaker/stopperedbottle/sample = new(sample_crate)
	sample.reagents.add_reagent("dq_experimental_medication", 5, list("contract_id" = trial.id))
	process_contract_export(sample_crate)
	TEST_ASSERT_EQUAL(espionage.state, CONTRACT_COMPLETED, "manifested medication export did not complete industrial espionage")

	var/datum/contract_definition/autopsy_definition = SScontracts.definitions["medical_trial_autopsy"]
	var/list/autopsy_context = list(
		"owner_account" = owner.account_number,
		"trial_id" = trial.id,
		"target_ref" = SScontracts.subject_identity(corpse)?.id,
		"target_name" = corpse.real_name,
	)
	var/datum/contract/medical_trial_personal/autopsy = autopsy_definition.create_contract(autopsy_context)
	TEST_ASSERT(autopsy.accept(owner), "corpse shipping contract could not be accepted")
	var/obj/structure/closet/crate/corpse_crate = new(run_loc_floor_bottom_left)
	create_contract_document(corpse_crate, "test corpse manifest", "test", trial.id, CONTRACT_DOCUMENT_MANIFEST, autopsy.issuer_name, list("side_contract_id" = autopsy.id))
	corpse.forceMove(corpse_crate)
	TEST_ASSERT(!SSsupply.forbidden_atoms_check(corpse_crate), "the real supply-shuttle freight guard rejected an eligible dead body")
	process_contract_export(corpse_crate)
	TEST_ASSERT_EQUAL(autopsy.state, CONTRACT_COMPLETED, "manifested irreversible corpse export did not complete recovery contract")

	// Evidence is accepted during grace, so unsubmitted consent must remain
	// revocable for that same interval.
	var/mob/living/carbon/human/grace_subject = new(test_turf)
	grace_subject.real_name = "Grace Subject"
	var/obj/item/paper/grace_consent = create_contract_document(test_turf, "grace consent", "<b>Subject signature:</b> <span class=\"paper_field\"></span>", trial.id, CONTRACT_DOCUMENT_CLINICAL_CASE, CONTRACT_FAX_VEYMED, list("issuer_account" = owner.account_number))
	grace_consent.on_field_written(grace_subject, 1, null)
	var/datum/contract_subject_identity/grace_identity = SScontracts.subject_identity(grace_subject)
	TEST_ASSERT(trial.participants[grace_identity.id], "grace-period subject was not enrolled before the deadline")
	TEST_ASSERT(trial.enter_grace(), "test study could not enter its evidence grace period")
	TEST_ASSERT(trial.print_consent_revocation(test_turf, grace_identity.id, owner.account_number), "participant could not print a withdrawal during evidence grace")
	var/obj/item/paper/grace_withdrawal
	for(var/obj/item/paper/page in test_turf)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.contract_id == trial.id && document.document_kind == CONTRACT_DOCUMENT_CONSENT_REVOCATION && document.payload["subject_id"] == grace_identity.id)
			grace_withdrawal = page
			break
	TEST_ASSERT(grace_withdrawal, "grace-period withdrawal paper was not created")
	grace_withdrawal.on_field_written(grace_subject, 1, null)
	TEST_ASSERT(process_contract_fax(grace_withdrawal, CONTRACT_FAX_VEYMED, owner.account_number), "signed withdrawal was rejected during evidence grace")
	TEST_ASSERT(!trial.participants[grace_identity.id], "grace-period withdrawal left the participant enrolled")

	qdel(advocate)
	qdel(coverup)
	qdel(espionage)
	qdel(autopsy)
	qdel(sample_crate)
	qdel(corpse_crate)
	qdel(trial)
	qdel(subject)
	qdel(withdrawing_subject)
	qdel(grace_subject)
	GLOB.all_money_accounts -= owner
	qdel(owner)

/datum/unit_test/dq_medical_contract_machine_integration

/datum/unit_test/dq_medical_contract_machine_integration/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/mob/living/carbon/human/doctor = new(test_turf)
	doctor.real_name = "Integration Doctor"
	var/obj/item/card/id/medical/head/head_id = new(doctor)
	var/obj/machinery/computer/skills/management = new(test_turf)
	management.scan = head_id
	var/datum/contract_definition/definition = SScontracts.definitions["experimental_medication_study"]
	var/datum/contract/medical_trial/trial = definition.create_contract()
	TEST_ASSERT(management.accept_management_contract(trial, doctor), "department management console rejected a valid medical trial")
	var/found_initial_bottle = FALSE
	for(var/obj/item/reagent_containers/glass/beaker/stopperedbottle/bottle in get_turf(management))
		if(medical_trial_reagent_amount(bottle.reagents, MEDICAL_TRIAL_REAGENT_ID, trial.id) > 0)
			TEST_ASSERT_EQUAL(bottle.type, /obj/item/reagent_containers/glass/beaker/stopperedbottle, "trial medication used a contract-only physical item instead of an ordinary chemistry bottle")
			found_initial_bottle = TRUE
			break
	TEST_ASSERT(found_initial_bottle, "console acceptance did not materialize coded trial supplies")
	var/datum/money_account/medical_account = GLOB.department_accounts[DEPARTMENT_MEDICAL]
	var/original_balance = medical_account.money
	medical_account.money = MEDICAL_TRIAL_RESUPPLY_COST + 100
	TEST_ASSERT(trial.request_resupply(get_turf(management)), "funded replacement-dose request failed")
	TEST_ASSERT_EQUAL(trial.resupplies_used, 1, "replacement-dose use was not recorded")
	TEST_ASSERT_EQUAL(medical_account.money, 100, "replacement dose did not debit Medical's budget")
	medical_account.money = original_balance
	qdel(trial)
	qdel(management)
	qdel(doctor)

/datum/unit_test/dq_rare_case_report_workflow

/datum/unit_test/dq_rare_case_report_workflow/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/mob/living/carbon/human/subject = new(test_turf)
	subject.real_name = "Rare Case Patient"
	var/datum/mind/test_mind = new
	test_mind.assigned_role = JOB_MEDICAL_DOCTOR
	test_mind.transfer_to(subject)
	var/obj/item/organ/lungs = subject.internal_organs_by_name[O_LUNGS]
	var/datum/medical_issue/condition/tension_pneumothorax/condition = new
	condition.set_severity(40)
	lungs.add_medical_issue(condition, subject)
	SScontracts.consider_rare_medical_case(subject)
	var/datum/contract/medical_case_report/report
	for(var/datum/contract/medical_case_report/candidate in SScontracts.offered_contracts)
		if(candidate.target_ref == SScontracts.subject_identity(subject)?.id)
			report = candidate
			break
	TEST_ASSERT(report, "qualifying rare condition did not publish a case-report offer")
	var/mob/living/carbon/human/doctor = new(test_turf)
	var/obj/item/card/id/medical/head/head_id = new(doctor)
	var/obj/machinery/computer/skills/management = new(test_turf)
	management.scan = head_id
	TEST_ASSERT(management.accept_management_contract(report, doctor), "department console rejected the rare-case report")
	TEST_ASSERT(report.print_case_forms(test_turf), "rare-case forms did not print (state [report.state], consent time [report.consent_time], location [test_turf])")
	var/obj/item/paper/consent
	var/obj/item/paper/narrative
	for(var/obj/item/paper/page in test_turf)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.contract_id != report.id)
			continue
		if(document.document_kind == CONTRACT_DOCUMENT_RARE_CASE_CONSENT)
			consent = page
		else if(document.document_kind == CONTRACT_DOCUMENT_RARE_CASE_REPORT)
			narrative = page
	TEST_ASSERT(consent && narrative, "rare-case consent or narrative form was missing")
	consent.on_field_written(subject, 1, null)
	TEST_ASSERT(report.consent_time, "patient signature did not register rare-case consent")
	TEST_ASSERT(report.print_case_forms(test_turf), "registered rare-case paperwork had no replacement path")
	report.consent_time = world.time - MEDICAL_TRIAL_OBSERVATION_TIME
	narrative.info += " Treatment relieved pleural pressure. Follow-up showed stable respiration without complication."
	narrative.on_field_written(doctor, 1, null)
	narrative.on_field_written(doctor, 2, null)
	var/obj/item/paper/baseline = new(test_turf)
	dq_contract_test_scan(baseline, subject, report.consent_time, null)
	lungs.remove_medical_issue(condition)
	qdel(condition)
	var/obj/item/paper/followup = new(test_turf)
	dq_contract_test_scan(followup, subject, world.time, null)
	var/obj/item/paper_bundle/packet = new(test_turf)
	consent.forceMove(packet)
	narrative.forceMove(packet)
	baseline.forceMove(packet)
	followup.forceMove(packet)
	packet.pages = list(consent, narrative, baseline, followup)
	var/obj/machinery/photocopier/faxmachine/fax = new(test_turf)
	fax.stat = 0
	fax.copyitem = packet
	fax.scan = head_id
	TEST_ASSERT(fax.sendfax(CONTRACT_FAX_CASE_REGISTRY, doctor), "powered fax machine rejected the authenticated rare-case packet")
	TEST_ASSERT_EQUAL(report.state, CONTRACT_COMPLETED, "real fax-machine submission did not complete the rare-case report")
	qdel(fax)
	qdel(management)
	qdel(doctor)
	qdel(subject)

/datum/unit_test/dq_rare_case_consent_revocation

/datum/unit_test/dq_rare_case_consent_revocation/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/mob/living/carbon/human/subject = new(test_turf)
	subject.real_name = "Registry Withdrawal Patient"
	var/datum/mind/subject_mind = new("rare_case_withdrawal_patient")
	subject_mind.assigned_role = JOB_MEDICAL_DOCTOR
	subject_mind.transfer_to(subject)
	var/obj/item/organ/lungs = subject.internal_organs_by_name[O_LUNGS]
	var/datum/medical_issue/condition/tension_pneumothorax/condition = new
	condition.set_severity(40)
	lungs.add_medical_issue(condition, subject)
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/contract_definition/definition = SScontracts.definitions["medical_rare_case_report"]
	var/datum/contract/medical_case_report/report = definition.create_contract(list(
		"target_ref" = identity.id,
		"target_name" = subject.real_name,
		"condition_type" = condition.type,
		"condition_name" = condition.name,
	))
	TEST_ASSERT(report, "eligible rare-case patient did not produce a report offer")
	TEST_ASSERT(report.accept(), "rare-case withdrawal report could not be accepted")
	TEST_ASSERT(report.print_case_forms(test_turf), "rare-case withdrawal forms could not be printed")
	var/obj/item/paper/consent
	for(var/obj/item/paper/page in test_turf)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.contract_id == report.id && document.document_kind == CONTRACT_DOCUMENT_RARE_CASE_CONSENT)
			consent = page
			break
	consent.on_field_written(subject, 1, null)
	var/consent_evidence_id = report.consent_evidence_id
	TEST_ASSERT(report.print_consent_revocation(test_turf), "rare-case patient could not obtain a withdrawal form")
	var/obj/item/paper/withdrawal
	for(var/obj/item/paper/page in test_turf)
		var/datum/component/contract_document/document = page.GetComponent(/datum/component/contract_document)
		if(document?.contract_id == report.id && document.document_kind == CONTRACT_DOCUMENT_CONSENT_REVOCATION)
			withdrawal = page
			break
	withdrawal.on_field_written(subject, 1, null)
	TEST_ASSERT(process_contract_fax(withdrawal, CONTRACT_FAX_CASE_REGISTRY, null, subject), "case-registry withdrawal was rejected by fax processing")
	TEST_ASSERT_EQUAL(report.state, CONTRACT_CANCELLED, "rare-case report remained active after patient withdrawal")
	var/datum/contract_evidence/voided_consent = SScontracts.evidence_by_id[consent_evidence_id]
	TEST_ASSERT(voided_consent?.void_reason, "rare-case withdrawal did not void the original consent")
	qdel(report)
	qdel(subject)
	qdel(subject_mind)

/proc/dq_contract_test_zero_rewards(datum/contract/contract)
	contract.base_terms_captured = TRUE
	contract.base_reward = 0
	contract.reward = 0
	contract.negotiated_station_bonus = 0
	contract.negotiated_department_bonus = 0
	contract.negotiated_staff_bonus = 0
	contract.base_station_reputation_reward = 0
	contract.base_department_reputation_reward = 0
	contract.base_personal_reputation_reward = 0
	contract.station_reputation_reward = 0
	contract.department_reputation_reward = 0
	contract.personal_reputation_reward = 0

/datum/unit_test/dq_expanded_contract_catalog

/datum/unit_test/dq_expanded_contract_catalog/Run()
	var/static/list/expected_definitions = list(
		"supermatter_performance",
		"research_export_portfolio",
		"cargo_freight_portfolio",
		"service_hospitality_census",
		"security_case_resolution",
		"command_budget_mandate",
		"engineering_safety_watch",
		"research_internal_access",
		"cargo_local_priority",
		"service_gratuity_drive",
		"security_record_suppression",
		"command_executive_reserve",
	)
	for(var/definition_id in expected_definitions)
		var/datum/contract_definition/definition = SScontracts.definitions[definition_id]
		TEST_ASSERT(definition, "expanded contract definition [definition_id] was not registered")
		TEST_ASSERT(definition.department != DEPARTMENT_PLANET, "expanded contract [definition_id] incorrectly targets Exploration")

/datum/unit_test/dq_expanded_department_outcomes

/datum/unit_test/dq_expanded_department_outcomes/Run()
	var/datum/contract_definition/engineering_definition = SScontracts.definitions["supermatter_performance"]
	var/datum/contract/outcome/engine_performance/engineering = engineering_definition.create_contract(list("duration" = 1))
	dq_contract_test_zero_rewards(engineering)
	TEST_ASSERT(engineering.negotiation_clauses["engine_output"], "Engineering performance offer lacked its output charter")
	TEST_ASSERT(engineering.select_negotiation_option("engine_output", "frontier", "Unit test"), "Engineering frontier output charter could not be negotiated")
	TEST_ASSERT_EQUAL(engineering.performance_requirement.target, 3, "Engineering charter did not expose three progressive stages")
	TEST_ASSERT_EQUAL(engineering.primary_target, 1000, "Engineering frontier charter did not update its maximum output")
	TEST_ASSERT(engineering.accept(), "Engineering outcome contract could not be accepted")
	// An idle reading and a non-station crystal must not qualify.
	emit_contract_event(CONTRACT_EVENT_MACHINE_RESULT, list("department" = DEPARTMENT_ENGINEERING, "machine_kind" = "supermatter", "machine_id" = "test-sm", "station_machine" = TRUE, "metrics" = list("eer" = 0, "integrity" = 100)), "expanded-engineering-idle:[REF(engineering)]")
	emit_contract_event(CONTRACT_EVENT_MACHINE_RESULT, list("department" = DEPARTMENT_ENGINEERING, "machine_kind" = "supermatter", "machine_id" = "test-sm", "station_machine" = FALSE, "metrics" = list("eer" = 1000, "integrity" = 95)), "expanded-engineering-offstation:[REF(engineering)]")
	TEST_ASSERT_EQUAL(engineering.state, CONTRACT_ACTIVE, "idle or off-station supermatter telemetry qualified")
	emit_contract_event(CONTRACT_EVENT_MACHINE_RESULT, list("department" = DEPARTMENT_ENGINEERING, "machine_kind" = "supermatter", "machine_id" = "test-sm", "station_machine" = TRUE, "metrics" = list("eer" = 1000, "integrity" = 95)), "expanded-engineering:[REF(engineering)]")
	sleep(2)
	TEST_ASSERT_EQUAL(engineering.state, CONTRACT_COMPLETED, "qualifying sustained supermatter telemetry did not complete Engineering's contract")
	qdel(engineering)

	var/datum/contract_definition/research_definition = SScontracts.definitions["research_export_portfolio"]
	var/datum/contract/outcome/research = research_definition.create_contract(list("value_target" = 200, "variety_target" = 2))
	dq_contract_test_zero_rewards(research)
	TEST_ASSERT(research.accept(), "Research outcome contract could not be accepted")
	emit_contract_event(CONTRACT_EVENT_ITEM_EXPORTED, list("department" = DEPARTMENT_RESEARCH, "handling_department" = DEPARTMENT_CARGO, "item_type" = /obj/item, "actor_account" = 810001, "fact_id" = "research-a", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("value" = 100)), "expanded-research-a:[REF(research)]")
	emit_contract_event(CONTRACT_EVENT_ITEM_EXPORTED, list("department" = DEPARTMENT_RESEARCH, "handling_department" = DEPARTMENT_CARGO, "item_type" = /obj/item, "actor_account" = 810001, "fact_id" = "research-repeat", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("value" = 100)), "expanded-research-repeat:[REF(research)]")
	TEST_ASSERT_EQUAL(research.state, CONTRACT_ACTIVE, "repeated exports of one design bypassed the portfolio variety target")
	emit_contract_event(CONTRACT_EVENT_ITEM_EXPORTED, list("department" = DEPARTMENT_RESEARCH, "handling_department" = DEPARTMENT_CARGO, "item_type" = /obj/item/stack, "actor_account" = 810001, "fact_id" = "research-b", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("value" = 100)), "expanded-research-b:[REF(research)]")
	TEST_ASSERT_EQUAL(research.state, CONTRACT_COMPLETED, "Research value and design variety did not complete its contract")
	qdel(research)

	var/datum/contract_definition/cargo_definition = SScontracts.definitions["cargo_freight_portfolio"]
	var/datum/contract/outcome/cargo = cargo_definition.create_contract(list("value_target" = 100, "variety_target" = 2))
	dq_contract_test_zero_rewards(cargo)
	TEST_ASSERT(cargo.accept(), "Cargo outcome contract could not be accepted")
	emit_contract_event(CONTRACT_EVENT_ITEM_EXPORTED, list("department" = null, "handling_department" = DEPARTMENT_CARGO, "item_type" = /obj/item/storage, "actor_account" = 810002, "fact_id" = "cargo-a", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("value" = 50)), "expanded-cargo-a:[REF(cargo)]")
	emit_contract_event(CONTRACT_EVENT_ITEM_EXPORTED, list("department" = DEPARTMENT_RESEARCH, "handling_department" = DEPARTMENT_CARGO, "item_type" = /obj/item/stack, "actor_account" = 810002, "fact_id" = "cargo-b", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("value" = 50)), "expanded-cargo-b:[REF(cargo)]")
	TEST_ASSERT_EQUAL(cargo.state, CONTRACT_COMPLETED, "Cargo value and freight variety did not complete its contract")
	qdel(cargo)

	var/datum/contract_definition/service_definition = SScontracts.definitions["service_hospitality_census"]
	var/datum/contract/outcome/service = service_definition.create_contract(list("revenue_target" = 100, "customer_target" = 2))
	dq_contract_test_zero_rewards(service)
	TEST_ASSERT(service.accept(), "Service outcome contract could not be accepted")
	emit_contract_event(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, list("department" = DEPARTMENT_CIVILIAN, "rollup" = "department", "accounting_period" = 1, "fact_id" = "expanded-service", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("amount" = 100, "customer_count" = 2)), "expanded-service:[REF(service)]")
	TEST_ASSERT_EQUAL(service.state, CONTRACT_COMPLETED, "Service revenue and customer diversity did not complete its contract")
	qdel(service)

	var/datum/contract_definition/security_definition = SScontracts.definitions["security_case_resolution"]
	var/datum/contract/outcome/security = security_definition.create_contract(list("case_target" = 2, "custody_duration" = 1))
	dq_contract_test_zero_rewards(security)
	var/datum/contract_requirement/event_count/security_cases = security.requirements[1]
	TEST_ASSERT_EQUAL(security_cases.unique_field, "physical_subject_id", "Security contract did not use physical identity for case uniqueness")
	TEST_ASSERT(security_cases.required, "Security's distinct-case requirement was configured as optional")
	TEST_ASSERT(security.accept(), "Security outcome contract could not be accepted")
	// The focused test world has no connected crew, so prepare_accept correctly
	// scales this to one case. Restore a representative live-round target to
	// exercise duplicate-record resistance rather than crew scaling.
	security.primary_target = 2
	security_cases.target = 2
	emit_contract_event(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, list("department" = DEPARTMENT_SECURITY, "subject_id" = "physical-a", "physical_subject_id" = "physical-a", "record_id" = "case-a", "previous_status" = "Incarcerated", "disposition" = "Released", "actor_account" = 810004, "physical_custody_verified" = TRUE, "fact_id" = "security-record:case-a", "fact_revision" = 1, "fact_active" = TRUE, "tags" = list("custody_resolution"), "metrics" = list("custody_duration" = 2)), "expanded-security-a:[REF(security)]")
	TEST_ASSERT_EQUAL(security_cases.progress, 1, "one physical prisoner did not count as exactly one Security case")
	TEST_ASSERT_EQUAL(security_cases.state, CONTRACT_REQUIREMENT_PENDING, "Security case requirement completed before its target")
	TEST_ASSERT_EQUAL(security.state, CONTRACT_ACTIVE, "one of two required Security cases completed the contract early")
	// A second record for the same prisoner is a new record fact, not a new case.
	emit_contract_event(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, list("department" = DEPARTMENT_SECURITY, "subject_id" = "physical-a", "physical_subject_id" = "physical-a", "record_id" = "case-a-duplicate", "previous_status" = "Incarcerated", "disposition" = "Parolled", "actor_account" = 810004, "physical_custody_verified" = TRUE, "fact_id" = "security-record:case-a-duplicate", "fact_revision" = 1, "fact_active" = TRUE, "tags" = list("custody_resolution"), "metrics" = list("custody_duration" = 2)), "expanded-security-a-duplicate:[REF(security)]")
	TEST_ASSERT_EQUAL(security_cases.progress, 1, "duplicate Security records advanced the physical-case counter")
	TEST_ASSERT_EQUAL(security.state, CONTRACT_ACTIVE, "duplicate records for one physical prisoner counted as distinct Security cases")
	emit_contract_event(CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED, list("department" = DEPARTMENT_SECURITY, "subject_id" = "physical-b", "physical_subject_id" = "physical-b", "record_id" = "case-b", "previous_status" = "Incarcerated", "disposition" = "Parolled", "actor_account" = 810004, "physical_custody_verified" = TRUE, "fact_id" = "security-record:case-b", "fact_revision" = 1, "fact_active" = TRUE, "tags" = list("custody_resolution"), "metrics" = list("custody_duration" = 2)), "expanded-security-b:[REF(security)]")
	TEST_ASSERT_EQUAL(security.state, CONTRACT_COMPLETED, "distinct qualifying Security resolutions did not complete its contract")
	qdel(security)

	var/datum/contract_definition/command_definition = SScontracts.definitions["command_budget_mandate"]
	var/datum/contract/outcome/command = command_definition.create_contract(list("allocation_target" = 1000, "department_target" = 2, "minimum_allocation" = 500))
	dq_contract_test_zero_rewards(command)
	TEST_ASSERT(command.accept(), "Command outcome contract could not be accepted")
	emit_contract_event(CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED, list("target_department" = DEPARTMENT_ENGINEERING, "target_is_department" = TRUE, "actor_account" = 810005, "metrics" = list("amount" = 100000)), "expanded-command-policy-only:[REF(command)]")
	TEST_ASSERT_EQUAL(command.state, CONTRACT_ACTIVE, "an unfunded Command policy edit incorrectly completed the mandate")
	emit_contract_event(CONTRACT_EVENT_BUDGET_CYCLE_SETTLED, list("department" = DEPARTMENT_COMMAND, "rollup" = "station", "accounting_period" = 1, "fact_id" = "expanded-budget", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("funded_allocation_total" = 1000, "funded_department_count" = 2, "command_allocation" = 0, "payroll_coverage" = 1)), "expanded-command-settlement:[REF(command)]")
	TEST_ASSERT_EQUAL(command.state, CONTRACT_COMPLETED, "diversified current budget allocations did not complete Command's contract")
	qdel(command)

/datum/unit_test/dq_linked_personal_outcome

/datum/unit_test/dq_linked_personal_outcome/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/owner_account = new
	owner_account.account_number = 830001
	owner_account.owner_name = "Internal Sales Tester"
	owner_account.money = 0
	GLOB.all_money_accounts += owner_account
	var/mob/living/carbon/human/owner = new(test_turf)
	var/datum/mind/owner_mind = new("linked_personal_contract_test")
	owner_mind.initial_account = owner_account
	owner_mind.transfer_to(owner)
	GLOB.player_list |= owner
	owner.ensure_faction_reputation().set_reputation(REPUTATION_FACTION_WORKERS_UNION, REPUTATION_NEUTRAL)

	var/datum/contract/parent = new
	parent.title = "Linked outcome parent"
	parent.department = DEPARTMENT_RESEARCH
	parent.reward = 0
	parent.add_requirement(new /datum/contract_requirement/event_count("linked-parent-event", 1))
	TEST_ASSERT(parent.accept(), "linked personal test parent could not be activated")
	var/datum/contract_definition/side_definition = SScontracts.definitions["research_internal_access"]
	var/datum/contract/personal_outcome/side = side_definition.create_contract(list(
		"owner_account" = owner_account.account_number,
		"parent_contract_id" = parent.id,
		"department" = DEPARTMENT_RESEARCH,
	))
	TEST_ASSERT(side, "eligible linked personal opportunity was not materialized")
	dq_contract_test_zero_rewards(side)
	TEST_ASSERT(side.accept(owner_account, owner), "linked personal opportunity could not be accepted by its owner")
	emit_contract_event(CONTRACT_EVENT_SERVICE_PERIOD_SETTLED, list("department" = DEPARTMENT_RESEARCH, "rollup" = "staff", "accounting_period" = 1, "actor_account" = owner_account.account_number, "staff_account" = owner_account.account_number, "fact_id" = "linked-personal-settlement", "fact_revision" = 1, "fact_active" = TRUE, "metrics" = list("amount" = 600, "customer_count" = 3, "verified_amount" = 600, "verified_item_count" = 3, "verified_type_count" = 2)), "linked-personal-settlement:[REF(side)]")
	TEST_ASSERT_EQUAL(side.state, CONTRACT_COMPLETED, "owner-attributed internal sales did not complete the linked personal contract")
	TEST_ASSERT_EQUAL(parent.state, CONTRACT_FAILED, "the mutually exclusive personal outcome did not close the public parent")
	owner.ensure_faction_reputation().set_reputation(REPUTATION_FACTION_SYNDICATE, REPUTATION_HOSTILE)
	var/datum/contract_definition/sensitive_definition = SScontracts.definitions["security_record_suppression"]
	TEST_ASSERT(!sensitive_definition.is_available(list("owner_account" = owner_account.account_number, "parent_contract_id" = parent.id)), "hostile Syndicate standing did not suppress a sensitive personal offer")
	qdel(side)
	qdel(parent)
	GLOB.player_list -= owner
	GLOB.all_money_accounts -= owner_account
	qdel(owner)
	qdel(owner_mind)
	qdel(owner_account)

/datum/unit_test/dq_contract_authoritative_producers

/datum/unit_test/dq_contract_authoritative_producers/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/money_account/actor_account = new
	actor_account.account_number = 850001
	actor_account.owner_name = "Contract Producer Tester"
	GLOB.all_money_accounts += actor_account
	var/mob/living/carbon/human/actor = new(test_turf)
	var/datum/mind/actor_mind = new("contract_producer_test")
	actor_mind.initial_account = actor_account
	actor_mind.transfer_to(actor)
	GLOB.player_list |= actor

	var/datum/contract_definition/command_definition = SScontracts.definitions["command_budget_mandate"]
	var/datum/contract/outcome/command = command_definition.create_contract(list("allocation_target" = 1000, "department_target" = 2, "minimum_allocation" = 500))
	dq_contract_test_zero_rewards(command)
	TEST_ASSERT(command.accept(), "producer-backed Command contract could not be accepted")
	var/obj/machinery/computer/skills/management = new(test_turf)
	var/obj/item/card/id/command_id = new(management)
	command_id.access |= ACCESS_CAPTAIN
	management.scan = command_id
	management.authenticated = actor.real_name
	var/datum/money_account/engineering_budget = GLOB.department_accounts[DEPARTMENT_ENGINEERING]
	var/datum/money_account/medical_budget = GLOB.department_accounts[DEPARTMENT_MEDICAL]
	var/old_engineering_allocation = engineering_budget.monthly_allocation
	var/old_medical_allocation = medical_budget.monthly_allocation
	TEST_ASSERT(management.set_department_allocation(DEPARTMENT_ENGINEERING, 500, actor), "authoritative Engineering allocation edit failed")
	TEST_ASSERT(management.set_department_allocation(DEPARTMENT_MEDICAL, 500, actor), "authoritative Medical allocation edit failed")
	TEST_ASSERT_EQUAL(command.state, CONTRACT_ACTIVE, "Department Management policy edits completed Command's contract before funds moved")
	SSsupply.publish_budget_cycle_settlement(list(DEPARTMENT_ENGINEERING = 2000, DEPARTMENT_MEDICAL = 2000), 99991)
	TEST_ASSERT_EQUAL(command.state, CONTRACT_COMPLETED, "the authoritative funded budget-cycle settlement did not complete Command's contract")
	engineering_budget.monthly_allocation = old_engineering_allocation
	medical_budget.monthly_allocation = old_medical_allocation
	qdel(command)
	qdel(management)

	var/datum/contract_definition/security_definition = SScontracts.definitions["security_case_resolution"]
	var/datum/contract/outcome/security = security_definition.create_contract(list("case_target" = 1, "custody_duration" = 1))
	dq_contract_test_zero_rewards(security)
	TEST_ASSERT(security.accept(), "producer-backed Security contract could not be accepted")
	var/obj/machinery/computer/secure_data/security_console = new(test_turf)
	var/datum/data/record/general_record = new
	general_record.fields["id"] = "producer-case"
	general_record.fields["name"] = actor.real_name
	GLOB.data_core.general += general_record
	var/datum/data/record/security_record = new
	security_record.fields["criminal"] = "Released"
	security_console.active1 = general_record
	security_console.active2 = security_record
	var/area/original_area = get_area(test_turf)
	var/area/security/brig/test_brig = new
	ChangeArea(test_turf, test_brig)
	SScontracts.refresh_physical_custody(actor)
	var/datum/contract_subject_identity/actor_identity = SScontracts.subject_identity(actor)
	SScontracts.custody_started_by_subject[actor_identity.id] = world.time - 2
	TEST_ASSERT(security_console.record_security_disposition("Incarcerated", "Released", actor), "authoritative Security disposition edit failed")
	TEST_ASSERT_EQUAL(security.state, CONTRACT_COMPLETED, "real Security disposition transition did not complete Security's contract")
	ChangeArea(test_turf, original_area)
	SScontracts.refresh_physical_custody(actor)
	qdel(security)
	qdel(security_console)
	qdel(general_record)
	qdel(security_record)

	GLOB.player_list -= actor
	GLOB.all_money_accounts -= actor_account
	qdel(actor)
	qdel(actor_mind)
	qdel(actor_account)

/datum/unit_test/dq_contract_budget_acceptance_feasibility

/datum/unit_test/dq_contract_budget_acceptance_feasibility/Run()
	var/station_money = GLOB.station_account.money
	var/old_salary_support = SSsupply.nt_salary_support
	GLOB.station_account.money = 2500
	SSsupply.nt_salary_support = 0
	var/datum/contract_definition/outcome/command_budget_mandate/definition = SScontracts.definitions["command_budget_mandate"]
	var/datum/contract/outcome/contract = definition.create_contract(list("allocation_target" = 20000, "department_target" = 5, "minimum_allocation" = 2000))
	var/prepared = definition.prepare_accept(contract, null, null, null)
	var/scaled_total = contract.primary_target
	var/scaled_departments = contract.secondary_target
	GLOB.station_account.money = station_money
	SSsupply.nt_salary_support = old_salary_support
	TEST_ASSERT(prepared, "fundable low-budget mandate was rejected instead of scaled")
	TEST_ASSERT(scaled_total <= 2500, "budget mandate exceeded authoritative next-cycle funding")
	TEST_ASSERT_EQUAL(scaled_departments, 1, "budget mandate retained more funded departments than available money supports")
	qdel(contract)

/datum/unit_test/dq_contract_reversible_portfolio

/datum/unit_test/dq_contract_reversible_portfolio/Run()
	var/datum/contract/contract = new
	contract.title = "Correction-aware portfolio"
	contract.reward = 0
	var/datum/contract_requirement/fact_portfolio/portfolio = new("test-correctable-fact", 150, "category", "value", 2)
	contract.add_requirement(portfolio)
	TEST_ASSERT(contract.accept(), "correction-aware test contract could not be accepted")
	emit_contract_event("test-correctable-fact", list("fact_id" = "fact-a", "fact_revision" = 1, "fact_active" = TRUE, "category" = "A", "metrics" = list("value" = 100)), "correctable:a:1")
	emit_contract_event("test-correctable-fact", list("fact_id" = "fact-b", "fact_revision" = 1, "fact_active" = TRUE, "category" = "B", "metrics" = list("value" = 40)), "correctable:b:1")
	TEST_ASSERT_EQUAL(portfolio.progress, 140, "portfolio did not aggregate current facts")
	emit_contract_event("test-correctable-fact", list("fact_id" = "fact-a", "fact_revision" = 2, "fact_active" = FALSE, "category" = "A", "metrics" = list("value" = 0)), "correctable:a:2")
	TEST_ASSERT_EQUAL(portfolio.progress, 40, "a correction did not retract the superseded fact")
	TEST_ASSERT_EQUAL(portfolio.state, CONTRACT_REQUIREMENT_PENDING, "a corrected portfolio remained complete")
	emit_contract_event("test-correctable-fact", list("fact_id" = "fact-c", "fact_revision" = 1, "fact_active" = TRUE, "category" = "C", "metrics" = list("value" = 110)), "correctable:c:1")
	TEST_ASSERT_EQUAL(contract.state, CONTRACT_COMPLETED, "corrected replacement evidence did not complete the portfolio")
	qdel(contract)

/datum/unit_test/dq_contract_refunds_do_not_settle

/datum/unit_test/dq_contract_refunds_do_not_settle/Run()
	var/mob/living/carbon/human/refund_operator = new
	refund_operator.job = JOB_BARTENDER
	var/datum/contract_definition/service_definition = SScontracts.definitions["service_hospitality_census"]
	var/datum/contract/outcome/service = service_definition.create_contract(list("revenue_target" = 300, "customer_target" = 2))
	dq_contract_test_zero_rewards(service)
	TEST_ASSERT(service.accept(), "refund settlement test contract could not be accepted")
	var/datum/money_account/provider = GLOB.department_accounts[DEPARTMENT_CIVILIAN]
	var/provider_expenses_before = provider.monthly_expenses
	var/provider_total_expenses_before = provider.total_expenses
	var/refunds_before = SSsupply.currency_refunded
	var/internal_refunds_before = SSsupply.currency_internal_refunded
	var/datum/money_account/customer = new
	customer.account_number = 860001
	customer.owner_name = "Refund Customer"
	GLOB.all_money_accounts += customer
	var/old_provider_money = provider.money
	provider.money = max(provider.money, 500)
	var/period = SSsupply.service_accounting_period
	var/datum/service_invoice/invoice = SSsupply.create_service_invoice(customer, provider, "Unit test checkout", list("Meal" = 1), list("Meal" = 200), list("total" = 200, "subsidy" = 0, "personal" = 200, "tip" = 0, "staff_tip" = 0, "service_tip" = 0), 0, null)
	TEST_ASSERT(invoice, "refund settlement test invoice was not created")
	TEST_ASSERT(SSsupply.refund_service_invoice(invoice, provider, "Unit test checkout", refund_operator), "test invoice refund failed")
	SSsupply.create_service_invoice(customer, provider, "Unit test checkout", list("Imaginary banquet" = 1), list("Imaginary banquet" = 1000000), list("total" = 1000000, "subsidy" = 0, "personal" = 1000000, "tip" = 0, "staff_tip" = 0, "service_tip" = 0), 0, null)
	var/datum/money_account/subsidized_customer = new
	subsidized_customer.account_number = 860002
	subsidized_customer.owner_name = "Subsidized Customer"
	GLOB.all_money_accounts += subsidized_customer
	var/datum/service_invoice/subsidized_invoice = SSsupply.create_service_invoice(subsidized_customer, provider, "Unit test checkout", list("Subsidized meal" = 1), list("Subsidized meal" = 200), list("total" = 200, "subsidy" = 200, "personal" = 0, "tip" = 0, "staff_tip" = 0, "service_tip" = 0), 0, null)
	SSsupply.settle_service_contract_period(period)
	TEST_ASSERT_EQUAL(service.state, CONTRACT_ACTIVE, "a refunded invoice or one fabricated high-price customer completed the settled Service contract")
	TEST_ASSERT(subsidized_invoice.settled, "closed-period invoice was not finalized")
	TEST_ASSERT(!SSsupply.refund_service_invoice(subsidized_invoice, provider, "Unit test checkout", refund_operator), "a finalized accounting-period invoice was refunded after contract settlement")
	provider.money = old_provider_money
	provider.monthly_expenses = provider_expenses_before
	provider.total_expenses = provider_total_expenses_before
	SSsupply.currency_refunded = refunds_before
	SSsupply.currency_internal_refunded = internal_refunds_before
	GLOB.all_money_accounts -= customer
	GLOB.all_money_accounts -= subsidized_customer
	qdel(customer)
	qdel(subsidized_customer)
	qdel(service)
	qdel(refund_operator)

/datum/unit_test/dq_contract_fake_security_record_rejected

/datum/unit_test/dq_contract_fake_security_record_rejected/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/datum/contract_definition/security_definition = SScontracts.definitions["security_case_resolution"]
	var/datum/contract/outcome/security = security_definition.create_contract(list("case_target" = 1, "custody_duration" = 1))
	dq_contract_test_zero_rewards(security)
	TEST_ASSERT(security.accept(), "fake-record Security test contract could not be accepted")
	var/obj/machinery/computer/secure_data/security_console = new(test_turf)
	var/datum/data/record/general_record = new
	general_record.fields["id"] = "nonexistent-subject"
	general_record.fields["name"] = "Nobody Aboard"
	var/datum/data/record/security_record = new
	security_record.fields["criminal"] = "Released"
	security_console.active1 = general_record
	security_console.active2 = security_record
	TEST_ASSERT(security_console.record_security_disposition("Incarcerated", "Released", null), "fake disposition did not publish its auditable rejected fact")
	TEST_ASSERT_EQUAL(security.state, CONTRACT_ACTIVE, "a record with no physical prisoner completed the Security contract")
	qdel(security_console)
	qdel(general_record)
	qdel(security_record)
	qdel(security)

/datum/unit_test/dq_contract_custody_rejects_dead_or_credentialed_subjects

/datum/unit_test/dq_contract_custody_rejects_dead_or_credentialed_subjects/Run()
	var/turf/test_turf = run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1)
	var/area/original_area = get_area(test_turf)
	var/area/security/brig/test_brig = new
	ChangeArea(test_turf, test_brig)
	var/mob/living/carbon/human/subject = new(test_turf)
	var/datum/mind/subject_mind = new("custody_subject")
	subject_mind.transfer_to(subject)
	TEST_ASSERT(SScontracts.is_physically_custodied(subject), "living stripped prisoner was not recognized as physically custodied")
	var/obj/item/storage/backpack/held_bag = new(subject)
	new /obj/item/card/id(held_bag)
	TEST_ASSERT(!SScontracts.is_physically_custodied(subject), "ID nested inside a carried container bypassed custody verification")
	qdel(held_bag)
	subject.stat = DEAD
	TEST_ASSERT(!SScontracts.is_physically_custodied(subject), "dead body was accepted as a physically custodied prisoner")
	ChangeArea(test_turf, original_area)
	qdel(subject)
	qdel(subject_mind)

/datum/unit_test/dq_contract_reputation_terms_and_failure

/datum/unit_test/dq_contract_reputation_terms_and_failure/Run()
	var/faction_id = REPUTATION_FACTION_TRADERS_GUILD
	var/old_station_reputation = get_station_faction_reputation(faction_id)
	var/datum/faction_reputation_ledger/department_ledger = GLOB.station_faction_relations.get_department_ledger(DEPARTMENT_CARGO)
	var/old_department_reputation = department_ledger.get_reputation(faction_id)
	GLOB.station_faction_relations.set_reputation(faction_id, REPUTATION_ALLIED)
	department_ledger.set_reputation(faction_id, REPUTATION_ALLIED)
	var/datum/contract_definition/definition = SScontracts.definitions["cargo_freight_portfolio"]
	var/datum/contract/outcome/contract = definition.create_contract(list("value_target" = 100, "variety_target" = 1))
	TEST_ASSERT(contract, "allied-standing contract was not created")
	var/datum/contract_negotiation_clause/relationship = contract.negotiation_clauses["relationship"]
	TEST_ASSERT(relationship, "friendly standing did not unlock relationship negotiation terms")
	TEST_ASSERT(relationship.options["preferred_rate"], "allied standing did not unlock the preferred-contractor rate")
	TEST_ASSERT(contract.accept(), "allied-standing failure test contract could not be accepted")
	var/pre_failure_station_reputation = get_station_faction_reputation(faction_id)
	var/pre_failure_department_reputation = get_department_faction_reputation(DEPARTMENT_CARGO, faction_id)
	TEST_ASSERT(contract.fail("Intentional reliability test failure"), "active contract could not be failed")
	TEST_ASSERT(get_station_faction_reputation(faction_id) < pre_failure_station_reputation, "contract failure did not reduce station sponsor standing")
	TEST_ASSERT(get_department_faction_reputation(DEPARTMENT_CARGO, faction_id) < pre_failure_department_reputation, "contract failure did not reduce department sponsor standing")
	qdel(contract)
	var/datum/contract/outcome/declined = definition.create_contract(list("value_target" = 100, "variety_target" = 1))
	var/pre_decline_station_reputation = get_station_faction_reputation(faction_id)
	TEST_ASSERT(declined.decline(), "offered contract could not be declined")
	TEST_ASSERT_EQUAL(get_station_faction_reputation(faction_id), pre_decline_station_reputation, "declining an unaccepted offer incorrectly damaged reputation")
	qdel(declined)
	GLOB.station_faction_relations.set_reputation(faction_id, old_station_reputation)
	department_ledger.set_reputation(faction_id, old_department_reputation)

/datum/unit_test/dq_contract_event_schema_rejection

/datum/unit_test/dq_contract_event_schema_rejection/Run()
	for(var/event_type in list(
		CONTRACT_EVENT_EVIDENCE_REGISTERED,
		CONTRACT_EVENT_EVIDENCE_CONSUMED,
		CONTRACT_EVENT_DOCUMENT_CREATED,
		CONTRACT_EVENT_DOCUMENT_SIGNED,
		CONTRACT_EVENT_FAX_ACCEPTED,
		CONTRACT_EVENT_MEDICAL_SCAN_CREATED,
		CONTRACT_EVENT_MEDICAL_OBSERVATION_ACCEPTED,
		CONTRACT_EVENT_MEDICAL_ANALYSIS_ACCEPTED,
		CONTRACT_EVENT_RARE_CASE_ACCEPTED,
		CONTRACT_EVENT_CONTRACT_ACTION_ACCEPTED,
		CONTRACT_EVENT_SHIPMENT_DEPARTED,
		CONTRACT_EVENT_ITEM_EXPORTED,
		CONTRACT_EVENT_SERVICE_INVOICE_CHANGED,
		CONTRACT_EVENT_SERVICE_PERIOD_SETTLED,
		CONTRACT_EVENT_MONEY_TRANSFERRED,
		CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED,
		CONTRACT_EVENT_BUDGET_CYCLE_SETTLED,
		CONTRACT_EVENT_MACHINE_RESULT,
		CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED,
		CONTRACT_EVENT_CUSTODY_CHANGED,
		CONTRACT_EVENT_ITEM_PRODUCED,
		CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED,
		CONTRACT_EVENT_INFRASTRUCTURE_DAMAGED,
		CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED,
		CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME,
		CONTRACT_EVENT_SUPPLY_SHORTAGE_DECLARED,
		CONTRACT_EVENT_SUPPLY_SHORTAGE_DELIVERY,
		CONTRACT_EVENT_STAKEHOLDER_APPROVED,
		CONTRACT_EVENT_POWER_SERVICE_CHANGED,
		CONTRACT_EVENT_ATMOS_SERVICE_CHANGED,
		CONTRACT_EVENT_BLOOD_DONATED,
		CONTRACT_EVENT_RESEARCH_MILESTONE,
		CONTRACT_EVENT_CHEMISTRY_RESULT,
		CONTRACT_EVENT_FOOD_CONSUMED,
		CONTRACT_EVENT_CROP_HARVESTED,
		CONTRACT_EVENT_SANITATION_COMPLETED,
		CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED,
		CONTRACT_EVENT_COVERT_MARKET_ACTIVITY,
		CONTRACT_EVENT_COVERT_MARKET_AUDIT,
	))
		TEST_ASSERT(contract_event_schema(event_type), "authoritative event type [event_type] has no validation schema")
	var/rejected_before = SScontracts.events_rejected
	TEST_ASSERT(!emit_contract_event(CONTRACT_EVENT_MACHINE_RESULT, list(
		"department" = DEPARTMENT_ENGINEERING,
		"machine_kind" = "supermatter",
		"machine_id" = "malformed-test-crystal",
		"metrics" = list("eer" = 600, "integrity" = "not numeric"),
	), "malformed-core-event:[world.time]"), "malformed authoritative event bypassed its schema")
	TEST_ASSERT_EQUAL(SScontracts.events_rejected, rejected_before + 1, "schema rejection was not visible in contract diagnostics")
	TEST_ASSERT(!emit_contract_event(CONTRACT_EVENT_SERVICE_INVOICE_CHANGED, list(
		"department" = DEPARTMENT_CIVILIAN,
		"provider_account" = 123,
		"invoice_id" = 1,
		"fact_id" = "malformed-invoice",
		"fact_revision" = 1,
		"metrics" = list("amount" = "not numeric"),
	), "malformed-invoice:[world.time]"), "malformed invoice event bypassed its schema")
	TEST_ASSERT_EQUAL(SScontracts.events_rejected, rejected_before + 2, "expanded schema rejection was not visible in contract diagnostics")
	TEST_ASSERT(emit_contract_event("test-extensible-event", list("arbitrary" = "payload"), "extensible-event:[world.time]"), "an extension-defined event was incorrectly rejected")

/datum/unit_test/dq_contract_personal_offer_reassignment

/datum/unit_test/dq_contract_personal_offer_reassignment/Run()
	var/list/players = list()
	var/list/accounts = list()
	for(var/index in 1 to 2)
		var/datum/money_account/account = new
		account.account_number = 870000 + index
		account.owner_name = "Reassignment Tester [index]"
		GLOB.all_money_accounts += account
		accounts += account
		var/mob/living/carbon/human/player = new(run_loc_floor_bottom_left)
		player.real_name = account.owner_name
		player.job = "Scientist"
		var/datum/mind/player_mind = new("reassignment_test_[index]")
		player_mind.initial_account = account
		player_mind.transfer_to(player)
		player.ensure_faction_reputation().set_reputation(REPUTATION_FACTION_WORKERS_UNION, REPUTATION_NEUTRAL)
		GLOB.player_list |= player
		players += player
	var/datum/contract/outcome/parent = new
	parent.title = "Reassignment parent"
	parent.department = DEPARTMENT_RESEARCH
	parent.reward = 0
	parent.add_requirement(new /datum/contract_requirement/event_count("reassignment-parent-event", 1))
	TEST_ASSERT(parent.accept(), "reassignment parent could not be accepted")
	TEST_ASSERT(parent.offer_linked_personal_contract("research_internal_access"), "initial linked personal offer was not assigned")
	var/datum/contract/personal_outcome/first_offer
	for(var/datum/contract/personal_outcome/candidate in SScontracts.offered_contracts)
		if(candidate.linked_parent_id == parent.id)
			first_offer = candidate
			break
	TEST_ASSERT(first_offer, "initial linked personal offer did not materialize")
	var/first_owner = first_offer.owner_account_number
	TEST_ASSERT(first_offer.decline(), "initial linked personal offer could not be declined")
	var/datum/contract/personal_outcome/reassigned_offer
	for(var/datum/contract/personal_outcome/candidate in SScontracts.offered_contracts)
		if(candidate.linked_parent_id == parent.id && candidate.owner_account_number != first_owner)
			reassigned_offer = candidate
			break
	TEST_ASSERT(reassigned_offer, "declined linked opportunity was not reassigned to another eligible crewmember")
	qdel(reassigned_offer)
	qdel(first_offer)
	qdel(parent)
	for(var/mob/living/carbon/human/player in players)
		GLOB.player_list -= player
		qdel(player.mind)
		qdel(player)
	for(var/datum/money_account/account in accounts)
		GLOB.all_money_accounts -= account
		qdel(account)

/datum/unit_test/dq_contract_negotiated_effects

/datum/unit_test/dq_contract_negotiated_effects/Run()
	var/datum/contract_definition/definition = SScontracts.definitions["experimental_medication_study"]
	var/datum/contract/medical_trial/trial = definition.create_contract(list("cohort" = MEDICAL_TRIAL_COHORT_HEALTHY, "target_metric" = "trauma"))
	TEST_ASSERT(trial, "medical trial for negotiated-effect test was not created")
	TEST_ASSERT(trial.select_negotiation_option("oversight", "independent", "Unit test"), "independent oversight could not be negotiated")
	TEST_ASSERT(trial.select_negotiation_option("identity", "anonymous", "Unit test"), "anonymous identity handling could not be negotiated")
	TEST_ASSERT_EQUAL(trial.negotiated_effect("oversight"), "independent", "clinical oversight negotiation did not produce a gameplay effect")
	TEST_ASSERT_EQUAL(trial.negotiated_effect("identity"), "anonymous", "identity negotiation did not produce a gameplay effect")
	TEST_ASSERT(trial.accept(), "negotiated-effect trial could not be accepted")
	var/mob/living/carbon/human/subject = new(run_loc_floor_bottom_left)
	subject.real_name = "Negotiated Privacy Subject"
	var/datum/contract_subject_identity/identity = SScontracts.subject_identity(subject)
	var/datum/medical_trial_participant/participant = new(identity.id, list(), TRUE, 0)
	participant.dose = MEDICAL_TRIAL_MINIMUM_DOSE
	participant.exposure_time = world.time - MEDICAL_TRIAL_OBSERVATION_TIME
	trial.participants[identity.id] = participant
	var/list/baseline = list("subject_id" = identity.id, "scan_time" = participant.exposure_time, "snapshot" = list(), "operator_account" = 0)
	var/list/trial_markers = list()
	trial_markers[trial.id] = 1
	var/list/followup = list("subject_id" = identity.id, "scan_time" = world.time, "snapshot" = list(), "operator_account" = 0, "trial_markers" = trial_markers)
	TEST_ASSERT(!trial.submit_subject_evidence(identity.id, baseline, followup, 0), "independent-oversight study accepted an unfiled consent record")
	participant.consent_resolution = "filed"
	TEST_ASSERT(trial.submit_subject_evidence(identity.id, baseline, followup, 0), "independent-oversight study rejected an advocate-filed consent record")
	qdel(trial)
	qdel(subject)

/datum/unit_test/dq_social_contract_catalog

/datum/unit_test/dq_social_contract_catalog/Run()
	var/list/definition_ids = list(
		"station_procurement_tender",
		"prototype_field_license",
		"emergency_reconstruction_bond",
		"restorative_settlement_program",
		"corporate_hospitality_commission",
		"interdepartmental_manufacturing_bid",
		"workforce_productivity_compact",
		"clinical_access_program",
		"freight_provenance_auction",
		"publication_patent_dispute",
		"station_development_grant",
		"supply_shortage_response",
	)
	for(var/definition_id in definition_ids)
		var/datum/contract_definition/social/definition = SScontracts.definitions[definition_id]
		TEST_ASSERT(istype(definition), "social contract definition [definition_id] was not registered")
		var/list/context = list()
		if(definition_id == "emergency_reconstruction_bond")
			context["trigger_area"] = "Unit Test Bay"
			context["trigger_damage"] = 100
		if(definition_id == "supply_shortage_response")
			context["shortage_id"] = "unit-test-shortage"
			context["quantity_target"] = 8
			context["variety_target"] = 3
		var/datum/contract/social/contract = definition.create_contract(context)
		TEST_ASSERT(istype(contract), "social contract [definition_id] did not materialize")
		if(!contract)
			continue
		TEST_ASSERT(!contract.validate(), "social contract [definition_id] failed validation: [contract.validate()]")
		TEST_ASSERT(length(contract.requirements) >= 2, "social contract [definition_id] lacks multidimensional outcome evidence")
		TEST_ASSERT(length(contract.stakeholder_roles) >= 2, "social contract [definition_id] lacks multiple stakeholder roles")
		qdel(contract)
	for(var/side_definition_id in list("research_exclusive_export", "emergency_exclusive_contractor", "clinical_priority_coordinator"))
		TEST_ASSERT(SScontracts.definitions[side_definition_id], "social counteroffer definition [side_definition_id] was not registered")

/datum/unit_test/dq_department_program_contract_catalog

/datum/unit_test/dq_department_program_contract_catalog/Run()
	var/list/definition_ids = list(
		"alternative_fuel_demonstration",
		"occupational_recovery_program",
		"blood_reserve_campaign",
		"rehabilitation_return_to_duty",
		"public_health_response",
		"materials_qualification_board",
		"independent_replication_study",
		"applied_chemistry_brief",
		"publication_consortium",
		"contraband_buyback_program",
		"forensic_case_portfolio",
		"community_resolution_docket",
		"emergency_response_accreditation",
		"budget_procurement_challenge",
		"local_supplier_cooperative",
		"materials_recovery_initiative",
		"cold_chain_logistics",
		"station_festival_commission",
		"nutritional_services_campaign",
		"agricultural_cooperative",
		"balanced_operations_charter",
		"interdepartmental_mutual_aid_compact",
		"emergency_continuity_award",
		"workforce_retention_agreement",
		"systems_uptime_accord",
		"automation_logistics_trial",
		"access_safety_audit",
		"human_synthetic_service_compact",
	)
	var/list/expected_departments = list(
		DEPARTMENT_ENGINEERING = 1,
		DEPARTMENT_MEDICAL = 4,
		DEPARTMENT_RESEARCH = 4,
		DEPARTMENT_SECURITY = 4,
		DEPARTMENT_CARGO = 4,
		DEPARTMENT_CIVILIAN = 3,
		DEPARTMENT_COMMAND = 4,
		DEPARTMENT_SYNTHETIC = 4,
	)
	var/list/actual_departments = list()
	var/list/allowed_events = list(
		CONTRACT_EVENT_POWER_SERVICE_CHANGED,
		CONTRACT_EVENT_ATMOS_SERVICE_CHANGED,
		CONTRACT_EVENT_BLOOD_DONATED,
		CONTRACT_EVENT_RESEARCH_MILESTONE,
		CONTRACT_EVENT_CHEMISTRY_RESULT,
		CONTRACT_EVENT_FOOD_CONSUMED,
		CONTRACT_EVENT_CROP_HARVESTED,
		CONTRACT_EVENT_SANITATION_COMPLETED,
		CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED,
		CONTRACT_EVENT_MACHINE_RESULT,
		CONTRACT_EVENT_INFRASTRUCTURE_REPAIRED,
		CONTRACT_EVENT_MEDICAL_TREATMENT_OUTCOME,
		CONTRACT_EVENT_MEDICAL_SCAN_CREATED,
		CONTRACT_EVENT_ITEM_PRODUCED,
		CONTRACT_EVENT_ITEM_EXPORTED,
		CONTRACT_EVENT_SECURITY_DISPOSITION_CHANGED,
		CONTRACT_EVENT_CUSTODY_CHANGED,
		CONTRACT_EVENT_MONEY_TRANSFERRED,
		CONTRACT_EVENT_SUPPLY_ORDER_FULFILLED,
		CONTRACT_EVENT_SERVICE_PERIOD_SETTLED,
		CONTRACT_EVENT_BUDGET_ALLOCATION_CHANGED,
		CONTRACT_EVENT_BUDGET_CYCLE_SETTLED,
	)
	for(var/definition_id in definition_ids)
		var/datum/contract_definition/social/program/definition = SScontracts.definitions[definition_id]
		TEST_ASSERT(istype(definition), "department program definition [definition_id] was not registered through the shared catalog")
		if(!definition)
			continue
		actual_departments[definition.department] = (actual_departments[definition.department] || 0) + 1
		TEST_ASSERT_EQUAL(definition.initial_offers, 1, "department program [definition_id] was not placed in the rotating standing catalog")
		TEST_ASSERT_EQUAL(definition.offer_kind, CONTRACT_OFFER_STANDING, "department program [definition_id] bypassed the generic standing-offer lifecycle")
		var/datum/contract/social/contract = definition.create_contract()
		TEST_ASSERT(istype(contract), "department program [definition_id] could not materialize")
		if(!contract)
			continue
		TEST_ASSERT(!contract.validate(), "department program [definition_id] failed validation: [contract.validate()]")
		TEST_ASSERT(length(contract.requirements) >= 2, "department program [definition_id] lacks independent graded evidence dimensions")
		TEST_ASSERT(length(contract.stakeholder_roles) >= 2, "department program [definition_id] lacks social stakeholder roles")
		for(var/datum/contract_requirement/requirement in contract.requirements)
			TEST_ASSERT(length(requirement.event_types), "department program [definition_id] contains a polling or manually-certified requirement")
			for(var/event_type in requirement.event_types)
				TEST_ASSERT(event_type in allowed_events, "department program [definition_id] uses non-generic event [event_type]")
		qdel(contract)
	for(var/department in expected_departments)
		TEST_ASSERT_EQUAL(actual_departments[department], expected_departments[department], "[department] did not receive exactly four new program contracts")

/datum/unit_test/dq_department_program_event_pipeline

/datum/unit_test/dq_department_program_event_pipeline/Run()
	var/list/event_types = list(
		CONTRACT_EVENT_POWER_SERVICE_CHANGED,
		CONTRACT_EVENT_ATMOS_SERVICE_CHANGED,
		CONTRACT_EVENT_BLOOD_DONATED,
		CONTRACT_EVENT_RESEARCH_MILESTONE,
		CONTRACT_EVENT_CHEMISTRY_RESULT,
		CONTRACT_EVENT_FOOD_CONSUMED,
		CONTRACT_EVENT_CROP_HARVESTED,
		CONTRACT_EVENT_SANITATION_COMPLETED,
		CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED,
	)
	var/datum/contract/social/contract = new
	contract.title = "Department event pipeline test"
	contract.scope = CONTRACT_SCOPE_STATION
	contract.reward = 0
	contract.deadline_duration = 5 MINUTES
	for(var/event_type in event_types)
		var/datum/contract_requirement/event_count/requirement = new(event_type, 1)
		requirement.name = "Pipeline [event_type]"
		contract.add_requirement(requirement)
	TEST_ASSERT(!contract.validate(), "generic department event fixture failed validation")
	TEST_ASSERT(contract.accept(), "generic department event fixture could not activate")

	var/list/events = list(
		list("type" = CONTRACT_EVENT_POWER_SERVICE_CHANGED, "data" = list("fact_id" = "test-power", "fact_revision" = 1, "service_id" = "apc-test", "operational" = TRUE, "metrics" = list("powered_channels" = 3, "cell_percent" = 90, "load" = 100))),
		list("type" = CONTRACT_EVENT_ATMOS_SERVICE_CHANGED, "data" = list("fact_id" = "test-atmos", "fact_revision" = 1, "service_id" = "alarm-test", "danger_level" = 0, "metrics" = list("pressure" = ONE_ATMOSPHERE, "temperature" = T20C))),
		list("type" = CONTRACT_EVENT_BLOOD_DONATED, "data" = list("subject_id" = "donor-test", "container_id" = "bag-test", "blood_type" = "O+", "amount" = 4)),
		list("type" = CONTRACT_EVENT_RESEARCH_MILESTONE, "data" = list("node_id" = "node-test", "node_name" = "Test node", "point_cost" = 1000, "design_count" = 3)),
		list("type" = CONTRACT_EVENT_CHEMISTRY_RESULT, "data" = list("reaction_id" = "reaction-test", "product_id" = "product-test", "amount" = 5, "reactant_count" = 3)),
		list("type" = CONTRACT_EVENT_FOOD_CONSUMED, "data" = list("subject_id" = "diner-test", "item_type" = /obj/item, "food_kind" = "meal", "portion" = 1, "finished" = TRUE)),
		list("type" = CONTRACT_EVENT_CROP_HARVESTED, "data" = list("crop_id" = "crop-test", "crop_name" = "test crop", "yield" = 4, "potency" = 20)),
		list("type" = CONTRACT_EVENT_SANITATION_COMPLETED, "data" = list("target_id" = "floor-test", "method" = "manual_mop", "cleaned_units" = 1)),
		list("type" = CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, "data" = list("bot_id" = "bot-test", "task_kind" = "cargo_delivery", "target_id" = "destination-test", "successful" = TRUE, "work_units" = 1)),
	)
	var/event_index = 0
	for(var/list/event_data as anything in events)
		event_index++
		TEST_ASSERT(emit_contract_event(event_data["type"], event_data["data"], "department-pipeline:[REF(contract)]:[event_index]"), "valid [event_data["type"]] evidence was rejected")
	for(var/datum/contract_requirement/requirement in contract.requirements)
		TEST_ASSERT_EQUAL(requirement.state, CONTRACT_REQUIREMENT_COMPLETE, "[requirement.name] did not dispatch through the generic event bus")
	qdel(contract)

/datum/unit_test/dq_opportunity_broker_guardrails

/datum/unit_test/dq_opportunity_broker_guardrails/Run()
	var/datum/contract_opportunity_rule/rule = SScontracts.opportunity_rules["dq_guardrail_test"]
	TEST_ASSERT(rule, "focused opportunity rule was not registered")
	var/window_key = rule.window_key("station")
	var/offer_key = "opportunity:dq_guardrail_test:station"
	var/datum/contract_opportunity_window/old_window = SScontracts.opportunity_windows[window_key]
	if(old_window)
		SScontracts.opportunity_windows -= window_key
		qdel(old_window)
	SScontracts.opportunity_cooldowns -= window_key

	var/list/fact_a = list("fact_id" = "guardrail-a", "fact_revision" = 1, "actor_account" = 910001, "entity" = "A", "category" = "alpha", "metrics" = list("value" = 100))
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", fact_a, "guardrail-a:1"), "first broker fact was rejected")
	TEST_ASSERT(!emit_contract_event("dq_opportunity_test", fact_a, "guardrail-a:1"), "global occurrence deduplication accepted the same broker event twice")
	TEST_ASSERT(!SScontracts.find_live_offer(offer_key) && !SScontracts.find_candidate(offer_key), "one capped fact generated an opportunity")

	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-a", "fact_revision" = 2, "actor_account" = 910001, "entity" = "A", "category" = "alpha", "metrics" = list("value" = 40)), "guardrail-a:2"), "new fact revision was rejected")
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-a", "fact_revision" = 1, "actor_account" = 910001, "entity" = "A", "category" = "alpha", "metrics" = list("value" = 100)), "guardrail-a:stale"), "stale revision did not reach the broker for its own rejection")
	var/datum/contract_opportunity_window/window = SScontracts.opportunity_windows[window_key]
	var/list/snapshot = window.signal_snapshot(rule.signals[1])
	TEST_ASSERT_EQUAL(snapshot["facts"], 1, "revision replacement duplicated one authoritative fact")
	TEST_ASSERT_EQUAL(snapshot["value"], 40, "stale revision replaced the newer broker fact")

	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-b", "fact_revision" = 1, "actor_account" = 910001, "entity" = "B", "category" = "alpha", "metrics" = list("value" = 100)), "guardrail-b:1"), "second broker fact was rejected")
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-c", "fact_revision" = 1, "actor_account" = 910002, "entity" = "C", "category" = "beta", "metrics" = list("value" = 20)), "guardrail-c:1"), "third broker fact was rejected")
	TEST_ASSERT(!SScontracts.find_live_offer(offer_key) && !SScontracts.find_candidate(offer_key), "per-fact and per-actor caps failed to suppress concentrated activity")

	var/history_before = length(SScontracts.opportunity_history)
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-d", "fact_revision" = 1, "actor_account" = 910002, "entity" = "D", "category" = "beta", "metrics" = list("value" = 30)), "guardrail-d:1"), "qualifying broker fact was rejected")
	TEST_ASSERT(SScontracts.find_live_offer(offer_key) || SScontracts.find_candidate(offer_key), "diverse threshold activity did not generate an opportunity")
	TEST_ASSERT_EQUAL(length(SScontracts.opportunity_history), history_before + 1, "successful broker trigger was not recorded")
	var/datum/contract/generated_offer = SScontracts.find_live_offer(offer_key)
	var/datum/contract_offer_candidate/generated_candidate = SScontracts.find_candidate(offer_key)
	var/list/generated_context = generated_offer ? generated_offer.offer_context : generated_candidate?.context
	var/list/trigger_values = generated_context?["trigger_values"]
	TEST_ASSERT(trigger_values?["entity"]?["A"] && trigger_values?["entity"]?["D"], "broker discarded the stable entities behind its trigger")

	window.latched = FALSE
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-e", "fact_revision" = 1, "actor_account" = 910003, "entity" = "E", "category" = "gamma", "metrics" = list("value" = 50)), "guardrail-e:1"), "cooldown probe event was rejected")
	TEST_ASSERT_EQUAL(length(SScontracts.opportunity_history), history_before + 1, "broker cooldown allowed immediate retriggering")
	window.latched = TRUE

	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-a", "fact_revision" = 3, "fact_active" = FALSE, "metrics" = list("value" = 0)), "guardrail-a:3"), "inactive fact revision was rejected")
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-b", "fact_revision" = 2, "fact_active" = FALSE, "metrics" = list("value" = 0)), "guardrail-b:2"), "second inactive fact revision was rejected")
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-c", "fact_revision" = 2, "fact_active" = FALSE, "metrics" = list("value" = 0)), "guardrail-c:2"), "third inactive fact revision was rejected")
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-d", "fact_revision" = 2, "fact_active" = FALSE, "metrics" = list("value" = 0)), "guardrail-d:2"), "fourth inactive fact revision was rejected")
	TEST_ASSERT(emit_contract_event("dq_opportunity_test", list("fact_id" = "guardrail-e", "fact_revision" = 2, "fact_active" = FALSE, "metrics" = list("value" = 0)), "guardrail-e:2"), "fifth inactive fact revision was rejected")
	TEST_ASSERT(!SScontracts.find_live_offer(offer_key) && !SScontracts.find_candidate(offer_key), "resolved trigger remained available for acceptance")
	SScontracts.opportunity_windows -= window_key
	qdel(window)
	SScontracts.opportunity_cooldowns -= window_key

/datum/unit_test/dq_opportunity_contract_catalog

/datum/unit_test/dq_opportunity_contract_catalog/Run()
	var/list/definition_ids = list(
		"opportunity_grid_restoration",
		"opportunity_atmos_containment",
		"opportunity_clinical_aftercare",
		"opportunity_breakthrough_translation",
		"opportunity_process_scaleup",
		"opportunity_case_review",
		"opportunity_supplier_option",
		"opportunity_procurement_rebate",
		"opportunity_hospitality_expansion",
		"opportunity_crop_forward_order",
		"opportunity_automation_expansion",
		"opportunity_operational_dividend",
	)
	for(var/definition_id in definition_ids)
		var/datum/contract_definition/social/program/opportunity/definition = SScontracts.definitions[definition_id]
		TEST_ASSERT(istype(definition), "opportunity contract [definition_id] was not registered")
		if(!definition)
			continue
		TEST_ASSERT_EQUAL(definition.initial_offers, 0, "opportunity contract [definition_id] leaked into the standing catalog")
		TEST_ASSERT_EQUAL(definition.offer_kind, CONTRACT_OFFER_OPPORTUNITY, "opportunity contract [definition_id] has the wrong lifecycle kind")
		TEST_ASSERT(!definition.auto_replace, "opportunity contract [definition_id] auto-replaces without a fresh gameplay trigger")
		var/list/context = list("trigger_values" = list("service_id" = list("bound-service" = TRUE), "atom_id" = list("bound-asset" = TRUE), "area_name" = list("Bound Area" = TRUE)))
		var/datum/contract/social/contract = definition.create_contract(context)
		TEST_ASSERT(istype(contract), "opportunity contract [definition_id] could not materialize")
		if(!contract)
			continue
		TEST_ASSERT(!contract.validate(), "opportunity contract [definition_id] failed validation: [contract.validate()]")
		TEST_ASSERT(length(contract.requirements) >= 2, "opportunity contract [definition_id] lacks independent outcome dimensions")
		TEST_ASSERT(length(contract.stakeholder_roles) >= 2, "opportunity contract [definition_id] lacks social participation roles")
		if(definition_id in list("opportunity_grid_restoration", "opportunity_atmos_containment"))
			var/bound_requirement_found = FALSE
			for(var/datum/contract_requirement/event_count/requirement in contract.requirements)
				if(length(requirement.filter.allowed_values?["service_id"]))
					bound_requirement_found = TRUE
			TEST_ASSERT(bound_requirement_found, "incident contract [definition_id] was not bound to its triggering services")
		qdel(contract)

	var/rule_count = 0
	for(var/rule_id in SScontracts.opportunity_rules)
		if(rule_id == "dq_guardrail_test")
			continue
		var/datum/contract_opportunity_rule/rule = SScontracts.opportunity_rules[rule_id]
		rule_count++
		TEST_ASSERT(length(rule.signals), "opportunity rule [rule_id] has no authoritative signal lanes")
		if(rule.definition_id)
			TEST_ASSERT(SScontracts.definitions[rule.definition_id], "opportunity rule [rule_id] targets missing definition [rule.definition_id]")
		for(var/datum/contract_opportunity_signal/signal in rule.signals)
			TEST_ASSERT(signal.minimum_facts >= 1, "opportunity rule [rule_id] accepts an empty signal window")
			TEST_ASSERT(signal.maximum_fact_value > 0 || length(signal.diversity_targets) || length(signal.filter.numeric_checks), "opportunity rule [rule_id] lacks value caps, diversity, or authoritative thresholds")
	TEST_ASSERT(rule_count >= 15, "the opportunity broker catalog does not cover the intended breadth of station systems")

/datum/unit_test/dq_covert_investigation_uses_opportunity_broker

/datum/unit_test/dq_covert_investigation_uses_opportunity_broker/Run()
	var/account_number = 919991
	var/offer_key = "covert-investigation:[account_number]"
	var/window_key = "covert_trade_trace|[account_number]"
	var/datum/faction_agent_record/record = new
	record.account_number = account_number
	record.faction_id = REPUTATION_FACTION_SYNDICATE
	record.tier = FACTION_AGENT_TIER_ACCREDITED
	GLOB.station_faction_relations.agent_records["[account_number]"] = record

	TEST_ASSERT(GLOB.station_faction_relations.add_agent_exposure(account_number, REPUTATION_FACTION_SYNDICATE, 15, "Focused trace A", "broker-trace-a"), "first covert trace was rejected")
	TEST_ASSERT(!SScontracts.find_live_offer(offer_key) && !SScontracts.find_candidate(offer_key), "one covert trace generated an investigation")
	TEST_ASSERT(GLOB.station_faction_relations.add_agent_exposure(account_number, REPUTATION_FACTION_SYNDICATE, 15, "Focused trace B", "broker-trace-b"), "second covert trace was rejected")
	TEST_ASSERT(record.counter_offer_queued, "broker threshold did not mark the investigation as queued")
	TEST_ASSERT(SScontracts.find_live_offer(offer_key) || SScontracts.find_candidate(offer_key), "diverse covert traces did not generate an investigation")

	var/datum/contract/investigation = SScontracts.find_live_offer(offer_key)
	if(investigation)
		qdel(investigation)
	var/datum/contract_offer_candidate/investigation_candidate = SScontracts.find_candidate(offer_key)
	if(investigation_candidate)
		SScontracts.withdraw_candidate(investigation_candidate, "Covert broker test cleanup")
	var/datum/contract_opportunity_window/window = SScontracts.opportunity_windows[window_key]
	SScontracts.opportunity_windows -= window_key
	qdel(window)
	SScontracts.opportunity_cooldowns -= window_key
	GLOB.station_faction_relations.agent_records -= "[account_number]"
	qdel(record)

/datum/unit_test/dq_supply_shortage_uses_opportunity_broker

/datum/unit_test/dq_supply_shortage_uses_opportunity_broker/Run()
	var/shortage_id = "focused-shortage"
	var/offer_key = "opportunity:supply_shortage:[shortage_id]"
	var/window_key = "supply_shortage|[shortage_id]"
	TEST_ASSERT(emit_contract_event(CONTRACT_EVENT_SUPPLY_SHORTAGE_DECLARED, list(
		"shortage_id" = shortage_id,
		"quantity_target" = 17,
		"variety_target" = 5,
	), "focused-shortage-declaration"), "authoritative shortage declaration was rejected")
	var/datum/contract/offer = SScontracts.find_live_offer(offer_key)
	var/datum/contract_offer_candidate/candidate = SScontracts.find_candidate(offer_key)
	TEST_ASSERT(offer || candidate, "shortage declaration did not reach the opportunity lifecycle")
	var/list/context = offer ? offer.offer_context : candidate?.context
	TEST_ASSERT_EQUAL(context?["shortage_id"], shortage_id, "broker did not forward the stable shortage identity")
	TEST_ASSERT_EQUAL(context?["quantity_target"], 17, "broker did not forward the shortage quantity")
	TEST_ASSERT_EQUAL(context?["variety_target"], 5, "broker did not forward the shortage breadth")
	if(offer)
		qdel(offer)
	if(candidate)
		SScontracts.withdraw_candidate(candidate, "Supply shortage broker test cleanup")
	var/datum/contract_opportunity_window/window = SScontracts.opportunity_windows[window_key]
	SScontracts.opportunity_windows -= window_key
	qdel(window)
	SScontracts.opportunity_cooldowns -= window_key

/datum/unit_test/dq_social_contract_grading_and_stakeholders

/datum/unit_test/dq_social_contract_grading_and_stakeholders/Run()
	var/datum/contract/social/contract = new
	contract.title = "Graded social test"
	contract.department = DEPARTMENT_CARGO
	contract.scope = CONTRACT_SCOPE_DEPARTMENT
	contract.reward = 1000
	contract.station_share = 0.2
	contract.department_share = 0.5
	contract.contributor_share = 0.3
	contract.deadline_duration = 10 MINUTES
	contract.add_stakeholder_role(new /datum/contract_stakeholder_role("lead", "Cargo lead", "Coordinates the test.", list(DEPARTMENT_CARGO), 1, 1))
	contract.add_stakeholder_role(new /datum/contract_stakeholder_role("partner", "Partner", "Represents another department.", list(DEPARTMENT_RESEARCH, DEPARTMENT_ENGINEERING), 2, 2))
	var/datum/contract_requirement/event_count/value = new("dq-social-grade", 100, null, "value")
	value.name = "Graded value"
	contract.add_requirement(value)
	var/datum/contract_requirement/event_count/breadth = new("dq-social-grade", 4)
	breadth.name = "Graded breadth"
	breadth.unique_field = "category"
	contract.add_requirement(breadth)
	TEST_ASSERT(!contract.validate(), "synthetic social contract failed pre-acceptance validation")
	var/list/accounts = list()
	for(var/index in 1 to 4)
		var/datum/money_account/account = new
		account.account_number = 920000 + index
		account.owner_name = "Social Tester [index]"
		account.department_id = index == 1 ? DEPARTMENT_CARGO : (index <= 3 ? DEPARTMENT_RESEARCH : DEPARTMENT_MEDICAL)
		GLOB.all_money_accounts += account
		accounts += account
	contract.lock_stakeholder_requirements(accounts)
	TEST_ASSERT(contract.accept(), "synthetic social contract could not activate")
	var/datum/money_account/lead = accounts[1]
	var/datum/money_account/partner_one = accounts[2]
	var/datum/money_account/partner_two = accounts[3]
	var/datum/money_account/ineligible = accounts[4]
	TEST_ASSERT(contract.propose_stakeholder(lead, "lead", 3), "eligible Cargo lead could not submit a proposal")
	TEST_ASSERT(!contract.propose_stakeholder(lead, "partner", 1), "one account could seek multiple stakeholder roles")
	TEST_ASSERT(contract.propose_stakeholder(partner_one, "partner", 1), "first eligible partner could not submit a proposal")
	TEST_ASSERT(contract.propose_stakeholder(partner_two, "partner", 2), "second eligible partner could not submit a proposal")
	TEST_ASSERT(!contract.propose_stakeholder(ineligible, "partner", 3), "ineligible department submitted a stakeholder proposal")
	TEST_ASSERT(contract.withdraw_stakeholder(partner_two, "partner"), "partner could not withdraw a pending proposal")
	TEST_ASSERT(contract.propose_stakeholder(partner_two, "partner", 2), "withdrawn partner could not reapply")
	TEST_ASSERT(contract.decide_stakeholder(lead.account_number, "lead", TRUE, "Unit test", 2), "Cargo lead proposal could not be countered")
	var/datum/contract_stakeholder_proposal/lead_proposal = contract.stakeholder_proposals[contract.proposal_key(lead.account_number, "lead")]
	TEST_ASSERT_EQUAL(lead_proposal.status, CONTRACT_STAKEHOLDER_COUNTERED, "different approved weight bypassed stakeholder counteroffer")
	TEST_ASSERT(contract.respond_stakeholder_counter(lead, "lead", TRUE), "Cargo lead could not accept the counteroffer")
	TEST_ASSERT(contract.decide_stakeholder(partner_one.account_number, "partner", TRUE, "Unit test"), "first partner proposal could not be approved")
	TEST_ASSERT(contract.decide_stakeholder(partner_two.account_number, "partner", TRUE, "Unit test"), "second partner proposal could not be approved")
	TEST_ASSERT(!contract.stakeholders_ready(), "approval alone qualified stakeholders without attributable work")
	for(var/index in 1 to 3)
		emit_contract_event("dq-social-grade", list(
			"actor_account" = index == 1 ? lead.account_number : partner_one.account_number,
			"category" = "category-[index]",
			"metrics" = list("value" = 25),
		), "dq-social-grade:[REF(contract)]:[index]")
	contract.record_contribution(partner_two.account_number, 1, "Completed partner review")
	TEST_ASSERT(contract.stakeholders_ready(), "approved stakeholders with attributable work remained incomplete")
	TEST_ASSERT(contract.revoke_stakeholder(partner_two.account_number, "partner", "Unit test"), "approved stakeholder could not be revoked")
	TEST_ASSERT(!contract.stakeholders_ready(), "revoked stakeholder continued satisfying the required slate")
	TEST_ASSERT(contract.propose_stakeholder(partner_two, "partner", 1), "revoked stakeholder could not submit a replacement application")
	TEST_ASSERT(contract.decide_stakeholder(partner_two.account_number, "partner", TRUE, "Unit test"), "replacement stakeholder application could not be approved")
	TEST_ASSERT(contract.stakeholders_ready(), "replacement approval did not retain the stakeholder's attributable work")
	TEST_ASSERT_EQUAL(contract.grade_for_ratio(contract.current_outcome_ratio()), CONTRACT_OUTCOME_SUCCESSFUL, "75% evidence did not project a successful grade")
	TEST_ASSERT(contract.can_finalize_outcome(), "successful evidence and stakeholders did not unlock settlement")
	TEST_ASSERT(contract.finalize_graded_outcome("Unit test"), "graded outcome could not be finalized")
	TEST_ASSERT_EQUAL(contract.outcome_grade, CONTRACT_OUTCOME_SUCCESSFUL, "finalized contract recorded the wrong grade")
	TEST_ASSERT_EQUAL(contract.reward, 800, "successful grade did not apply the 80% reward band")
	TEST_ASSERT_EQUAL(contract.state, CONTRACT_COMPLETED, "finalized graded contract did not complete")
	qdel(contract)
	for(var/datum/money_account/account in accounts)
		GLOB.all_money_accounts -= account
		qdel(account)

/datum/unit_test/dq_social_contract_population_scaling

/datum/unit_test/dq_social_contract_population_scaling/Run()
	var/datum/contract/social/contract = new
	contract.add_stakeholder_role(new /datum/contract_stakeholder_role("crew", "Crew", "Open role.", null, 5, 8))
	contract.add_stakeholder_role(new /datum/contract_stakeholder_role("specialist", "Specialist", "Restricted role.", list(DEPARTMENT_ENGINEERING), 3, 4))
	var/list/accounts = list()
	for(var/index in 1 to 3)
		var/datum/money_account/account = new
		account.account_number = 930000 + index
		account.owner_name = "Scaling Tester [index]"
		account.department_id = index == 1 ? DEPARTMENT_ENGINEERING : DEPARTMENT_CIVILIAN
		accounts += account
	contract.lock_stakeholder_requirements(accounts)
	var/datum/contract_stakeholder_role/specialist = contract.stakeholder_roles["specialist"]
	var/datum/contract_stakeholder_role/crew = contract.stakeholder_roles["crew"]
	TEST_ASSERT_EQUAL(specialist.required_minimum, 1, "population scaling failed to preserve the scarce eligible specialist")
	TEST_ASSERT_EQUAL(crew.required_minimum, 2, "population scaling required more general participants than remained available")
	TEST_ASSERT_EQUAL(specialist.required_minimum + crew.required_minimum, 3, "population scaling assigned one account to multiple required roles")
	qdel(contract)
	for(var/datum/money_account/account in accounts)
		qdel(account)

#endif

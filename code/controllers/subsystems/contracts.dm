SUBSYSTEM_DEF(contracts)
	name = "Contracts"
	flags = SS_NO_FIRE
	var/next_contract_id = 1
	var/next_subject_id = 1
	var/next_evidence_id = 1
	var/next_event_id = 1
	var/list/contracts_by_id
	var/list/offered_contracts
	var/list/active_contracts
	var/list/grace_contracts
	var/list/closed_contracts
	var/list/offer_candidates
	var/list/offer_cooldowns
	var/list/lifecycle_history
	var/next_candidate_id = 1
	var/suppress_offer_reconcile = FALSE
	var/offers_materialized = 0
	var/offers_declined = 0
	var/offers_expired = 0
	var/offers_withdrawn = 0
	var/list/event_subscriptions
	var/list/definitions
	var/list/subject_identities
	var/list/evidence_by_id
	var/list/pending_subject_reconciliations
	/// Bounded diagnostic history of published immutable event snapshots.
	var/list/recent_events
	/// Round-local idempotency ledger, keyed by event type and producer occurrence ID.
	var/list/seen_event_occurrences
	var/list/event_occurrence_order
	var/events_published = 0
	var/events_dispatched = 0
	var/events_matched = 0
	var/events_rejected = 0
	var/events_deduplicated = 0
	var/list/completions_by_definition
	var/list/payout_by_definition
	var/list/custody_started_by_subject
	var/list/custody_last_duration_by_subject
	var/list/custody_last_ended_at_by_subject
	/// Stable record-to-mob bindings established only from an unambiguous live identity.
	var/list/security_record_subject_ids
	var/list/infrastructure_fact_revisions
	var/next_custody_revision = 1
	/// Event-indexed, rolling opportunity detector. Rules observe the same
	/// validated immutable facts as contracts, but never count trigger facts as
	/// completion evidence for the offers they create.
	var/list/opportunity_rules
	var/list/opportunity_rules_by_event
	var/list/opportunity_windows
	var/list/opportunity_cooldowns
	var/list/opportunity_history
	var/opportunity_events_observed = 0
	var/opportunities_triggered = 0
	var/opportunities_suppressed = 0

/datum/controller/subsystem/contracts/Initialize()
	contracts_by_id = list()
	offered_contracts = list()
	active_contracts = list()
	grace_contracts = list()
	closed_contracts = list()
	offer_candidates = list()
	offer_cooldowns = list()
	lifecycle_history = list()
	event_subscriptions = list()
	definitions = list()
	subject_identities = list()
	evidence_by_id = list()
	pending_subject_reconciliations = list()
	recent_events = list()
	seen_event_occurrences = list()
	event_occurrence_order = list()
	completions_by_definition = list()
	payout_by_definition = list()
	custody_started_by_subject = list()
	custody_last_duration_by_subject = list()
	custody_last_ended_at_by_subject = list()
	security_record_subject_ids = list()
	infrastructure_fact_revisions = list()
	RegisterSignal(SSdcs, COMSIG_GLOB_MOB_CREATED, PROC_REF(on_mob_created))
	RegisterSignal(SSdcs, COMSIG_GLOB_MOB_DEATH, PROC_REF(on_mob_death))
	RegisterSignal(SSdcs, COMSIG_GLOB_PAYMENT_ACCOUNT_STATUS, PROC_REF(on_payment_account_status))
	for(var/mob/living/carbon/human/subject in GLOB.human_mob_list)
		watch_contract_subject(subject)
	for(var/definition_type as anything in subtypesof(/datum/contract_definition))
		if(is_abstract(definition_type))
			continue
		var/datum/contract_definition/definition = new definition_type
		definitions[definition.id] = definition
	initialize_opportunity_broker()
	for(var/definition_id in definitions)
		var/datum/contract_definition/definition = definitions[definition_id]
		for(var/offer_index in 1 to definition.initial_offers)
			queue_offer(definition.id, list("offer_index" = offer_index, "defer_materialization" = TRUE), "Initial rotating catalog", "[definition.id]:initial:[offer_index]", rand(20, 60))
	reconcile_offer_board("Initial randomized contract rotation")
	GLOB.alldepartments |= list("VeyMed Clinical Development", "VeyMed Clinical Risk", "Worker's Union Advocacy", "Commercial Acquisitions")
	GLOB.alldepartments |= CONTRACT_FAX_CASE_REGISTRY
	GLOB.alldepartments |= CONTRACT_FAX_ENGINEERING
	return SS_INIT_SUCCESS

/datum/controller/subsystem/contracts/proc/next_infrastructure_revision(atom/source)
	var/key = REF(source)
	var/revision = (infrastructure_fact_revisions[key] || 0) + 1
	infrastructure_fact_revisions[key] = revision
	return revision

/datum/controller/subsystem/contracts/proc/on_mob_created(datum/source, mob/created_mob)
	SIGNAL_HANDLER
	var/mob/living/carbon/human/subject = created_mob
	if(istype(subject))
		watch_contract_subject(subject)

/datum/controller/subsystem/contracts/proc/watch_contract_subject(mob/living/carbon/human/subject)
	RegisterSignal(subject, COMSIG_MOB_MEDICAL_ISSUES_CHANGED, PROC_REF(on_medical_issues_changed), override = TRUE)
	RegisterSignal(subject, COMSIG_AFFLICTION_SEVERITY_CHANGED, PROC_REF(on_affliction_severity_changed), override = TRUE)
	RegisterSignal(subject, COMSIG_BODY_AFFLICTIONS_CHANGED, PROC_REF(on_body_afflictions_changed), override = TRUE)
	RegisterSignal(subject, COMSIG_LIVING_REVIVE, PROC_REF(on_medical_subject_revived), override = TRUE)
	RegisterSignal(subject, COMSIG_MOB_LOGIN, PROC_REF(on_medical_subject_availability), override = TRUE)
	RegisterSignal(subject, COMSIG_MOB_LOGOUT, PROC_REF(on_medical_subject_availability), override = TRUE)
	RegisterSignal(subject, COMSIG_MOB_MIND_TRANSFERRED_INTO, PROC_REF(on_medical_subject_availability), override = TRUE)
	RegisterSignal(subject, COMSIG_MOB_MIND_TRANSFERRED_OUT_OF, PROC_REF(on_medical_subject_availability), override = TRUE)
	RegisterSignal(subject, COMSIG_MOVABLE_MOVED, PROC_REF(on_custody_input_changed), override = TRUE)
	RegisterSignal(subject, COMSIG_MOB_EQUIPPED_ITEM, PROC_REF(on_custody_input_changed), override = TRUE)
	RegisterSignal(subject, COMSIG_MOB_UNEQUIPPED_ITEM, PROC_REF(on_custody_input_changed), override = TRUE)
	refresh_physical_custody(subject)

/datum/controller/subsystem/contracts/proc/on_custody_input_changed(mob/living/carbon/human/subject)
	SIGNAL_HANDLER
	refresh_physical_custody(subject)

/datum/controller/subsystem/contracts/proc/is_physically_custodied(mob/living/carbon/human/subject)
	if(!subject?.mind || subject.stat == DEAD)
		return FALSE
	var/turf/location = get_turf(subject)
	if(!istype(location?.loc, /area/security/brig))
		return FALSE
	// Custody means the prisoner has actually been stripped of credentials.
	// Recursive contents include IDs inside PDAs, wallets, boxes, and backpacks.
	if(length(subject.get_all_contents_type(/obj/item/card/id)))
		return FALSE
	return TRUE

/datum/controller/subsystem/contracts/proc/refresh_physical_custody(mob/living/carbon/human/subject)
	if(QDELETED(subject))
		return FALSE
	var/datum/contract_subject_identity/identity = subject_identity(subject)
	if(!identity)
		return FALSE
	var/key = identity.id
	var/started_at = custody_started_by_subject[key] || 0
	var/active = is_physically_custodied(subject)
	if(active && !started_at)
		var/start_revision = next_custody_revision++
		custody_started_by_subject[key] = world.time
		emit_contract_event(CONTRACT_EVENT_CUSTODY_CHANGED, list(
			"subject_id" = key,
			"subject_name" = subject.real_name,
			"fact_id" = "custody:[key]",
			"fact_revision" = start_revision,
			"fact_active" = TRUE,
			"metrics" = list("custody_duration" = 0),
		), "custody:[key]:[start_revision]:start", subject, null, subject)
		return TRUE
	if(!active && started_at)
		var/end_revision = next_custody_revision++
		var/duration = max(0, world.time - started_at)
		custody_started_by_subject -= key
		custody_last_duration_by_subject[key] = duration
		custody_last_ended_at_by_subject[key] = world.time
		emit_contract_event(CONTRACT_EVENT_CUSTODY_CHANGED, list(
			"subject_id" = key,
			"subject_name" = subject.real_name,
			"fact_id" = "custody:[key]",
			"fact_revision" = end_revision,
			"fact_active" = FALSE,
			"metrics" = list("custody_duration" = duration),
		), "custody:[key]:[end_revision]:end", subject, null, subject)
		return TRUE
	return FALSE

/datum/controller/subsystem/contracts/proc/find_subject_for_record(record_id, subject_name) as /mob/living/carbon/human
	var/bound_subject_id = security_record_subject_ids["[record_id]"]
	if(bound_subject_id)
		for(var/mob/living/carbon/human/bound_subject in GLOB.human_mob_list)
			if(!QDELETED(bound_subject) && subject_identity(bound_subject)?.id == bound_subject_id)
				return bound_subject
		return
	var/list/candidates = list()
	for(var/mob/living/carbon/human/subject in GLOB.human_mob_list)
		if(QDELETED(subject) || !subject.mind)
			continue
		if(subject_name && subject.real_name == subject_name)
			candidates += subject
	if(length(candidates) != 1)
		return
	var/mob/living/carbon/human/resolved = candidates[1]
	var/datum/contract_subject_identity/identity = subject_identity(resolved)
	if(record_id && identity)
		security_record_subject_ids["[record_id]"] = identity.id
	return resolved

/datum/controller/subsystem/contracts/proc/physical_custody_snapshot(record_id, subject_name)
	var/mob/living/carbon/human/subject = find_subject_for_record(record_id, subject_name)
	if(!subject)
		return list("verified" = FALSE, "duration" = 0)
	refresh_physical_custody(subject)
	var/datum/contract_subject_identity/identity = subject_identity(subject)
	var/started_at = custody_started_by_subject[identity.id] || 0
	var/duration = started_at ? max(0, world.time - started_at) : (custody_last_duration_by_subject[identity.id] || 0)
	var/ended_at = custody_last_ended_at_by_subject[identity.id] || 0
	var/turf/current_location = get_turf(subject)
	var/released_alive_outside_brig = subject.stat != DEAD && !istype(current_location?.loc, /area/security/brig)
	var/recently_released = released_alive_outside_brig && ended_at && world.time - ended_at <= 2 MINUTES
	return list(
		"verified" = !!started_at || recently_released,
		"active" = !!started_at,
		"duration" = duration,
		"subject_id" = identity.id,
		"subject_name" = subject.real_name,
	)

/datum/controller/subsystem/contracts/proc/on_payment_account_status(datum/source, datum/money_account/account)
	SIGNAL_HANDLER
	if(!account || account.suspended)
		return
	// Requirements can already be complete when a payout was deferred. Account
	// reactivation is the authoritative dependency change that makes it viable.
	for(var/datum/contract/contract in (active_contracts + grace_contracts).Copy())
		contract.reconcile_completion()

/datum/controller/subsystem/contracts/proc/record_contract_completion(datum/contract/contract)
	if(!contract?.definition_id)
		return
	completions_by_definition[contract.definition_id] = (completions_by_definition[contract.definition_id] || 0) + 1
	payout_by_definition[contract.definition_id] = (payout_by_definition[contract.definition_id] || 0) + contract.reward

/datum/controller/subsystem/contracts/proc/maybe_queue_reputation_followup(datum/contract/contract)
	var/datum/contract/outcome/outcome = contract
	var/datum/contract_definition/outcome/definition = definitions[contract?.definition_id]
	if(!istype(outcome) || !istype(definition))
		return FALSE
	var/station_standing = get_station_faction_reputation(contract.issuer_faction)
	var/department_standing = contract.department ? get_department_faction_reputation(contract.department, contract.issuer_faction) : station_standing
	var/standing = isnum(department_standing) ? round((station_standing + department_standing) / 2) : station_standing
	if(standing < definition.followup_reputation_threshold)
		return FALSE
	var/list/context = contract.offer_context ? deepCopyList(contract.offer_context) : list()
	context["offer_kind"] = CONTRACT_OFFER_OPPORTUNITY
	context["followup"] = TRUE
	switch(definition.id)
		if("supermatter_performance")
			context["eer_target"] = round(outcome.primary_target * 1.15)
			context["integrity_target"] = outcome.secondary_target
			context["duration"] = outcome.outcome_duration + 30 SECONDS
		if("research_export_portfolio", "cargo_freight_portfolio")
			context["value_target"] = round(outcome.primary_target * 1.25)
			context["variety_target"] = outcome.secondary_target + 1
		if("service_hospitality_census")
			context["revenue_target"] = round(outcome.primary_target * 1.25)
			context["customer_target"] = outcome.secondary_target + 1
		if("security_case_resolution")
			context["case_target"] = outcome.primary_target + 1
			context["custody_duration"] = outcome.outcome_duration
		if("command_budget_mandate")
			context["allocation_target"] = round(outcome.primary_target * 1.15)
			context["department_target"] = outcome.secondary_target
			context["minimum_allocation"] = outcome.outcome_duration
		else
			return FALSE
	var/completion_number = completions_by_definition[definition.id] || 0
	return !!queue_offer(definition.id, context, "Allied standing unlocked a higher-tier follow-up commission", "followup:[definition.id]:[completion_number]", 90)

/datum/controller/subsystem/contracts/proc/on_medical_subject_availability(mob/living/carbon/human/subject)
	SIGNAL_HANDLER
	queue_medical_subject_reconciliation(subject)

/datum/controller/subsystem/contracts/proc/queue_medical_subject_reconciliation(mob/living/carbon/human/subject)
	var/key = subject ? REF(subject) : "global"
	if(pending_subject_reconciliations[key])
		return
	pending_subject_reconciliations[key] = TRUE
	addtimer(CALLBACK(src, PROC_REF(reconcile_subject_availability), subject, key), 0)

/datum/controller/subsystem/contracts/proc/reconcile_subject_availability(mob/living/carbon/human/subject, key)
	pending_subject_reconciliations -= key
	if(QDELETED(subject))
		reconcile_medical_trial_offers()
		return
	if(subject.mind)
		subject_identity(subject)
	subject.contract_medical_indications = null
	subject.refresh_contract_medical_eligibility()
	reconcile_medical_trial_offers()
	reconcile_offer_eligibility("Crew availability changed")
	reconcile_medical_trial_side_contracts()
	consider_rare_medical_case(subject)

/datum/controller/subsystem/contracts/proc/on_medical_issues_changed(mob/living/carbon/human/subject)
	SIGNAL_HANDLER
	subject.refresh_contract_medical_eligibility()
	consider_rare_medical_case(subject)

/datum/controller/subsystem/contracts/proc/on_mob_death(datum/source, mob/living/dead_mob, gibbed)
	SIGNAL_HANDLER
	if(ishuman(dead_mob))
		var/mob/living/carbon/human/dead_subject = dead_mob
		refresh_physical_custody(dead_subject)
		reconcile_medical_trial_offers()
		withdraw_rare_case_offers(dead_mob)

/datum/controller/subsystem/contracts/proc/on_medical_subject_revived(mob/living/carbon/human/subject)
	SIGNAL_HANDLER
	subject.contract_medical_indications = null
	subject.refresh_contract_medical_eligibility()

/datum/controller/subsystem/contracts/proc/reconcile_medical_trial_offers(list/availability = medical_trial_station_availability())
	var/list/viable = medical_trial_viable_conditional_protocols(availability)
	var/datum/contract/medical_trial/conditional_offer
	var/has_active_conditional = FALSE
	for(var/datum/contract/medical_trial/trial in active_contracts + grace_contracts)
		if(trial.conditional_offer)
			if(!length(trial.participants) && !medical_trial_protocol_is_viable(trial.profile.cohort, trial.profile.target_metric, availability))
				trial.withdraw("The qualifying cohort was no longer available before enrollment; no penalty was assessed.")
				continue
			has_active_conditional = TRUE
			break
	for(var/datum/contract/medical_trial/trial in offered_contracts.Copy())
		if(!trial.conditional_offer)
			continue
		if(!medical_trial_protocol_is_viable(trial.profile.cohort, trial.profile.target_metric, availability))
			trial.withdraw("The qualifying cohort is no longer present.")
			continue
		conditional_offer = trial
	var/has_conditional_candidate = FALSE
	for(var/datum/contract_offer_candidate/candidate in offer_candidates.Copy())
		if(candidate.definition_id != "experimental_medication_study" || !candidate.context["conditional_offer"])
			continue
		if(!medical_trial_protocol_is_viable(candidate.context["cohort"], candidate.context["target_metric"], availability))
			withdraw_candidate(candidate, "The qualifying cohort is no longer present.")
			continue
		has_conditional_candidate = TRUE
	if(has_active_conditional || conditional_offer || has_conditional_candidate || !length(viable))
		return
	var/list/protocol = pick(viable)
	queue_offer("experimental_medication_study", list(
		"cohort" = protocol["cohort"],
		"target_metric" = protocol["target_metric"],
		"conditional_offer" = TRUE,
		"eligibility_confirmed" = TRUE,
		"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
	), "A qualifying patient cohort became available", "experimental_medication_study:conditional", 80)

/datum/controller/subsystem/contracts/proc/ensure_routine_medical_offer()
	queue_offer("experimental_medication_study", list("offer_kind" = CONTRACT_OFFER_STANDING), "Routine VeyMed study catalog", "experimental_medication_study:initial:1")

/datum/controller/subsystem/contracts/proc/on_contract_closed(datum/contract/contract)
	handle_contract_closed(contract)
	if(istype(contract, /datum/contract/faction_agent))
		handle_agent_contract_closed(contract)
	else if(contract.definition_id == "covert_market_investigation")
		handle_covert_market_investigation_closed(contract)
	var/datum/contract/personal_outcome/personal_outcome = contract
	if(istype(personal_outcome) && !personal_outcome.accepted_at && (personal_outcome.closure_code in list(CONTRACT_CLOSE_DECLINED, CONTRACT_CLOSE_EXPIRED, CONTRACT_CLOSE_INELIGIBLE)))
		var/datum/contract/outcome/linked_parent = contracts_by_id[personal_outcome.linked_parent_id]
		if(istype(linked_parent) && linked_parent.state == CONTRACT_ACTIVE)
			linked_parent.offer_linked_personal_contract(personal_outcome.definition_id, null, personal_outcome.owner_account_number)
	var/datum/contract/medical_trial_personal/medical_side = contract
	if(istype(medical_side) && !medical_side.accepted_at && (medical_side.closure_code in list(CONTRACT_CLOSE_DECLINED, CONTRACT_CLOSE_EXPIRED, CONTRACT_CLOSE_INELIGIBLE)))
		var/datum/contract/medical_trial/linked_trial = contracts_by_id[medical_side.linked_trial_id]
		if(istype(linked_trial) && linked_trial.state == CONTRACT_ACTIVE)
			if(medical_side.definition_id == "medical_trial_espionage")
				medical_trial_offer_industrial_espionage(linked_trial, medical_side.owner_account_number)
			else if(medical_side.definition_id == "medical_trial_autopsy")
				var/datum/medical_trial_participant/participant = linked_trial.participants?[medical_side.target_ref]
				if(participant)
					medical_trial_offer_corpse_autopsy(linked_trial, participant, medical_side.owner_account_number)
	if(istype(contract, /datum/contract/outcome))
		// Unaccepted linked counter-offers only make sense while their public
		// parent is live. Already-accepted personal agreements remain binding.
		reconcile_offer_eligibility("A linked public contract closed")
	if(contract.definition_id == "experimental_medication_study")
		var/datum/contract/medical_trial/trial = contract
		if(istype(trial) && trial.conditional_offer)
			reconcile_medical_trial_offers()

/datum/controller/subsystem/contracts/proc/register_contract(datum/contract/contract)
	if(!contract || contract.id)
		return FALSE
	contract.id = "DQ-[next_contract_id++]"
	contracts_by_id[contract.id] = contract
	offered_contracts += contract
	return TRUE

/datum/controller/subsystem/contracts/proc/unregister_contract(datum/contract/contract)
	if(!contract)
		return
	contracts_by_id -= contract.id
	offered_contracts -= contract
	active_contracts -= contract
	grace_contracts -= contract
	closed_contracts -= contract
	for(var/event_type in event_subscriptions)
		event_subscriptions[event_type] -= contract

/datum/controller/subsystem/contracts/proc/set_contract_state(datum/contract/contract, old_state, new_state)
	if(!contract)
		return
	if(old_state == CONTRACT_OFFERED)
		offered_contracts -= contract
	else if(old_state == CONTRACT_ACTIVE)
		active_contracts -= contract
	else if(old_state == CONTRACT_GRACE)
		grace_contracts -= contract
	if(new_state == CONTRACT_OFFERED)
		offered_contracts |= contract
	else if(new_state == CONTRACT_ACTIVE)
		active_contracts |= contract
	else if(new_state == CONTRACT_GRACE)
		grace_contracts |= contract
	else
		closed_contracts |= contract

/datum/controller/subsystem/contracts/proc/subscribe(datum/contract/contract, event_type)
	if(!contract || !istext(event_type) || !length(event_type))
		return FALSE
	LAZYINITLIST(event_subscriptions[event_type])
	event_subscriptions[event_type] |= contract
	return TRUE

/datum/controller/subsystem/contracts/proc/has_event_subscribers(event_type)
	return !!length(event_subscriptions?[event_type])

/datum/controller/subsystem/contracts/proc/unsubscribe(datum/contract/contract, event_type)
	if(!contract || !event_subscriptions[event_type])
		return
	event_subscriptions[event_type] -= contract
	if(!length(event_subscriptions[event_type]))
		event_subscriptions -= event_type

/datum/controller/subsystem/contracts/proc/publish_event(datum/contract_event/event)
	if(!event?.is_valid())
		events_rejected++
		qdel(event)
		return FALSE
	if(event.occurrence_id)
		var/dedup_key = "[event.event_type]|[event.occurrence_id]"
		if(seen_event_occurrences[dedup_key])
			events_deduplicated++
			qdel(event)
			return FALSE
		seen_event_occurrences[dedup_key] = TRUE
		event_occurrence_order += dedup_key
		if(length(event_occurrence_order) > CONTRACT_EVENT_DEDUP_LIMIT)
			var/expired_key = event_occurrence_order[1]
			event_occurrence_order.Cut(1, 2)
			seen_event_occurrences -= expired_key
	event.id = "DQ-CE-[next_event_id++]"
	event.occurred_at = world.time
	events_published++
	recent_events += event
	if(length(recent_events) > CONTRACT_EVENT_HISTORY_LIMIT)
		var/datum/contract_event/expired_event = recent_events[1]
		recent_events.Cut(1, 2)
		qdel(expired_event)
	observe_opportunity_event(event)
	var/list/subscribers = event_subscriptions[event.event_type]
	var/list/listeners = subscribers?.Copy()
	for(var/datum/contract/contract in listeners)
		if(!(contract.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
			continue
		events_dispatched++
		if(contract.receive_event(event))
			events_matched++
	return event.id

/// Incident response begins when the incident happens, not when a head reaches
/// a console. Replay only authenticated events after the triggering fact; the
/// trigger itself remains ineligible and every requirement's normal identity,
/// scope, and deduplication rules still apply.
/datum/controller/subsystem/contracts/proc/replay_post_trigger_events(datum/contract/contract)
	var/trigger_event_id = contract?.offer_context?["trigger_event_id"]
	var/triggered_at = contract?.offer_context?["opportunity_triggered_at"]
	if(!contract || !trigger_event_id || !isnum(triggered_at))
		return FALSE
	var/trigger_in_history = FALSE
	for(var/datum/contract_event/event in recent_events)
		if(event.id == trigger_event_id)
			trigger_in_history = TRUE
			break
	var/past_trigger = !trigger_in_history
	var/replayed = FALSE
	for(var/datum/contract_event/event in recent_events)
		if(!past_trigger)
			if(event.id == trigger_event_id)
				past_trigger = TRUE
			continue
		if(event.id == trigger_event_id || event.occurred_at < triggered_at || !(event.event_type in event_subscriptions))
			continue
		var/list/subscribers = event_subscriptions[event.event_type]
		if(!(contract in subscribers) || !(contract.state in list(CONTRACT_ACTIVE, CONTRACT_GRACE)))
			continue
		events_dispatched++
		if(contract.receive_event(event))
			events_matched++
			replayed = TRUE
	if(replayed)
		contract.audit(CONTRACT_AUDIT_PROGRESS, "Authenticated response work performed after the originating incident was credited at acceptance.")
	return replayed

/// Compatibility entry point for older producers while they migrate to typed
/// event construction. The resulting event still receives full validation,
/// deduplication, stable metadata, and indexed dispatch.
/datum/controller/subsystem/contracts/proc/emit_event(event_type, list/context, occurrence_id, atom/source, mob/living/actor, mob/living/subject)
	return emit_contract_event(event_type, context, occurrence_id, source, actor, subject)

/datum/controller/subsystem/contracts/proc/event_observability()
	var/subscription_count = 0
	for(var/event_type in event_subscriptions)
		subscription_count += length(event_subscriptions[event_type])
	return list(
		"published" = events_published,
		"dispatched" = events_dispatched,
		"matched" = events_matched,
		"rejected" = events_rejected,
		"deduplicated" = events_deduplicated,
		"event_types" = length(event_subscriptions),
		"subscriptions" = subscription_count,
		"recent" = length(recent_events),
		"opportunity_events" = opportunity_events_observed,
		"opportunities_triggered" = opportunities_triggered,
		"opportunities_suppressed" = opportunities_suppressed,
		"opportunity_windows" = length(opportunity_windows),
	)

/datum/controller/subsystem/contracts/proc/requirement_rows(datum/contract/contract)
	var/list/rows = list()
	for(var/datum/contract_requirement/requirement in contract.requirements)
		rows.Add(list(list(
			"name" = requirement.name,
			"description" = requirement.description,
			"state" = requirement.state,
			"required" = requirement.required,
			"progress" = requirement.progress,
			"target" = requirement.target,
			"progress_text" = requirement.progress_text(),
			"stages" = requirement.ui_stage_rows(),
		)))
	return rows

/datum/controller/subsystem/contracts/proc/negotiation_rows(datum/contract/contract)
	var/list/rows = list()
	for(var/clause_id in contract.negotiation_clauses)
		var/datum/contract_negotiation_clause/clause = contract.negotiation_clauses[clause_id]
		var/list/options = list()
		for(var/option_id in clause.options)
			var/datum/contract_clause_option/option = clause.options[option_id]
			var/station_reputation = option.station_reputation_delta
			var/list/raw_other_reputation = LAZYACCESS(option.effects, "other_faction_reputation")
			var/list/distinct_other_reputation = raw_other_reputation?.Copy()
			var/issuer_reputation = distinct_other_reputation?[contract.issuer_faction]
			if(isnum(issuer_reputation))
				station_reputation += issuer_reputation
				distinct_other_reputation -= contract.issuer_faction
			var/list/other_reputation = faction_reputation_rows(distinct_other_reputation)
			options.Add(list(list(
				"id" = option.id,
				"title" = option.title,
				"description" = option.description,
				"station_money" = option.station_reward_delta,
				"department_money" = option.department_reward_delta,
				"staff_money" = option.staff_reward_delta,
				"station_reputation" = station_reputation,
				"department_reputation" = option.department_reputation_delta,
				"staff_reputation" = option.staff_reputation_delta,
				"deadline_minutes" = option.deadline_delta / (1 MINUTE),
				"other_reputation" = other_reputation,
			)))
		rows.Add(list(list(
			"id" = clause.id,
			"title" = clause.title,
			"description" = clause.description,
			"selected" = contract.negotiation_selections[clause.id],
			"options" = options,
		)))
	return rows

/datum/controller/subsystem/contracts/proc/faction_reputation_rows(list/reputation_changes)
	var/list/rows = list()
	for(var/faction_id in reputation_changes)
		var/change = reputation_changes[faction_id]
		if(!isnum(change) || !change)
			continue
		var/datum/reputation_faction/faction = GLOB.reputation_factions[faction_id]
		rows.Add(list(list(
			"faction" = faction?.short_name || faction_id,
			"acronym" = faction?.acronym || "EXT",
			"color" = faction?.color || "#6ba4c7",
			"amount" = change,
		)))
	return rows

/datum/controller/subsystem/contracts/proc/contract_row(mob/living/user, datum/contract/contract, can_accept = FALSE)
	var/datum/reputation_faction/faction = GLOB.reputation_factions[contract.issuer_faction]
	var/list/row = list(
		"id" = contract.id,
		"title" = contract.title,
		"description" = contract.description,
		"scope" = contract.scope,
		"state" = contract.state,
		"issuer" = contract.issuer_name,
		"issuer_faction" = faction?.short_name || contract.issuer_name,
		"issuer_acronym" = faction?.acronym || "EXT",
		"issuer_color" = faction?.color || "#6ba4c7",
		"department" = contract.department,
		"reward" = contract.reward,
		"paid_reward" = contract.paid_reward,
		"reward_distribution" = list(
			"station" = contract.negotiated_station_amount(),
			"department" = contract.negotiated_department_amount(),
			"staff" = contract.negotiated_staff_amount(),
		),
		"reputation_distribution" = list(
			"station" = contract.station_reputation_reward,
			"department" = contract.department_reputation_reward,
			"staff" = contract.personal_reputation_reward,
		),
		"secondary_reputation" = faction_reputation_rows(contract.secondary_faction_reputation_rewards),
		"standing_score" = contract.standing_score,
		"standing_tier" = contract.standing_tier,
		"standing_reward_modifier" = contract.standing_reward_modifier,
		"term_class" = contract.deadline_duration <= CONTRACT_SHORT_TERM_CUTOFF ? CONTRACT_TERM_SHORT : CONTRACT_TERM_LONG,
		"negotiation_locked" = contract.negotiation_locked,
		"negotiation_clauses" = negotiation_rows(contract),
		"deadline" = contract.deadline,
		"offer_expires_at" = contract.offer_expires_at,
		"offer_time_remaining" = contract.offer_expires_at > world.time ? DisplayTimeText(contract.offer_expires_at - world.time, 1) : null,
		"accepted_at" = contract.accepted_at,
		"deadline_remaining" = contract.deadline > world.time ? DisplayTimeText(contract.deadline - world.time, 1) : null,
		"can_accept" = can_accept && contract.state == CONTRACT_OFFERED,
		"can_decline" = can_accept && contract.state == CONTRACT_OFFERED,
		"offer_kind" = contract.offer_kind,
		"closure_code" = contract.closure_code,
		"grace_time_remaining" = contract.grace_until > world.time ? DisplayTimeText(contract.grace_until - world.time, 1) : null,
		"requirements" = requirement_rows(contract),
		"contributor_count" = length(contract.contributions),
	)
	row["details"] = contract.ui_details(user)
	return row

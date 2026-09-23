/// One eligible offer waiting for capacity on its station, department, or
/// personal board. Candidates are deliberately cheaper than live contracts:
/// no timers, requirements, physical supplies, or event subscriptions exist
/// until the lifecycle engine admits them.
/datum/contract_offer_candidate
	var/id
	var/definition_id
	var/offer_key
	var/board_key
	var/offer_kind
	var/reason
	var/created_at
	var/expires_at
	var/priority = 50
	var/list/context

/datum/contract_offer_candidate/New(_id, _definition_id, _offer_key, _board_key, _offer_kind, _reason, list/_context, _expires_at, _priority)
	. = ..()
	id = _id
	definition_id = _definition_id
	offer_key = _offer_key
	board_key = _board_key
	offer_kind = _offer_kind
	reason = _reason
	created_at = world.time
	expires_at = _expires_at
	priority = _priority
	context = _context ? deepCopyList(_context) : list()

/datum/contract_offer_candidate/Destroy()
	context = null
	return ..()

/datum/contract_lifecycle_entry
	var/time
	var/action
	var/contract_id
	var/definition_id
	var/offer_key
	var/board_key
	var/reason

/datum/contract_lifecycle_entry/New(_action, _contract_id, _definition_id, _offer_key, _board_key, _reason)
	. = ..()
	time = world.time
	action = _action
	contract_id = _contract_id
	definition_id = _definition_id
	offer_key = _offer_key
	board_key = _board_key
	reason = _reason

/datum/controller/subsystem/contracts/proc/record_lifecycle(action, datum/contract/contract, datum/contract_offer_candidate/candidate, reason)
	var/datum/contract_lifecycle_entry/entry = new(
		action,
		contract?.id,
		contract?.definition_id || candidate?.definition_id,
		contract?.offer_key || candidate?.offer_key,
		contract?.board_key || candidate?.board_key,
		reason,
	)
	lifecycle_history += entry
	if(length(lifecycle_history) > CONTRACT_LIFECYCLE_HISTORY_LIMIT)
		var/datum/contract_lifecycle_entry/expired = lifecycle_history[1]
		lifecycle_history.Cut(1, 2)
		qdel(expired)

/datum/controller/subsystem/contracts/proc/find_live_offer(offer_key) as /datum/contract
	if(!offer_key)
		return null
	for(var/datum/contract/contract in offered_contracts)
		if(contract.offer_key == offer_key)
			return contract
	for(var/datum/contract/contract in active_contracts)
		if(contract.offer_key == offer_key)
			return contract
	for(var/datum/contract/contract in grace_contracts)
		if(contract.offer_key == offer_key)
			return contract

/datum/controller/subsystem/contracts/proc/find_candidate(offer_key) as /datum/contract_offer_candidate
	for(var/datum/contract_offer_candidate/candidate in offer_candidates)
		if(candidate.offer_key == offer_key)
			return candidate

/datum/controller/subsystem/contracts/proc/withdraw_candidate(datum/contract_offer_candidate/candidate, reason = "The triggering opportunity ended before publication.")
	if(!candidate || !(candidate in offer_candidates))
		return FALSE
	record_lifecycle("candidate-withdrawn", null, candidate, reason)
	offer_candidates -= candidate
	qdel(candidate)
	return TRUE

/datum/controller/subsystem/contracts/proc/board_limit(datum/contract_definition/definition)
	switch(definition.scope)
		if(CONTRACT_SCOPE_STATION)
			return CONTRACT_BOARD_STATION_LIMIT
		if(CONTRACT_SCOPE_DEPARTMENT)
			return CONTRACT_BOARD_DEPARTMENT_LIMIT
		if(CONTRACT_SCOPE_PERSONAL)
			return CONTRACT_BOARD_PERSONAL_LIMIT
	return 0

/datum/controller/subsystem/contracts/proc/definition_term_class(datum/contract_definition/definition)
	return definition.expected_duration <= CONTRACT_SHORT_TERM_CUTOFF ? CONTRACT_TERM_SHORT : CONTRACT_TERM_LONG

/datum/controller/subsystem/contracts/proc/definition_live_count(definition_id)
	var/count = 0
	for(var/datum/contract/contract in offered_contracts)
		if(contract.definition_id == definition_id)
			count++
	for(var/datum/contract/contract in active_contracts)
		if(contract.definition_id == definition_id)
			count++
	for(var/datum/contract/contract in grace_contracts)
		if(contract.definition_id == definition_id)
			count++
	return count

/datum/controller/subsystem/contracts/proc/candidate_has_capacity(datum/contract_offer_candidate/candidate, datum/contract_definition/definition)
	if(!candidate?.board_key || !definition)
		return FALSE
	if(definition_live_count(definition.id) >= definition.max_simultaneous)
		return FALSE
	var/board_count = 0
	var/faction_count = 0
	var/same_term_count = 0
	var/candidate_term = definition_term_class(definition)
	for(var/datum/contract/contract in offered_contracts)
		if(contract.board_key != candidate.board_key)
			continue
		board_count++
		if(definition.issuer_faction && contract.issuer_faction == definition.issuer_faction)
			faction_count++
		var/datum/contract_definition/offered_definition = definitions[contract.definition_id]
		if(offered_definition && definition_term_class(offered_definition) == candidate_term)
			same_term_count++
	if(board_count >= board_limit(definition))
		return FALSE
	if(definition.issuer_faction && faction_count >= CONTRACT_BOARD_FACTION_LIMIT)
		return FALSE
	// The second standing slot must complement the first. Time-sensitive
	// opportunities may still displace a standing offer through priority.
	if(candidate.offer_kind == CONTRACT_OFFER_STANDING && board_count && same_term_count == board_count)
		return FALSE
	return TRUE

/datum/controller/subsystem/contracts/proc/make_priority_capacity(datum/contract_offer_candidate/candidate, datum/contract_definition/definition)
	if(candidate_has_capacity(candidate, definition))
		return TRUE
	var/datum/contract/displaced
	var/displaced_priority = INFINITY
	for(var/datum/contract/offer in offered_contracts)
		if(offer.board_key != candidate.board_key || offer.offer_kind != CONTRACT_OFFER_STANDING)
			continue
		var/offer_priority = offer.offer_context?["offer_priority"] || 50
		if(offer_priority >= candidate.priority || offer_priority >= displaced_priority)
			continue
		displaced = offer
		displaced_priority = offer_priority
	if(!displaced)
		return FALSE
	suppress_offer_reconcile = TRUE
	displaced.withdraw("A higher-priority time-sensitive opportunity displaced this standing offer.")
	suppress_offer_reconcile = FALSE
	return candidate_has_capacity(candidate, definition)

/// Submit one currently eligible opportunity. The return value is the live
/// contract when capacity allowed immediate publication; otherwise the
/// candidate remains queued and will be reconsidered when the board changes.
/datum/controller/subsystem/contracts/proc/queue_offer(definition_id, list/context, reason = "Gameplay eligibility event", offer_key, priority = 50) as /datum/contract
	var/datum/contract_definition/definition = definitions[definition_id]
	if(!definition)
		return null
	var/list/candidate_context = context ? deepCopyList(context) : list()
	offer_key ||= definition.candidate_key(candidate_context)
	var/board_key = definition.board_key(candidate_context)
	if(!offer_key || !board_key || !definition.is_available(candidate_context))
		return null
	var/datum/contract/existing = find_live_offer(offer_key)
	if(existing)
		return existing
	if(find_candidate(offer_key))
		return null
	var/candidate_offer_kind = candidate_context["offer_kind"] || definition.offer_kind
	var/candidate_expires_at = candidate_offer_kind == CONTRACT_OFFER_STANDING ? 0 : world.time + definition.candidate_duration
	var/datum/contract_offer_candidate/candidate = new(
		"DQ-CAND-[next_candidate_id++]",
		definition_id,
		offer_key,
		board_key,
		candidate_offer_kind,
		reason,
		candidate_context,
		candidate_expires_at,
		priority,
	)
	offer_candidates += candidate
	record_lifecycle("candidate", null, candidate, reason)
	var/datum/contract/materialized = candidate_context["defer_materialization"] ? null : try_materialize_candidate(candidate)
	if(materialized)
		return materialized
	var/cooldown_until = offer_cooldowns[offer_key] || 0
	var/recheck_delay = candidate_expires_at ? max(1, candidate_expires_at - world.time) : 0
	if(cooldown_until > world.time)
		recheck_delay = recheck_delay ? min(recheck_delay, cooldown_until - world.time) : cooldown_until - world.time
	if(recheck_delay)
		addtimer(CALLBACK(src, PROC_REF(reconcile_offer_board), "Candidate timer"), recheck_delay)
	return null

/datum/controller/subsystem/contracts/proc/try_materialize_candidate(datum/contract_offer_candidate/candidate) as /datum/contract
	if(!candidate || !(candidate in offer_candidates))
		return null
	var/datum/contract_definition/definition = definitions[candidate.definition_id]
	if(!definition || (candidate.expires_at && world.time >= candidate.expires_at) || !definition.is_available(candidate.context))
		withdraw_candidate(candidate, "Eligibility ended before publication.")
		return null
	if((offer_cooldowns[candidate.offer_key] || 0) > world.time || !make_priority_capacity(candidate, definition))
		return null
	var/list/materialization_context = deepCopyList(candidate.context)
	materialization_context["offer_key"] = candidate.offer_key
	materialization_context["board_key"] = candidate.board_key
	materialization_context["offer_reason"] = candidate.reason
	materialization_context["offer_kind"] = candidate.offer_kind
	materialization_context["offer_priority"] = candidate.priority
	var/reason = candidate.reason
	var/datum/contract/contract = definition.create_contract(materialization_context)
	if(!contract)
		record_lifecycle("candidate-error", null, candidate, "Definition failed to create a valid contract.")
		withdraw_candidate(candidate, "Definition failed to create a valid contract.")
		return null
	offer_candidates -= candidate
	record_lifecycle("offered", contract, candidate, reason)
	qdel(candidate)
	offers_materialized++
	notify_contract(contract, "New [contract.offer_kind] contract: [contract.title].")
	return contract

/datum/controller/subsystem/contracts/proc/reconcile_offer_board(reason = "Board capacity changed")
	var/made_progress = TRUE
	while(made_progress)
		made_progress = FALSE
		var/list/pending = offer_candidates.Copy()
		while(length(pending))
			var/datum/contract_offer_candidate/best_candidate
			for(var/datum/contract_offer_candidate/candidate in pending)
				if(!best_candidate || candidate.priority > best_candidate.priority || (candidate.priority == best_candidate.priority && candidate.created_at < best_candidate.created_at))
					best_candidate = candidate
			pending -= best_candidate
			if(try_materialize_candidate(best_candidate))
				made_progress = TRUE
				break
	if(reason)
		record_lifecycle("board-reconciled", null, null, reason)

/datum/controller/subsystem/contracts/proc/reconcile_offer_eligibility(reason = "Gameplay state changed")
	for(var/datum/contract/contract in offered_contracts.Copy())
		var/datum/contract_definition/definition = definitions[contract.definition_id]
		if(definition && !definition.offer_remains_available(contract))
			contract.withdraw("The issuer withdrew this offer because its triggering opportunity no longer exists.")
	for(var/datum/contract/contract in active_contracts.Copy() + grace_contracts.Copy())
		var/datum/contract_definition/definition = definitions[contract.definition_id]
		if(!definition || definition.active_remains_possible(contract))
			continue
		if(definition.amend_impossible_contract(contract, reason))
			contract.audit(CONTRACT_AUDIT_RECOVERY, "Terms automatically amended after: [reason].")
			notify_contract(contract, "Contract [contract.id] was amended because its original terms became impossible.")
		else
			contract.withdraw("The contract became impossible through no fault of the crew and was withdrawn without penalty.")
	for(var/datum/contract_offer_candidate/candidate in offer_candidates.Copy())
		var/datum/contract_definition/definition = definitions[candidate.definition_id]
		if(!definition || !definition.is_available(candidate.context))
			withdraw_candidate(candidate, reason)
	reconcile_offer_board(reason)

/datum/controller/subsystem/contracts/proc/handle_contract_accepted(datum/contract/contract)
	record_lifecycle("accepted", contract, null, "Negotiated version accepted; terms locked.")
	notify_contract(contract, "Contract [contract.id] accepted: [contract.title].")
	reconcile_offer_eligibility("Offer accepted; board capacity changed")

/datum/controller/subsystem/contracts/proc/handle_contract_closed(datum/contract/contract)
	if(!contract?.offer_key)
		return
	var/datum/contract_definition/definition = definitions[contract.definition_id]
	var/cooldown = contract.accepted_at ? definition?.repeat_cooldown : definition?.offer_cooldown
	if(definition?.auto_replace && contract.offer_kind == CONTRACT_OFFER_STANDING)
		cooldown = rand(CONTRACT_ROTATION_MIN_DELAY, CONTRACT_ROTATION_MAX_DELAY)
	if(isnum(cooldown) && cooldown > 0)
		offer_cooldowns[contract.offer_key] = world.time + cooldown
	switch(contract.closure_code)
		if(CONTRACT_CLOSE_DECLINED)
			offers_declined++
		if(CONTRACT_CLOSE_EXPIRED)
			offers_expired++
		if(CONTRACT_CLOSE_INELIGIBLE)
			offers_withdrawn++
	var/datum/contract_audit_entry/last_audit = length(contract.audit_log) ? contract.audit_log[length(contract.audit_log)] : null
	record_lifecycle(contract.closure_code || "closed", contract, null, last_audit?.detail)
	notify_contract(contract, "Contract [contract.id] closed: [contract.title] ([contract.closure_code]).")
	if(definition?.auto_replace && contract.offer_kind == CONTRACT_OFFER_STANDING && contract.closure_code != CONTRACT_CLOSE_INELIGIBLE)
		queue_offer(definition.id, contract.offer_context, "Standing offer replacement", contract.offer_key)
	if(!suppress_offer_reconcile)
		reconcile_offer_board("Contract closed; board slot released")

/datum/controller/subsystem/contracts/proc/notify_contract(datum/contract/contract, message)
	if(!contract || !message)
		return
	for(var/obj/item/pda/device in REGISTRY_MEMBERS(REGISTRY_PDAS))
		var/datum/data/pda/app/contracts/app = device.find_program(/datum/data/pda/app/contracts)
		if(!app)
			continue
		if(contract.scope == CONTRACT_SCOPE_PERSONAL)
			if(device.id?.associated_account_number == contract.owner_account_number)
				app.notify(message)
			continue
		var/mob/living/holder = get(device, /mob/living)
		if(!holder || !(ACCESS_HEADS in device.id?.access))
			continue
		if(contract.scope == CONTRACT_SCOPE_STATION || department_for_mob(holder) == contract.department)
			app.notify(message)

/datum/controller/subsystem/contracts/proc/lifecycle_summary()
	return list(
		"candidates" = length(offer_candidates),
		"offered" = length(offered_contracts),
		"active" = length(active_contracts),
		"grace" = length(grace_contracts),
		"closed" = length(closed_contracts),
		"materialized" = offers_materialized,
		"declined" = offers_declined,
		"expired" = offers_expired,
		"withdrawn" = offers_withdrawn,
	)

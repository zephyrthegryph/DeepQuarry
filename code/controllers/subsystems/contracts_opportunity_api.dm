// Contract-system operations moved from code/modules/contracts/opportunity_broker.dm.

/datum/system/contracts/proc/initialize_opportunity_broker()
	opportunity_rules = list()
	opportunity_rules_by_event = list()
	opportunity_windows = list()
	opportunity_cooldowns = list()
	rel_clear(src, nameof(opportunity_history))
	for(var/rule_type as anything in subtypesof(/datum/contract_opportunity_rule))
		if(is_abstract(rule_type))
			continue
		var/datum/contract_opportunity_rule/rule = new rule_type
		if(!rule.id || !length(rule.signals) || opportunity_rules[rule.id])
			spent(rule)
			continue
		if(rule.definition_id && !definitions[rule.definition_id])
			stack_trace("Opportunity rule [rule.id] targets missing contract definition [rule.definition_id].")
			spent(rule)
			continue
		opportunity_rules[rule.id] = rule
		for(var/datum/contract_opportunity_signal/signal in rule.signals)
			LAZYINITLIST(opportunity_rules_by_event[signal.event_type])
			opportunity_rules_by_event[signal.event_type] |= rule

/datum/system/contracts/proc/observe_opportunity_event(datum/contract_event/event)
	// Machinery initialization and pregame setup can legitimately publish
	// transient state. They are useful to active contracts in tests, but must
	// never manufacture live-round opportunities.
	if(!contract_unit_test_mode() && (!SSticker || ticker_current_state() < GAME_STATE_PLAYING))
		return FALSE
	var/list/rules = opportunity_rules_by_event?[event?.event_type]
	if(!length(rules))
		return FALSE
	opportunity_events_observed++
	for(var/datum/contract_opportunity_rule/rule in rules)
		var/bucket = rule.bucket_for(event)
		if(isnull(bucket))
			continue
		var/window_key = rule.window_key(bucket)
		var/datum/contract_opportunity_window/window = opportunity_windows[window_key]
		if(!window)
			window = new(window_key, bucket, rule)
			opportunity_windows[window_key] = window
		// A batch (damage_batch.dm) prunes each window once and evaluates it
		// once, when the batch ends, with its last event.
		var/batching = contract_batch_depth > 0
		if(!batching || !pruned_opportunity_windows?[window_key])
			window.prune(rule)
			if(batching)
				LAZYSET(pruned_opportunity_windows, window_key, TRUE)
		var/changed = FALSE
		for(var/datum/contract_opportunity_signal/signal in rule.signals)
			if(signal.event_type == event.event_type && window.revise(signal, event))
				changed = TRUE
		if(!changed)
			continue
		if(batching)
			rel_set(window, nameof(window.batch_event), event)
			LAZYSET(pending_opportunity_windows, window_key, TRUE)
			continue
		evaluate_opportunity_window(rule, window, window_key, event)
	return TRUE

/// Snapshots `window` and queues, withdraws or suppresses its offer. `event`
/// is the fact that last revised it.
/datum/system/contracts/proc/evaluate_opportunity_window(datum/contract_opportunity_rule/rule, datum/contract_opportunity_window/window, window_key, datum/contract_event/event)
	var/list/signal_snapshots = rule.snapshots(window)
	if(window.latched)
		if(rule.should_reset(signal_snapshots))
			window.latched = FALSE
			withdraw_unaccepted_opportunity(rule, window, "The originating incident resolved before acceptance.")
		else
			opportunities_suppressed++
			return
	if(!rule.is_ready(signal_snapshots))
		return
	var/cooldown_until = opportunity_cooldowns[window_key] || 0
	if(BEFORE(src, cooldown_until, CLOCK_WORLD))
		opportunities_suppressed++
		return
	if(!rule.trigger(src, window, event, signal_snapshots))
		// Avoid retrying a definition with exhausted demand on every event.
		opportunity_cooldowns[window_key] = EXPIRY_AT(null, CLOCK_WORLD, 0) + 2 MINUTES
		opportunities_suppressed++
		return
	window.latched = TRUE
	opportunity_cooldowns[window_key] = EXPIRY_AT(null, CLOCK_WORLD, 0) + rule.cooldown
	opportunities_triggered++
	var/datum/contract_opportunity_history_entry/history_entry = new(rule, window, event, signal_snapshots)
	rel_add(src, nameof(opportunity_history), history_entry)
	if(length(opportunity_history) > CONTRACT_OPPORTUNITY_HISTORY_LIMIT)
		var/datum/contract_opportunity_history_entry/expired = opportunity_history[1]
		rel_remove(src, nameof(opportunity_history), expired)
		lapsed(expired)

/datum/system/contracts/proc/withdraw_unaccepted_opportunity(datum/contract_opportunity_rule/rule, datum/contract_opportunity_window/window, reason)
	var/offer_key = "opportunity:[rule.id]:[window.bucket]"
	var/datum/contract/offer = find_live_offer(offer_key)
	if(offer?.state == CONTRACT_OFFERED)
		offer.withdraw(reason)
	var/datum/contract_offer_candidate/candidate = find_candidate(offer_key)
	if(candidate)
		withdraw_candidate(candidate, reason)

/datum/system/contracts/proc/opportunity_observability()
	return list(
		"rules" = length(opportunity_rules),
		"windows" = length(opportunity_windows),
		"events" = opportunity_events_observed,
		"triggered" = opportunities_triggered,
		"suppressed" = opportunities_suppressed,
		"history" = length(opportunity_history),
	)

/datum/system/contracts/proc/opportunity_near_misses()
	var/list/result = list()
	for(var/window_key in opportunity_windows)
		var/datum/contract_opportunity_window/window = opportunity_windows[window_key]
		var/rule_id = splittext(window_key, "|")[1]
		var/datum/contract_opportunity_rule/rule = opportunity_rules[rule_id]
		if(!rule || window.latched)
			continue
		var/list/snapshots = rule.snapshots(window)
		var/progress = 1
		var/list/lanes = list()
		for(var/datum/contract_opportunity_signal/signal in rule.signals)
			var/list/snapshot = snapshots[signal.id]
			var/value_ratio = signal.target > 0 ? min(1, (snapshot["value"] || 0) / signal.target) : 1
			var/fact_ratio = signal.minimum_facts > 0 ? min(1, (snapshot["facts"] || 0) / signal.minimum_facts) : 1
			var/lane_progress = min(value_ratio, fact_ratio)
			for(var/field in signal.diversity_targets)
				var/list/diversity = snapshot["diversity"]
				lane_progress = min(lane_progress, min(1, (diversity[field] || 0) / signal.diversity_targets[field]))
			progress = min(progress, lane_progress)
			lanes += "[signal.id] [round(lane_progress * 100)]% ([round(snapshot["value"], 0.1)]/[signal.target], [snapshot["facts"]]/[signal.minimum_facts] facts)"
		result += list(list(
			"rule" = rule.id,
			"bucket" = window.bucket,
			"progress" = round(progress * 100),
			"lanes" = jointext(lanes, "; "),
			"last_event_at" = window.last_event_at,
		))
	return result

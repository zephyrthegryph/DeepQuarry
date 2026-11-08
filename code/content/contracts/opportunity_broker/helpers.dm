/// Generic event-driven opportunity broker.
///
/// Rules consume only validated events from SScontracts.publish_event(). Each
/// rule keeps a bounded rolling window of revision-aware facts. A contract is
/// queued only after every signal lane meets its value, fact-count, actor, and
/// diversity thresholds. Trigger evidence predates acceptance and therefore
/// can never satisfy the resulting contract.

/datum/contract_opportunity_observation
	var/fact_key
	var/revision = 0
	var/occurred_at = 0
	var/value = 0
	var/actor_key
	var/list/diversity_values

SCHEMA(/datum/contract_opportunity_observation, value, num())

/datum/contract_opportunity_observation/New(_fact_key, datum/contract_event/event, datum/contract_opportunity_signal/signal)
	. = ..()
	fact_key = _fact_key
	revision = event.fact_revision
	occurred_at = event.occurred_at
	value = signal.event_value(event)
	actor_key = event.value(signal.actor_field) || event.source_ref || event.value("producer_id")
	diversity_values = list()
	for(var/field in signal.diversity_targets)
		diversity_values[field] = event.value(field)

/// One independently required lane in a broker rule. A rule may combine
/// unrelated systems (for example, production plus real crew sales) without a
/// bespoke callback or polling loop.
/datum/contract_opportunity_signal
	var/id
	var/event_type
	var/target = 1
	var/value_field
	var/aggregation = CONTRACT_OPPORTUNITY_AGGREGATE_SUM
	var/minimum_facts = 1
	var/actor_field = "actor_account"
	var/minimum_actors = 0
	var/maximum_fact_value = 0
	var/maximum_actor_value = 0
	var/require_station_source = FALSE
	var/datum/contract_event_filter/filter
	/// field -> minimum number of distinct values
	var/list/diversity_targets

CAPABILITIES(/datum/contract_opportunity_signal)
	owns_one(nameof(filter), /datum/contract_event_filter)

/datum/contract_opportunity_signal/New(_id, _event_type, _target = 1, _value_field = null)
	. = ..()
	id = _id
	event_type = _event_type
	target = _target
	value_field = _value_field
	rel_set(src, nameof(filter), new /datum/contract_event_filter)
	diversity_targets = list()

/datum/contract_opportunity_signal/proc/require_value(key, expected)
	return filter.require_value(key, expected)

/datum/contract_opportunity_signal/proc/forbid_value(key, forbidden)
	return filter.forbid_value(key, forbidden)

/datum/contract_opportunity_signal/proc/require_number(key, comparator, expected)
	return filter.require_number(key, comparator, expected)

/datum/contract_opportunity_signal/proc/require_diversity(field, count)
	if(!istext(field) || !length(field) || !isnum(count) || count < 1)
		return FALSE
	diversity_targets[field] = round(count)
	return TRUE

/datum/contract_opportunity_signal/proc/event_matches(datum/contract_event/event)
	if(event?.event_type != event_type)
		return FALSE
	if(require_station_source)
		if(!event.z || !(event.z in using_map.station_levels))
			return FALSE
	for(var/key in filter.exact_values)
		if(event.value(key) != filter.exact_values[key])
			return FALSE
	for(var/key in filter.forbidden_values)
		if(event.value(key) == filter.forbidden_values[key])
			return FALSE
	for(var/tag in filter.required_tags)
		if(!(tag in event.tags))
			return FALSE
	for(var/list/check as anything in filter.numeric_checks)
		if(!contract_evidence_compare(event.value(check["key"]), check["comparator"], check["expected"]))
			return FALSE
	return TRUE

/datum/contract_opportunity_signal/proc/event_value(datum/contract_event/event)
	var/measured = value_field ? event.value(value_field) : 1
	if(!isnum(measured) || measured <= 0)
		return 0
	if(maximum_fact_value > 0)
		measured = min(measured, maximum_fact_value)
	return measured

/// A bucket is normally station-wide. Rules may instead bucket by a stable
/// event field, such as the principal account behind covert market activity.
/datum/contract_opportunity_window
	var/key
	var/bucket
	var/created_at = 0
	var/last_event_at = 0
	var/latched = FALSE
	var/list/facts_by_signal
	/// Owns the records indexed by facts_by_signal; the nested maps retain their lookup order.
	var/list/observations
	/// The last event that revised this window during an open batch (a relation; damage_batch.dm).
	var/datum/contract_event/batch_event

CAPABILITIES(/datum/contract_opportunity_window)
	ref_one(nameof(batch_event), /datum/contract_event)
	owns_many(nameof(observations), /datum/contract_opportunity_observation)

/datum/contract_opportunity_window/New(_key, _bucket, datum/contract_opportunity_rule/rule)
	. = ..()
	key = _key
	bucket = _bucket
	STAMP(src, created_at, CLOCK_WORLD)
	STAMP(src, last_event_at, CLOCK_WORLD)
	facts_by_signal = list()
	for(var/datum/contract_opportunity_signal/signal in rule.signals)
		facts_by_signal[signal.id] = list()

// its facts (nested per signal) go with it.
/datum/contract_opportunity_window/on_destroy(force)
	for(var/signal_id in facts_by_signal)
		var/list/facts = facts_by_signal[signal_id]
		for(var/fact_key in facts)
			rel_remove(src, nameof(observations), facts[fact_key])
	..()

/datum/contract_opportunity_window/proc/prune(datum/contract_opportunity_rule/rule)
	var/cutoff = world.time - rule.window_duration
	for(var/datum/contract_opportunity_signal/signal in rule.signals)
		var/list/facts = facts_by_signal[signal.id]
		for(var/fact_key in facts.Copy())
			var/datum/contract_opportunity_observation/observation = facts[fact_key]
			if(observation.occurred_at >= cutoff)
				continue
			facts -= fact_key
			rel_remove(src, nameof(observations), observation)

/datum/contract_opportunity_window/proc/revise(datum/contract_opportunity_signal/signal, datum/contract_event/event)
	var/stable_fact_id = event.fact_id || event.occurrence_id
	if(!stable_fact_id)
		return FALSE
	var/fact_key = "[stable_fact_id]|[event.event_type]" // varying part first: see contract_infrastructure_fact_id()
	var/list/facts = facts_by_signal[signal.id]
	var/datum/contract_opportunity_observation/previous = facts[fact_key]
	if(previous)
		if(event.fact_revision > 0 && event.fact_revision <= previous.revision)
			return FALSE
		if(event.fact_revision <= 0)
			return FALSE
		facts -= fact_key
		rel_remove(src, nameof(observations), previous)
	STAMP(src, last_event_at, CLOCK_WORLD)
	if(!event.fact_active || !signal.event_matches(event))
		return TRUE
	facts[fact_key] = rel_add(src, nameof(observations), new /datum/contract_opportunity_observation(fact_key, event, signal))
	while(length(facts) > CONTRACT_OPPORTUNITY_FACT_LIMIT)
		var/oldest_key
		var/oldest_time = INFINITY
		for(var/candidate_key in facts)
			var/datum/contract_opportunity_observation/candidate = facts[candidate_key]
			if(candidate.occurred_at < oldest_time)
				oldest_key = candidate_key
				oldest_time = candidate.occurred_at
		var/datum/contract_opportunity_observation/expired = facts[oldest_key]
		facts -= oldest_key
		rel_remove(src, nameof(observations), expired)
	return TRUE

/datum/contract_opportunity_window/proc/signal_snapshot(datum/contract_opportunity_signal/signal)
	var/list/facts = facts_by_signal[signal.id]
	var/list/actor_totals = list()
	var/anonymous_total = 0
	var/maximum_value = 0
	var/list/distinct_by_field = list()
	for(var/field in signal.diversity_targets)
		distinct_by_field[field] = list()
	for(var/fact_key in facts)
		var/datum/contract_opportunity_observation/observation = facts[fact_key]
		maximum_value = max(maximum_value, observation.value)
		if(observation.actor_key)
			actor_totals["[handle_text(observation.actor_key)]"] = (actor_totals["[handle_text(observation.actor_key)]"] || 0) + observation.value
		else
			anonymous_total += observation.value
		for(var/field in signal.diversity_targets)
			var/distinct_value = observation.diversity_values[field]
			if(!isnull(distinct_value))
				var/list/field_values = distinct_by_field[field]
				field_values["[handle_text(distinct_value)]"] = TRUE
	var/aggregate = anonymous_total
	for(var/actor_key in actor_totals)
		var/actor_value = actor_totals[actor_key]
		aggregate += signal.maximum_actor_value > 0 ? min(actor_value, signal.maximum_actor_value) : actor_value
	if(signal.aggregation == CONTRACT_OPPORTUNITY_AGGREGATE_MAX)
		aggregate = maximum_value
	var/list/distinct_counts = list()
	var/list/distinct_values = list()
	var/diversity_satisfied = TRUE
	for(var/field in signal.diversity_targets)
		var/list/field_values = distinct_by_field[field]
		distinct_counts[field] = length(field_values)
		distinct_values[field] = field_values.Copy()
		if(length(field_values) < signal.diversity_targets[field])
			diversity_satisfied = FALSE
	var/satisfied = aggregate >= signal.target && length(facts) >= signal.minimum_facts && length(actor_totals) >= signal.minimum_actors && diversity_satisfied
	return list(
		"value" = aggregate,
		"facts" = length(facts),
		"actors" = length(actor_totals),
		"diversity" = distinct_counts,
		"values" = distinct_values,
		"satisfied" = satisfied,
	)

/datum/contract_opportunity_rule
	abstract_type = /datum/contract_opportunity_rule
	var/id
	var/definition_id
	var/description = "Authoritative station telemetry identified a new commission."
	var/window_duration = CONTRACT_OPPORTUNITY_DEFAULT_WINDOW
	var/cooldown = CONTRACT_OPPORTUNITY_DEFAULT_COOLDOWN
	var/reset_ratio = CONTRACT_OPPORTUNITY_RESET_RATIO
	var/bucket_field
	var/priority = 70
	var/list/signals
	/// event field -> offer-context field
	var/list/context_fields

CAPABILITIES(/datum/contract_opportunity_rule)
	owns_many(nameof(signals))

/datum/contract_opportunity_rule/New()
	. = ..()
	rel_take_all(src, nameof(signals))
	context_fields = list()
	configure()

/datum/contract_opportunity_rule/proc/configure()
	return

/datum/contract_opportunity_rule/proc/add_signal(datum/contract_opportunity_signal/signal)
	if(!signal?.id || !signal.event_type)
		spent(signal)
		return null
	for(var/datum/contract_opportunity_signal/existing in signals)
		if(existing.id == signal.id)
			spent(signal)
			return null
	rel_add(src, nameof(signals), signal)
	return signal

/datum/contract_opportunity_rule/proc/forward_context(event_field, context_field = null)
	if(!istext(event_field) || !length(event_field))
		return FALSE
	context_fields[event_field] = context_field || event_field
	return TRUE

/datum/contract_opportunity_rule/proc/bucket_for(datum/contract_event/event)
	var/bucket_value = bucket_field ? event.value(bucket_field) : "station"
	return isnull(bucket_value) ? null : "[bucket_value]"

/datum/contract_opportunity_rule/proc/window_key(bucket)
	return "[id]|[bucket]"

/datum/contract_opportunity_rule/proc/snapshots(datum/contract_opportunity_window/window)
	var/list/result = list()
	for(var/datum/contract_opportunity_signal/signal in signals)
		result[signal.id] = window.signal_snapshot(signal)
	return result

/datum/contract_opportunity_rule/proc/is_ready(list/signal_snapshots)
	if(!length(signals))
		return FALSE
	for(var/datum/contract_opportunity_signal/signal in signals)
		var/list/snapshot = signal_snapshots[signal.id]
		if(!snapshot?["satisfied"])
			return FALSE
	return TRUE

/datum/contract_opportunity_rule/proc/should_reset(list/signal_snapshots)
	for(var/datum/contract_opportunity_signal/signal in signals)
		var/list/snapshot = signal_snapshots[signal.id]
		if((snapshot?["value"] || 0) < signal.target * reset_ratio)
			return TRUE
	return FALSE

/datum/contract_opportunity_rule/proc/trigger(datum/system/contracts/controller, datum/contract_opportunity_window/window, datum/contract_event/event, list/signal_snapshots)
	var/list/context = list(
		"offer_kind" = CONTRACT_OFFER_OPPORTUNITY,
		"opportunity_rule" = id,
		"opportunity_bucket" = window.bucket,
		"opportunity_triggered_at" = TIME_NOW(CLOCK_WORLD),
		"trigger_event_id" = event.id,
		"trigger_area" = event.area_name,
		"trigger_signals" = deepCopyList(signal_snapshots),
	)
	var/list/trigger_values = list()
	for(var/signal_id in signal_snapshots)
		var/list/snapshot = signal_snapshots[signal_id]
		var/list/values = snapshot?["values"]
		for(var/field in values)
			LAZYINITLIST(trigger_values[field])
			var/list/field_values = trigger_values[field]
			field_values |= values[field]
	context["trigger_values"] = trigger_values
	for(var/event_field in context_fields)
		context[context_fields[event_field]] = event.value(event_field)
	var/offer_key = "opportunity:[id]:[window.bucket]"
	var/datum/contract/queued = controller.queue_offer(definition_id, context, description, offer_key, priority)
	return !!queued || !!controller.find_live_offer(offer_key) || !!controller.find_candidate(offer_key)

/datum/contract_opportunity_history_entry
	var/time = 0
	var/rule_id
	var/bucket
	var/event_id
	var/offer_key
	var/list/snapshots

/datum/contract_opportunity_history_entry/New(datum/contract_opportunity_rule/rule, datum/contract_opportunity_window/window, datum/contract_event/event, list/_snapshots)
	. = ..()
	STAMP(src, time, CLOCK_WORLD)
	rule_id = rule.id
	bucket = window.bucket
	event_id = event.id
	offer_key = "opportunity:[rule.id]:[window.bucket]"
	snapshots = deepCopyList(_snapshots)

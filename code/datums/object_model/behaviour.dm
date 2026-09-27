// A behaviour is shared definition data. Its configuration is stored once on
// each archetype; only explicitly requested state belongs to an instance.
/datum/object_model/behaviour
	/// Config key -> default value. Unknown keys fail archetype validation.
	var/list/config_schema
	var/list/requires
	var/list/provides
	var/list/needs
	var/list/events
	/// Derived views are optional. These are shared declarations, not instance datums.
	var/derived_input_mask = 0
	/// Each row is list(slot_id, child_change_mask).
	var/list/derived_owned_inputs
	/// Each row is list(relation_kind, direction, related_change_mask).
	var/list/derived_relation_inputs
	var/list/after
	var/list/before
	var/list/requires_behaviour
	var/list/excludes
	var/period = 0
	/// Opt-in scheduling: only declared local change groups queue on_run().
	var/run_change_mask = 0
	/// Same row shapes as derived inputs; membership also wakes these behaviours.
	var/list/run_owned_inputs
	var/list/run_relation_inputs
	/// Typed events that queue on_run(); occurrences merge and state is re-read.
	var/list/run_events
	/// Default delay between on_run() calls while continuous work is needed.
	/// Zero leaves the behaviour asleep until a declared change or explicit wake.
	var/run_period = 0
	/// Larger values are dispatched first among due runtimes; declaration order still
	/// governs behaviours on the same entity. Zero is ordinary background work.
	var/run_priority = SCHEDULE_PRIORITY_BACKGROUND
	/// Maximum acceptable wall-clock queue delay, in deciseconds. Zero means no alert.
	var/run_max_lateness = 0
	/// Starting estimate for cost-aware dispatch, replaced by measured cost.
	var/run_cost_hint_ms = 0.1
	/// Share the regular cadence with other owners of this behaviour type.
	/// Exceptional deadlines still use the owner's native reactor timer.
	var/run_shared_cadence = FALSE
	/// Null uses world time; a domain path uses virtual time for delay and seconds.
	var/run_clock
	/// Optional source-owned suspension group. Independent of time dilation.
	var/run_set
	/// A change wake may run early without postponing this behaviour's deadline.
	var/preserve_deadline_on_wake = FALSE
	/// Enable missed-wake audits for this behaviour's sleeping state.
	var/audit_sleep = FALSE
	/// Optional finite state machine. transitions maps old state -> allowed list.
	var/list/states
	var/initial_state
	var/list/transitions

/datum/object_model/behaviour/proc/validate_config(list/config, list/errors)
	for(var/key in config)
		if(!config_schema || !(key in config_schema))
			errors += "[type]: unknown config key [key]"
	for(var/key in config_schema)
		if(!(key in config))
			config[key] = config_schema[key]

/// Override for meaningful constraints, including units and ranges.
/datum/object_model/behaviour/proc/validate_value(key, value)
	return null

/datum/object_model/behaviour/proc/on_activate(datum/source, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/object_model/behaviour/proc/on_deactivate(datum/source, list/config, reason)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/object_model/behaviour/proc/on_tick(datum/source, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// A scheduled, non-sleeping unit of work. Return a nonnegative delay to
/// override run_period for this entity; zero sleeps until the next wake.
/datum/object_model/behaviour/proc/on_run(datum/source, seconds, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return null

/// Return a reason when the behaviour has work despite being asleep.
/datum/object_model/behaviour/proc/sleep_violation(datum/source, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return null

/datum/object_model/behaviour/proc/on_state_enter(datum/source, state, old_state, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/object_model/behaviour/proc/on_state_exit(datum/source, state, new_state, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/object_model/behaviour/proc/on_event(datum/source, datum/object_model/event/E, a, b, c, d, list/config)
	SHOULD_NOT_SLEEP(TRUE)
	return

/datum/object_model/interface
	/// Interface definitions may override validate_provider() for proc contracts.

/datum/object_model/interface/proc/validate_provider(datum/object_model/behaviour/B)
	return null

/proc/om_interface(path)
	if(!ispath(path, /datum/object_model/interface))
		return null
	var/static/list/cache = list()
	var/datum/object_model/interface/I = cache[path]
	if(!I)
		I = new path
		cache[path] = I
	return I

/proc/om_behaviour(path)
	if(!ispath(path, /datum/object_model/behaviour))
		return null
	var/static/list/cache = list()
	var/datum/object_model/behaviour/B = cache[path]
	if(!B)
		B = new path
		cache[path] = B
	return B

/datum/object_model/bundle

/datum/object_model/bundle/proc/apply(datum/object_model/archetype/A, list/params)
	return

/proc/om_bundle(path)
	if(!ispath(path, /datum/object_model/bundle))
		return null
	var/static/list/cache = list()
	var/datum/object_model/bundle/B = cache[path]
	if(!B)
		B = new path
		cache[path] = B
	return B

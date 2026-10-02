// The recorder (round 5, U1): in test builds the engine verbs report to a recorder, and a fixture reads back what happened.
//
//     test_record(actor, door)              // start; the entities named here are the ones whose tracked deltas are kept
//     ... drive the op ...
//     var/list/events = test_recorded()     // the record, in order, as /datum/test_event rows; clears it
//
// What it records: op outcomes, notices (with their outcome), log lines, slot transfers, resource reserve / commit /
// release, activation attach / detach, drain spills, and the tracked-var deltas of the entities named in test_record(). Every
// engine verb that does one of these reports it through a TEST_REC_* macro (code/__defines/engine/test_hooks.dm), which
// compiles out of production. The phase-2 behaviour snapshot harness is built on the same recorder.
//
// Who owns what. E0 fixes the API (test_record / test_recorded), the row shape and the report calls, and ships the placeholder
// store below so the proofs compile and so a fixture can compare runs; the store itself belongs to E6 (round 5), which
// replaces test_rec_event() and keeps the rest.
//
// Comparing runs. A run on three identical fixtures touches three different entities, so a row also carries the `role`
// of its entity: its position among the entities test_record() was given (null for any other entity). test_events_diff()
// compares two records by role instead of by entity, minus the columns the test says differ by design.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// One row of the record: what kind of event, which entity it concerns, the key it is about (an op key, a notice type, a
/// resource, a var, a slot), and the values it went from and to (`from_value`, `to_value`: `to` is a DM keyword).
/datum/test_event
	/// TEST_EVENT_*: "outcome", "notice", "notice_queued", "log", "transfer", "reserve", "commit", "release", "attach", "detach", "delta", "spill".
	var/kind
	/// The entity the row concerns (the actor of an outcome, the item of a transfer, the holder of a reservation or an activation).
	var/datum/entity
	var/key
	var/from_value
	var/to_value
	/// The 1-based position of `entity` among the entities test_record() named, or null. Set when the record is read.
	var/role

/// Starts recording. The entities named here are the ones whose tracked deltas are kept, and the ones rows are compared by.
/proc/test_record(...)
	var/datum/test_driver/D = GLOB.test_driver
	D.recording = list()
	D.recorded_entities = args.Copy()

/// Stops the recording and returns it, in order, as /datum/test_event rows. Clears it.
/proc/test_recorded()
	var/datum/test_driver/D = GLOB.test_driver
	. = D.recording || list()
	for(var/datum/test_event/event in .)
		event.role = D.recorded_entities.Find(event.entity) || null
	D.recording = null
	D.recorded_entities = null

/// The one store write. A placeholder: E6 replaces this proc (and nothing else in this file) with its recorder.
/proc/test_rec_event(kind, datum/entity, key, from_value, to_value)
	var/datum/test_driver/D = GLOB.test_driver
	if(isnull(D.recording))
		return
	// A delta is kept only for an entity the test named; every other kind is kept whatever it concerns.
	if(kind == TEST_EVENT_DELTA && !(entity in D.recorded_entities))
		return
	var/datum/test_event/event = new
	event.kind = kind
	event.entity = entity // ALLOW(ownership): a test-only row the test reads and drops
	event.key = key
	event.from_value = from_value
	event.to_value = to_value
	D.recording += event // ALLOW(ownership): a test-only row the test reads and drops

/// A row as comparable text: its kind, its entity as a role (or its type), key, from and to, minus the `ignoring` columns
/// ("entity", "key", "from", "to"). A datum in a from/to column is shown by role or type too.
/proc/test_event_text(datum/test_event/event, list/entities, list/ignoring)
	var/list/parts = list(event.kind)
	if(!("entity" in ignoring))
		parts += "entity=[test_event_value(event.entity, entities)]"
	if(!("key" in ignoring))
		parts += "key=[test_event_value(event.key, entities)]"
	if(!("from" in ignoring))
		parts += "from=[test_event_value(event.from_value, entities)]"
	if(!("to" in ignoring))
		parts += "to=[test_event_value(event.to_value, entities)]"
	return jointext(parts, " ")

/proc/test_event_value(value, list/entities)
	if(isdatum(value))
		var/role = entities.Find(value)
		if(role)
			return "<[role]>"
		var/datum/anything = value
		return "[anything.type]"
	if(isnull(value))
		return "null"
	return "[value]"

/// Null when two records say the same thing, comparing entities by role (`entities_a` and `entities_b` are the lists each run
/// gave test_record(), in the same order) and leaving out the `ignoring` columns; else a text naming the first row that differs.
/proc/test_events_diff(list/events_a, list/entities_a, list/events_b, list/entities_b, list/ignoring)
	for(var/i in 1 to max(length(events_a), length(events_b)))
		var/left = i <= length(events_a) ? test_event_text(events_a[i], entities_a, ignoring) : "(nothing)"
		var/right = i <= length(events_b) ? test_event_text(events_b[i], entities_b, ignoring) : "(nothing)"
		if(left != right)
			return "row [i] of [length(events_a)] vs [length(events_b)]: '[left]' vs '[right]'"
	return null

/// How many rows of `kind` a record holds, optionally only those about `key`.
/proc/test_events_count(list/events, kind, key)
	. = 0
	for(var/datum/test_event/event in events)
		if(event.kind == kind && (isnull(key) || event.key == key))
			.++

// ---- The report calls (TEST_REC_*) ----

/proc/test_rec_outcome(key, outcome, reason, datum/actor)
	test_rec_event(TEST_EVENT_OUTCOME, actor, key, reason, outcome)

/proc/test_rec_transfer(datum/item, datum/source_holder, datum/dest_holder, slot)
	test_rec_event(TEST_EVENT_TRANSFER, item, slot, source_holder, dest_holder)

/proc/test_rec_resource(event, resource, datum/holder, amount, op_key)
	test_rec_event(event, holder, resource, op_key, amount)

/proc/test_rec_activation(event, definition, datum/source, datum/holder)
	test_rec_event(event, holder, definition, source, null)

/proc/test_rec_delta(datum/entity, key, old_value, new_value)
	test_rec_event(TEST_EVENT_DELTA, entity, key, old_value, new_value)

#endif

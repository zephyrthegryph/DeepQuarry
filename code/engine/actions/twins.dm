// The PUBLISH / OM_EMIT twins (doc/rewrite/final_api.html, "Coexistence rules", Events; section 19 "E4").
//
// While old and new forms run side by side, one occurrence is heard on both sides: PUBLISH of a notice also OM_EMITs its twin event to the
// om_hook listeners, and OM_EMIT of an event also publishes its twin notice to the on_notice listeners. No hand-written bridge: the pairs are
// the rows of GLOB.event_twin_notice (code/engine/_generated/event_twins.dm, `analyze gen event_twins`, from tools/dx/codemods/om_event_map.json)
// and each row names the notice's fields in the order of the event's New() arguments. The last event deletes the map (step A7).
//
// A bridged delivery sets GLOB.twin_in_flight, so the twin does not bounce back. Nothing is built unless the other side has a listener: the
// wants checks (event_twin_wanted(), notice_twin_wanted()) are what om_wants() and notice_wanted() ask.

/// True while a twin is being delivered across the bridge.
GLOBAL_VAR_INIT(twin_in_flight, FALSE)
/// notice type -> list(event type, fields...), built from event_twin_notice on first use.
GLOBAL_LIST_EMPTY(notice_twin_event)
GLOBAL_VAR_INIT(notice_twin_built, FALSE)

/proc/notice_twin_row(notice_type)
	if(!GLOB.notice_twin_built)
		GLOB.notice_twin_built = TRUE
		for(var/event_type in GLOB.event_twin_notice)
			var/list/row = GLOB.event_twin_notice[event_type]
			GLOB.notice_twin_event[row[1]] = list(event_type) + row.Copy(2)
	return GLOB.notice_twin_event[notice_type]

/// Does the notice side of event `event_type` have a listener on E? (om_wants() asks this when the event itself has none.)
/proc/event_twin_wanted(datum/E, event_type)
	if(GLOB.twin_in_flight)
		return FALSE
	var/list/row = GLOB.event_twin_notice[event_type]
	return row && notice_wanted_native(E, row[1], ACT_COMMITTED)

/// Does the event side of notice `notice_type` have an om listener on E?
/proc/notice_twin_wanted(datum/E, notice_type)
	if(GLOB.twin_in_flight)
		return FALSE
	var/list/row = notice_twin_row(notice_type)
	return row && om_wants_direct(E, row[1])

/// OM_EMIT of `event` on E: its twin notice is published to the on_notice listeners.
/proc/event_to_notice_twin(datum/E, datum/om/event/event)
	if(GLOB.twin_in_flight)
		return
	var/list/row = GLOB.event_twin_notice[event.type]
	if(!row || !notice_wanted_native(E, row[1], ACT_COMMITTED))
		return
	var/datum/notice/N = notice_take(row[1])
	for(var/i in 2 to length(row))
		var/field = row[i]
		var/source_field = copytext(field, -1) == "_" && !(field in event.vars) ? copytext(field, 1, -1) : field
		N.vars[field] = event.vars[source_field] // ALLOW(api): the twin copies the event's payload into the notice by the field names of the generated map
	GLOB.twin_in_flight = TRUE
	notice_publish(E, N, ACT_COMMITTED)
	GLOB.twin_in_flight = FALSE

/// A committed notice delivered on holder: its twin event is emitted to the om_hook listeners.
/proc/notice_to_event_twin(datum/holder, datum/notice/N)
	if(GLOB.twin_in_flight)
		return
	var/list/row = notice_twin_row(N.type)
	if(!row || !om_wants_direct(holder, row[1]))
		return
	var/event_type = row[1]
	var/list/values = list()
	for(var/i in 2 to length(row))
		values += list(N.vars[row[i]]) // ALLOW(api): the twin copies the notice's fields into the event's constructor by the generated map
	var/datum/om/event/event = new event_type(arglist(values))
	GLOB.twin_in_flight = TRUE
	om_emit(holder, event)
	GLOB.twin_in_flight = FALSE

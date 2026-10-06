// The PUBLISH / OM_EMIT twins (doc/rewrite/final_api.html, "Coexistence rules", Events; section 19 "E4").
//
// While old and new forms run side by side, one occurrence is heard on both sides: PUBLISH of a notice also OM_EMITs its twin event to the
// event listeners, and OM_EMIT of an event also publishes its twin notice to the on_notice listeners. No hand-written bridge: the pairs are
// the rows of GLOB.event_twin_notice (code/engine/_generated/event_twins.dm, `analyze gen event_twins`, from tools/dx/codemods/om_event_map.json)
// and each row names the notice's fields in the order of the event's New() arguments. The last event deletes the map (step A7).
//
// A bridged delivery marks its pair in GLOB.twin_in_flight (event type -> depth), so that twin does not bounce back. Only the pair in flight
// is held: a listener of one twin may emit a different event (a body change raising a medical-issues change) and that one crosses normally. Nothing is built unless the other side has a listener: the
// wants checks (event_twin_wanted(), notice_twin_wanted()) are what om_wants() and notice_wanted() ask.

/// Event type -> count, for each twin pair being delivered across the bridge right now.
GLOBAL_LIST_EMPTY(twin_in_flight)
/// notice type -> list(event type, fields...), built from event_twin_notice on first use.
GLOBAL_LIST_EMPTY(notice_twin_event)
GLOBAL_VAR_INIT(notice_twin_built, FALSE)

/proc/notice_twin_row(notice_type)
	// During global init (a datum deleted while the globals are still being made) the tables may not exist yet: no twin.
	if(!islist(GLOB.notice_twin_event) || !islist(GLOB.event_twin_notice))
		return null
	if(!GLOB.notice_twin_built)
		GLOB.notice_twin_built = TRUE
		for(var/event_type in GLOB.event_twin_notice)
			var/list/row = GLOB.event_twin_notice[event_type]
			GLOB.notice_twin_event[row[1]] = list(event_type) + row.Copy(2)
	return GLOB.notice_twin_event[notice_type]

/// Does the notice side of event `event_type` have a listener on E? (om_wants() asks this when the event itself has none.)
/proc/event_twin_wanted(datum/E, event_type)
	if(GLOB.twin_in_flight?[event_type])
		return FALSE
	var/list/row = GLOB.event_twin_notice[event_type]
	return row && notice_wanted_native(E, row[1], ACT_COMMITTED)

/// Does the event side of notice `notice_type` have an om listener on E?
/proc/notice_twin_wanted(datum/E, notice_type)
	var/list/row = notice_twin_row(notice_type)
	if(row && GLOB.twin_in_flight?[row[1]])
		return FALSE
	return row && om_wants_direct(E, row[1])

/// OM_EMIT of `event` on E: its twin notice is published to the on_notice listeners.
/proc/event_to_notice_twin(datum/E, datum/om/event/event)
	if(GLOB.twin_in_flight?[event.type])
		return
	var/list/row = GLOB.event_twin_notice[event.type]
	if(!row || !notice_wanted_native(E, row[1], ACT_COMMITTED))
		return
	var/datum/notice/N = notice_take(row[1])
	for(var/i in 2 to length(row))
		var/field = row[i]
		var/source_field = copytext(field, -1) == "_" && !(field in event.vars) ? copytext(field, 1, -1) : field
		N.vars[field] = event.vars[source_field] // ALLOW(api): the twin copies the event's payload into the notice by the field names of the generated map
	twin_flight_enter(event.type)
	try
		notice_publish(E, N, ACT_COMMITTED)
	catch(var/exception/fault)
		twin_flight_leave(event.type)
		throw fault
	twin_flight_leave(event.type)

/// A committed notice delivered on holder: its twin event is emitted to the event listeners.
/proc/notice_to_event_twin(datum/holder, datum/notice/N)
	var/list/row = notice_twin_row(N.type)
	if(row && GLOB.twin_in_flight?[row[1]])
		return
	if(!row || !om_wants_direct(holder, row[1]))
		return
	var/event_type = row[1]
	var/list/values = list()
	for(var/i in 2 to length(row))
		values += list(N.vars[row[i]])
	var/datum/om/event/event = new event_type(arglist(values))
	twin_flight_enter(event_type)
	try
		om_emit(holder, event)
	catch(var/exception/fault)
		twin_flight_leave(event_type)
		throw fault
	twin_flight_leave(event_type)

/proc/twin_flight_enter(event_type)
	if(!GLOB.twin_in_flight)
		GLOB.twin_in_flight = list()
	GLOB.twin_in_flight[event_type] = (GLOB.twin_in_flight[event_type] || 0) + 1

/proc/twin_flight_leave(event_type)
	if(!GLOB.twin_in_flight)
		return
	var/depth = (GLOB.twin_in_flight[event_type] || 1) - 1
	if(depth > 0)
		GLOB.twin_in_flight[event_type] = depth
	else
		GLOB.twin_in_flight -= event_type

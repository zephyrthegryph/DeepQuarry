// after_init(delay, parts...) (doc/rewrite/final_api.html, section 3 "Time"; section 6 "Lifecycle"; section 11 entry 11).
//
//	CAPABILITIES(/obj/machinery/door_timer)
//		after_init(0, then(PROC_REF(find_cells)))                  // when the instance's init is complete: the map around it exists
//	CAPABILITIES(/obj/effect/energy_net)
//		after_init(2 SECONDS, then(PROC_REF(check_empty)))         // an after() armed when the instance initializes
//	CAPABILITIES(/obj/structure/timer_door)
//		after_init(nameof(time_til_open), then(PROC_REF(open_up)))  // the delay read per instance from a holder var
//	CAPABILITIES(/obj/effect/gateway/active)
//		after_init(PROC_REF(open_delay), then(PROC_REF(spawn_and_qdel)))  // or asked of a holder proc when it is armed
//
// It is not a separate mechanism: it is an after() on the holder (its own clock, dropped with it, paused in stasis), armed once when the
// instance's init is complete. That moment is the end of its Initialize() (the type's own code after ..() has run) for an instance made at
// runtime, and the close of the map-load frame for one the map loads: by then every atom of the load exists and has initialized, so this is the
// form that replaces LateInitialize(). A delay of 0 runs the parts at that moment; a positive delay arms the timer then.
//
// The handler is x(datum/act/timer/A): A.holder the instance, A.mapload TRUE when it was loaded with the map, A.cap the capability when the entry
// came from a capability's entries(). An enclosing when() gates it once, when it is due. A subtype inherits its parent's after_init() entries; to
// change what one does, override the handler proc (calling ..() keeps the parent's part).

/// after_init(delay, parts...): `delay` is deciseconds, nameof() a holder var read per instance when it is armed, or PROC_REF(x) of a holder
/// proc x(datum/act/timer/A) answering it then (a random wait).
/proc/after_init(delay, p1, p2, p3, p4)
	if(!(istext(delay) && length(delay)) && (!isnum(delay) || delay < 0))
		declare_report("after_init(): the delay must be a number of deciseconds (0 or more) or nameof() a holder var, got [isnull(delay) ? "null" : "[delay]"]")
		return null
	var/list/parts = entry_flatten(list(p1, p2, p3, p4))
	if(!length(parts))
		declare_report("after_init(): no parts: give it then(PROC_REF(x))")
		return null
	return entry_make(ENTRY_AFTER_INIT, null, list("delay" = delay), parts)

/// The engine's init found after_init() entries on `holder` (engine_holder_init()): an atom waits for its Initialize() to return (the atoms
/// system keeps it), any other datum is armed at once.
/proc/after_init_note(datum/holder, mapload)
	if(!isatom(holder))
		after_init_arm(holder, mapload)
		return
	materialization_host().after_init_wait(holder)

/// Arms every after_init() entry of `holder`'s type table: a delay of 0 runs now, a positive one is an after() from now.
/proc/after_init_arm(datum/holder, mapload)
	var/datum/type_table/T = table_of(holder)
	var/index = 0
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_AFTER_INIT))
		index++
		var/datum/entry/E = C.item
		var/delay = E.args["delay"]
		if(istext(delay))
			delay = (delay in holder.vars) ? holder.vars[delay] : call(holder, delay)(null) // nameof(var), or PROC_REF(x) answering it
		if(!isnum(delay) || delay <= 0)
			after_init_fire(holder, C, mapload)
		else
			after(holder, delay, GLOBAL_PROC_REF(after_init_fire), key = "after_init:[index]", with = list(holder, C, mapload))
		if(QDELETED(holder))
			return

/// One after_init() is due: its parts run on the holder (unless an enclosing when() is false now).
/proc/after_init_fire(datum/holder, datum/centry/C, mapload)
	if(!holder || QDELETED(holder) || !C)
		return
	if(!op_whens_hold(holder, C.whens))
		return
	var/datum/entry/E = C.item
	var/datum/act/timer/T = every_context(holder, null, holder, 0)
	T.mapload = !!mapload
	if(!isnull(C.owner))
		T.cap = table_of(holder).caps?[C.owner]
	var/depth = GLOB.act_depth
	try
		hook_run_parts(null, T, E.children)
	catch(var/exception/fault)
		stack_trace("after_init() on [holder.type]: [fault] ([fault.file]:[fault.line])")
	GLOB.act_depth = depth
	T.release()

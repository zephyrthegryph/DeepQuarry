// starts_as(STATE) and derives(target, PROC_REF(x), from =) (doc/rewrite/final_api.html section 6 "Lifecycle forms", form 7).
//
//	CAPABILITIES(/obj/machinery/door/airlock/open_start)
//		starts_as("door.open")                       // the op's effects run at creation: no actor, no messages, no costs, no requirements
//	CAPABILITIES(/obj/machinery/power/apc/hatch_open)
//		starts_as(COVER_OPEN)                        // a state key: the op that sets it runs, or the key is set when no op does
//	CAPABILITIES(/obj/item/tank)
//		derives(nameof(pressure_desc), PROC_REF(describe_pressure), from = list(nameof(pressure), nameof(volume)))
//
// starts_as() replaces the Initialize() that called an op's handler (open(), toggle(), set_state()) to put a mapped variant in a state: the
// op named by its key, or the op that sets the state key, runs its effects on the instance when it initializes, after its capabilities,
// silently (GLOB.starts_as_running is set while it runs: a handler that messages checks it, and says() and plays() parts do not run). It is
// not a player action: nothing is required, reserved, logged or announced.
//
// derives(target, PROC_REF(x), from = list(nameof(a), ...)) keeps `target` equal to x() of the holder: computed at init, recomputed when a var
// in `from` is written (each must publish its writes: TRACKED or a setter calling tracked_changed()), and published itself, so another derives
// or an on_change can read it. x() is pure: it reads the holder and answers the value.

/proc/starts_as(state)
	return entry_make(ENTRY_STARTS_AS, "starts_as:[state]", list("state" = state))

/proc/derives(target, proc_ref, from = null)
	if(!istext(target) || !istext(proc_ref))
		declare_report("derives(): needs nameof(target) and PROC_REF(x)")
		return null
	if(!isnull(from) && !islist(from))
		from = list(from)
	return entry_make(ENTRY_DERIVES, "derives:[target]", list("target" = target, "proc" = proc_ref, "from" = from))

/// TRUE while a starts_as() runs an op's effects: handlers send no messages and start no player-facing work.
GLOBAL_VAR_INIT(starts_as_running, FALSE)
/// holder -> TRUE while one of its derives() computes (a derives that writes what it reads stops after one round).
GLOBAL_LIST_EMPTY(derives_running)

/proc/starts_as_init(datum/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.starts_as)
		var/datum/entry/E = C.item
		if(C.whens && !op_whens_hold(holder, C.whens))
			continue
		starts_as_apply(holder, E.args["state"], C.origin)

/// Puts `holder` in `state`: an op key runs that op's effects; a capability state key runs the op that sets it, or sets the key.
/proc/starts_as_apply(datum/holder, state, origin = null)
	var/datum/op_plan/plan = null
	if(istext(state))
		plan = op_plan_for(holder, state, list())
		if(!plan)
			declare_report("[origin]: starts_as(\"[state]\") on [holder.type]: no op of that key")
			return FALSE
	else if(isnum(state))
		plan = starts_as_plan_setting(holder, state)
		if(!plan)
			cap_key_set(holder, state, TRUE, null)
			return TRUE
	else
		declare_report("[origin]: starts_as([state]) on [holder.type]: a state is an op key or a capability state key")
		return FALSE
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one run and is reset on release
	A.target = holder
	A.key = plan.key
	A.oplan = plan // ALLOW(ownership): a pooled context names its op's plan for one run and is reset on release
	A.outcome = ACT_COMMITTED
	var/was = GLOB.starts_as_running
	GLOB.starts_as_running = TRUE
	. = TRUE
	for(var/datum/entry/part/effect/F as anything in plan.effects)
		if(op_run_effect(A, F) == OP_FAILED)
			declare_report("[origin]: starts_as(\"[plan.key]\") on [holder.type]: effect [F.part_name] failed")
			. = FALSE
			break
	GLOB.starts_as_running = was
	A.release()

/// The op of `holder`'s table whose effects set state key `key_id` to TRUE (toggles() or sets(key, TRUE)), or null.
/proc/starts_as_plan_setting(datum/holder, key_id)
	var/datum/type_table/T = table_of(holder)
	for(var/op_key in op_index_of_table(T).by_key)
		var/datum/op_plan/plan = op_index_of_table(T).by_key[op_key]
		for(var/datum/entry/part/effect/F as anything in plan.effects)
			if(F.args?["key"] != key_id)
				continue
			if(istype(F, /datum/entry/part/effect/toggles) || (istype(F, /datum/entry/part/effect/sets) && F.args["value"]))
				return plan
	return null

/proc/derives_init(datum/holder, datum/lifeform_plan/P)
	for(var/datum/centry/C as anything in P.derives)
		derives_compute(holder, C, TRUE)

/// Recomputes one derives() target; publishes it when it state_changed (not during init, when nothing reads it yet).
/proc/derives_compute(datum/holder, datum/centry/C, init = FALSE)
	var/datum/entry/E = C.item
	var/target = E.args["target"]
	if(!(target in holder.vars))
		declare_report("[C.origin]: derives(\"[target]\") on [holder.type]: no such var")
		return
	var/list/running = GLOB.derives_running
	if(running[holder])
		return
	running[holder] = TRUE
	var/value
	try
		value = call(holder, E.args["proc"])()
	catch(var/exception/e)
		stack_trace("derives([target]) on [holder.type]: [e] ([e.file]:[e.line])")
		running -= holder
		return
	running -= holder
	if(holder.vars[target] == value)
		return
	holder.vars[target] = value // ALLOW(api): the engine writes a derives() target and publishes it
	if(!init)
		tracked_changed(holder, target)

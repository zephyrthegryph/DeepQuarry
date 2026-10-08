// every() of a capability (doc/rewrite/final_api.html, section 10 "Hooks and events", section 16.9; section 19 "E4").
//
//	every(1 SECOND, then(CAP_PROC(drain_energy)))      // in a capability's entries(): runs while the activation lives
//
// A capability's every() is periodic work an ACTIVATION owns. It is applied by the entry engine below when the activation attaches, runs on the
// holder's own clock (so stasis pauses it), and ends with the activation by the one teardown path: a revoked activation is dead at once, so a
// handler that revokes its own activation (the phased drain ending the shift) finishes, and nothing of it ever runs again.
//
// The handler is x(datum/act/A) with the timer context (A.holder the holder, A.cap, A.activation, A.source, A.dt the interval in deciseconds).
// A shadowed activation (a BEST or UNIQUE stack where another activation runs) keeps its clock and skips its handler, so it resumes the moment
// it wins. The system forms of every() (a /datum/system's work items, code/engine/actions/reactions.dm) keep their own shape.

/// every(interval, then(...) | parts..., when = cond, phase =, lane =, members =): one entry. `interval` is deciseconds of the holder's clock, or a PROC_REF of a holder proc
/// x(datum/act/A) answering them, asked again before every run (a flicker that waits a random while). The system form every(interval, PROC_REF(x), ...)
/// is reactions.dm's and never reaches here.
/proc/every_entry(interval, p1, p2, p3, p4, when = null, members = null, phase = null, lane = null)
	if(!(istext(interval) && length(interval)) && (!isnum(interval) || interval <= 0))
		declare_report("every(): the interval must be a positive number of deciseconds or a PROC_REF, got [isnull(interval) ? "null" : "[interval]"]")
		return null
	if(!isnull(phase) && !(phase in list(KERNEL_PHASE_K, KERNEL_PHASE_S, KERNEL_PHASE_N, KERNEL_PHASE_D, KERNEL_PHASE_P, KERNEL_PHASE_R, KERNEL_PHASE_G)))
		declare_report("every(): phase [phase] is not a periodic kernel phase")
		return null
	if(!isnull(lane) && !(lane in list(LANE_URGENT, LANE_SIMULATION, LANE_DERIVED, LANE_PRESENTATION, LANE_BACKGROUND, LANE_WORLD)))
		declare_report("every(): lane [lane] is not a kernel lane")
		return null
	return entry_make(ENTRY_EVERY, null, list("interval" = interval, "when" = when, "members" = members, "phase" = phase, "lane" = lane), entry_flatten(list(p1, p2, p3, p4)))

/datum/entry_engine/every
	kind = ENTRY_EVERY

/datum/entry_engine/every/validate(datum/activation/A, datum/entry/E)
	if(E.args["members"] && A && !istype(A.holder, /datum/system))
		return "every(members =): only a system may sweep members"
	if(!length(E.children))
		return "every() has no parts: give it then(CAP_PROC(x))"
	return null

/datum/entry_engine/every/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	activation_every_arm(A, E)
	return TRUE

/datum/entry_engine/every/remove(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(holder && !QDELETED(holder))
		cancel_after(holder, activation_every_key(A, E))

/// The timer key of one every() of one activation.
/proc/activation_every_key(datum/activation/A, datum/entry/E)
	return "every:[A.serial]:[copytext(md5(E.sig), 1, 9)]"

/// The deciseconds to the next run of an every() on `holder`: its interval, or what the holder proc the interval names answers now (never below one
/// decisecond). The proc gets a real timer context (A is the activation, null for a type-level every()), like a handler. A runtime in it is logged and
/// the every() keeps running on a one second fallback: one fault must not end the every() for the instance's life.
/proc/every_interval(datum/holder, datum/entry/E, datum/activation/A = null)
	var/interval = E.args["interval"]
	if(!istext(interval))
		return interval
	var/datum/act/timer/T = every_context(holder, A, A ? A.source : holder, 0)
	var/answer = 1 SECOND
	try
		answer = call(holder, interval)(T)
	catch(var/exception/fault)
		dq_report_caught(fault, "every() interval [interval] on [holder.type]; re-armed on the fallback")
		answer = 1 SECOND
	T.release()
	return isnum(answer) ? max(1, answer) : 1

/// Does the `when =` condition `cond` of an every() on `holder` hold? A runtime in it is logged and counts as "does not hold" this run (the next run is
/// still armed by the caller).
/proc/every_gate_holds(datum/holder, cond, what)
	var/held = FALSE
	try
		held = !!change_condition(holder, cond)
	catch(var/exception/fault)
		dq_report_caught(fault, "every() gate of [what] on [holder.type]; skipped this run")
	return held

/// The pooled timer context of one every() run: holder, the activation (null for a type-level every()), its source and the interval.
/proc/every_context(datum/holder, datum/activation/A, source, dt)
	var/datum/act/timer/T = take(/datum/act/timer)
	T.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	T.cap = A?.def
	T.activation = A // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	T.source = source // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	T.dt = dt
	return T

/// Arms the next run, an interval from now on the holder's clock.
/proc/activation_every_arm(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder) || A.dead)
		return
	after(holder, every_interval(holder, E, A), GLOBAL_PROC_REF(activation_every_fire), key = activation_every_key(A, E), with = list(A, E), keeps_dead = TRUE)

/// One run of an every(): the handler (unless the activation is shadowed or its when fails), then the next arming unless the handler ended the activation.
/proc/activation_every_fire(datum/activation/A, datum/entry/E, dispatched = FALSE)
	if(!A || !E || A.dead)
		return
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return
	if(!dispatched && every_dispatch_needed(E))
		every_dispatch_queue(E, GLOBAL_PROC_REF(activation_every_fire), list(A, E, TRUE))
		return
	var/gated = A.runs
	var/cond = E.args["when"]
	if(gated && !isnull(cond))
		gated = every_gate_holds(holder, cond, A.def.key)
	if(gated && E.args["members"])
		every_members_start(holder, A, E)
		return
	if(gated)
		var/datum/act/timer/T = every_context(holder, A, A.source, isnum(E.args["interval"]) ? E.args["interval"] : 0)
		var/depth = GLOB.act_depth
		try
			every_run_parts(T, E)
		catch(var/exception/fault)
			dq_report_caught(fault, "every() of [A.def.key] on [holder.type]")
		GLOB.act_depth = depth
		T.release()
	if(!A.dead)
		activation_every_arm(A, E)

// ---- type-level every() ----
//
//	CAPABILITIES(/obj/machinery/x, every(5 SECONDS, then(PROC_REF(tick)), when = "on"))      // work the TYPE owns: runs while the instance lives
//
// An every() written in a type's own CAPABILITIES list (not in a capability's entries()) is armed when the instance initializes (engine_holder_init())
// and runs on the instance's own clock until it is deleted (the entity's timers die with it). Its handler is the same x(datum/act/timer/A) with the holder
// the instance, A.cap and A.activation null, A.source the instance and A.dt the interval. The `when =` argument and any enclosing when() block gate
// each run; a gated run is skipped and the next one still armed, so the work resumes the moment the gate holds again.

/datum/rx_state
	/// The type-level every() entries (by their number among the type's) parked because their `when =` is false: nothing is scheduled for them.
	var/list/every_parked

/// Arms the type-level every() entries of `holder`, an interval from now on its clock. One whose `when =` is false now parks instead (see below).
/proc/type_every_arm(datum/holder, datum/type_table/T)
	var/index = 0
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_EVERY))
		if(!isnull(C.owner))
			continue // a capability's: its activation arms it
		index++
		if(type_every_parkable(holder, C) && !type_every_gate(holder, C))
			type_every_park(holder, index)
			continue
		type_every_schedule(holder, C, index)

/proc/type_every_schedule(datum/holder, datum/centry/C, index)
	var/datum/entry/E = C.item
	after(holder, every_interval(holder, E), GLOBAL_PROC_REF(type_every_fire), key = "every:type:[index]", with = list(holder, C, index), keeps_dead = TRUE)

/// TRUE when the type-level every() `C` is held by its own `when =` alone (no enclosing when() block) and that condition is built only of tracked vars of the
/// holder (nameof(var), cond_not/cond_all/cond_any of those): every write of such a var publishes, so the every() PARKS while the condition is false (no timer
/// runs at all) and wakes when it publishes true (doc section 3, section 7). Any other gate (a block, a proc, a stat, a relation hop: something a write might not
/// announce) keeps the polling form: the timer runs and a gated run is skipped.
/proc/type_every_parkable(datum/holder, datum/centry/C)
	var/datum/entry/E = C.item
	var/cond = E.args["when"]
	if(isnull(cond) || length(C.whens))
		return FALSE
	var/static/list/known = list()
	var/id = "[holder.type]|[E.sig]"
	if(isnull(known[id]))
		known[id] = type_every_cond_tracked(holder, cond) ? TRUE : FALSE
	return known[id]

/// Is `cond` a tracked var of `holder` or a stat id (STAT_RELEVANCE), or a cond_not/cond_all/cond_any tree of them?
/proc/type_every_cond_tracked(datum/holder, cond)
	if(islist(cond))
		var/list/tree = cond
		if(length(tree) < 2)
			return FALSE
		for(var/i in 2 to length(tree))
			if(!type_every_cond_tracked(holder, tree[i]))
				return FALSE
		return TRUE
	if(isnum(cond))
		return cond >= STAT_ID_BASE && cond < CAPKEY_ID_BASE // a stat: every write of it publishes to a reader (the wake hook is one)
	return istext(cond) && (cond in holder.vars) && hascall(holder, "__setter_[cond]")

/// Does the `when =` of the every() `C` hold on the holder now?
/proc/type_every_gate(datum/holder, datum/centry/C)
	var/datum/entry/E = C.item
	var/cond = E.args["when"]
	if(!op_whens_hold(holder, C.whens))
		return FALSE
	return isnull(cond) || !!change_condition(holder, cond)

/// Parks the every() number `index` of `holder`: nothing is scheduled until type_every_wake() finds its condition true.
/proc/type_every_park(datum/holder, index)
	var/datum/rx_state/S = rx_of(holder)
	LAZYOR(S.every_parked, index)

/// The wake of every parked every(): the synthesized on_change hook of an every() with `when =` runs this when the condition becomes true. Each parked
/// every() whose condition holds now is armed an interval from now.
/proc/type_every_wake(datum/act/A)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return
	var/datum/rx_state/S = holder.rx
	if(!length(S?.every_parked))
		return
	var/index = 0
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_EVERY))
		if(!isnull(C.owner))
			continue
		index++
		if(!(index in S.every_parked) || !type_every_gate(holder, C))
			continue
		S.every_parked -= index
		type_every_schedule(holder, C, index)
	if(!length(S.every_parked))
		S.every_parked = null

/// The change hook that wakes a parked every(): ENTER of its `when =`, running type_every_wake(). Built once per every() entry (hooks.dm asks for it).
/proc/type_every_wake_entry(datum/entry/E)
	var/static/list/made = list()
	var/datum/entry/known = made[E.sig]
	if(!known)
		known = entry_make(ENTRY_ON_CHANGE, null, list("cond" = E.args["when"], "edge" = ENTER), list(then(GLOBAL_PROC_REF(type_every_wake))))
		made[E.sig] = known
	return known

/// One run of a type-level every(): the handler unless the gate fails, then the next arming. A parkable every() whose gate fails parks instead of re-arming.
/proc/type_every_fire(datum/holder, datum/centry/C, index, dispatched = FALSE)
	if(!holder || QDELETED(holder) || !C)
		return
	var/datum/entry/E = C.item
	if(!dispatched && every_dispatch_needed(E))
		every_dispatch_queue(E, GLOBAL_PROC_REF(type_every_fire), list(holder, C, index, TRUE))
		return
	var/gated = FALSE
	try
		gated = op_whens_hold(holder, C.whens)
	catch(var/exception/when_fault)
		dq_report_caught(when_fault, "every() when() block on [holder.type]; skipped this run")
	var/cond = E.args["when"]
	if(gated && !isnull(cond))
		gated = every_gate_holds(holder, cond, "type every()")
	if(!gated && type_every_parkable(holder, C))
		type_every_park(holder, index)
		return
	if(gated && E.args["members"])
		every_members_start(holder, null, E, C, index)
		return
	if(gated)
		var/datum/act/timer/T = every_context(holder, null, holder, isnum(E.args["interval"]) ? E.args["interval"] : 0)
		var/depth = GLOB.act_depth
		try
			every_run_parts(T, E)
		catch(var/exception/fault)
			dq_report_caught(fault, "type every() on [holder.type]")
		GLOB.act_depth = depth
		T.release()
	if(!QDELETED(holder))
		type_every_schedule(holder, C, index)

/// A memberless run still uses the same immediate hook protocol.
/proc/every_run_parts(datum/act/timer/T, datum/entry/E)
	return hook_run_parts(null, T, E.children)

/// One snapshot per interval, weakly naming its members. The next interval is
/// armed only when this sweep closes: yielding cannot build a periodic backlog.
/proc/every_members_start(datum/holder, datum/activation/A, datum/entry/E, datum/centry/C = null, index = null)
	if(!istype(holder, /datum/system))
		CRASH("every(members =): [holder.type] is not a system")
	var/list/snapshot = list()
	for(var/datum/member as anything in members_of(E.args["members"]))
		var/handle = entity_handle(member)
		if(handle)
			snapshot += handle
	every_members_queue(holder, A, E, C, index, snapshot, 1)

/// Capture the five entity/context parameters, then append the already-weak
/// snapshot without repeatedly scanning it through capture_args().
/proc/every_members_queue(datum/holder, datum/activation/A, datum/entry/E, datum/centry/C, index, list/snapshot, cursor)
	var/list/captured = capture_args(list(holder, A, E, C, index), TRUE)
	if(!captured)
		return
	var/list/arguments = captured[1]
	arguments += list(snapshot, cursor)
	var/datum/system/S = holder
	every_dispatch_captured(E, GLOBAL_PROC_REF(every_members_fire), captured, S.phase)

/// One member per queued continuation. The kernel work store yields between
/// continuations, retaining this snapshot and cursor until the budget returns.
/proc/every_members_fire(datum/holder, datum/activation/A, datum/entry/E, datum/centry/C, index, list/snapshot, cursor)
	if(!holder || QDELETED(holder) || !E || (!A && !C) || A?.dead)
		return
	var/gated = FALSE
	try
		gated = A ? A.runs : type_every_gate(holder, C)
	catch(var/exception/gate_fault)
		dq_report_caught(gate_fault, "every() member sweep gate on [holder.type]")
	if(A && gated && !isnull(E.args["when"]))
		gated = every_gate_holds(holder, E.args["when"], A.def.key)
	if(!gated)
		if(C && type_every_parkable(holder, C))
			type_every_park(holder, index)
		else if(A)
			activation_every_arm(A, E)
		else
			type_every_schedule(holder, C, index)
		return
	if(cursor <= length(snapshot))
		var/datum/member = resolve_handle(snapshot[cursor])
		if(member && !QDELETED(member) && member_is(E.args["members"], member))
			var/datum/act/timer/T = every_context(holder, A, A ? A.source : holder, isnum(E.args["interval"]) ? E.args["interval"] : 0)
			T.set_member_target(member)
			var/depth = GLOB.act_depth
			try
				hook_run_parts(null, T, E.children)
			catch(var/exception/fault)
				dq_report_caught(fault, "every() member sweep on [holder.type]")
			GLOB.act_depth = depth
			T.set_member_target(null)
			T.release()
		if(QDELETED(holder) || A?.dead)
			return
		every_members_queue(holder, A, E, C, index, snapshot, cursor + 1)
		return
	if(A)
		activation_every_arm(A, E)
	else
		type_every_schedule(holder, C, index)

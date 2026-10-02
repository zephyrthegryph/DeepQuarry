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
// it wins. The system forms of every() (a /datum/system's work items, code/datums/reactions/reactions.dm) keep their own shape.

/// The entry kind of a capability's every().
#define ENTRY_EVERY "every"

/// every(interval, then(...) | parts..., when = cond): one entry. `interval` is deciseconds of the holder's clock. The system form
/// every(interval, PROC_REF(x), ...) is reactions.dm's and never reaches here.
/proc/every_entry(interval, p1, p2, p3, p4, when = null)
	if(!isnum(interval) || interval <= 0)
		declare_report("every(): the interval must be a positive number of deciseconds, got [isnull(interval) ? "null" : "[interval]"]")
		return null
	return entry_make(ENTRY_EVERY, null, list("interval" = interval, "when" = when), entry_flatten(list(p1, p2, p3, p4)))

/datum/entry_engine/every
	kind = ENTRY_EVERY

/datum/entry_engine/every/validate(datum/activation/A, datum/entry/E)
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

/// Arms the next run, an interval from now on the holder's clock.
/proc/activation_every_arm(datum/activation/A, datum/entry/E)
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder) || A.dead)
		return
	after(holder, E.args["interval"], GLOBAL_PROC_REF(activation_every_fire), key = activation_every_key(A, E), with = list(A, E))

/// One run of an every(): the handler (unless the activation is shadowed or its when fails), then the next arming unless the handler ended the activation.
/proc/activation_every_fire(datum/activation/A, datum/entry/E)
	if(!A || !E || A.dead)
		return
	var/datum/holder = A.holder
	if(!holder || QDELETED(holder))
		return
	var/gated = A.runs
	var/cond = E.args["when"]
	if(gated && !isnull(cond))
		gated = !!change_condition(holder, cond)
	if(gated)
		var/datum/act/timer/T = take(/datum/act/timer)
		T.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		T.cap = A.def
		T.activation = A // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		T.source = A.source // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		T.dt = E.args["interval"]
		var/depth = GLOB.act_depth
		try
			hook_run_parts(null, T, E.children)
		catch(var/exception/fault)
			stack_trace("every() of [A.def.key] on [holder.type]: [fault] ([fault.file]:[fault.line])")
		GLOB.act_depth = depth
		T.release()
	if(!A.dead)
		activation_every_arm(A, E)

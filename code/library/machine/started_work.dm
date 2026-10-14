// Started work (doc/rewrite/final_api.html, section 11 "The library", section 3 "every()"): a machine's periodic work that something starts and
// the work itself ends. A machine declares started_work(step = PROC_REF(x)): x(datum/act/timer/A) runs every `interval` while the work is
// started (its state key STARTED_WORK_ACTIVE), and when it answers PROCESS_KILL the work stops until something starts it again
// (work_start(machine): a player's switch, an item put in, a signal). A step that cannot go on without power answers
// work_wait_for_power(src): the work stops and starts again by itself when the machine is powered and whole.
//
//   started_work(step = PROC_REF(x))                            stopped until work_start()
//   started_work(step = PROC_REF(x), starts = TRUE)             started from the machine's initialization
//   started_work(step = PROC_REF(x), starts = PROC_REF(y))      started from its initialization when y(A) answers TRUE
//   started_work(step = PROC_REF(x), when = nameof(v))          ...and it runs only while `when` holds as well (a stat, a tracked var)
//   started_work(step = PROC_REF(x), wakes_on = list(nameof(v)))   ...and any change of v starts it again (work that waits on a state)
//   started_work(step = PROC_REF(x), unpowered = TRUE)          ...and it runs while the machine is not operable too (a step that reads power itself)
//   started_work(step = PROC_REF(x), gate = PROC_REF(y))        ...and a step runs only when y(A) answers TRUE (a computed test, asked each
//                                                                interval; a list of PROC_REFs must all answer TRUE)
//
// This is the final form of the machine pipeline's step stage (the old machine_step() with MACHINE_WAKE() and PROCESS_KILL, deleted): the old wake and sleep
// calls on a machine that declares started work were work_start() and work_stop().

MSG_DEF_SELF(started_work/stopped, "It isn't running.")
MSG_DEF_SELF(started_work/running, "It is running.")

CAPABILITY_TYPE(started_work, CAP_STARTED_WORK, /datum/capability/lib/started_work, key = NONE, step = null, interval = MACHINE_SERVICE_INTERVAL, starts = FALSE, when = null, wakes_on = null, gate = null, unpowered = FALSE)
cap_keys(CAP_STARTED_WORK, ACTIVE = MSG(started_work/stopped), WAITING_POWER = MSG(started_work/running))

/datum/capability/lib/started_work
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/started_work/entries()
	var/gate = when ? cond_all(STARTED_WORK_ACTIVE, when) : STARTED_WORK_ACTIVE
	if(!unpowered)
		gate = cond_all(gate, STAT_OPERABLE) // an unpowered or broken machine's work parks and costs nothing
	. = list(
		every(interval, then(CAP_PROC(run_step)), when = gate),
		on_change(STAT_OPERABLE, ANY, then(CAP_PROC(condition_changed))))
	for(var/key in wakes_on)
		. += on_change(key, ANY, then(CAP_PROC(woken)))

/// A state the work waits on changed: it starts again.
/datum/capability/lib/started_work/proc/woken(datum/act/A)
	key_set(A.holder, STARTED_WORK_WAITING_POWER, FALSE)
	key_set(A.holder, STARTED_WORK_ACTIVE, TRUE)

/datum/capability/lib/started_work/on_holder_init(datum/act/eval/A)
	var/wanted = starts
	if(istext(wanted))
		wanted = call(A.holder, wanted)(A)
	if(wanted)
		key_set(A.holder, STARTED_WORK_ACTIVE, TRUE)

/// One step of the work: the machine's step; PROCESS_KILL ends the work.
/datum/capability/lib/started_work/proc/run_step(datum/act/timer/A)
	for(var/test in (islist(gate) ? gate : (gate ? list(gate) : null)))
		if(!call(A.holder, test)()) // no arguments: a gate may be a proc with optional parameters of its own (operable())
			return
	if(call(A.holder, step)(A) == PROCESS_KILL)
		key_set(A.holder, STARTED_WORK_ACTIVE, FALSE)

/// Power came back or the machine was mended: work that stopped for want of power starts again.
/datum/capability/lib/started_work/proc/condition_changed(datum/act/A)
	var/obj/machinery/M = A.holder
	if(!istype(M) || !cap_key_get(M, STARTED_WORK_WAITING_POWER) || !M.operable())
		return
	key_set(M, STARTED_WORK_WAITING_POWER, FALSE)
	key_set(M, STARTED_WORK_ACTIVE, TRUE)

/// Starts `M`'s work (it runs from its next interval).
/proc/work_start(datum/M)
	if(!M || QDELETED(M) || !cap_of(M, CAP_STARTED_WORK))
		return FALSE
	key_set(M, STARTED_WORK_WAITING_POWER, FALSE)
	key_set(M, STARTED_WORK_ACTIVE, TRUE)
	return TRUE

/// Stops `M`'s work.
/proc/work_stop(datum/M)
	if(!M || QDELETED(M) || !cap_of(M, CAP_STARTED_WORK))
		return FALSE
	key_set(M, STARTED_WORK_WAITING_POWER, FALSE)
	key_set(M, STARTED_WORK_ACTIVE, FALSE)
	return TRUE

/// TRUE while `M`'s work is started.
/proc/work_started(datum/M)
	return !!cap_key_get(M, STARTED_WORK_ACTIVE)

/// For a step: the machine cannot work unpowered or broken; its work stops and starts again by itself once it is powered and whole.
/// Returns PROCESS_KILL: `return work_wait_for_power(src)`.
/proc/work_wait_for_power(obj/machinery/M)
	key_set(M, STARTED_WORK_WAITING_POWER, TRUE)
	return PROCESS_KILL

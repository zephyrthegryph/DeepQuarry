// Expiry runtime (code/__defines/sys_expiry.dm, doc/rewrite/systems.md section 17).

/// D's OM timer clock in deciseconds (the clock after() timers on D run on). Falls back to
/// world.time for a null or deleted datum so a read on a dead holder never runtimes.
/proc/expiry_clock_now(datum/D)
	READS_FROM() // a clock, asked when a choice is made, never cached
	if(!D || QDELETED(D))
		return world.time
	var/datum/om/rec/rec = om_rec_of(D)
	if(!rec)
		return world.time
	return om_timer_local(rec)

// ---- EXPIRY_ON_LAPSE: run a proc when an expiry lapses (code/__defines/sys_expiry.dm) ----
//
// Declarative: EXPIRY_ON_LAPSE(PATH, var, clock, PROC_REF(x)) stores the hook in the type's
// lifecycle declaration table. It is armed (one timer in the holder's "expiry_lapse:<var>" timer
// slot, owned and cancelled with it, on the var's clock) whenever EXPIRY_SET/EXPIRY_EXTEND writes the var, and again at
// materialize for a value that is still running, so it fires however the holder was created or
// restored (a holder that materializes with the expiry not running lapses at once). The slot is
// keyed per var, so re-arming replaces the pending timer: there is never more than one lapse
// timer per var. When it fires the hook runs only if the var has really lapsed; EXPIRY_CLEAR also
// counts as lapsed. Hooks should still be idempotent (a materialize re-arm can re-run one).

/// Called by EXPIRY_SET / EXPIRY_EXTEND with the value being written; returns it unchanged.
/proc/expiry_written(datum/D, var_name, value)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(D)
	if(decls?.expiry_hooks && decls.expiry_hooks[var_name])
		expiry_arm(D, var_name, value)
	return value

/// Schedules D's lapse hook for `var_name` at `value` (a point on the hook's clock).
/// `at_materialize`: the holder is coming into the world, so an expiry that is not running (never
/// set, 0, or already past) is lapsed and the hook runs on the next timer tick.
/proc/expiry_arm(datum/D, var_name, value, at_materialize = FALSE)
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(D)
	var/list/hook = decls?.expiry_hooks?[var_name]
	if(!hook || QDELETED(D) || (!value && (!at_materialize || hook[3])))
		return
	var/left = value - EXPIRY_NOW(D, hook[1])
	if(left < 0)
		left = 0
	after(D, left, GLOBAL_PROC_REF(expiry_lapse_fire), key = "expiry_lapse:[var_name]", with = list(D, var_name))

/proc/expiry_lapse_fire(datum/D, var_name)
	if(QDELETED(D))
		return
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(D)
	var/list/hook = decls?.expiry_hooks?[var_name]
	if(!hook)
		return
	var/value = D.vars[var_name]
	if(value > EXPIRY_NOW(D, hook[1]))
		return // re-set later (its own timer will fire)
	call(D, hook[2])()

/// Legacy contribution APIs forward to the engine store.

/proc/om_apply(datum/target, effect_id, datum/source, duration, value = TRUE, key)
	return contribution_apply(arglist(args))

/proc/om_hold(datum/target, effect_id, datum/source, value = TRUE, key)
	return contribution_hold(arglist(args))

/proc/om_apply_until(datum/target, effect_id, datum/source, expires_at, value = TRUE, key)
	return contribution_apply_until(arglist(args))

/proc/om_contrib_until(datum/om/rec/rec, datum/om/effect/eff, datum/source, expires_at, value = TRUE, key)
	return contribution_contrib_until(arglist(args))

/proc/om_contrib_expiry(datum/om/rec/rec, eidx, datum/source, key)
	return contribution_contrib_expiry(arglist(args))

/proc/om_contrib_release_timed(datum/om/rec/rec, datum/om/effect/eff)
	return contribution_contrib_release_timed(arglist(args))

/proc/om_expires_at(datum/target, effect_id, datum/source, key)
	return contribution_expires_at(arglist(args))

/proc/om_time_of(datum/E)
	return scheduler_time_of(arglist(args))

/proc/om_release(datum/target, effect_id, datum/source, key)
	return contribution_release(arglist(args))

/proc/om_has(datum/target, effect_id)
	return contribution_has(arglist(args))

/proc/om_value_of(datum/target, effect_id)
	return contribution_value_of(arglist(args))

/proc/om_contrib_find(datum/om/rec/rec, eidx, source, key)
	return contribution_contrib_find(arglist(args))

/proc/om_contrib_set(datum/om/rec/rec, datum/om/effect/eff, datum/source, value, expires, key, duration, exact = FALSE)
	return contribution_contrib_set(arglist(args))

/proc/om_contrib_remove(datum/om/rec/rec, datum/om/effect/eff, i)
	return contribution_contrib_remove(arglist(args))

/proc/om_cval_drop(datum/om/rec/rec, eidx)
	return contribution_cval_drop(arglist(args))

/proc/om_effect_value(datum/om/rec/rec, datum/om/effect/eff)
	return contribution_effect_value(arglist(args))

/proc/om_effect_eval(datum/om/rec/rec, expr)
	return contribution_effect_eval(arglist(args))

/proc/om_effect_changed(datum/om/rec/rec, datum/om/effect/eff, old)
	return contribution_effect_changed(arglist(args))

/proc/om_expiry_reschedule(datum/om/rec/rec)
	return contribution_expiry_reschedule(arglist(args))

/proc/om_release_all_from(datum/source)
	return contribution_release_all_from(arglist(args))

/proc/om_clear_target(datum/E)
	return contribution_clear_target(arglist(args))

/proc/om_reconcile_holds(datum/om/rec/rec, bid, epoch)
	return contribution_reconcile_holds(arglist(args))

/proc/om_release_hook_holds(datum/om/rec/rec, bid)
	return contribution_release_hook_holds(arglist(args))

/proc/om_grant(target, kind, id, datum/source)
	return contribution_grant(arglist(args))

/proc/om_revoke(target, kind, id, datum/source)
	return contribution_revoke(arglist(args))

/proc/om_has_grant(target, kind, id)
	READS_FROM() // Grant queries are evaluated at choice time, matching the engine implementation.
	return contribution_has_grant(arglist(args))

/proc/om_grant_sources(target, kind, id)
	return contribution_grant_sources(arglist(args))

/proc/om_grants_from(target, datum/source)
	return contribution_grants_from(arglist(args))

/proc/om_clock_entry(datum/om/rec/rec, cidx)
	return contribution_clock_entry(arglist(args))

/proc/om_clock_compute(datum/om/rec/rec, cidx)
	return contribution_clock_compute(arglist(args))

/proc/om_clock_rate(datum/om/rec/rec, cidx)
	return contribution_clock_rate(arglist(args))

/proc/om_clock_local(datum/om/rec/rec, cidx)
	return contribution_clock_local(arglist(args))

/proc/om_clock_settle(datum/om/rec/rec, cidx)
	return contribution_clock_settle(arglist(args))

/proc/om_clock_changed(datum/om/rec/rec, cidx)
	return contribution_clock_changed(arglist(args))

/datum/om/behaviour/internal/expiry
	parent_type = /datum/scheduled_behaviour/internal/expiry
	abstract_type = /datum/om/behaviour/internal/expiry

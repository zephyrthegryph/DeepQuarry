// Legacy spellings forward to the time engine; timer state and execution live there.

/proc/om_handle(datum/D)
	return entity_handle(arglist(args))

/proc/om_handle_of(datum/D)
	return entity_handle_of(arglist(args))

/proc/om_handle_is(h, datum/D)
	return entity_handle_is(arglist(args))

/proc/om_handle_park(datum/D)
	return entity_handle_park(arglist(args))

/proc/om_handle_unpark(datum/D, id)
	return entity_handle_unpark(arglist(args))

/proc/om_handle_release_parked(id)
	return entity_handle_release_parked(arglist(args))

/proc/om_resolve(h)
	return resolve_handle(arglist(args))

/proc/om_handle_collected_report(target_type)
	return entity_handle_collected_report(arglist(args))

/proc/om_handle_release(datum/D)
	return entity_handle_release(arglist(args))

/proc/om_is_handle(h)
	return is_entity_handle(arglist(args))

/proc/om_capture_value(value, depth, nulls_for_gone = FALSE)
	return capture_value(arglist(args))

/proc/om_callable(datum/target, proc_ref, ...)
	return deferred_call(arglist(args))

/proc/om_run(list/spec, ...)
	return deferred_run(arglist(args))

/proc/om_run_async(list/spec, ...)
	return deferred_run_async(arglist(args))

/proc/om_resolve_value(value, nulls_for_gone)
	return resolve_captured_value(arglist(args))

/proc/om_global_owner()
	RETURN_TYPE(/datum/om/global_owner)
	return timer_global_owner(arglist(args))

/proc/om_cancel_timer_slot(datum/E, slot)
	return timer_cancel_slot(arglist(args))

/proc/om_timer_slot_pending(datum/E, slot)
	return timer_slot_pending(arglist(args))

/proc/om_timer_slot_left(datum/E, slot)
	return timer_slot_left(arglist(args))

/proc/om_proc_is_global(proc_ref)
	return deferred_proc_is_global(arglist(args))

/proc/om_timer_index(datum/om/rec/rec, id)
	return timer_index(arglist(args))

/proc/om_timer_remove_at(datum/om/rec/rec, at)
	return timer_remove_at(arglist(args))

/proc/om_timers_recompute_soonest(datum/om/rec/rec)
	return timers_recompute_soonest(arglist(args))

/proc/om_timers_clear(datum/om/rec/rec)
	return timers_clear(arglist(args))

/proc/om_timer_heap_push(datum/om/rec/rec, due, id)
	return timer_heap_push(arglist(args))

/proc/om_timer_heap_pop(datum/om/rec/rec)
	return timer_heap_pop(arglist(args))

/proc/om_timer_heap_clean_top(datum/om/rec/rec)
	return timer_heap_clean_top(arglist(args))

/proc/om_timer_heap_rebuild(datum/om/rec/rec)
	return timer_heap_rebuild(arglist(args))

/proc/om_cancel_timer(datum/E, id)
	return timer_cancel(arglist(args))

/proc/om_timer_pending(datum/E, id)
	return timer_pending(arglist(args))

/proc/om_timer_left(datum/E, id)
	return timer_left(arglist(args))

/proc/om_timer_rate(datum/om/rec/rec)
	return timer_rate(arglist(args))

/proc/om_timer_local(datum/om/rec/rec)
	return timer_local(arglist(args))

/proc/om_timers_rate_changed(datum/om/rec/rec)
	return timers_rate_changed(arglist(args))

/proc/om_timers_reschedule(datum/om/rec/rec)
	return timers_reschedule(arglist(args))

/proc/om_timers_arm(datum/om/rec/rec)
	return timers_arm(arglist(args))

/proc/om_invoke(datum/E, proc_ref, list/call_args, is_global = null)
	return deferred_invoke(arglist(args))

/proc/om_guarded_call(datum/E, proc_ref, list/call_args, is_global = null)
	return deferred_guarded_call(arglist(args))

/proc/om_trampoline(list/state, datum/E, proc_ref, list/call_args, is_global = null)
	return deferred_trampoline(arglist(args))

/proc/om_captured_matches(captured_value, arg)
	return captured_matches(arglist(args))

/proc/om_realtime_fire(due, proc_ref, ...)
	return timer_realtime_fire(arglist(args))

/datum/om/global_owner
	parent_type = /datum/timer_owner

// Legacy carriers still declare relations on this concrete owner subtype.
/datum/time_scheduler/make_timer_owner()
	return new /datum/om/global_owner

/datum/proc/om_timer_clock()
	return timer_clock()

/mob/living/timer_clock()
	return CLOCK_BIO

/datum/om/behaviour/internal/timers
	parent_type = /datum/scheduled_behaviour/internal/timers
	abstract_type = /datum/om/behaviour/internal/timers

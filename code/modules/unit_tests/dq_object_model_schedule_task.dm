#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/datum/object_model_test_actor
	var/timer_hits = 0
	var/wake_hits = 0
	var/periodic_hits = 0
	var/rearm_hits = 0
	var/stock = 0
	var/watch_hits = 0
	var/watch_truth = FALSE
	var/rate_hits = 0
	var/clock_seconds = 0

/datum/object_model/behaviour/test_clocked
	run_clock = /datum/object_model/clock_domain/biology
	run_period = 10 SECONDS

/datum/object_model/behaviour/test_clocked/on_run(datum/source, seconds, list/config)
	var/datum/object_model_test_actor/A = source
	A.timer_hits++
	A.clock_seconds = seconds
	return null

/datum/object_model_test_clocked
	parent_type = /datum/object_model_test_actor

/datum/object_model_test_clocked/om_declare(datum/object_model/archetype/A)
	..()
	A.add(/datum/object_model/behaviour/test_clocked)

/datum/object_model/behaviour/test_suspended
	run_set = /datum/object_model/schedule_set/biology
	run_period = 10 SECONDS

/datum/object_model/behaviour/test_suspended/on_run(datum/source, seconds, list/config)
	var/datum/object_model_test_actor/A = source
	A.timer_hits++
	A.clock_seconds = seconds
	return null

/datum/object_model_test_suspended
	parent_type = /datum/object_model_test_actor

/datum/object_model_test_suspended/om_declare(datum/object_model/archetype/A)
	..()
	A.add(/datum/object_model/behaviour/test_suspended)

/datum/unit_test/dq_object_model_schedule_suspension
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_schedule_suspension/Run()
	var/datum/object_model_test_suspended/A = new
	var/datum/first = new
	var/datum/second = new
	var/datum/object_model/suspension/hold_a = om_suspend(A, /datum/object_model/schedule_set/biology, first)
	var/datum/object_model/suspension/hold_b = om_suspend(A, /datum/object_model/schedule_set/biology, second)
	TEST_ASSERT_NOTNULL(hold_a, "first suspension has a token")
	TEST_ASSERT_NOTNULL(hold_b, "second suspension has a token")
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(A)
	R.run_ready()
	TEST_ASSERT_EQUAL(A.timer_hits, 0, "suspended behaviour does not run")
	TEST_ASSERT(R.run_suspended[/datum/object_model/behaviour/test_suspended], "suspended work remains pending")
	om_resume(hold_a)
	R.run_ready()
	TEST_ASSERT_EQUAL(A.timer_hits, 0, "one of two holds cannot resume the set")
	qdel(second)
	R.run_ready()
	TEST_ASSERT_EQUAL(A.timer_hits, 1, "source deletion releases the final hold")
	TEST_ASSERT_EQUAL(A.clock_seconds, 0, "resumed work does not catch up suspended time")
	qdel(first)
	qdel(A)

/datum/unit_test/dq_object_model_virtual_clock
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_virtual_clock/Run()
	var/datum/object_model_test_clocked/A = new
	var/datum/source = new
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(A)
	TEST_ASSERT_NOTNULL(R, "clocked actor needs a behaviour runtime")
	R.run_ready()
	TEST_ASSERT_EQUAL(A.timer_hits, 1, "clocked behaviour starts once")
	var/path = /datum/object_model/behaviour/test_clocked
	var/initial_due = R.run_due[path]
	TEST_ASSERT(initial_due > world.time, "clocked behaviour has a world deadline")
	var/initial_clock_due = R.run_clock_due[path]
	om_behaviour_wake(A, path)
	R.run_ready()
	TEST_ASSERT_EQUAL(R.run_clock_due[path], initial_clock_due, "a change wake cannot postpone virtual-time work")
	TEST_ASSERT(om_clock_set(A, /datum/object_model/clock_domain/biology, source, 2), "rate source was accepted")
	TEST_ASSERT(R.run_due[path] < initial_due, "double-rate clock advances the deadline")
	var/datum/object_model/clock_state/C = om_clock_for(A, /datum/object_model/clock_domain/biology)
	var/before = C.settle()
	C.last_world -= 10
	TEST_ASSERT_EQUAL(C.settle(), before + 20, "virtual time integrates elapsed world time at the old rate")
	TEST_ASSERT(om_clock_set(A, /datum/object_model/clock_domain/biology, source, 2, 1), "inhibition was accepted")
	TEST_ASSERT_EQUAL(C.rate, 0, "total inhibition stops the clock")
	TEST_ASSERT_NULL(R.run_due[path], "stopped clock has no reactor deadline")
	TEST_ASSERT_NOTNULL(R.run_clock_due[path], "stopped clock retains pending virtual work")
	TEST_ASSERT(om_clock_set(A, /datum/object_model/clock_domain/biology, source, 2, 0), "clock resumed")
	TEST_ASSERT(R.run_due[path] > world.time, "resuming re-arms the deadline")
	qdel(source)
	TEST_ASSERT_EQUAL(C.rate, 1, "deleting a source removes its clock effect")
	qdel(A)

/// Independent time sources compose without stealing another source's contribution.
/datum/unit_test/dq_object_model_clock_sources
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_clock_sources/Run()
	var/datum/object_model_test_clocked/A = new
	var/datum/slow_source = new
	var/datum/fast_source = new
	var/domain = /datum/object_model/clock_domain/biology
	var/datum/object_model/clock_state/C = om_clock_for(A, domain)
	TEST_ASSERT(om_clock_set(A, domain, slow_source, 1, 0.5), "the slowing source was accepted")
	TEST_ASSERT_EQUAL(C.rate, 0.5, "half inhibition halves local time")
	TEST_ASSERT(om_clock_set(A, domain, fast_source, 4), "the speeding source was accepted")
	TEST_ASSERT_EQUAL(C.rate, 2, "independent speed and inhibition compose")
	var/before = C.settle()
	C.last_world -= 10
	TEST_ASSERT_EQUAL(C.settle(), before + 20, "elapsed time is charged at the old composed rate")
	TEST_ASSERT(om_clock_set(A, domain, slow_source, 1, 1), "total inhibition was accepted")
	TEST_ASSERT_EQUAL(C.rate, 0, "total inhibition pauses despite another speed source")
	qdel(slow_source)
	TEST_ASSERT_EQUAL(C.rate, 4, "deleting the inhibition source resumes the remaining speed")
	TEST_ASSERT(om_clock_set(A, domain, fast_source), "default contribution removes the speed source")
	TEST_ASSERT_EQUAL(C.rate, 1, "removing the final source restores real time")
	qdel(fast_source)
	qdel(A)

/datum/object_model_test_actor/om_on_timer(datum/entity, key)
	if(key == "test")
		timer_hits++

/datum/object_model_test_actor/proc/on_owned_timer()
	timer_hits++

/datum/object_model_test_actor/proc/on_rearming_timer()
	rearm_hits++
	if(rearm_hits == 1)
		EnsureAfter(world.tick_lag, PROC_REF(on_rearming_timer))

/datum/object_model_test_actor/proc/on_owned_periodic(seconds)
	periodic_hits++

/datum/object_model_test_actor/om_on_wake(datum/entity, reason)
	wake_hits++

/datum/object_model_test_actor/om_on_periodic(datum/entity, seconds)
	periodic_hits++

/datum/object_model_test_actor/om_watch_value(datum/entity, datum/subject, key)
	var/datum/object_model_test_actor/stock_owner = subject
	return stock_owner.stock > 0

/datum/object_model_test_actor/om_on_watch(datum/entity, datum/subject, key, truth, previous)
	watch_hits++
	watch_truth = truth

/datum/object_model_test_actor/om_on_rate(datum/entity, key, crossing, value)
	rate_hits++

/datum/object_model_test_declared_rate
	parent_type = /datum/object_model_test_actor

/datum/object_model_test_declared_rate/om_declare(datum/object_model/archetype/A)
	..()
	A.rate("charge", 0, 20, list("half" = list(REACT_CMP_ABOVE, 5)), 2)

/datum/object_model/event/test_declared_watch_transition

/datum/object_model/behaviour/test_declared_watch_listener
	events = list(/datum/object_model/event/test_declared_watch_transition)

/datum/object_model/behaviour/test_declared_watch_listener/on_event(datum/source, datum/object_model/event/E, a, b, c, d, list/config)
	var/datum/object_model_test_actor/actor = source
	actor.watch_hits++
	actor.watch_truth = b

/datum/object_model/watch_definition/test_declared_stock
	event_path = /datum/object_model/event/test_declared_watch_transition

/datum/object_model/watch_definition/test_declared_stock/test(datum/entity, datum/subject, list/config)
	var/datum/object_model_test_actor/actor = subject
	return actor.stock > 0

/datum/object_model_test_declared_watch
	parent_type = /datum/object_model_test_actor

/datum/object_model_test_declared_watch/om_declare(datum/object_model/archetype/A)
	..()
	A.add(/datum/object_model/behaviour/test_declared_watch_listener)
	A.watch(/datum/object_model/watch_definition/test_declared_stock)

/datum/object_model_test_related_watch
	parent_type = /datum/object_model_test_actor

/datum/object_model/relation/test_declared_watch_subject
	from_type = /datum/object_model_test_related_watch
	to_type = /datum/object_model_test_actor
	source_single = TRUE

/datum/object_model/watch_definition/test_declared_related_stock
	event_path = /datum/object_model/event/test_declared_watch_transition
	relation_path = /datum/object_model/relation/test_declared_watch_subject

/datum/object_model/watch_definition/test_declared_related_stock/test(datum/entity, datum/subject, list/config)
	var/datum/object_model_test_actor/actor = subject
	return actor.stock > 0

/datum/object_model_test_related_watch/om_declare(datum/object_model/archetype/A)
	..()
	A.add(/datum/object_model/behaviour/test_declared_watch_listener)
	A.relation(/datum/object_model/relation/test_declared_watch_subject)
	A.watch(/datum/object_model/watch_definition/test_declared_related_stock)

/datum/object_model/task/object_model_test_purchase
	duration = 10 SECONDS

/datum/object_model/task/object_model_test_purchase/check(datum/object_model/check/task/C, datum/actor, datum/object, datum/implement, list/parameters)
	var/datum/object_model_test_actor/stock_owner = object
	C.unchanged(stock_owner)
	C.require(stock_owner.stock > 0, "Sold out.")

/datum/object_model/task/object_model_test_purchase/complete(datum/actor, datum/object, datum/implement, list/parameters)
	var/datum/object_model_test_actor/stock_owner = object
	stock_owner.stock--
	om_bump_revision(stock_owner)

/datum/object_model/task/prompt/object_model_test_prompt

/datum/object_model/task/prompt/object_model_test_prompt/check(datum/object_model/check/task/C, datum/actor, datum/object, datum/implement, list/parameters)
	C.unchanged(object)

/datum/object_model/task/prompt/object_model_test_prompt/answered(datum/actor, datum/object, datum/implement, list/parameters, answer)
	var/datum/object_model_test_actor/stock_owner = object
	if(answer == "yes")
		stock_owner.stock++

/datum/object_model/task/object_model_test_movement
	duration = 10 SECONDS
	watch_actor_location = TRUE
	watch_target_location = TRUE

/datum/object_model/event/object_model_test_task_dependency_changed

/datum/object_model/task/object_model_test_dependency
	duration = 10 SECONDS

/datum/object_model/task/object_model_test_dependency/check(datum/object_model/check/task/C, datum/actor, datum/object, datum/implement, list/parameters)
	var/datum/object_model_test_actor/stock_owner = object
	C.require(stock_owner.stock > 0, "Sold out.", list(/datum/object_model/event/object_model_test_task_dependency_changed))

/datum/object_model/task/object_model_test_dependency_stamp
	duration = 10 SECONDS

/datum/object_model/task/object_model_test_dependency_stamp/check(datum/object_model/check/task/C, datum/actor, datum/object, datum/implement, list/parameters)
	C.unchanged(object)
	C.require(TRUE, null, list(/datum/object_model/event/object_model_test_task_dependency_changed))

/datum/unit_test/dq_object_model_task_declared_dependency
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_task_declared_dependency/Run()
	var/datum/object_model_test_actor/actor = new
	var/datum/object_model_test_actor/stock_owner = new
	stock_owner.stock = 1
	var/datum/object_model/task/T = om_start_task(/datum/object_model/task/object_model_test_dependency, actor, stock_owner)
	TEST_ASSERT(istype(T), "task with a declared event dependency did not start")
	TEST_ASSERT_EQUAL(length(T.dependency_subscriptions), 2, "task did not subscribe to both participants")
	om_emit(stock_owner, /datum/object_model/event/object_model_test_task_dependency_changed)
	TEST_ASSERT(!QDELETED(T), "valid dependency event canceled the task")
	stock_owner.stock = 0
	om_emit(stock_owner, /datum/object_model/event/object_model_test_task_dependency_changed)
	TEST_ASSERT(QDELETED(T), "declared dependency event did not cancel the invalid task")
	T = om_start_task(/datum/object_model/task/object_model_test_dependency, actor, stock_owner)
	TEST_ASSERT(!istype(T), "task started after its requirement failed")
	T = om_start_task(/datum/object_model/task/object_model_test_dependency_stamp, actor, stock_owner)
	TEST_ASSERT(istype(T), "stamp task did not start")
	om_bump_revision(stock_owner)
	om_emit(stock_owner, /datum/object_model/event/object_model_test_task_dependency_changed)
	TEST_ASSERT(QDELETED(T), "dependency recheck overwrote the task's initial revision stamp")
	qdel(actor)
	qdel(stock_owner)

/datum/unit_test/dq_object_model_task_interrupts_on_move
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_task_interrupts_on_move/Run()
	var/turf/first = locate(1, 1, 1)
	var/turf/second = locate(2, 1, 1)
	var/obj/actor = new(first)
	var/obj/target = new(first)
	var/datum/object_model/task/T = om_start_task(/datum/object_model/task/object_model_test_movement, actor, target)
	TEST_ASSERT(istype(T), "guarded task did not start")
	actor.forceMove(second)
	TEST_ASSERT(QDELETED(T), "actor movement did not interrupt task")
	T = om_start_task(/datum/object_model/task/object_model_test_movement, actor, target)
	TEST_ASSERT(istype(T), "second guarded task did not start")
	target.forceMove(second)
	TEST_ASSERT(QDELETED(T), "target movement did not interrupt task")
	qdel(actor)
	qdel(target)

/datum/unit_test/dq_object_model_timed_action_compat
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_timed_action_compat/Run()
	var/turf/spot = locate(1, 1, 1)
	var/mob/actor = new(spot)
	var/obj/target = new(spot)
	TEST_ASSERT(do_after(actor, 0, target, progress = FALSE), "zero-duration do_after did not complete")
	TEST_ASSERT(!LAZYACCESS(actor.do_afters, target), "compatibility action left its interaction count")
	qdel(actor)
	qdel(target)

/datum/object_model_test_do_after_signals
	var/began = 0
	var/ended = 0

/datum/object_model_test_do_after_signals/proc/on_began(datum/source)
	SIGNAL_HANDLER
	began++

/datum/object_model_test_do_after_signals/proc/on_ended(datum/source)
	SIGNAL_HANDLER
	ended++

/datum/unit_test/dq_object_model_do_after_interaction_count
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_do_after_interaction_count/Run()
	var/turf/spot = locate(1, 1, 1)
	var/mob/actor = new(spot)
	var/obj/target = new(spot)
	var/datum/object_model_test_do_after_signals/signals = new
	signals.RegisterSignal(actor, COMSIG_DO_AFTER_BEGAN, TYPE_PROC_REF(/datum/object_model_test_do_after_signals, on_began))
	signals.RegisterSignal(actor, COMSIG_DO_AFTER_ENDED, TYPE_PROC_REF(/datum/object_model_test_do_after_signals, on_ended))
	LAZYSET(actor.do_afters, target, 1)
	TEST_ASSERT(!do_after(actor, 0, target, progress = FALSE), "interaction cap allowed an action")
	TEST_ASSERT_EQUAL(signals.began, 0, "capped action emitted a begin signal")
	TEST_ASSERT(do_after(actor, 0, target, max_interact_count = 2, progress = FALSE), "allowed concurrent action did not complete")
	TEST_ASSERT_EQUAL(LAZYACCESS(actor.do_afters, target), 1, "concurrent action did not release only its reservation")
	TEST_ASSERT_EQUAL(signals.began, 1, "action did not emit one begin signal")
	TEST_ASSERT_EQUAL(signals.ended, 1, "action did not emit one end signal")
	LAZYREMOVE(actor.do_afters, target)
	signals.UnregisterSignal(actor, list(COMSIG_DO_AFTER_BEGAN, COMSIG_DO_AFTER_ENDED))
	qdel(signals)
	qdel(actor)
	qdel(target)

/datum/unit_test/dq_object_model_do_after_interrupts
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_do_after_interrupts/Run()
	var/turf/first = locate(1, 1, 1)
	var/turf/second = locate(2, 1, 1)
	var/mob/actor = new(first)
	var/obj/target = new(first)
	spawn(world.tick_lag)
		actor.forceMove(second)
	TEST_ASSERT(!do_after(actor, 5 * world.tick_lag, target, progress = FALSE), "movement did not interrupt do_after")
	TEST_ASSERT(!LAZYACCESS(actor.do_afters, target), "interrupted action left its interaction reservation")
	qdel(actor)
	qdel(target)

/datum/unit_test/dq_object_model_owned_timer
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_owned_timer/Run()
	var/datum/object_model_test_actor/owner = new
	var/datum/object_model/schedule_entry/E = om_timer(owner, 3 * world.tick_lag, owner, "test")
	TEST_ASSERT(E, "owned timer was not created")
	qdel(owner)
	sleep(5 * world.tick_lag)
	TEST_ASSERT(QDELETED(E), "timer survived owner destruction")

/datum/unit_test/dq_object_model_proc_timers
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_proc_timers/Run()
	var/datum/object_model_test_actor/owner = new
	var/datum/object_model/schedule_entry/once = owner.After(2 * world.tick_lag, TYPE_PROC_REF(/datum/object_model_test_actor, on_owned_timer))
	var/datum/object_model/schedule_entry/repeating = owner.Every(2 * world.tick_lag, TYPE_PROC_REF(/datum/object_model_test_actor, on_owned_periodic))
	TEST_ASSERT(once && repeating && om_owner(once) == owner && om_owner(repeating) == owner, "proc timers should be owned")
	sleep(5 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.timer_hits, 1, "one-shot proc timer fired the wrong number of times")
	TEST_ASSERT(owner.periodic_hits > 0, "periodic proc timer did not fire")
	qdel(owner)
	TEST_ASSERT(QDELETED(repeating), "periodic proc timer survived owner destruction")

/datum/unit_test/dq_object_model_keyed_proc_timers
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_keyed_proc_timers/Run()
	var/datum/object_model_test_actor/owner = new
	var/callback = TYPE_PROC_REF(/datum/object_model_test_actor, on_owned_timer)
	var/datum/object_model/schedule_entry/first = owner.EnsureAfter(5 * world.tick_lag, callback)
	TEST_ASSERT(first && owner.PendingAfter(callback) == first, "keyed timer should be pending")
	TEST_ASSERT(owner.EnsureAfter(2 * world.tick_lag, callback) == first, "ensure should preserve first timer")
	var/datum/object_model/schedule_entry/second = owner.ReplaceAfter(2 * world.tick_lag, callback)
	TEST_ASSERT(second && second != first && QDELETED(first), "replace should cancel old deadline")
	sleep(4 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.timer_hits, 1, "replacement should invoke callback once")
	TEST_ASSERT(!owner.PendingAfter(callback), "key should clear before or during callback")
	TEST_ASSERT(!owner.CancelAfter(callback), "elapsed timer should not be cancellable")
	owner.EnsureAfter(world.tick_lag, TYPE_PROC_REF(/datum/object_model_test_actor, on_rearming_timer))
	sleep(4 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.rearm_hits, 2, "callback should be able to rearm its own proc key")
	TEST_ASSERT(!owner.PendingAfter(TYPE_PROC_REF(/datum/object_model_test_actor, on_rearming_timer)), "rearmed timer should clear after firing")
	var/datum/object_model/schedule_entry/third = owner.EnsureAfter(5 * world.tick_lag, callback)
	TEST_ASSERT(owner.CancelAfter(callback) && QDELETED(third), "cancel should delete pending keyed timer")
	var/datum/object_model/schedule_entry/fourth = owner.EnsureAfter(5 * world.tick_lag, callback)
	qdel(owner)
	TEST_ASSERT(QDELETED(fourth), "owner deletion should cancel keyed timer")

/datum/unit_test/dq_telecube_owned_cooldown
	needs_test_block = FALSE

/datum/unit_test/dq_telecube_owned_cooldown/Run()
	var/obj/item/telecube/cube = new(locate(1, 1, 1))
	cube.cooldown_time = 2 * world.tick_lag
	cube.cooldown()
	var/datum/object_model/schedule_entry/first = cube.cooldown_timer
	TEST_ASSERT(first && om_owner(first) == cube, "telecube cooldown is not owned by the cube")
	TEST_ASSERT(!cube.ready, "telecube did not enter cooldown")
	cube.cooldown()
	TEST_ASSERT(cube.cooldown_timer == first, "repeated cooldown created another timer")
	sleep(4 * world.tick_lag)
	TEST_ASSERT(cube.ready && !cube.cooldown_timer, "telecube did not become ready when its timer fired")
	cube.cooldown_time = 10 * world.tick_lag
	cube.cooldown()
	var/datum/object_model/schedule_entry/second = cube.cooldown_timer
	qdel(cube)
	TEST_ASSERT(QDELETED(second), "telecube cooldown survived cube destruction")

/datum/unit_test/dq_germ_sensitive_owned_timer
	needs_test_block = FALSE

/datum/unit_test/dq_germ_sensitive_owned_timer/Run()
	var/turf/simulated/floor/floor_turf
	for(var/turf/simulated/floor/candidate in world)
		if(!candidate.get_gravity() || islava(candidate) || ismineralturf(candidate))
			continue
		var/elevated = FALSE
		for(var/atom/movable/content as anything in candidate.contents)
			if(GLOB.typecache_elevated_structures[content.type])
				elevated = TRUE
				break
		if(!elevated)
			floor_turf = candidate
			break
	TEST_ASSERT(floor_turf, "no gravity floor available for germ exposure test")
	var/obj/item/food = new(floor_turf)
	var/datum/component/germ_sensitive/germs = food.AddComponent(/datum/component/germ_sensitive)
	TEST_ASSERT(germs, "germ sensitive component did not attach")
	var/datum/object_model/schedule_entry/first = germs.PendingAfter(TYPE_PROC_REF(/datum/component/germ_sensitive, expose_to_germs))
	TEST_ASSERT(first, "floor exposure did not start a timer")
	germs.handle_movement()
	TEST_ASSERT(germs.PendingAfter(TYPE_PROC_REF(/datum/component/germ_sensitive, expose_to_germs)) == first, "repeated movement restarted the exposure countdown")
	SEND_SIGNAL(food, COMSIG_ITEM_PICKUP, null)
	TEST_ASSERT(!germs.PendingAfter(TYPE_PROC_REF(/datum/component/germ_sensitive, expose_to_germs)) && QDELETED(first), "pickup did not cancel the exposure countdown")
	food.moveToNullspace()
	food.forceMove(floor_turf)
	var/datum/object_model/schedule_entry/second = germs.PendingAfter(TYPE_PROC_REF(/datum/component/germ_sensitive, expose_to_germs))
	TEST_ASSERT(second && second != first, "returning to floor did not start a new countdown")
	qdel(food)
	TEST_ASSERT(QDELETED(second), "exposure countdown survived its food")

/datum/unit_test/dq_object_model_expire_rearm
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_expire_rearm/Run()
	var/obj/item/thing = new
	thing.expire(5 * world.tick_lag)
	var/datum/object_model/schedule_entry/old_entry = thing.lifecycle_lifetime_timer
	TEST_ASSERT(old_entry && om_owner(old_entry) == thing, "expiry timer is not owned by its atom")
	thing.expire(9 * world.tick_lag)
	TEST_ASSERT(QDELETED(old_entry), "rearming expiry left the previous timer alive")
	sleep(6 * world.tick_lag)
	TEST_ASSERT(!QDELETED(thing), "old expiry deleted the atom after rearming")
	sleep(5 * world.tick_lag)
	TEST_ASSERT(QDELETED(thing), "rearmed expiry did not delete the atom")

/datum/unit_test/dq_object_model_expire_owner_deletion
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_expire_owner_deletion/Run()
	var/obj/item/thing = new
	thing.expire(5 * world.tick_lag)
	var/datum/object_model/schedule_entry/entry = thing.lifecycle_lifetime_timer
	qdel(thing)
	TEST_ASSERT(QDELETED(entry), "expiry entry survived atom destruction")

/datum/unit_test/dq_object_model_wake_coalesces
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_wake_coalesces/Run()
	var/datum/object_model_test_actor/owner = new
	var/datum/object_model/schedule_entry/first = om_wake(owner, owner, "one")
	var/datum/object_model/schedule_entry/second = om_wake(owner, owner, "two")
	TEST_ASSERT(first == second, "wake calls were not coalesced")
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.wake_hits, 1, "coalesced wake fired more than once")
	qdel(owner)

/datum/unit_test/dq_object_model_periodic_owned
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_periodic_owned/Run()
	var/datum/object_model_test_actor/owner = new
	var/datum/object_model/schedule_entry/E = om_periodic(owner, world.tick_lag, owner)
	TEST_ASSERT(E, "periodic schedule did not start")
	sleep(4 * world.tick_lag)
	TEST_ASSERT(owner.periodic_hits > 0, "periodic schedule did not run")
	qdel(owner)
	TEST_ASSERT(QDELETED(E), "periodic schedule survived owner destruction")

/datum/stockMarket/dq_timer_test
	var/process_hits = 0

/datum/stockMarket/dq_timer_test/generateBrokers()
	stockBrokers = list()

/datum/stockMarket/dq_timer_test/generateStocks(amt = 15)
	stocks = list()

/datum/stockMarket/dq_timer_test/process()
	process_hits++
	return ..()

/datum/unit_test/dq_object_model_stock_market_timer
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_stock_market_timer/Run()
	var/datum/stockMarket/dq_timer_test/market = new
	var/datum/object_model/schedule_entry/initial_timer = market.process_timer
	TEST_ASSERT(initial_timer && om_owner(initial_timer) == market, "market process timer is not owned by the market")
	market.schedule_process()
	TEST_ASSERT(market.process_timer == initial_timer, "market scheduled a duplicate process timer")
	qdel(initial_timer)
	market.process_timer = market.After(2 * world.tick_lag, TYPE_PROC_REF(/datum/stockMarket, process))
	sleep(4 * world.tick_lag)
	TEST_ASSERT_EQUAL(market.process_hits, 1, "market process timer did not fire once")
	var/datum/object_model/schedule_entry/next_timer = market.process_timer
	TEST_ASSERT(next_timer && next_timer != initial_timer && om_owner(next_timer) == market, "market did not schedule the next owned timer")
	qdel(market)
	TEST_ASSERT(QDELETED(next_timer), "market process timer survived market destruction")

/datum/unit_test/dq_object_model_competing_tasks
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_competing_tasks/Run()
	var/datum/object_model_test_actor/actor = new
	var/datum/object_model_test_actor/stock_owner = new
	stock_owner.stock = 1
	var/datum/object_model/task/first = om_start_task(/datum/object_model/task/object_model_test_purchase, actor, stock_owner)
	var/datum/object_model/task/second = om_start_task(/datum/object_model/task/object_model_test_purchase, actor, stock_owner)
	TEST_ASSERT(istype(first) && istype(second), "competing tasks should both start")
	TEST_ASSERT(om_test_clock_finish(first), "first task should commit")
	TEST_ASSERT(!om_test_clock_finish(second), "second task should fail its stamp")
	TEST_ASSERT_EQUAL(stock_owner.stock, 0, "stock was spent more than once")
	qdel(actor)
	qdel(stock_owner)

/datum/unit_test/dq_object_model_prompt_stamp
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_prompt_stamp/Run()
	var/datum/object_model_test_actor/actor = new
	var/datum/object_model_test_actor/stock_owner = new
	var/datum/object_model/task/prompt/P = om_start_task(/datum/object_model/task/prompt/object_model_test_prompt, actor, stock_owner)
	TEST_ASSERT(istype(P), "prompt did not start")
	om_bump_revision(stock_owner)
	TEST_ASSERT(!P.answer("yes"), "stale prompt was accepted")
	TEST_ASSERT_EQUAL(stock_owner.stock, 0, "stale prompt changed stock")
	qdel(actor)
	qdel(stock_owner)

/datum/unit_test/dq_object_model_event_watch
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_event_watch/Run()
	var/datum/object_model_test_actor/owner = new
	var/datum/object_model_test_actor/subject = new
	var/datum/object_model/watch/W = om_watch(owner, subject, owner, "stock")
	TEST_ASSERT(W, "watch did not start")
	subject.stock = 1
	om_changed(subject)
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.watch_hits, 1, "watch did not fire once on transition")
	TEST_ASSERT(owner.watch_truth, "watch did not report true")
	om_changed(subject)
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.watch_hits, 1, "watch fired with unchanged truth")
	qdel(subject)
	TEST_ASSERT(QDELETED(W), "watch survived subject deletion")
	qdel(owner)

/datum/unit_test/dq_object_model_rate_terms
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_rate_terms/Run()
	var/datum/object_model_test_actor/owner = new
	var/datum/object_model_test_actor/source = new
	var/datum/object_model/rate/R = om_rate(owner, "fuel", 10, 0, 20, owner)
	TEST_ASSERT(R, "rate did not start")
	TEST_ASSERT(R.contribute(source, -2), "rate contribution failed")
	sleep(2 SECONDS)
	TEST_ASSERT(R.value() < 10, "rate did not decrease")
	var/at_removal = R.value()
	qdel(source)
	sleep(2 SECONDS)
	TEST_ASSERT(abs(R.value() - at_removal) < 0.5, "rate continued after contributor deletion")
	qdel(owner)
	TEST_ASSERT(QDELETED(R), "rate survived owner deletion")

/datum/unit_test/dq_object_model_rate_threshold
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_rate_threshold/Run()
	var/datum/object_model_test_actor/owner = new
	var/datum/object_model_test_actor/source = new
	var/datum/object_model/rate/R = om_rate(owner, "charge", 0, 0, 20, owner)
	TEST_ASSERT(R.watch_threshold("half", REACT_CMP_ABOVE, 5), "rate threshold did not register")
	TEST_ASSERT(R.contribute(source, 10), "rate source did not register")
	sleep(1 SECONDS)
	TEST_ASSERT_EQUAL(owner.rate_hits, 1, "rate crossing did not fire exactly once")
	qdel(owner)
	qdel(source)

/datum/unit_test/dq_object_model_declared_rate
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_declared_rate/Run()
	var/datum/object_model_test_declared_rate/owner = new
	TEST_ASSERT_NULL(owner.om_state, "An untouched declared rate allocates no instance state")
	var/datum/object_model/rate/R = om_declared_rate(owner, "charge")
	TEST_ASSERT_NOTNULL(R, "Declared rate resolves on first use")
	TEST_ASSERT_EQUAL(R.value(), 2, "Declared initial value is installed")
	TEST_ASSERT_EQUAL(om_owner(R), owner, "Declared rate is lifetime-owned")
	TEST_ASSERT_NOTNULL(R.threshold_watches?["half"], "Declared threshold installs its crossing watch")
	TEST_ASSERT_EQUAL(om_declared_rate(owner, "charge"), R, "Repeated reads reuse the same rate")
	TEST_ASSERT(om_declared_rate_set(owner, "charge", 3), "Declared rate setter accepts a valid value")
	TEST_ASSERT_EQUAL(om_declared_rate_value(owner, "charge"), 3, "Declared rate getter reads the changed value")
	var/datum/object_model_test_actor/source = new
	TEST_ASSERT(om_declared_rate_contribute(owner, "charge", source, 1), "Declared rate accepts an owned contributor")
	TEST_ASSERT_EQUAL(length(R.contributions), 1, "Contribution is attached to the shared rate")
	qdel(source)
	TEST_ASSERT(!length(R.contributions), "Deleting the contributor removes its rate term")
	qdel(R)
	TEST_ASSERT_NULL(owner.om_state.declared_rates?["charge"], "Deleting a declared rate clears its cached field")
	var/datum/object_model/rate/rebuilt = om_declared_rate(owner, "charge")
	TEST_ASSERT_NOTNULL(rebuilt, "A retired field can be recreated from its declaration")
	TEST_ASSERT(rebuilt != R, "The recreated rate is a distinct datum")
	qdel(owner)
	TEST_ASSERT(QDELETED(rebuilt), "Owner deletion cancels the declared rate")

/datum/unit_test/dq_object_model_declared_rate_validation
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_declared_rate_validation/Run()
	var/datum/object_model/archetype/A = new
	A.entity_type = /datum/object_model_test_declared_rate
	A.rate("invalid_bounds", 10, 1)
	TEST_ASSERT(length(A.errors), "Invalid bounds must fail at declaration time")
	A.errors = list()
	A.rate("invalid_threshold", 0, 20, list("half" = list(REACT_CMP_ABOVE, 25)), 2)
	TEST_ASSERT(length(A.errors), "Out-of-range threshold must fail at declaration time")
	qdel(A)

/datum/unit_test/dq_object_model_declared_watch
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_declared_watch/Run()
	var/datum/object_model_test_declared_watch/owner = new
	TEST_ASSERT_NULL(owner.om_state, "An untouched declaration has no instance watch")
	var/datum/object_model/behaviour_runtime/runtime = om_behaviour_start(owner)
	TEST_ASSERT_NOTNULL(runtime, "Archetype runtime starts")
	var/datum/object_model/watch/W = runtime.static_watches[/datum/object_model/watch_definition/test_declared_stock]
	TEST_ASSERT_NOTNULL(W, "Runtime automatically starts its declared watch")
	TEST_ASSERT_EQUAL(W.subject, owner, "Default watch observes its entity")
	var/datum/object_model/watch_definition/D = om_watch_definition(/datum/object_model/watch_definition/test_declared_stock)
	TEST_ASSERT(!W._signal_procs?[D]?[COMSIG_QDELETING], "Immortal watch definitions need no per-instance deletion signal")
	owner.stock = 1
	om_changed(owner)
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.watch_hits, 1, "Transition emits one typed event")
	TEST_ASSERT(owner.watch_truth, "Positive stock reports true")
	om_changed(owner)
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.watch_hits, 1, "Unchanged truth does not emit")
	owner.stock = 0
	om_changed(owner)
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.watch_hits, 2, "Reverse transition emits once")
	TEST_ASSERT(!owner.watch_truth, "Empty stock reports false")
	qdel(owner)
	TEST_ASSERT(QDELETED(W), "Deleting the entity tears down its static watch")

/datum/unit_test/dq_object_model_declared_watch_validation
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_declared_watch_validation/Run()
	var/datum/object_model/archetype/A = new
	A.entity_type = /datum/object_model_test_declared_watch
	A.watch(/datum/object_model/watch_definition/test_declared_stock, list("dynamic_subject" = TRUE))
	TEST_ASSERT(length(A.errors), "A.watch rejects ad hoc dynamic-subject config")
	qdel(A)

/datum/unit_test/dq_object_model_related_watch_rebinding
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_related_watch_rebinding/Run()
	var/datum/object_model_test_related_watch/owner = new
	var/datum/object_model_test_actor/first = new
	var/datum/object_model_test_actor/second = new
	first.stock = 1
	var/datum/object_model/behaviour_runtime/runtime = om_behaviour_start(owner)
	TEST_ASSERT_NOTNULL(runtime, "Related watch archetype starts")
	var/watch_path = /datum/object_model/watch_definition/test_declared_related_stock
	TEST_ASSERT_NULL(runtime.static_watches[watch_path], "Unbound relation allocates no subject watch")
	TEST_ASSERT(om_link(owner, /datum/object_model/relation/test_declared_watch_subject, first), "First subject links")
	var/datum/object_model/watch/first_watch = runtime.static_watches[watch_path]
	TEST_ASSERT_NOTNULL(first_watch, "Linking a subject starts its watch")
	TEST_ASSERT_EQUAL(first_watch.subject, first, "Watch follows the first endpoint")
	TEST_ASSERT_EQUAL(owner.watch_hits, 1, "Initially true related condition emits on binding")
	TEST_ASSERT(owner.watch_truth, "Initial related condition is true")
	TEST_ASSERT(om_link(owner, /datum/object_model/relation/test_declared_watch_subject, second), "Second subject replaces first")
	TEST_ASSERT(QDELETED(first_watch), "Replacing the relation tears down the old watch")
	var/datum/object_model/watch/second_watch = runtime.static_watches[watch_path]
	TEST_ASSERT_EQUAL(second_watch.subject, second, "Watch rebinds to the replacement")
	TEST_ASSERT(!owner.watch_truth, "Losing the true first subject emits false")
	var/hits_after_rebind = owner.watch_hits
	first.stock = 0
	om_changed(first)
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.watch_hits, hits_after_rebind, "Former subject cannot publish stale transitions")
	second.stock = 1
	om_changed(second)
	sleep(3 * world.tick_lag)
	TEST_ASSERT_EQUAL(owner.watch_hits, hits_after_rebind + 1, "Replacement subject publishes changes")
	qdel(second)
	TEST_ASSERT(QDELETED(second_watch), "Endpoint deletion tears down its watch")
	TEST_ASSERT_NULL(runtime.static_watches[watch_path], "Deleted endpoint leaves no stale watch entry")
	TEST_ASSERT(!owner.watch_truth, "Endpoint loss emits false")
	qdel(owner)
	qdel(first)

#define OM_TEST_SCHEDULED_CHANGE (1<<0)
#define OM_TEST_SCHEDULED_UNRELATED (1<<1)

/datum/object_model_test_scheduled
	var/value = 0
	var/last_seen = 0
	var/fast_runs = 0
	var/slow_runs = 0
	var/event_runs = 0
	var/granted_runs = 0
	var/requirement_checks = 0
	var/enabled = TRUE

/datum/object_model/requirement/test_scheduled_enabled
	change_mask = OM_TEST_SCHEDULED_CHANGE

/datum/object_model/requirement/test_scheduled_enabled/check(datum/source, mob/actor, atom/target, obj/item/held)
	var/datum/object_model_test_scheduled/E = source
	E.requirement_checks++
	return E.enabled

/datum/object_model/behaviour/test_scheduled_required
	requires = list(/datum/object_model/requirement/test_scheduled_enabled)

/datum/object_model/event/test_scheduled_poke

/datum/object_model/behaviour/test_scheduled_event
	run_events = list(/datum/object_model/event/test_scheduled_poke)

/datum/object_model/behaviour/test_scheduled_event/on_run(datum/source, seconds, list/config)
	var/datum/object_model_test_scheduled/E = source
	E.event_runs++
	return 0

/datum/object_model/behaviour/test_scheduled_granted
	run_events = list(/datum/object_model/event/test_scheduled_poke)

/datum/object_model/behaviour/test_scheduled_granted/on_run(datum/source, seconds, list/config)
	var/datum/object_model_test_scheduled/E = source
	E.granted_runs++
	return 0

/datum/object_model/behaviour/test_scheduled_fast
	run_change_mask = OM_TEST_SCHEDULED_CHANGE
	audit_sleep = TRUE

/datum/object_model/behaviour/test_scheduled_fast/on_run(datum/source, seconds, list/config)
	var/datum/object_model_test_scheduled/E = source
	E.fast_runs++
	E.last_seen = E.value
	return 0

/datum/object_model/behaviour/test_scheduled_fast/sleep_violation(datum/source, list/config)
	var/datum/object_model_test_scheduled/E = source
	return E.value != E.last_seen ? "value changed without notification" : null

/datum/object_model/behaviour/test_scheduled_slow
	run_period = 30 SECONDS

/datum/object_model/behaviour/test_scheduled_slow/on_run(datum/source, seconds, list/config)
	var/datum/object_model_test_scheduled/E = source
	E.slow_runs++
	return null

/datum/object_model/declaration/test_scheduled
	target_type = /datum/object_model_test_scheduled

/datum/object_model/declaration/test_scheduled/build(datum/object_model/archetype/A)
	A.track_changes(OM_TEST_SCHEDULED_CHANGE | OM_TEST_SCHEDULED_UNRELATED)
	A.add(/datum/object_model/behaviour/test_scheduled_fast)
	A.add(/datum/object_model/behaviour/test_scheduled_slow)
	A.add(/datum/object_model/behaviour/test_scheduled_required)
	A.add(/datum/object_model/behaviour/test_scheduled_event)

/datum/unit_test/dq_object_model_scheduled_behaviours
	needs_test_block = FALSE

/datum/unit_test/dq_object_model_scheduled_behaviours/Run()
	var/datum/object_model_test_scheduled/E = new
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(E)
	TEST_ASSERT_NOTNULL(R, "Scheduled behaviour runtime starts")
	R.run_ready()
	TEST_ASSERT_EQUAL(E.fast_runs, 1, "Changed behaviour runs once on activation")
	TEST_ASSERT_EQUAL(E.slow_runs, 1, "Periodic behaviour runs once on activation")
	TEST_ASSERT_EQUAL(E.event_runs, 1, "Event behaviour runs once on activation")
	var/slow = /datum/object_model/behaviour/test_scheduled_slow
	var/fast = /datum/object_model/behaviour/test_scheduled_fast
	var/slow_due = R.run_due[slow]
	TEST_ASSERT(slow_due > world.time, "Periodic behaviour has a future deadline")
	var/checks = E.requirement_checks
	om_mark_changed(E, OM_TEST_SCHEDULED_UNRELATED)
	TEST_ASSERT_EQUAL(E.requirement_checks, checks, "Unrelated tracked write skips requirement evaluation")
	E.value++
	om_mark_changed(E, OM_TEST_SCHEDULED_CHANGE)
	TEST_ASSERT(E.requirement_checks > checks, "Declared tracked write refreshes its requirement")
	R.run_ready()
	TEST_ASSERT_EQUAL(E.fast_runs, 2, "Declared change wakes only its behaviour")
	TEST_ASSERT_EQUAL(E.slow_runs, 1, "Unrelated periodic behaviour stays asleep")
	TEST_ASSERT_EQUAL(R.run_due[slow], slow_due, "Unrelated write preserves the later deadline")
	TEST_ASSERT(om_behaviour_wake(E, fast), "Explicit wake targets the named behaviour")
	R.run_ready()
	TEST_ASSERT_EQUAL(E.fast_runs, 3, "Explicit wake runs its target")
	TEST_ASSERT_EQUAL(E.slow_runs, 1, "Explicit wake does not run the other behaviour")
	om_emit(E, /datum/object_model/event/test_scheduled_poke)
	om_emit(E, /datum/object_model/event/test_scheduled_poke)
	R.run_ready()
	TEST_ASSERT_EQUAL(E.event_runs, 2, "Two event occurrences coalesce to one scheduled run")
	var/datum/grant_source = new
	TEST_ASSERT(om_behaviour_grant(E, /datum/object_model/behaviour/test_scheduled_granted, grant_source), "Dynamic scheduled grant activates")
	R.run_ready()
	TEST_ASSERT_EQUAL(E.granted_runs, 1, "Granted behaviour gets its initial run")
	om_emit(E, /datum/object_model/event/test_scheduled_poke)
	R.run_ready()
	TEST_ASSERT_EQUAL(E.granted_runs, 2, "Typed event wakes a dynamically granted behaviour")
	om_behaviour_revoke(E, /datum/object_model/behaviour/test_scheduled_granted, grant_source)
	om_emit(E, /datum/object_model/event/test_scheduled_poke)
	R.run_ready()
	TEST_ASSERT_EQUAL(E.granted_runs, 2, "Revoked behaviour no longer wakes")
	qdel(grant_source)
	E.value++
	TEST_ASSERT_NOTNULL(R.react_sleep_violation(), "Audit catches a direct write that missed its wake")
	om_mark_changed(E, OM_TEST_SCHEDULED_CHANGE)
	TEST_ASSERT_NULL(R.react_sleep_violation(), "A queued changed behaviour is not a missed wake")
	R.run_ready()
	TEST_ASSERT_NULL(R.react_sleep_violation(), "The behaviour settles after running")
	qdel(E)
	TEST_ASSERT(QDELETED(R), "Owner destruction cancels scheduled behaviour state")

#undef OM_TEST_SCHEDULED_CHANGE
#undef OM_TEST_SCHEDULED_UNRELATED
#endif

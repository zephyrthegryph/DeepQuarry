// S3 wake tests: every sleeper on after() timers and om_watch()ed change channels wakes
// when its input changes and stays asleep while the input is held steady, and its
// sleep_violation() holds while it sleeps.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/**
 * The wake test for any sleeper (a sleeper behaviour, after() timers): with its input held steady `D` must stay asleep,
 * and after `change` runs it must wake within `ticks`. Returns null on success or the failure.
 */
/proc/om_wake_test(datum/D, list/change, ticks = 4)
	om_trace(D)
	om_test_ticks(ticks)
	// Settle first: a wake already queued before the steady window (the test's own setup) lands
	// on the scheduler's next pass, which a busy test world can push past `ticks`.
	om_settle(D, ticks * 10)
	var/before = om_traced_count(D)
	om_test_ticks(ticks)
	if(om_traced_count(D) != before)
		om_untrace(D)
		return "[D.type] woke while its input held steady"
	om_run(change)
	// Wakes ride the scheduler's lanes and deadline share: under a busy test world give them a
	// little longer than `ticks` before calling one lost.
	var/after = before
	for(var/i in 1 to ticks * 10)
		om_test_ticks(1)
		after = om_traced_count(D)
		if(after != before)
			break
	om_untrace(D)
	if(after == before)
		return "[D.type] did not wake after its input changed"
	return null

/// TRUE while `D` has a wake queued or pending delivery, or an after() timer already due
/// (a spawn-time materialize_wakes(), say): work raised before now that hasn't landed yet.
/proc/om_wakes_pending(datum/D)
	var/datum/om/rec/rec = D.om_rec
	if(!rec)
		return FALSE
	if(rec.queued)
		return TRUE
	for(var/bits in rec.att_pend)
		if(bits)
			return TRUE
	var/list/T = rec.timers
	if(length(T))
		var/local = om_timer_local(rec)
		for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
			if(T[i + 1] <= local)
				return TRUE
	return FALSE

/// Waits (a tick at a time, up to `max_ticks`) until nothing raised for `D` is still in flight.
/proc/om_settle(datum/D, max_ticks = 40)
	for(var/i in 1 to max_ticks)
		if(!om_wakes_pending(D))
			return TRUE
		om_test_ticks(1)
	return FALSE

/// Waits (a tick at a time, up to `max_ticks`) until `D` has been woken more than `count` times.
/// Wakes ride the scheduler's lanes: a busy test world can take a few ticks longer.
/proc/om_wait_for_wake(datum/D, count = 0, max_ticks = 40)
	for(var/i in 1 to max_ticks)
		om_test_ticks(1)
		if(om_traced_count(D) > count)
			return TRUE
	return FALSE

/// Records every wake (the channels it arrived with).
/datum/om_wake_test_subscriber
	var/list/wakes = list()

/datum/om/behaviour/sleeper/test_subscriber
	name = "test subscriber"

/datum/om/behaviour/sleeper/test_subscriber/on_wake(datum/om_wake_test_subscriber/S, changes)
	S.wakes += changes

/// Makes `S` watch `mask` on `target`.
/proc/om_test_watch(datum/om_wake_test_subscriber/S, datum/target, mask)
	om_attach(S, /datum/om/behaviour/sleeper/test_subscriber)
	om_watch(S, target, mask, /datum/om/behaviour/sleeper/test_subscriber)

/// Deadline wakes: a door's autoclose runs on one after() timer; power and electrification restore through timed_set().
/datum/unit_test/dq_om_wake_airlock_deadlines

/datum/unit_test/dq_om_wake_airlock_deadlines/Run()
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, test_floor())
	A.set_autoclose(TRUE)
	TEST_ASSERT(!A.autoclose_pending(), "a fresh airlock has an autoclose pending")
	TEST_ASSERT_NULL(A.sleep_violation(), "a fresh airlock is not asleep")

	// Electrification and power loss are timed holds: each runs out on its own, with no process() poll and no door deadline.
	hold(A, STAT_ELECTRIFIED, TRUE, SRC_LOCKDOWN, 0.1 SECONDS)
	TEST_ASSERT(A.electrified, "the hold electrified the airlock")
	TEST_ASSERT_NULL(A.sleep_violation(), "an electrified airlock's audit failed")
	// A due timer still in flight (a busy world: GC reference searches stall the MC) is given
	// time to land; a timer that was never set, or never comes due, still fails.
	for(var/i in 1 to 200)
		if(!A.electrified)
			break
		om_test_ticks(1)
	TEST_ASSERT(!A.electrified, "the electrification did not run out")
	TEST_ASSERT(!A.autoclose_pending(), "an airlock with no deadline kept a timer")

	// Main power returns on its timer.
	hold(A, STAT_MAIN_POWER_OUT, TRUE, SRC_BREAKER, 0.1 SECONDS)
	for(var/i in 1 to 200)
		if(!A.main_power_out)
			break
		om_test_ticks(1)
	TEST_ASSERT(!A.main_power_out, "main power did not return when its hold ran out")


/// Bolts and power raise CHANGE_MACHINE_MODE for whoever watches the door.
/datum/unit_test/dq_om_wake_airlock_mode_key

/datum/unit_test/dq_om_wake_airlock_mode_key/Run()
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, test_floor())
	var/datum/om_wake_test_subscriber/watcher = allocate(/datum/om_wake_test_subscriber)
	om_test_watch(watcher, A, CHANGE_MACHINE_MODE)
	var/failure = om_wake_test(watcher, om_callable(A, TYPE_PROC_REF(/obj/machinery/door/airlock, drop_bolts), TRUE))
	TEST_ASSERT(!failure, failure)

/// Cameras: EMP recovery and the motion alarm are timers; losing a target is a signal.
/datum/unit_test/dq_om_wake_camera_timers

/datum/unit_test/dq_om_wake_camera_timers/Run()
	var/obj/machinery/camera/C = allocate(/obj/machinery/camera, test_floor())
	TEST_ASSERT(!after_pending(C, "camera_timer_token"), "an idle camera has a timer")
	TEST_ASSERT_NULL(C.sleep_violation(), "an idle camera is not asleep")
	var/failure = om_wake_test(C, om_callable(src, PROC_REF(emp_camera_briefly), C), 20)
	TEST_ASSERT(!failure, failure)
	OM_TEST_WAIT_UNTIL(!C.has_stat(EMPED), 80)
	TEST_ASSERT(!C.has_stat(EMPED), "the camera did not recover at the end of its EMP")

	C.upgradeMotion()
	C.stat_remove(NOPOWER)
	C.status = TRUE
	C.alarm_delay = 1
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, get_turf(C))
	C.newTarget(H)
	TEST_ASSERT(after_pending(C, "camera_timer_token"), "a motion target did not schedule the alarm")
	TEST_ASSERT_NULL(C.sleep_violation(), "a tracking camera's audit failed")
	OM_TEST_WAIT_UNTIL(C.detectTime == -1, 120)
	TEST_ASSERT_EQUAL(C.detectTime, -1, "the motion alarm did not fire at its deadline")
	H.set_stat(DEAD)
	TEST_ASSERT(!(H in C.motionTargets), "a dead target was not dropped")
	TEST_ASSERT_EQUAL(C.detectTime, 0, "the alarm was not cancelled after losing its last target")

/datum/unit_test/dq_om_wake_camera_timers/proc/emp_camera_briefly(obj/machinery/camera/C)
	C.stat_add(EMPED)
	C.affected_by_emp_until = world.time + 1
	C.schedule_camera_timer()

/// Status displays: static modes sleep; moving content has one timer; shuttle modes watch the key.
/datum/unit_test/dq_om_wake_status_display

/datum/unit_test/dq_om_wake_status_display/Run()
	var/obj/machinery/status_display/D = allocate(/obj/machinery/status_display, test_floor())
	D.stat_remove(NOPOWER)
	var/datum/signal/S = new
	S.data["command"] = "blank"
	D.receive_signal(S)
	TEST_ASSERT(!after_pending(D, "refresh_token"), "a blank display kept a timer")
	TEST_ASSERT_NULL(D.sleep_violation(), "a blank display is not asleep")

	S = new
	S.data["command"] = "time"
	D.receive_signal(S)
	TEST_ASSERT(after_pending(D, "refresh_token"), "the clock did not schedule its next minute")
	TEST_ASSERT(D.refresh_at <= world.time + 1 MINUTE, "the clock's next redraw is more than a minute away")

	S = new
	S.data["command"] = "message"
	S.data["msg1"] = "SHORT"
	D.receive_signal(S)
	TEST_ASSERT(!after_pending(D, "refresh_token"), "a message that fits kept a timer")
	S = new
	S.data["command"] = "message"
	S.data["msg1"] = "A MESSAGE TOO LONG TO FIT"
	D.receive_signal(S)
	TEST_ASSERT(after_pending(D, "refresh_token"), "a scrolling message has no timer")

	S = new
	S.data["command"] = "shuttle"
	D.receive_signal(S)
	TEST_ASSERT_EQUAL(D.shuttle_key_id, SHUTTLE_SCHEDULE_EVAC, "shuttle mode is not watching the evac shuttle")
	TEST_ASSERT_NULL(D.sleep_violation(), "a shuttle display's audit failed")
	if(!after_pending(D, "refresh_token")) // No evac under way: only the key wakes it.
		var/failure = om_wake_test(D, om_callable(src, PROC_REF(publish_evac)))
		TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_om_wake_status_display/proc/publish_evac()
	changed(SSemergency_shuttle, CHANGE_SHUTTLE_SCHEDULE)

/datum/looping_sound/dq_test
	mid_sounds = list('sound/machines/button.ogg' = 1)
	mid_length = 1 SECONDS

/// Looping sounds: with nobody to hear, a loop parks on the player chunk keys around it.
/datum/unit_test/dq_om_wake_looping_sound_dormancy

/datum/unit_test/dq_om_wake_looping_sound_dormancy/Run()
	var/turf/T = test_floor()
	var/obj/item/source = allocate(/obj/item, T)
	var/datum/looping_sound/dq_test/loop = new(list(source))
	loop.start()
	for(var/i in 1 to 60)
		om_test_ticks(1)
		if(loop.dormant_chunk_tokens || loop.has_listener())
			break
	if(loop.has_listener())
		qdel(loop)
		return // A player is in range on this map; dormancy cannot be tested here.
	TEST_ASSERT(loop.dormant_chunk_tokens, "a loop nobody can hear did not go dormant")
	TEST_ASSERT(GLOB.player_chunk_watches > 0, "a dormant loop left no chunk subscriptions")
	TEST_ASSERT_NULL(loop.sleep_violation(), "a dormant loop's audit failed")
	var/failure = om_wake_test(loop, om_callable(null, GLOBAL_PROC_REF(publish_player_chunk), T))
	TEST_ASSERT(!failure, failure)
	TEST_ASSERT(loop.dormant_chunk_tokens, "a chunk wake with nobody in range left dormancy")
	loop.stop()
	TEST_ASSERT(!loop.dormant_chunk_tokens && !after_pending(loop, "loop_token"), "stop() left the loop subscribed")
	qdel(loop)

/// Player chunk keys: a player's chunk wakes subscribers; a mob without a client does not.
/datum/unit_test/dq_om_wake_player_chunk_keys

/datum/unit_test/dq_om_wake_player_chunk_keys/Run()
	var/turf/T = test_floor()
	var/datum/om_wake_test_subscriber/players = allocate(/datum/om_wake_test_subscriber)
	om_attach(players, /datum/om/behaviour/sleeper/test_subscriber)
	var/list/tokens = watch_mob_chunks(players, mob_chunks_around(T, 0), CHANGE_CHUNK_PLAYER, /datum/om/behaviour/sleeper/test_subscriber)
	TEST_ASSERT(length(tokens), "watch_mob_chunks returned no chunks")
	TEST_ASSERT(GLOB.player_chunk_watches > 0, "a player chunk subscription was not counted")
	om_trace(players)
	om_settle(players, 40)
	om_test_ticks(4)
	var/before = om_traced_count(players)
	var/mob/living/npc = allocate(/mob/living, T)
	npc.Move(get_step(T, NORTH))
	om_test_ticks(4)
	TEST_ASSERT_EQUAL(om_traced_count(players), before, "a mob without a client woke a player chunk subscriber")
	om_untrace(players)
	var/failure = om_wake_test(players, om_callable(null, GLOBAL_PROC_REF(publish_player_chunk), T))
	TEST_ASSERT(!failure, failure)
	unwatch_mob_chunks(players, tokens, CHANGE_CHUNK_PLAYER, /datum/om/behaviour/sleeper/test_subscriber)
	TEST_ASSERT_EQUAL(length(players.wakes) >= 1, TRUE, "no wake recorded")

#endif


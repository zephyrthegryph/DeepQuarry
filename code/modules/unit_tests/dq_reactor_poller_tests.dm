// S3 wake tests (doc/rewrite/reactor.md §7, §9): every poller converted to SSreactor wakes when
// its input changes and stays asleep while the input is held steady, and its
// react_sleep_violation() holds while it sleeps.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Deadline wakes: a door's autoclose, power and electrification deadlines share one REACT_AT.
/datum/unit_test/dq_reactor_airlock_deadlines

/datum/unit_test/dq_reactor_airlock_deadlines/Run()
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, test_floor())
	A.autoclose = TRUE
	TEST_ASSERT(!A.next_door_deadline(), "a fresh airlock has a deadline ([A.next_door_deadline()])")
	TEST_ASSERT_NULL(A.react_sleep_violation(), "a fresh airlock is not asleep")

	var/failure = react_wake_test(A, CALLBACK(A, TYPE_PROC_REF(/obj/machinery/door, autoclose_in), 1), 20)
	TEST_ASSERT(!failure, failure)

	// Electrification expires on its timer, with no process() poll.
	A.close_door_at = 0
	A.schedule_door_timer()
	A.electrified_until = world.time + 1
	A.schedule_door_timer()
	TEST_ASSERT(!isnull(A.door_timer_token), "electrifying did not schedule the door's timer")
	TEST_ASSERT_NULL(A.react_sleep_violation(), "an electrified airlock's audit failed")
	react_test_ticks(20)
	TEST_ASSERT_EQUAL(A.electrified_until, 0, "the electrification deadline passed without a wake")
	TEST_ASSERT(isnull(A.door_timer_token), "an airlock with no deadline kept a timer")

	// Main power returns on its timer.
	A.main_power_lost_until = world.time + 1
	A.backup_power_lost_until = -1
	A.schedule_door_timer()
	react_test_ticks(20)
	TEST_ASSERT(A.main_power_lost_until <= 0, "main power did not return at its deadline ([A.main_power_lost_until])")

	// A missing timer is what the audit catches.
	A.close_door_at = world.time + 10 SECONDS
	TEST_ASSERT_NOTNULL(A.react_sleep_violation(), "the audit missed a deadline without a timer")
	A.close_door_at = 0

/// Bolts and power publish REACT_KEY_DOOR_MODE for whoever watches the door.
/datum/unit_test/dq_reactor_airlock_mode_key

/datum/unit_test/dq_reactor_airlock_mode_key/Run()
	var/obj/machinery/door/airlock/A = allocate(/obj/machinery/door/airlock, test_floor())
	var/datum/react_test_subscriber/watcher = allocate(/datum/react_test_subscriber)
	REACT_ON_KEY(watcher, REACT_KEY_DOOR_MODE, REACT_ID(A), REACT_DOOR_BOLTS)
	var/failure = react_wake_test(watcher, CALLBACK(A, TYPE_PROC_REF(/obj/machinery/door/airlock, lock), TRUE))
	TEST_ASSERT(!failure, failure)

/// Cameras: EMP recovery and the motion alarm are timers; losing a target is a signal.
/datum/unit_test/dq_reactor_camera_timers

/datum/unit_test/dq_reactor_camera_timers/Run()
	var/obj/machinery/camera/C = allocate(/obj/machinery/camera, test_floor())
	TEST_ASSERT(isnull(C.camera_timer_token), "an idle camera has a timer")
	TEST_ASSERT_NULL(C.react_sleep_violation(), "an idle camera is not asleep")
	var/failure = react_wake_test(C, CALLBACK(src, PROC_REF(emp_camera_briefly), C), 20)
	TEST_ASSERT(!failure, failure)
	react_test_ticks(4)
	TEST_ASSERT(!(C.stat & EMPED), "the camera did not recover at the end of its EMP")

	C.upgradeMotion()
	C.stat &= ~NOPOWER
	C.status = TRUE
	C.alarm_delay = 1
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, get_turf(C))
	C.newTarget(H)
	TEST_ASSERT(!isnull(C.camera_timer_token), "a motion target did not schedule the alarm")
	TEST_ASSERT_NULL(C.react_sleep_violation(), "a tracking camera's audit failed")
	react_test_ticks(20)
	TEST_ASSERT_EQUAL(C.detectTime, -1, "the motion alarm did not fire at its deadline")
	H.set_stat(DEAD)
	TEST_ASSERT(!(H in C.motionTargets), "a dead target was not dropped")
	TEST_ASSERT_EQUAL(C.detectTime, 0, "the alarm was not cancelled after losing its last target")

/datum/unit_test/dq_reactor_camera_timers/proc/emp_camera_briefly(obj/machinery/camera/C)
	C.stat |= EMPED
	C.affected_by_emp_until = world.time + 1
	C.schedule_camera_timer()

/// Lights: area power is a key; emergency discharge and recharge are timers.
/datum/unit_test/dq_reactor_light_area_power

/datum/unit_test/dq_reactor_light_area_power/Run()
	var/obj/machinery/light/L = allocate(/obj/machinery/light, test_floor())
	var/area/A = get_area(L)
	TEST_ASSERT(!isnull(L.area_power_token), "a light did not subscribe to its area's power key")
	TEST_ASSERT_NULL(L.react_sleep_violation(), "a new light is not asleep")
	var/failure = react_wake_test(L, CALLBACK(A, TYPE_PROC_REF(/area, power_change)))
	TEST_ASSERT(!failure, failure)

	// Losing light power puts a charged light on its cell, on a timer. (The light switch
	// does not: a switched-off light stays dark.)
	var/old_power = A.power_light
	var/was_powered = L.has_power() && A.requires_power
	A.power_light = FALSE
	A.power_change()
	react_test_ticks(4)
	if(was_powered && L.has_cell() && L.has_emergency_power(0.2) && L.status == LIGHT_OK && !L.no_emergency)
		TEST_ASSERT(L.emergency_mode, "an unpowered charged light did not go to emergency power")
		TEST_ASSERT(L.emergency_discharge_at && !isnull(L.light_timer_token), "emergency discharge has no timer")
	TEST_ASSERT_NULL(L.react_sleep_violation(), "an unpowered light's audit failed")
	A.power_light = old_power
	A.power_change()
	react_test_ticks(4)
	if(L.has_power())
		TEST_ASSERT(!L.emergency_mode, "power returned but the light stayed on its cell")
		TEST_ASSERT(!L.emergency_discharge_at, "power returned but emergency discharge kept its deadline")

/// Status displays: static modes sleep; moving content has one timer; shuttle modes watch the key.
/datum/unit_test/dq_reactor_status_display

/datum/unit_test/dq_reactor_status_display/Run()
	var/obj/machinery/status_display/D = allocate(/obj/machinery/status_display, test_floor())
	D.stat &= ~NOPOWER
	var/datum/signal/S = new
	S.data["command"] = "blank"
	D.receive_signal(S)
	TEST_ASSERT(isnull(D.refresh_token), "a blank display kept a timer")
	TEST_ASSERT_NULL(D.react_sleep_violation(), "a blank display is not asleep")

	S = new
	S.data["command"] = "time"
	D.receive_signal(S)
	TEST_ASSERT(!isnull(D.refresh_token), "the clock did not schedule its next minute")
	TEST_ASSERT(D.refresh_at <= world.time + 1 MINUTE, "the clock's next redraw is more than a minute away")

	S = new
	S.data["command"] = "message"
	S.data["msg1"] = "SHORT"
	D.receive_signal(S)
	TEST_ASSERT(isnull(D.refresh_token), "a message that fits kept a timer")
	S = new
	S.data["command"] = "message"
	S.data["msg1"] = "A MESSAGE TOO LONG TO FIT"
	D.receive_signal(S)
	TEST_ASSERT(!isnull(D.refresh_token), "a scrolling message has no timer")

	S = new
	S.data["command"] = "shuttle"
	D.receive_signal(S)
	TEST_ASSERT_EQUAL(D.shuttle_key_id, REACT_SHUTTLE_EVAC, "shuttle mode is not watching the evac shuttle")
	TEST_ASSERT_NULL(D.react_sleep_violation(), "a shuttle display's audit failed")
	if(isnull(D.refresh_token)) // No evac under way: only the key wakes it.
		var/failure = react_wake_test(D, CALLBACK(src, PROC_REF(publish_evac)))
		TEST_ASSERT(!failure, failure)

/datum/unit_test/dq_reactor_status_display/proc/publish_evac()
	REACT_PUBLISH(REACT_KEY_SHUTTLE_SCHEDULE, REACT_SHUTTLE_EVAC, 1)

/datum/looping_sound/dq_test
	mid_sounds = list('sound/machines/button.ogg' = 1)
	mid_length = 1 SECONDS

/// Looping sounds: with nobody to hear, a loop parks on the player chunk keys around it.
/datum/unit_test/dq_reactor_looping_sound_dormancy

/datum/unit_test/dq_reactor_looping_sound_dormancy/Run()
	var/turf/T = test_floor()
	var/obj/item/source = allocate(/obj/item, T)
	var/datum/looping_sound/dq_test/loop = new(list(source))
	loop.start()
	react_test_ticks(6)
	if(loop.has_listener())
		qdel(loop)
		return // A player is in range on this map; dormancy cannot be tested here.
	TEST_ASSERT(loop.dormant_chunk_tokens, "a loop nobody can hear did not go dormant")
	TEST_ASSERT(SSreactor.player_chunk_subscriptions > 0, "a dormant loop left no chunk subscriptions")
	TEST_ASSERT_NULL(loop.react_sleep_violation(), "a dormant loop's audit failed")
	var/failure = react_wake_test(loop, CALLBACK(SSreactor, TYPE_PROC_REF(/datum/controller/subsystem/reactor, publish_player_chunk), T))
	TEST_ASSERT(!failure, failure)
	TEST_ASSERT(loop.dormant_chunk_tokens, "a chunk wake with nobody in range left dormancy")
	loop.stop()
	TEST_ASSERT(!loop.dormant_chunk_tokens && isnull(loop.loop_token), "stop() left the loop subscribed")
	qdel(loop)

/// Player chunk keys: a player's chunk wakes subscribers; a mob without a client does not.
/datum/unit_test/dq_reactor_player_chunk_keys

/datum/unit_test/dq_reactor_player_chunk_keys/Run()
	var/turf/T = test_floor()
	var/datum/react_test_subscriber/players = allocate(/datum/react_test_subscriber)
	var/list/tokens = SSreactor.subscribe_player_chunks(players, T, 0)
	TEST_ASSERT(length(tokens), "subscribe_player_chunks returned no tokens")
	TEST_ASSERT(SSreactor.player_chunk_subscriptions > 0, "a player chunk subscription was not counted")
	SSreactor.trace(players)
	react_test_ticks(4)
	var/before = SSreactor.traced_wakes(players)
	var/mob/living/npc = allocate(/mob/living, T)
	npc.Move(get_step(T, NORTH))
	react_test_ticks(4)
	TEST_ASSERT_EQUAL(SSreactor.traced_wakes(players), before, "a mob without a client woke a player chunk subscriber")
	SSreactor.untrace(players)
	var/failure = react_wake_test(players, CALLBACK(SSreactor, TYPE_PROC_REF(/datum/controller/subsystem/reactor, publish_player_chunk), T))
	TEST_ASSERT(!failure, failure)
	SSreactor.unsubscribe_player_chunks(players, tokens)
	TEST_ASSERT_EQUAL(length(players.wakes) >= 1, TRUE, "no wake recorded")

#endif

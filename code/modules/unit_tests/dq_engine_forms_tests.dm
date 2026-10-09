// The engine forms of doc/rewrite/ai_packs.md part A: coalesce(), modes()/go()/after_in_state(), and keyed standings standing()/standing_toward().

// ---------------------------------------------------------------- fixtures

/// A notice the fixtures listen for: forms_ping is published by hand.
ACTION(forms_ping, FIXED)

/// Runs of every handler below, across entities: a deleted holder cannot count its own, so a "no run" claim reads this.
GLOBAL_VAR_INIT(forms_runs, 0)
GLOBAL_VAR_INIT(forms_ticks, 0)

/// A holder of coalesced hooks (type-level, and through a granted capability).
/obj/forms_listener
	name = "forms listener"
	anchored = TRUE
	var/runs = 0
	var/charge = 0
	var/charge_runs = 0
	var/charge_seen = 0
	var/cap_runs = 0

TRACKED(/obj/forms_listener, charge)

CAPABILITIES(/obj/forms_listener)
	on_notice(/datum/notice/forms_pinged, coalesce(2 SECONDS), then(PROC_REF(coalesced_ping)))
	on_change(nameof(charge), ANY, coalesce(PROC_REF(charge_window)), then(PROC_REF(coalesced_charge)))

/obj/forms_listener/proc/coalesced_ping(datum/act/A)
	runs++
	GLOB.forms_runs++

/obj/forms_listener/proc/charge_window(datum/act/timer/A)
	return 3 SECONDS

/obj/forms_listener/proc/coalesced_charge(datum/act/A)
	charge_runs++
	charge_seen = charge

CAPABILITY_TYPE(forms_listening, CAP_FORMS_LISTENING, /datum/capability/forms_listening, key = NONE)
/datum/capability/forms_listening/entries()
	return list(on_notice(/datum/notice/forms_pinged, coalesce(2 SECONDS), then(CAP_PROC(cap_ran))))

/datum/capability/forms_listening/proc/cap_ran(datum/act/A)
	var/obj/forms_listener/L = A.holder
	L.cap_runs++
	GLOB.forms_runs++

/// A holder with modes(): idle, working, jammed.
/obj/forms_machine
	name = "forms machine"
	anchored = TRUE
	var/mode = /datum/capability/forms_idle
	var/charge = 0
	var/idle_ticks = 0
	var/work_ticks = 0
	var/jam_ticks = 0
	var/before_go_runs = 0
	var/after_go_runs = 0
	var/charge_runs = 0
	var/list/heard

TRACKED(/obj/forms_machine, mode)
TRACKED(/obj/forms_machine, charge)

CAPABILITIES(/obj/forms_machine)
	modes(nameof(mode))
	on_notice(/datum/notice/mode_changed, then(PROC_REF(heard_mode)))

/obj/forms_machine/proc/heard_mode(datum/act/A)
	var/datum/notice/mode_changed/N = A
	LAZYADD(heard, "[N.old_mode]>[N.new_mode]@[N.mode_var]")

CAPABILITY_TYPE(forms_idle, CAP_FORMS_IDLE, /datum/capability/forms_idle, key = NONE)
/datum/capability/forms_idle/entries()
	return list(every(1 SECOND, then(CAP_PROC(tick))))

/datum/capability/forms_idle/proc/tick(datum/act/timer/A)
	var/obj/forms_machine/M = A.holder
	M.idle_ticks++
	GLOB.forms_ticks++

CAPABILITY_TYPE(forms_working, CAP_FORMS_WORKING, /datum/capability/forms_working, key = NONE)
/datum/capability/forms_working/entries()
	return list(
		every(1 SECOND, then(CAP_PROC(tick))),
		on_notice(/datum/notice/forms_pinged, then(CAP_PROC(before_go)), go(/datum/capability/forms_jammed), then(CAP_PROC(after_go))),
		on_change("charge", ANY, coalesce(1 SECOND), then(CAP_PROC(charge_run))),
		after_in_state(10 SECONDS, go(/datum/capability/forms_jammed)))

/datum/capability/forms_working/proc/tick(datum/act/timer/A)
	var/obj/forms_machine/M = A.holder
	M.work_ticks++
	GLOB.forms_ticks++

/datum/capability/forms_working/proc/before_go(datum/act/A)
	var/obj/forms_machine/M = A.holder
	M.before_go_runs++

/datum/capability/forms_working/proc/after_go(datum/act/A)
	var/obj/forms_machine/M = A.holder
	M.after_go_runs++

/datum/capability/forms_working/proc/charge_run(datum/act/A)
	var/obj/forms_machine/M = A.holder
	M.charge_runs++

CAPABILITY_TYPE(forms_jammed, CAP_FORMS_JAMMED, /datum/capability/forms_jammed, key = NONE)
/datum/capability/forms_jammed/entries()
	return list(every(1 SECOND, then(CAP_PROC(tick))))

/datum/capability/forms_jammed/proc/tick(datum/act/timer/A)
	var/obj/forms_machine/M = A.holder
	M.jam_ticks++
	GLOB.forms_ticks++

CAPABILITY_TYPE(forms_plain_state, CAP_FORMS_PLAIN_STATE, /datum/capability/forms_plain_state, key = NONE)
/datum/capability/forms_plain_state/entries()
	return list()

/// A plain datum (not an atom) with modes(): it starts in the state its var names.
/datum/forms_plain_machine
	var/mode = /datum/capability/forms_plain_state

TRACKED(/datum/forms_plain_machine, mode)

CAPABILITIES(/datum/forms_plain_machine)
	modes(nameof(mode))

/datum/unit_test/forms_modes_plain_datum_initial_state

/datum/unit_test/forms_modes_plain_datum_initial_state/Run()
	var/datum/forms_plain_machine/M = new
	TEST_ASSERT(granted(M, /datum/capability/forms_plain_state), "a plain datum with modes() was not granted the state its var names when it was made")
	TEST_ASSERT_EQUAL(mode_now(M, "mode"), /datum/capability/forms_plain_state, "mode_now() does not report the initial state of a plain datum")
	qdel(M)

/// A capability type nothing declared with CAPABILITY_TYPE: not a valid mode.
/datum/capability/forms_undeclared

/// A holder of standings, and the things it holds them toward.
/obj/forms_holder
	name = "forms holder"
	anchored = TRUE
	var/changes = 0

CAPABILITIES(/obj/forms_holder)
	on_notice(/datum/notice/standing_changed, then(PROC_REF(heard_change)))

/obj/forms_holder/proc/heard_change(datum/act/A)
	changes++

/obj/forms_subject
	name = "forms subject"
	anchored = TRUE
	var/faction = "wolves"
	var/is_player = FALSE

/obj/forms_subject/standing_player()
	return is_player

// ---------------------------------------------------------------- coalesce

/datum/unit_test/dq_forms
	abstract_type = /datum/unit_test/dq_forms

/// A clean driver, and the declaration reports captured: some tests make them on purpose.
/datum/unit_test/dq_forms/Run()
	test_driver_begin()
	GLOB.declare_report_capture = list()
	run_forms()
	GLOB.declare_report_capture = null
	test_driver_end()

/datum/unit_test/dq_forms/proc/run_forms()
	return

/datum/unit_test/dq_forms/coalesce_burst_runs_once

/datum/unit_test/dq_forms/coalesce_burst_runs_once/run_forms()
	var/obj/forms_listener/L = allocate(/obj/forms_listener)
	for(var/i in 1 to 6)
		PUBLISH(L, forms_ping)
	TEST_ASSERT_EQUAL(L.runs, 0, "a burst runs nothing inside the window")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(L), 1, "and the six triggers share one timer")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(L.runs, 0, "still inside the window")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(L.runs, 1, "the window closes into exactly one run")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(L.runs, 1, "and no more without another trigger")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(L), 0, "an idle holder has no timer")

/datum/unit_test/dq_forms/coalesce_sustained_runs_at_the_interval

/datum/unit_test/dq_forms/coalesce_sustained_runs_at_the_interval/run_forms()
	var/obj/forms_listener/L = allocate(/obj/forms_listener)
	for(var/i in 1 to 20)
		PUBLISH(L, forms_ping)
		test_time(1 SECOND)
	TEST_ASSERT(L.runs >= 8 && L.runs <= 10, "twenty triggers over twenty seconds on a two second window: about one run per interval, got [L.runs]")
	test_time(5 SECONDS)
	TEST_ASSERT(time_scheduler().timer_count(L) == 0, "and when the triggers stop the holder is quiet again")

/datum/unit_test/dq_forms/coalesce_on_change_with_an_interval_proc

/datum/unit_test/dq_forms/coalesce_on_change_with_an_interval_proc/run_forms()
	var/obj/forms_listener/L = allocate(/obj/forms_listener)
	L.set_charge(1)
	L.set_charge(2)
	L.set_charge(3)
	test_drain()
	TEST_ASSERT_EQUAL(L.charge_runs, 0, "the change opens a window")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(L.charge_runs, 0, "the interval proc said three seconds")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(L.charge_runs, 1, "three writes, one run")
	TEST_ASSERT_EQUAL(L.charge_seen, 3, "that reads the latest value")

/datum/unit_test/dq_forms/coalesce_dies_with_the_holder

/datum/unit_test/dq_forms/coalesce_dies_with_the_holder/run_forms()
	var/obj/forms_listener/L = new(run_loc_floor_bottom_left)
	var/before = GLOB.forms_runs
	PUBLISH(L, forms_ping)
	qdel(L)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(GLOB.forms_runs, before, "a window open when the holder is deleted never runs")

/datum/unit_test/dq_forms/coalesce_dies_with_the_capability

/datum/unit_test/dq_forms/coalesce_dies_with_the_capability/run_forms()
	var/obj/forms_listener/L = allocate(/obj/forms_listener)
	var/datum/forms_source/S = allocate(/datum/forms_source)
	// Control: a granted capability's coalesced hook runs.
	TEST_ASSERT(grant(L, /datum/capability/forms_listening, S), "granted")
	PUBLISH(L, forms_ping)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(L.cap_runs, 1, "the granted capability's hook runs once")
	// Revoked mid-window.
	PUBLISH(L, forms_ping)
	TEST_ASSERT(revoke(L, /datum/capability/forms_listening, S), "revoked mid-window")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(L.cap_runs, 1, "a revoked capability's pending run never happens")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(L), 0, "and its window is cancelled, not left to expire")

/datum/forms_source

// ---------------------------------------------------------------- modes

/datum/unit_test/dq_forms/modes_grant_and_revoke

/datum/unit_test/dq_forms/modes_grant_and_revoke/run_forms()
	GLOB.forms_trace = TRUE
	var/obj/forms_machine/M = allocate(/obj/forms_machine)
	TEST_ASSERT(granted(M, /datum/capability/forms_idle), "the var's capability is granted when the holder initializes")
	TEST_ASSERT_EQUAL(mode_now(M, "mode"), /datum/capability/forms_idle, "and is the mode")
	TEST_ASSERT(mode_enter(M, "mode", /datum/capability/forms_working), "go to working")
	TEST_ASSERT(granted(M, /datum/capability/forms_working), "the new state is granted")
	TEST_ASSERT(!granted(M, /datum/capability/forms_idle), "the previous one is revoked")
	TEST_ASSERT_EQUAL(M.heard[length(M.heard)], "[/datum/capability/forms_idle]>[/datum/capability/forms_working]@mode", "mode_changed carries old, new and the var")
	TEST_ASSERT(!mode_enter(M, "mode", /datum/capability/forms_working), "setting the same mode changes nothing")
	TEST_ASSERT(mode_enter(M, "mode", null), "no mode at all")
	TEST_ASSERT(!granted(M, /datum/capability/forms_working), "revokes the state")
	GLOB.forms_trace = FALSE

/datum/unit_test/dq_forms/modes_setter_is_picked_up

/datum/unit_test/dq_forms/modes_setter_is_picked_up/run_forms()
	var/obj/forms_machine/M = allocate(/obj/forms_machine)
	M.set_mode(/datum/capability/forms_working)
	test_drain()
	TEST_ASSERT(granted(M, /datum/capability/forms_working), "a write through the setter reaches the grant at the next drain")
	TEST_ASSERT(!granted(M, /datum/capability/forms_idle), "and revokes the old state")

/datum/unit_test/dq_forms/modes_state_entries_live_and_stop

/datum/unit_test/dq_forms/modes_state_entries_live_and_stop/run_forms()
	var/obj/forms_machine/M = allocate(/obj/forms_machine)
	test_time(3 SECONDS)
	TEST_ASSERT(M.idle_ticks >= 2, "the idle state's every() runs while it is the mode")
	mode_enter(M, "mode", /datum/capability/forms_working)
	var/idle_then = M.idle_ticks
	test_time(3 SECONDS)
	TEST_ASSERT(M.work_ticks >= 2, "the working state's every() runs")
	TEST_ASSERT_EQUAL(M.idle_ticks, idle_then, "the idle state's every() stopped when it left")
	M.set_charge(1)
	test_drain()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(M.charge_runs, 1, "a state's on_change with coalesce() runs")
	mode_enter(M, "mode", /datum/capability/forms_jammed)
	var/work_then = M.work_ticks
	M.set_charge(2)
	test_drain()
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(M.work_ticks, work_then, "the working state's every() stopped when it left")
	TEST_ASSERT_EQUAL(M.charge_runs, 1, "and so did its on_change")
	TEST_ASSERT(M.jam_ticks >= 2, "while the new state's every() runs")

/datum/unit_test/dq_forms/modes_state_timer_is_cancelled_on_exit

/datum/unit_test/dq_forms/modes_state_timer_is_cancelled_on_exit/run_forms()
	var/obj/forms_machine/M = allocate(/obj/forms_machine)
	mode_enter(M, "mode", /datum/capability/forms_working)
	test_time(3 SECONDS)
	mode_enter(M, "mode", /datum/capability/forms_idle)
	test_time(30 SECONDS)
	TEST_ASSERT_EQUAL(M.mode, /datum/capability/forms_idle, "the working state's after_in_state() never fired after it was left")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(M), 1, "only the idle state's every() is scheduled")
	// Control: left alone, the timer fires and the state's own go() moves the mode.
	mode_enter(M, "mode", /datum/capability/forms_working)
	test_time(11 SECONDS)
	TEST_ASSERT_EQUAL(M.mode, /datum/capability/forms_jammed, "after_in_state(10 SECONDS, go(jammed)) moved the mode")
	TEST_ASSERT(granted(M, /datum/capability/forms_jammed) && !granted(M, /datum/capability/forms_working), "through a grant and a revoke")

/datum/unit_test/dq_forms/modes_transition_from_inside_a_handler

/datum/unit_test/dq_forms/modes_transition_from_inside_a_handler/run_forms()
	var/obj/forms_machine/M = allocate(/obj/forms_machine)
	mode_enter(M, "mode", /datum/capability/forms_working)
	PUBLISH(M, forms_ping)
	TEST_ASSERT_EQUAL(M.mode, /datum/capability/forms_jammed, "a state's own handler moved the mode with go()")
	TEST_ASSERT_EQUAL(M.before_go_runs, 1, "the parts before go() ran")
	TEST_ASSERT_EQUAL(M.after_go_runs, 0, "the parts after go() did not: their state is gone")
	TEST_ASSERT(!granted(M, /datum/capability/forms_working), "the state ended at once")
	var/work_then = M.work_ticks
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(M.work_ticks, work_then, "and nothing of it ran again")
	var/count = 0
	for(var/line in M.heard)
		if(line == "[/datum/capability/forms_working]>[/datum/capability/forms_jammed]@mode")
			count++
	TEST_ASSERT_EQUAL(count, 1, "one notice for the transition")

/datum/unit_test/dq_forms/modes_holder_destroyed_in_a_state

/datum/unit_test/dq_forms/modes_holder_destroyed_in_a_state/run_forms()
	var/obj/forms_machine/M = new(run_loc_floor_bottom_left)
	mode_enter(M, "mode", /datum/capability/forms_working)
	test_time(2 SECONDS)
	qdel(M)
	var/before = GLOB.forms_ticks
	test_time(30 SECONDS)
	TEST_ASSERT_EQUAL(GLOB.forms_ticks, before, "a deleted holder's state runs nothing: no every(), no after_in_state()")

/datum/unit_test/dq_forms/modes_rejects_invalid_types

/datum/unit_test/dq_forms/modes_rejects_invalid_types/run_forms()
	var/obj/forms_machine/M = allocate(/obj/forms_machine)
	TEST_ASSERT(isnull(go(/datum/forms_source)), "go() of a type that is no capability is refused at declaration")
	TEST_ASSERT(isnull(go(/datum/capability/forms_undeclared)), "and so is a capability nothing declared")
	TEST_ASSERT(isnull(go(null)), "and null")
	TEST_ASSERT(isnull(modes(null)), "modes() needs a var name")
	TEST_ASSERT(isnull(after_in_state(0, go(/datum/capability/forms_idle))), "after_in_state() needs a positive delay")
	TEST_ASSERT_EQUAL(length(GLOB.declare_report_capture), 5, "each was reported: [json_encode(GLOB.declare_report_capture)]")
	GLOB.declare_report_capture = list()
	TEST_ASSERT(!mode_enter(M, "mode", /datum/capability/forms_undeclared), "mode_enter() refuses it")
	M.set_mode(/datum/capability/forms_undeclared)
	test_drain()
	TEST_ASSERT_EQUAL(M.mode, /datum/capability/forms_idle, "a bad value written through the setter is reported and put back")
	TEST_ASSERT(granted(M, /datum/capability/forms_idle), "the mode did not move")
	TEST_ASSERT_EQUAL(length(GLOB.declare_report_capture), 2, "both reported: [json_encode(GLOB.declare_report_capture)]")
	GLOB.declare_report_capture = list()

// ---------------------------------------------------------------- standings

/datum/unit_test/dq_forms/standing_composition_order

/datum/unit_test/dq_forms/standing_composition_order/run_forms()
	var/obj/forms_holder/H = allocate(/obj/forms_holder)
	var/obj/forms_subject/S = allocate(/obj/forms_subject)
	var/datum/forms_source/src_a = allocate(/datum/forms_source)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_NEUTRAL, "no row: the default")
	TEST_ASSERT_EQUAL(standing_toward(H, S, STANDING_WARY), STANDING_WARY, "or the one asked for")
	standing(H, toward = STANDING_ANY, value = STANDING_FRIENDLY, source = src_a)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_FRIENDLY, "STANDING_ANY applies to everything")
	standing(H, toward = "wolves", value = STANDING_WARY, source = src_a)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_WARY, "a faction row beats the any row at the same priority (more hostile)")
	TEST_ASSERT_EQUAL(standing_toward(H, "wolves"), STANDING_WARY, "a faction key is a subject too")
	var/datum/forms_source/src_b = allocate(/datum/forms_source)
	standing(H, toward = S, value = STANDING_ALLY, source = src_b, priority = 50)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_ALLY, "a higher-priority row toward the subject wins whatever its value")
	var/obj/forms_subject/other = allocate(/obj/forms_subject)
	other.faction = "bears"
	TEST_ASSERT_EQUAL(standing_toward(H, other), STANDING_FRIENDLY, "another faction falls back to the any row")
	other.faction = "wolves"
	TEST_ASSERT_EQUAL(standing_toward(H, other), STANDING_WARY, "a subject that joins the faction gets its row (the cache follows the faction)")

/datum/unit_test/dq_forms/standing_priority_and_ties

/datum/unit_test/dq_forms/standing_priority_and_ties/run_forms()
	var/obj/forms_holder/H = allocate(/obj/forms_holder)
	var/obj/forms_subject/S = allocate(/obj/forms_subject)
	var/datum/forms_source/a = allocate(/datum/forms_source)
	var/datum/forms_source/b = allocate(/datum/forms_source)
	standing(H, toward = S, value = STANDING_HOSTILE, source = a, priority = 10)
	standing(H, toward = S, value = STANDING_FRIENDLY, source = b, priority = 20)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_FRIENDLY, "the higher priority wins even when it is the friendlier")
	standing(H, toward = S, value = STANDING_WARY, source = b, priority = 10)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_HOSTILE, "on a tie the most hostile wins")
	TEST_ASSERT_EQUAL(standing_decided_by(H, S), a, "and says whose row decided")
	// A tie across tiers: a faction row against a row toward the subject itself.
	standing(H, toward = "wolves", value = STANDING_ALLY, source = a, priority = 99)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_ALLY, "priority also decides across tiers")

/datum/unit_test/dq_forms/standing_dedup_expiry_and_release

/datum/unit_test/dq_forms/standing_dedup_expiry_and_release/run_forms()
	var/obj/forms_holder/H = allocate(/obj/forms_holder)
	var/obj/forms_subject/S = allocate(/obj/forms_subject)
	var/datum/forms_source/a = allocate(/datum/forms_source)
	standing(H, toward = S, value = STANDING_HOSTILE, source = a)
	standing(H, toward = S, value = STANDING_WARY, source = a)
	TEST_ASSERT_EQUAL(length(splittext(standing_explain(H), "\n")), 1, "one source holds one row per subject")
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_WARY, "and stancing again replaces the value")
	TEST_ASSERT_EQUAL(unstanding(H, S, a), 1, "unstanding() releases it")
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_NEUTRAL, "and the answer is the default again")
	// Expiry.
	standing(H, toward = S, value = STANDING_HOSTILE, source = a, lasts = 10 SECONDS)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_HOSTILE, "a timed stance holds inside its time")
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_NEUTRAL, "and expires on its own")
	// A deleted source releases its rows, timed or not.
	var/datum/forms_source/doomed = new
	standing(H, toward = S, value = STANDING_HOSTILE, source = doomed, lasts = 5 MINUTES)
	standing(H, toward = STANDING_ANY, value = STANDING_ALLY, source = doomed)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_HOSTILE, "placed")
	qdel(doomed)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_NEUTRAL, "a deleted source's rows are released, even a timed one")
	TEST_ASSERT_EQUAL(standing_explain(H), "", "none left")

/datum/unit_test/dq_forms/standing_cache_invalidation

/datum/unit_test/dq_forms/standing_cache_invalidation/run_forms()
	var/obj/forms_holder/H = allocate(/obj/forms_holder)
	var/obj/forms_subject/S = allocate(/obj/forms_subject)
	var/datum/forms_source/a = allocate(/datum/forms_source)
	GLOB.forms_trace = TRUE
	standing(H, toward = "wolves", value = STANDING_WARY, source = a)
	TEST_ASSERT_EQUAL(H.changes, 1, "placing a row publishes standing_changed")
	var/misses = GLOB.standing_cache_misses
	var/hits = GLOB.standing_cache_hits
	standing_toward(H, S)
	standing_toward(H, S)
	standing_toward(H, S)
	TEST_ASSERT_EQUAL(GLOB.standing_cache_misses, misses + 1, "the first read computes")
	TEST_ASSERT_EQUAL(GLOB.standing_cache_hits, hits + 2, "the next two are cached")
	var/drops = GLOB.standing_cache_drops
	var/datum/forms_source/b = allocate(/datum/forms_source)
	standing(H, toward = "wolves", value = STANDING_HOSTILE, source = b)
	TEST_ASSERT_EQUAL(GLOB.standing_cache_drops, drops + 1, "a row change drops the cache")
	TEST_ASSERT_EQUAL(H.changes, 2, "and publishes")
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_HOSTILE, "so the next read sees the new row")
	unstanding(H, "wolves", b)
	TEST_ASSERT_EQUAL(H.changes, 3, "a release publishes too")
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_WARY, "and the read follows it")
	standing(H, toward = "wolves", value = STANDING_FRIENDLY, source = a, lasts = 2 SECONDS)
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_FRIENDLY, "a timed replacement")
	var/changes = H.changes
	test_time(3 SECONDS)
	TEST_ASSERT(H.changes > changes, "an expiry publishes")
	TEST_ASSERT_EQUAL(standing_toward(H, S), STANDING_NEUTRAL, "and the cache did not keep the expired row")
	GLOB.forms_trace = FALSE

/datum/unit_test/dq_forms/standing_players_and_any

/datum/unit_test/dq_forms/standing_players_and_any/run_forms()
	var/obj/forms_holder/H = allocate(/obj/forms_holder)
	var/obj/forms_subject/npc = allocate(/obj/forms_subject)
	var/obj/forms_subject/player = allocate(/obj/forms_subject)
	player.is_player = TRUE
	var/datum/forms_source/a = allocate(/datum/forms_source)
	standing(H, toward = STANDING_PLAYERS, value = STANDING_HOSTILE, source = a)
	TEST_ASSERT_EQUAL(standing_toward(H, player), STANDING_HOSTILE, "a STANDING_PLAYERS row applies to a player-controlled subject")
	TEST_ASSERT_EQUAL(standing_toward(H, npc), STANDING_NEUTRAL, "and not to anyone else")
	player.is_player = FALSE
	TEST_ASSERT_EQUAL(standing_toward(H, player), STANDING_NEUTRAL, "the answer follows who controls the subject now")
	player.is_player = TRUE
	standing(H, toward = STANDING_ANY, value = STANDING_ALLY, source = a)
	TEST_ASSERT_EQUAL(standing_toward(H, npc), STANDING_ALLY, "STANDING_ANY reaches the npc")
	TEST_ASSERT_EQUAL(standing_toward(H, player), STANDING_HOSTILE, "and the player row is more hostile than the any row at the same priority")
	// Refusals are reported, not placed.
	GLOB.declare_report_capture = list()
	TEST_ASSERT(isnull(standing(H, toward = null, value = STANDING_ALLY, source = a)), "no subject")
	TEST_ASSERT(isnull(standing(H, toward = npc, value = "friendly", source = a)), "no number")
	TEST_ASSERT(isnull(standing(H, toward = npc, value = STANDING_ALLY, source = "text")), "no source")
	TEST_ASSERT_EQUAL(length(GLOB.declare_report_capture), 3, "reported: [json_encode(GLOB.declare_report_capture)]")
	GLOB.declare_report_capture = list()

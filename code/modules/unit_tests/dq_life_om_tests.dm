// Mob Life on the kernel's Life sequence (doc/rewrite/life_sequences.md, doc/rewrite/om_retirement.md L1): content
// (tables, overrides, conditions) and the scheduling the sequence owns for Life: cadence and catch-up, sleep and wake
// by channel, once steps, parking, rewakes, suspension, relevance, stasis, statuses, the canmove/HUD/sight reactions,
// and one test per bug the Codex prototype had.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#define LIFE_SEQ /datum/sequence/life

/// Puts a test mob on a floor (the living core is gated on "placed"), and makes it relevant: the
/// test world has no living player on any z-level.
/proc/life_test_place(mob/living/L)
	L.set_low_priority(FALSE)
	if(isturf(L.loc))
		return TRUE
	var/turf/simulated/floor/T = locate() in world
	if(!T)
		return FALSE
	L.forceMove(T)
	return isturf(L.loc)

/// `L`'s state on the Life sequence.
/proc/life_test_state(mob/living/L)
	RETURN_TYPE(/datum/seq_state)
	var/datum/sequence/S = sequence_def(LIFE_SEQ)
	return SEQ_STATE_OF(L, S.idx)

/// The step keys of `L`'s Life table, in run order.
/proc/life_test_steps(mob/living/L)
	. = list()
	var/datum/seq_state/state = life_test_state(L)
	for(var/datum/seq_step/S as anything in state?.table.steps)
		. += S.key

/// Frames the Life sequence ran on `L`.
/proc/life_test_frames(mob/living/L)
	return life_test_state(L)?.frames || 0

/proc/life_test_parked(mob/living/L)
	return seq_parked(L, LIFE_SEQ)

/// TRUE when every key in `expected` appears in `actual`, in the same relative order.
/proc/life_test_in_order(list/actual, list/expected)
	var/last = 0
	for(var/key in expected)
		var/index = actual.Find(key)
		if(!index || index < last)
			return FALSE
		last = index
	return TRUE

/// A mouse that can park: placed on a floor, its AI asleep, and its environment limits opened
/// so the test floor's air can't hurt it.
/proc/life_test_idle_mouse(mob/living/simple_mob/M)
	if(!life_test_place(M))
		return FALSE
	M.ai_brain?.go_sleep()
	M.min_oxy = 0
	M.max_oxy = 0
	M.min_tox = 0
	M.max_tox = 0
	M.min_n2 = 0
	M.max_n2 = 0
	M.min_co2 = 0
	M.max_co2 = 0
	M.min_ch4 = 0
	M.max_ch4 = 0
	M.minbodytemp = 0
	M.maxbodytemp = INFINITY
	M.temperature_range = INFINITY
	return TRUE

/// Runs frames until the mob parks, at most `frames` times. Returns TRUE if it did. Each frame is followed by a
/// pass of the test scheduler, so the changes it raised are delivered before the next frame, as they are live.
/proc/life_test_settle(mob/living/L, frames = 6)
	for(var/i in 1 to frames)
		if(life_test_parked(L))
			return TRUE
		seq_run_frame_now(L, LIFE_SEQ)
		om_scheduler().run_pass(1e9)
	return life_test_parked(L)

/// Keys of the steps that would keep this mob awake (should_run() holds), for failure messages.
/proc/life_test_busy(mob/living/L)
	var/list/names = list()
	var/datum/seq_state/state = life_test_state(L)
	for(var/datum/seq_step/S as anything in state?.table.steps)
		if(seq_should_run(S, L, state))
			names += S.key
	return jointext(names, ", ")

/// TRUE when step `key` sleeps on `L`.
/proc/life_test_asleep(mob/living/L, key)
	return seq_step_asleep(L, LIFE_SEQ, key)

/// Steps of `L` that are awake.
/proc/life_test_awake(mob/living/L)
	. = list()
	var/datum/seq_state/state = life_test_state(L)
	for(var/datum/seq_step/S as anything in state?.table.steps)
		if(!seq_step_asleep(L, LIFE_SEQ, S.key))
			. += S.key

/// The test clock: the kernel on its injected clock (test_time()), the OM test scheduler current, and the Life sweep
/// owned by the test so test_time() drives it in the game run level.
/proc/life_test_clock_begin()
	RETURN_TYPE(/datum/om/scheduler)
	test_driver_begin()
	var/datum/sequence/S = sequence_def(LIFE_SEQ)
	var/datum/work_item/sequence/W = S.work
	W.test_owned = TRUE
	W.test_runlevel = RUNLEVEL_GAME
	W.test_reset()
	var/datum/controller/kernel/K = kernel()
	K.test_dirty = TRUE
	K.work_dirty = TRUE
	return om_scheduler()

/proc/life_test_clock_end()
	var/datum/sequence/S = sequence_def(LIFE_SEQ)
	var/datum/work_item/sequence/W = S.work
	W.test_owned = FALSE
	W.test_runlevel = null
	W.test_reset()
	var/datum/controller/kernel/K = kernel()
	K.test_dirty = TRUE
	K.work_dirty = TRUE
	test_driver_end()

/// Lets `seconds` of test time pass: every kernel phase, drain and sweep that falls due.
/proc/life_test_advance(seconds)
	test_time(seconds * 10)

// --- Test-only contributed steps (added per mob with seq_extra_add(); never in a table otherwise) ---------------------

/// A contributed step: counts its runs per mob and remembers the dt of the frame it last ran in.
/datum/life_test_step
	var/list/runs
	var/last_dt = 0

/datum/life_test_step/proc/life_steps()
	return list()

/datum/life_test_step/proc/count(mob/living/L, datum/seq_frame/life/F)
	LAZYSET(runs, "[REF(L)]", (LAZYACCESS(runs, "[REF(L)]") || 0) + 1)
	last_dt = F?.dt

/datum/life_test_step/proc/runs_on(mob/living/L)
	return LAZYACCESS(runs, "[REF(L)]") || 0

/datum/life_test_step/proc/no_work(mob/living/L)
	return FALSE

/// Always awake: runs every frame.
/datum/life_test_step/counter/life_steps()
	return list(seq_step(PROC_REF(count), after = list(LIFE_TAIL, "life_test_deleter"), key = "life_test_counter"))

/// Sleeps after every run, with a rewake.
/datum/life_test_step/timer/life_steps()
	return list(seq_step(PROC_REF(count), after = LIFE_TAIL, key = "life_test_timer", should_run = PROC_REF(no_work), rewake = 3 SECONDS))

/// Raises a health change on its mob during the frame.
/datum/life_test_step/raiser/life_steps()
	return list(seq_step(PROC_REF(raise), after = LIFE_INPUT, key = "life_test_raiser", should_run = PROC_REF(no_work)))

/datum/life_test_step/raiser/proc/raise(mob/living/L, datum/seq_frame/life/F)
	changed(L, CHANGE_MOB_HEALTH)

/// Runs once per wake; health changes wake it.
/datum/life_test_step/sleeper/life_steps()
	return list(seq_step(PROC_REF(count), after = LIFE_TAIL, key = "life_test_sleeper", reads = CHANGE_MOB_HEALTH, once = TRUE))

/// Deletes its mob during the frame.
/datum/life_test_step/deleter/life_steps()
	return list(seq_step(PROC_REF(delete_mob), after = LIFE_TAIL, key = "life_test_deleter"))

/datum/life_test_step/deleter/proc/delete_mob(mob/living/L, datum/seq_frame/life/F)
	qdel(L)

/// Adds a test step of `type` to `L`'s Life table. Returns the contributor.
/proc/life_test_add(mob/living/L, type)
	var/datum/life_test_step/C = new type
	seq_extra_add(L, LIFE_SEQ, C)
	return C

/// A ghost that counts its upkeep runs.
/mob/observer/dead/life_test
	var/upkeeps = 0

/mob/observer/dead/life_test/upkeep()
	upkeeps++
	return ..()

// --- Base: every scheduling test runs on the test clock --------------------------------------------------------------

/datum/unit_test/life_om
	abstract_type = /datum/unit_test/life_om
	var/datum/om/scheduler/sched

/datum/unit_test/life_om/Run()
	rel_set(src, nameof(sched), life_test_clock_begin())
	try
		run_life()
	catch(var/exception/e)
		TEST_FAIL("runtime in life test: [e] ([e.file]:[e.line])")
	life_test_clock_end()

/datum/unit_test/life_om/proc/run_life()
	return

/// The handlers (as text) of `L`'s on_change() reactions.
/proc/life_test_reaction_handlers(mob/living/L)
	. = list()
	var/datum/rx_table/T = rx_table_of(L)
	for(var/key in T?.by_key)
		for(var/datum/reaction/R as anything in T.by_key[key])
			. |= "[R.handler]"

/// Raises a mob change the way its producer does: the OM channel (Life steps still wake on it) and the change key the
/// presentation reactions read (PUBLISH_CHANGE).
/proc/life_test_raise(mob/living/L, channel)
	changed(L, channel)
	var/static/list/keys = list("[CHANGE_MOB_STATUS]" = MOB_KEY_STATUS, "[CHANGE_MOB_HEALTH]" = MOB_KEY_HEALTH, \
		"[CHANGE_MOB_LOC]" = MOB_KEY_LOC, "[CHANGE_MOB_EQUIPMENT]" = MOB_KEY_EQUIPMENT, "[CHANGE_MOB_CONDITIONS]" = MOB_KEY_CONDITIONS, \
		"[CHANGE_MOB_CLIENT]" = MOB_KEY_CLIENT)
	var/key = keys["[channel]"]
	if(key)
		PUBLISH_CHANGE(L, key)

/// TRUE when `L`'s reaction with `handler` is queued for the next drain.
/proc/life_test_rx_queued(mob/living/L, handler)
	var/list/per = GLOB.rx_pending[L]
	for(var/datum/reaction/R in per)
		if(R.handler == handler)
			return TRUE
	return FALSE

// --- Content: tables, overrides, conditions ----------------------------------------------------------------------------

/// Every Life table builds without errors (no cycle, every condition known) for the main mob families.
/datum/unit_test/dq_life_tables_are_clean

/datum/unit_test/dq_life_tables_are_clean/Run()
	var/datum/sequence/S = sequence_def(LIFE_SEQ)
	for(var/path in list(/mob/living/carbon/human, /mob/living/simple_mob/animal/passive/mouse, /mob/living/simple_mob/animal/passive/chicken, \
		/mob/living/simple_mob/slime/xenobio/amber, /mob/living/silicon/robot, /mob/living/silicon/pai, \
		/mob/living/carbon/brain, /mob/living/carbon/alien/larva, /mob/living/bot/secbot))
		var/mob/living/L = allocate(path)
		var/datum/seq_table/T = S.table_for(L, null)
		TEST_ASSERT_EQUAL(length(T.errors), 0, "[path]'s Life table has errors: [jointext(T.errors, "; ")]")
		TEST_ASSERT(T.n > 0, "[path] runs Life steps")

/// A human runs the living core, carbon germs and the human tail in the legacy order; canmove, HUD and sight are
/// reactions on the mob.
/datum/unit_test/dq_life_human_plan_order

/datum/unit_test/dq_life_human_plan_order/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/keys = life_test_steps(H)
	var/list/expected = list(
		"life_type_pre",
		"life_upkeep",
		"life_instability",
		"life_light",
		"life_breathing",
		"life_mutations",
		"life_radiation",
		"life_random_events",
		"life_afk",
		"life_chemicals",
		"life_environment",
		"life_ambience",
		"life_movement",
		"life_status",
		"life_disabilities",
		"life_addictions",
		"life_tf_holder",
		"life_vr_derez",
		"life_germs",
		"life_voice",
		"life_stasis_sleep",
		"life_fall",
		"life_changeling",
		"life_thermoregulation",
		"life_weight",
		"life_shock",
		"life_medical",
		"life_heartbeat",
		"life_nif",
		"life_phobias",
		"life_npc",
		"life_species_components",
		"life_visible_name",
		"life_pulse",
	)
	TEST_ASSERT(life_test_in_order(keys, expected), "human steps are missing or out of order: [jointext(keys, ", ")]")
	TEST_ASSERT(!("life_robot_power" in keys), "a human must not get robot steps")
	var/list/handlers = life_test_reaction_handlers(H)
	TEST_ASSERT(("[TYPE_PROC_REF(/mob/living, life_canmove_changed)]" in handlers) && ("[TYPE_PROC_REF(/mob/living, life_hud_changed)]" in handlers) && ("[TYPE_PROC_REF(/mob/living, life_vision_changed)]" in handlers), "canmove, HUD and sight are reactions on the mob: [jointext(handlers, ", ")]")
	TEST_ASSERT(H.life_canmove_wanted() && H.life_vision_wanted(), "a human derives canmove and sight, client or not")
	TEST_ASSERT(!H.life_hud_wanted(), "but draws no HUD without a client")

/// Every human of a type shares one table; a cyborg's table comes from the robot set only.
/datum/unit_test/dq_life_plan_is_shared

/datum/unit_test/dq_life_plan_is_shared/Run()
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(life_test_state(first).table, life_test_state(second).table, "two plain humans should share one table")

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/list/keys = life_test_steps(R)
	var/list/expected = list(
		"life_robot_cycle",
		"life_robot_senses",
		"life_instability",
		"life_robot_power",
		"life_robot_body",
		"life_robot_alarms",
	)
	TEST_ASSERT(life_test_in_order(keys, expected), "robot steps are missing or out of order: [jointext(keys, ", ")]")
	TEST_ASSERT_EQUAL(length(keys), length(expected), "a robot should run only the robot set: [jointext(keys, ", ")]")
	TEST_ASSERT(R.life_canmove_wanted(), "a robot derives canmove reactively")
	TEST_ASSERT(R.life_vision_wanted(), "a robot's sight and HUD are the presentation reactions")

/// A simple mob's subtype code runs as its own override after the simple mob core; humans have no simple mob steps.
/datum/unit_test/dq_life_simple_mob_variants

/datum/unit_test/dq_life_simple_mob_variants/Run()
	var/mob/living/simple_mob/animal/passive/chicken/C = allocate(/mob/living/simple_mob/animal/passive/chicken)
	TEST_ASSERT("life_type_post" in life_test_steps(C), "a chicken runs its own post-core code")
	TEST_ASSERT(C.life_type_post_due(), "and keeps it awake")
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(!M.life_type_post_due(), "a mouse's simple mob post code does nothing, so it sleeps")
	var/mob/living/simple_mob/slime/xenobio/amber/A = allocate(/mob/living/simple_mob/slime/xenobio/amber)
	TEST_ASSERT("life_special" in life_test_steps(A), "an amber slime runs its own special behaviour")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!("life_special" in life_test_steps(H)), "humans have no simple mob special behaviour")

/// The "alive" condition skips breathing for a dead body; a living body breathes on its cadence.
/datum/unit_test/dq_life_alive_fact_skips_stages

/datum/unit_test/dq_life_alive_fact_skips_stages/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/cycle_before = H.breath_cycle
	seq_run_frame_now(H, LIFE_SEQ)
	TEST_ASSERT_NOTEQUAL(H.breath_cycle, cycle_before, "a living human's breathing step should advance its breath cadence")

	H.death()
	TEST_ASSERT_EQUAL(H.stat, DEAD, "the human should be dead for the condition check")
	seq_wake(H, LIFE_SEQ)
	cycle_before = H.breath_cycle
	var/life_tick_before = H.life_tick
	seq_run_frame_now(H, LIFE_SEQ)
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a dead human must not run the alive-only breathing step")
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "a dead human still runs the rest of its frame")
	TEST_ASSERT(life_test_asleep(H, "life_breathing"), "a step a condition with reads (death) skips sleeps")

/// The human pre code aborts the whole frame while transforming, as the old early return did, and an aborted frame
/// puts nothing to sleep.
/datum/unit_test/dq_life_transforming_human_aborts

/datum/unit_test/dq_life_transforming_human_aborts/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/seq_state/S = life_test_state(H)
	seq_wake(H, LIFE_SEQ)
	var/life_tick_before = H.life_tick
	var/cycle_before = H.breath_cycle
	H.set_transforming(TRUE)
	seq_run_frame_now(H, LIFE_SEQ)
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before, "a transforming human must not tick")
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a transforming human must not breathe")
	TEST_ASSERT(!S.asleep, "an aborted frame puts nothing to sleep")
	H.set_transforming(FALSE)
	life_test_place(H)
	seq_run_frame_now(H, LIFE_SEQ)
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "the human should tick again once the transformation ends")

/// A transforming simple mob still runs its upkeep: transformation is a condition, not a suspension (Codex bug: it
/// halted all upkeep).
/datum/unit_test/dq_life_transforming_keeps_upkeep

/datum/unit_test/dq_life_transforming_keeps_upkeep/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_place(M), "no floor to place the test mouse on")
	var/datum/life_test_step/counter/counter = life_test_add(M, /datum/life_test_step/counter)
	M.set_transforming(TRUE)
	seq_run_frame_now(M, LIFE_SEQ)
	TEST_ASSERT_EQUAL(counter.runs_on(M), 1, "steps no condition gates run while transforming")
	TEST_ASSERT(!om_value_of(M, EFFECT_SUSPENDED), "transforming is not a suspension")
	M.set_transforming(FALSE)

/// A trait state's step joins the table while the state is attached.
/datum/unit_test/dq_life_trait_stage_follows_component

/datum/unit_test/dq_life_trait_stage_follows_component/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!("life_trait_photosynth" in life_test_steps(H)), "a plain human has no photosynthesis step")
	var/datum/trait_state/photosynth/P = H.add_trait_state(/datum/trait_state/photosynth)
	TEST_ASSERT_NOTNULL(P, "the photosynthesis trait state should attach")
	var/list/keys = life_test_steps(H)
	TEST_ASSERT("life_trait_photosynth" in keys, "attaching the state should add its step")
	TEST_ASSERT(life_test_in_order(keys, list("life_type_pre", "life_trait_photosynth", "life_upkeep")), "trait steps run where the old Life signal fired: [jointext(keys, ", ")]")
	qdel(P)
	TEST_ASSERT(!("life_trait_photosynth" in life_test_steps(H)), "removing the state should remove its step")

/// Loose organs never join Life (Codex bug: they rotted).
/datum/unit_test/dq_life_loose_organs_have_no_life

/datum/unit_test/dq_life_loose_organs_have_no_life/Run()
	var/obj/item/organ/internal/heart/heart = allocate(/obj/item/organ/internal/heart)
	TEST_ASSERT(!length(heart.seq_states), "a loose organ runs no sequence")

// --- Scheduling ----------------------------------------------------------------------------

/// One frame per LIFE_CYCLE, carrying LIFE_CYCLE_SECONDS of dt-scaled time.
/datum/unit_test/life_om/cadence

/datum/unit_test/life_om/cadence/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT_NOTNULL(life_test_state(H), "a living mob runs the Life sequence")
	var/datum/life_test_step/counter/counter = life_test_add(H, /datum/life_test_step/counter)
	life_test_advance(LIFE_CYCLE_SECONDS)
	var/before = life_test_frames(H)
	life_test_advance(LIFE_CYCLE_SECONDS * 10)
	var/frames = life_test_frames(H) - before
	TEST_ASSERT(frames >= 9 && frames <= 11, "expected 10 frames in 10 cycles, got [frames]")
	TEST_ASSERT_EQUAL(counter.last_dt, LIFE_CYCLE_SECONDS, "a frame covers one cycle of dt")

/// Skipped ticks: after a long gap the frame runs at most LIFE_MAX_CATCHUP times in one pass, never skips the mob,
/// and counts the dropped frames as breaches.
/datum/unit_test/life_om/catch_up_is_bounded

/datum/unit_test/life_om/catch_up_is_bounded/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	life_test_add(H, /datum/life_test_step/counter)
	life_test_advance(LIFE_CYCLE_SECONDS * 2)
	var/before = life_test_frames(H)
	var/datum/sequence/seq = sequence_def(LIFE_SEQ)
	var/breaches_before = seq.breaches
	// A long gap with no slot run in it, then the slot that sees it.
	var/datum/controller/kernel/K = kernel()
	K.test_now += LIFE_CYCLE * 20
	life_test_advance(LIFE_CYCLE_SECONDS)
	var/frames = life_test_frames(H) - before
	TEST_ASSERT(frames >= 1, "a mob is never skipped after skipped ticks")
	TEST_ASSERT(frames <= LIFE_MAX_CATCHUP + 1, "catch-up is capped at [LIFE_MAX_CATCHUP] frames per pass, ran [frames]")
	TEST_ASSERT(seq.breaches > breaches_before, "dropped frames are counted as breaches")
	before = life_test_frames(H)
	life_test_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT((life_test_frames(H) - before) <= 1, "after catching up, one frame per cycle again")

/// A healthy idle mob parks (out of the sweep); a change wakes the steps that read it and brings it back; the frame
/// after a long nap covers at most one cycle (Codex bug: the whole nap was passed as seconds).
/datum/unit_test/life_om/parking

/datum/unit_test/life_om/parking/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "an idle healthy mouse should park; still busy: [life_test_busy(M)]")
	var/datum/sequence/seq = sequence_def(LIFE_SEQ)
	TEST_ASSERT(member_is(seq.parked_key, M), "a parked mob is listed")
	TEST_ASSERT_NULL(seq.missed_wake(M), "a freshly parked mob has no missed wake")
	// Only rewakes bring a parked mob back (the simple mob environment's is 15 s); without them it runs no frames.
	seq_cancel_rewakes(M, life_test_state(M))
	var/before = life_test_frames(M)
	life_test_advance(LIFE_CYCLE_SECONDS * 20)
	TEST_ASSERT_EQUAL(life_test_frames(M), before, "a parked mob with no rewake runs no frames")
	TEST_ASSERT(M.injure(INJURY_BLUNT, 1) > 0, "the injury should land")
	TEST_ASSERT(!life_test_parked(M), "injure() unparks a mob")
	TEST_ASSERT(!life_test_asleep(M, "life_simple_vitals"), "the steps that read health wake")
	before = life_test_frames(M)
	life_test_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT((life_test_frames(M) - before) <= 1, "the first frame after a nap covers at most one cycle, ran [life_test_frames(M) - before]")

/// A sleeping step wakes only on its own reads; a once step runs once per wake; a change raised during a frame wakes
/// a later step back.
/datum/unit_test/life_om/channels_wake_stages

/datum/unit_test/life_om/channels_wake_stages/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	var/datum/life_test_step/sleeper/S = life_test_add(M, /datum/life_test_step/sleeper)
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	TEST_ASSERT(life_test_asleep(M, "life_test_sleeper"), "a once step sleeps after its run")
	var/runs = S.runs_on(M)
	changed(M, CHANGE_MOB_EQUIPMENT)
	TEST_ASSERT(life_test_asleep(M, "life_test_sleeper"), "a channel the step doesn't read leaves it asleep")
	changed(M, CHANGE_MOB_HEALTH)
	TEST_ASSERT(!life_test_asleep(M, "life_test_sleeper"), "its read wakes it")
	seq_run_frame_now(M, LIFE_SEQ)
	TEST_ASSERT_EQUAL(S.runs_on(M), runs + 1, "a woken once step runs in the next frame, with no pre-check")
	TEST_ASSERT(life_test_asleep(M, "life_test_sleeper"), "and sleeps again")

	// A step early in the frame raises the channel; the later step runs after it in the same frame (it sees the
	// change), so nothing is lost when it sleeps again.
	life_test_add(M, /datum/life_test_step/raiser)
	runs = S.runs_on(M)
	seq_run_frame_now(M, LIFE_SEQ)
	TEST_ASSERT_EQUAL(S.runs_on(M), runs + 1, "the later step runs after the change raised earlier in the frame")

/// A rewake brings a parked mob back partially: only the step whose rewake is due.
/datum/unit_test/life_om/rewake_unparks_partially

/datum/unit_test/life_om/rewake_unparks_partially/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	life_test_add(M, /datum/life_test_step/timer)
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	TEST_ASSERT(seq_rewake_pending(M, LIFE_SEQ, "life_test_timer"), "the test step's rewake is pending")
	var/waited = 0
	while(life_test_parked(M) && waited < 60)
		life_test_advance(0.1)
		waited++
	TEST_ASSERT(!life_test_parked(M) || life_test_state(M).frames, "the rewake brought the mob back")
	var/list/awake = life_test_awake(M)
	TEST_ASSERT(!length(awake - "life_test_timer"), "only the rewoken step wakes, not [jointext(awake - "life_test_timer", ", ")]")

/// A rewake wakes a sleeping step by its timer and never runs an extra frame on an awake mob (Codex bug: +20-30%
/// frames).
/datum/unit_test/life_om/rewakes_do_not_run_frames

/datum/unit_test/life_om/rewakes_do_not_run_frames/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	life_test_add(H, /datum/life_test_step/timer)
	seq_run_frame_now(H, LIFE_SEQ)
	TEST_ASSERT(life_test_asleep(H, "life_test_timer"), "the step sleeps")
	TEST_ASSERT(seq_rewake_pending(H, LIFE_SEQ, "life_test_timer"), "with a rewake pending")
	var/frames = life_test_frames(H)
	// Advance past the rewake (3 s) but not a whole cycle.
	var/waited = 0
	while(seq_rewake_pending(H, LIFE_SEQ, "life_test_timer") && waited < 40)
		life_test_advance(0.1)
		waited++
	TEST_ASSERT(!seq_rewake_pending(H, LIFE_SEQ, "life_test_timer"), "the rewake went off")
	TEST_ASSERT(life_test_frames(H) - frames <= 1, "the rewake ran no extra frame")

/// Deleting a mob during its frame stops the frame at once; its rewakes go with it.
/datum/unit_test/life_om/deletion_mid_frame

/datum/unit_test/life_om/deletion_mid_frame/run_life()
	var/mob/living/carbon/human/H = new(run_loc_floor_bottom_left)
	life_test_add(H, /datum/life_test_step/timer)
	life_test_add(H, /datum/life_test_step/deleter)
	var/datum/life_test_step/counter/counter = life_test_add(H, /datum/life_test_step/counter)
	seq_run_frame_now(H, LIFE_SEQ)
	TEST_ASSERT(QDELETED(H), "the deleter step deleted the mob")
	TEST_ASSERT(!counter.runs_on(H), "no step runs on a deleted mob")
	life_test_advance(2)
	TEST_ASSERT_EQUAL(length(sched.errors), 0, "no scheduler errors after deleting a mob with a pending rewake: [jointext(sched.errors, "; ")]")

/// Death wakes the steps that read stat; a dead mob parks too; revival brings it back.
/datum/unit_test/life_om/death_and_revive

/datum/unit_test/life_om/death_and_revive/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	M.death()
	TEST_ASSERT(!life_test_parked(M), "death is a stat change: it unparks the mob")
	var/before = life_test_frames(M)
	seq_run_frame_now(M, LIFE_SEQ)
	TEST_ASSERT_EQUAL(life_test_frames(M), before + 1, "a dead mob still runs its frame")
	TEST_ASSERT(life_test_settle(M), "a dead mob parks: its alive-only steps sleep on the stat channel; still busy: [life_test_busy(M)]")
	M.revive()
	TEST_ASSERT(!life_test_parked(M), "revival wakes the mob")
	TEST_ASSERT_NOTEQUAL(M.stat, DEAD, "the mouse is alive again")

/// Suspension (absorbed prey, bodies kept for reforming) runs no frame until resumed.
/datum/unit_test/life_om/suspension

/datum/unit_test/life_om/suspension/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	life_test_add(H, /datum/life_test_step/counter)
	life_test_advance(LIFE_CYCLE_SECONDS)
	om_suspend(H, H)
	TEST_ASSERT(om_value_of(H, EFFECT_SUSPENDED), "suspended")
	var/before = life_test_frames(H)
	life_test_advance(LIFE_CYCLE_SECONDS * 5)
	TEST_ASSERT_EQUAL(life_test_frames(H), before, "a suspended mob runs no frame")
	om_unsuspend(H, H)
	life_test_advance(LIFE_CYCLE_SECONDS * 2)
	TEST_ASSERT(life_test_frames(H) > before, "a resumed mob runs again")

/// Relevance replaces the per-frame z-level test: a low-priority mob on a z-level without living players leaves the
/// sweep; one that isn't low priority holds its own relevance.
/datum/unit_test/life_om/relevance_parks_low_priority

/datum/unit_test/life_om/relevance_parks_low_priority/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	life_test_add(H, /datum/life_test_step/counter)
	TEST_ASSERT_EQUAL(om_relevance(H), RELEVANCE_NEAR, "a mob that isn't low priority keeps itself relevant")
	H.set_low_priority(TRUE)
	var/z = get_z(H)
	var/datum/life_z_presence/P = life_z_presence(z)
	TEST_ASSERT(H in P.members, "its z-level's presence lists it")
	if(P.occupied)
		TEST_NOTICE(src, "the test z-level has a living player; relevance by presence not checked")
		H.set_low_priority(FALSE)
		return
	TEST_ASSERT_EQUAL(om_relevance(H), RELEVANCE_NONE, "a low-priority mob on a z-level without players is not relevant")
	life_test_advance(LIFE_CYCLE_SECONDS)
	var/before = life_test_frames(H)
	life_test_advance(LIFE_CYCLE_SECONDS * 3)
	TEST_ASSERT_EQUAL(life_test_frames(H), before, "and runs no frame, with nothing tested per frame")
	GLOB.living_players_by_zlevel[z] += H
	defer_cleanup(null, GLOBAL_PROC_REF(life_test_drop_living_player), z, H)
	life_z_occupancy_changed(z)
	TEST_ASSERT_EQUAL(om_relevance(H), RELEVANCE_NEAR, "a living player arriving makes the z-level's low-priority mobs relevant")
	life_test_advance(LIFE_CYCLE_SECONDS * 2)
	TEST_ASSERT(life_test_frames(H) > before, "so they run again")
	life_test_drop_living_player(z, H)
	TEST_ASSERT_EQUAL(om_relevance(H), RELEVANCE_NONE, "and the last one leaving takes them out of the sweep")
	H.set_low_priority(FALSE)
	TEST_ASSERT(!(H in P.members), "a mob that isn't low priority leaves the presence")

/// Stasis slows biology, not the frame: deep stasis (0.9) runs biology one frame in ten, total stasis never; the frame
/// itself keeps running.
/datum/unit_test/life_om/stasis_clock

/datum/unit_test/life_om/stasis_clock/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.set_stasis(/datum/body_effect/stasis/deep, src)
	TEST_ASSERT(abs(om_clock_rate_of(H, CLOCK_BIO) - 0.1) < 0.001, "deep stasis holds the biology clock at 0.1, got [om_clock_rate_of(H, CLOCK_BIO)]")
	var/biology = 0
	var/frames_before = life_test_frames(H)
	for(var/i in 1 to 20)
		seq_run_frame_now(H, LIFE_SEQ)
		if(!H.body.stasis_paused)
			biology++
	TEST_ASSERT_EQUAL(biology, 2, "deep stasis runs biology on 2 frames in 20")
	TEST_ASSERT_EQUAL(life_test_frames(H), frames_before + 20, "the frame itself keeps running in stasis")
	H.set_stasis(/datum/body_effect/stasis/total, src)
	TEST_ASSERT_EQUAL(om_clock_rate_of(H, CLOCK_BIO), 0, "total stasis stops the biology clock")
	biology = 0
	for(var/i in 1 to 10)
		seq_run_frame_now(H, LIFE_SEQ)
		if(!H.body.stasis_paused)
			biology++
	TEST_ASSERT_EQUAL(biology, 0, "total stasis never runs biology")
	H.set_stasis(null, src)
	TEST_ASSERT_EQUAL(om_clock_rate_of(H, CLOCK_BIO), 1, "leaving stasis restores the clock")
	seq_run_frame_now(H, LIFE_SEQ)
	TEST_ASSERT(!H.body.stasis_paused, "biology runs every frame again")

/// Stun, weaken and paralysis are timed statuses: durations in LIFE_CYCLE units, exact set and adjust semantics, and
/// canmove follows at once.
/datum/unit_test/life_om/statuses_are_contributions

/datum/unit_test/life_om/statuses_are_contributions/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	// Statuses end in real time on their own: no frame is needed (or wanted: a test human's own frames can knock it
	// out and hide canmove).
	om_suspend(H, H)
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(H.has_status(EFFECT_STUNNED), "status_at_least() applies EFFECT_STUNNED")
	TEST_ASSERT(om_has(H, EFFECT_STUNNED), "as a contribution")
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_STUNNED), 2, "two units left")
	TEST_ASSERT_EQUAL(H.status_remaining(EFFECT_STUNNED), 2 * LIFE_CYCLE, "status_remaining() reads the time left")
	TEST_ASSERT(!H.canmove, "canmove follows the stun at once, without a frame")
	TEST_ASSERT(!om_value_of(H, EFFECT_CAN_MOVE), "EFFECT_CAN_MOVE reads it")
	H.status_at_least(EFFECT_STUNNED, 1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_STUNNED), 2, "status_at_least() never shortens")
	life_test_advance(LIFE_CYCLE_SECONDS + 0.1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_STUNNED), 1, "one unit per LIFE_CYCLE of real time")
	life_test_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "the stun ends on its own")
	TEST_ASSERT(H.canmove, "canmove comes back when it ends (stat [H.stat], sleeping [H.has_status(EFFECT_SLEEPING)], lying [H.lying], resting [H.resting], paralysed [H.has_status(EFFECT_PARALYZED)], weakened [H.has_status(EFFECT_WEAKENED)], buckled [H?.buckled_to()])")

	H.status_at_least(EFFECT_WEAKENED, 5)
	H.status_set(EFFECT_WEAKENED, 1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_WEAKENED), 1, "status_set() sets the remaining duration")
	H.status_adjust(EFFECT_WEAKENED, 2)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_WEAKENED), 3, "status_adjust() adds to it")
	H.status_adjust(EFFECT_WEAKENED, -10)
	TEST_ASSERT(!H.has_status(EFFECT_WEAKENED), "adjusting below zero ends it")
	H.status_at_least(EFFECT_PARALYZED, 3)
	H.status_set(EFFECT_PARALYZED, 0)
	TEST_ASSERT(!H.has_status(EFFECT_PARALYZED), "status_set(0) ends it")

/// canmove is a reaction: a status change derives it at the drain, with no Life frame. A clientless mob's HUD
/// reaction queues nothing (its `when` gate).
/datum/unit_test/life_om/derive_and_present

/datum/unit_test/life_om/derive_and_present/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/frames = life_test_frames(H)
	H.status_set(EFFECT_SLEEPING, 2)
	H.canmove = TRUE
	life_test_raise(H, CHANGE_MOB_STATUS)
	TEST_ASSERT(!life_test_rx_queued(H, TYPE_PROC_REF(/mob/living, life_hud_changed)), "a clientless mob queues no HUD pass")
	TEST_ASSERT(life_test_rx_queued(H, TYPE_PROC_REF(/mob/living, life_canmove_changed)), "the canmove reaction is queued")
	rx_drain()
	TEST_ASSERT(!H.canmove, "a status change ran the canmove derivation without a frame")
	TEST_ASSERT_EQUAL(life_test_frames(H), frames, "no life frame ran for it")
	H.status_set(EFFECT_SLEEPING, 0)

/// A human whose HUD gate and HUD pass the tests control (no client is possible in a test).
/mob/living/carbon/human/dq_test_hud_probe
	var/pretend_client = FALSE
	var/hud_runs = 0

/mob/living/carbon/human/dq_test_hud_probe/life_hud_wanted()
	return pretend_client

/mob/living/carbon/human/dq_test_hud_probe/life_hud()
	hud_runs++
	return ..()

/// The HUD reaction's `when` is the has_client gate: without one a HUD channel queues nothing and nothing runs; with
/// one the next drain draws it.
/datum/unit_test/life_om/hud_gate_has_client

/datum/unit_test/life_om/hud_gate_has_client/run_life()
	var/mob/living/carbon/human/dq_test_hud_probe/H = allocate(/mob/living/carbon/human/dq_test_hud_probe)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	rx_drain()
	H.hud_runs = 0
	for(var/channel in list(CHANGE_MOB_LOC, CHANGE_MOB_HEALTH, CHANGE_MOB_EQUIPMENT, CHANGE_MOB_STATUS))
		life_test_raise(H, channel)
	TEST_ASSERT(!life_test_rx_queued(H, TYPE_PROC_REF(/mob/living, life_hud_changed)), "no client: nothing is queued")
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 0, "and no HUD pass runs")
	H.pretend_client = TRUE
	life_test_raise(H, CHANGE_MOB_CLIENT)
	TEST_ASSERT(life_test_rx_queued(H, TYPE_PROC_REF(/mob/living, life_hud_changed)), "a client logging in queues the HUD")
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 1, "which draws once")

/// on_change(at_most = LIFE_PRESENT_MIN_INTERVAL): a walking player raises a location change most ticks; the HUD draws
/// once, then the changes inside the window are held and drawn once when it ends.
/datum/unit_test/life_om/hud_at_most_coalesces

/datum/unit_test/life_om/hud_at_most_coalesces/run_life()
	var/mob/living/carbon/human/dq_test_hud_probe/H = allocate(/mob/living/carbon/human/dq_test_hud_probe)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.pretend_client = TRUE
	rx_drain()
	life_test_advance(LIFE_PRESENT_MIN_INTERVAL / 10 + 0.1)
	rx_drain()
	H.hud_runs = 0
	life_test_raise(H, CHANGE_MOB_LOC)
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 1, "the first change draws at the drain")
	for(var/i in 1 to 4)
		life_test_raise(H, CHANGE_MOB_LOC)
		life_test_raise(H, CHANGE_MOB_HEALTH)
		rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 1, "changes inside the window are held")
	life_test_advance(LIFE_PRESENT_MIN_INTERVAL / 10 + 0.1)
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 2, "and drawn once when it ends")
	life_test_advance(LIFE_PRESENT_MIN_INTERVAL / 10 + 0.1)
	rx_drain()
	TEST_ASSERT_EQUAL(H.hud_runs, 2, "nothing more was held")

/// Ghosts, AI eyes and the blob overmind run their upkeep on their own behaviour.
/datum/unit_test/life_om/observer_upkeep

/datum/unit_test/life_om/observer_upkeep/run_life()
	var/mob/observer/dead/life_test/G = allocate(/mob/observer/dead/life_test)
	TEST_ASSERT(om_attached(G, /datum/om/behaviour/observer_upkeep), "observers carry the upkeep behaviour")
	life_test_advance(OBSERVER_UPKEEP_INTERVAL / 10 * 3)
	TEST_ASSERT(G.upkeeps >= 2, "observer upkeep runs on its cadence, ran [G.upkeeps]")

/// The step profiler samples by a sequence-wide frame counter, so every mob is sampled at the same rate (Codex bug:
/// sampling bias from a run list that restarted each cycle), and a sampled frame records the steps it ran.
/datum/unit_test/life_om/profiler_is_uniform

/datum/unit_test/life_om/profiler_is_uniform/run_life()
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(A) && life_test_place(B), "no floor to place the test humans on")
	var/datum/sequence/seq = sequence_def(LIFE_SEQ)
	var/stride = seq.profile_stride
	if(!stride)
		TEST_NOTICE(src, "built without the step profiler (OM_NO_STAGE_PROFILE)")
		return
	life_test_add(A, /datum/life_test_step/counter)
	life_test_add(B, /datum/life_test_step/counter)
	seq_run_frame_now(A, LIFE_SEQ)
	var/slot = seq.slot_of["life_test_counter"]
	TEST_ASSERT(slot, "the counter step has a cost slot")
	var/frames_before = seq_frames(list(A, B), LIFE_SEQ)
	var/calls_before = seq.step_calls[slot]
	for(var/i in 1 to stride * 2)
		seq_wake(A, LIFE_SEQ)
		seq_wake(B, LIFE_SEQ)
		seq_run_frame_now(A, LIFE_SEQ)
		seq_run_frame_now(B, LIFE_SEQ)
	var/frames = seq_frames(list(A, B), LIFE_SEQ) - frames_before
	var/sampled = (seq.step_calls[slot] - calls_before) / stride
	TEST_ASSERT_EQUAL(frames, stride * 4, "every frame counted")
	TEST_ASSERT(abs(sampled - frames / stride) <= 1, "one frame in [stride] is sampled: [sampled] of [frames]")

// --- Producers and the audit -----------------------------------------------------------------

/// A reagent entering a parked mob wakes it.
/datum/unit_test/life_om/reagent_wakes

/datum/unit_test/life_om/reagent_wakes/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	if(!M.reagents)
		M.create_reagents(30)
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	M.reagents.add_reagent(REAGENT_ID_WATER, 5)
	life_test_advance(0.1)
	TEST_ASSERT(!life_test_parked(M), "adding a reagent should wake a parked mob")

/// A stun wakes the mob; once it wears off the mob parks again.
/datum/unit_test/life_om/stun_wakes_then_parks

/datum/unit_test/life_om/stun_wakes_then_parks/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	M.status_at_least(EFFECT_STUNNED, 3)
	TEST_ASSERT_EQUAL(M.status_units(EFFECT_STUNNED), 3, "the stun should land")
	TEST_ASSERT(!life_test_parked(M), "a stun should wake a parked mob")
	life_test_advance(LIFE_CYCLE_SECONDS * 3 + 1)
	TEST_ASSERT_EQUAL(M.status_units(EFFECT_STUNNED), 0, "the stun should have worn off")
	life_test_advance(LIFE_CYCLE_SECONDS * 4)
	TEST_ASSERT(life_test_parked(M), "the mouse should park again once the stun wears off; still busy: [life_test_busy(M)]")

/// A client logging in wakes the whole mob.
/datum/unit_test/life_om/client_login_wakes

/datum/unit_test/life_om/client_login_wakes/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	// /mob/living/Login() calls this hook; a unit test has no client to log in with.
	M.on_client_changed("login")
	TEST_ASSERT(!life_test_parked(M), "a login should wake a parked mob")
	TEST_ASSERT(!life_test_state(M).asleep, "a login wakes every step (CHANGE_MOB_CLIENT is one of the sequence's wake_all channels)")

/// The missed-wake audit finds a change made without raising its channel, logs it and wakes the mob.
/datum/unit_test/life_om/audit_catches_missed_wake

/datum/unit_test/life_om/audit_catches_missed_wake/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	var/datum/sequence/seq = sequence_def(LIFE_SEQ)
	TEST_ASSERT_NULL(seq.missed_wake(M), "the audit must not flag a mob that is correctly parked")
	// A deliberately missed wake: write state a sleeping step reads (healing ears) without raising a channel.
	// Bypasses set_ear_damage() on purpose, by name, since every direct write to a declared field is linted
	// (field_write); this is the one write that must not raise.
	M.vars["ear_damage"] = 50
	TEST_ASSERT(life_test_parked(M), "a direct write must not wake the mob (that is the bug the audit catches)")
	var/missed_before = seq.missed
	seq_audit(400, 0, TRUE)
	TEST_ASSERT_EQUAL(seq.missed, missed_before + 1, "the audit should count the missed wake")
	TEST_ASSERT(!life_test_parked(M), "the audit should wake the mob")
	M.set_ear_damage(0)

// --- Statuses, immunity and the frame's own changes (doc/rewrite/archive/life_on_om.md §7) ---------------------------

/// Every former counter is a timed status: it ends by deadline, in its own units per cycle, with no frame running;
/// the magnitude statuses read back in points.
/datum/unit_test/life_om/statuses_expire_by_deadline

/datum/unit_test/life_om/statuses_expire_by_deadline/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_suspend(H, H)
	var/frames_before = life_test_frames(H)
	var/list/one_per_cycle = list(EFFECT_CONFUSED, EFFECT_BLINDED, EFFECT_BLURRY, EFFECT_DEAFENED, EFFECT_STUTTERING, EFFECT_MUTED, EFFECT_DRUGGED, EFFECT_SLURRING, EFFECT_DROWSY)
	for(var/id in one_per_cycle)
		H.status_at_least(id, 2)
		TEST_ASSERT_EQUAL(H.status_units(id), 2, "[id]: two units after status_at_least(2)")
	life_test_advance(LIFE_CYCLE_SECONDS + 0.1)
	for(var/id in one_per_cycle)
		TEST_ASSERT_EQUAL(H.status_units(id), 1, "[id]: one unit wears off per cycle")
	life_test_advance(LIFE_CYCLE_SECONDS)
	for(var/id in one_per_cycle)
		TEST_ASSERT(!H.has_status(id), "[id]: ends on its own after two cycles")
	TEST_ASSERT_EQUAL(life_test_frames(H), frames_before, "no frame ran: nothing counts statuses down")

	// Hallucination wore off two points per cycle.
	H.status_at_least(EFFECT_HALLUCINATING, 10)
	life_test_advance(LIFE_CYCLE_SECONDS * 2 + 0.1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_HALLUCINATING), 6, "hallucination: 2 points per cycle")

	// Dizziness: 3 points per cycle, 15 while resting, capped at 1000.
	H.status_adjust(EFFECT_DIZZY, 5000)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 1000, "dizziness is capped at 1000 points")
	TEST_ASSERT(om_attached(H, /datum/om/behaviour/dizzy_shake), "the shake follows the status (its on_start hook)")
	H.status_set(EFFECT_DIZZY, 30)
	life_test_advance(LIFE_CYCLE_SECONDS + 0.1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 27, "dizziness: 3 points per cycle")
	H.set_resting(TRUE)
	H.status_rate_check(EFFECT_DIZZY)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 27, "a rate change keeps the points left")
	life_test_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 12, "dizziness: 15 points per cycle while resting")
	H.set_resting(FALSE)
	H.status_end(EFFECT_DIZZY)
	TEST_ASSERT(!om_attached(H, /datum/om/behaviour/dizzy_shake), "the shake ends with the status (its on_end hook)")

	// Alerts follow the status, with no step maintaining them.
	H.status_at_least(EFFECT_CONFUSED, 1)
	TEST_ASSERT(H.alerts?["confused"], "the confused alert starts with the status")
	life_test_advance(LIFE_CYCLE_SECONDS + 0.1)
	TEST_ASSERT(!H.alerts?["confused"], "and ends with it")

/// Immunity is an effect: it blocks the statuses that name it, gaining it ends them, and every source holds its own
/// (mob type declarations, mutations, godmode).
/datum/unit_test/life_om/status_immunity

/datum/unit_test/life_om/status_immunity/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_suspend(H, H)
	var/datum/source = new /datum
	om_hold(H, EFFECT_IMMUNE_STUN, source)
	TEST_ASSERT(H.status_immune(EFFECT_STUNNED), "the immunity is held")
	H.status_at_least(EFFECT_STUNNED, 3)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "an immune mob can't be stunned")
	H.status_at_least(EFFECT_WEAKENED, 3)
	TEST_ASSERT(H.has_status(EFFECT_WEAKENED), "stun immunity doesn't block weakness")
	om_release(H, EFFECT_IMMUNE_STUN, source)
	H.status_at_least(EFFECT_STUNNED, 3)
	TEST_ASSERT(H.has_status(EFFECT_STUNNED), "without the immunity the stun lands")
	om_hold(H, EFFECT_IMMUNE_STUN, source)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "gaining the immunity ends an active stun")
	qdel(source)
	TEST_ASSERT(!H.status_immune(EFFECT_STUNNED), "the immunity dies with its source")

	// Mutations: the hulk can't be stunned, weakened or paralysed.
	H.add_mutation(HULK)
	TEST_ASSERT(!H.has_status(EFFECT_WEAKENED), "becoming a hulk ends weakness")
	H.status_at_least(EFFECT_PARALYZED, 2)
	TEST_ASSERT(!H.has_status(EFFECT_PARALYZED), "a hulk can't be paralysed")
	H.remove_mutation(HULK)
	H.status_at_least(EFFECT_PARALYZED, 2)
	TEST_ASSERT(H.has_status(EFFECT_PARALYZED), "losing the mutation loses the immunity")
	H.status_end(EFFECT_PARALYZED)

	// Godmode is an effect implying all three; removing it releases only its own.
	var/datum/other = new /datum
	om_hold(H, EFFECT_IMMUNE_WEAKEN, other)
	H.enable_godmode()
	TEST_ASSERT(om_has(H, EFFECT_GODMODE), "the godmode element holds EFFECT_GODMODE")
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "godmode blocks stuns")
	H.disable_godmode()
	TEST_ASSERT(!om_has(H, EFFECT_GODMODE), "removing the element ends godmode")
	TEST_ASSERT(!H.status_immune(EFFECT_STUNNED), "ending godmode ends its stun immunity")
	TEST_ASSERT(H.status_immune(EFFECT_WEAKENED), "but not another source's immunity (the old flags were cleared wholesale)")
	qdel(other)

	// Mob types declare theirs (one multi-type decl for the natural immunes).
	var/mob/living/simple_mob/animal/sif/leech/leech = allocate(/mob/living/simple_mob/animal/sif/leech)
	TEST_ASSERT(leech.status_immune(EFFECT_STUNNED) && leech.status_immune(EFFECT_WEAKENED) && leech.status_immune(EFFECT_PARALYZED), "leeches are immune to incapacitation by declaration")
	leech.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(!leech.has_status(EFFECT_STUNNED), "so a stun doesn't land")
	TEST_ASSERT(EFFECT_IMMUNE_STUN in om_registry().type_table(/mob/living/simple_mob/vore/morph).self_effects, "the last type of the multi-type decl gets it too")
	var/list/ai_table = om_registry().type_table(/mob/living/silicon/ai).self_effects
	TEST_ASSERT((EFFECT_IMMUNE_WEAKEN in ai_table) && !(EFFECT_IMMUNE_STUN in ai_table), "the AI can be stunned but not knocked down")
	TEST_ASSERT(EFFECT_IMMUNE_DIZZY in om_registry().type_table(/mob/living/silicon/robot).self_effects, "silicons don't get dizzy")

/// Godmode is an effect: code asks om_has(EFFECT_GODMODE), and harm is cancelled.
/datum/unit_test/life_om/godmode_effect

/datum/unit_test/life_om/godmode_effect/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_suspend(H, H)
	TEST_ASSERT(!om_has(H, EFFECT_GODMODE), "no godmode by default")
	H.enable_godmode()
	TEST_ASSERT(om_has(H, EFFECT_GODMODE), "the element holds the effect")
	TEST_ASSERT(om_has(H, EFFECT_IMMUNE_PARALYZE), "godmode implies the incapacitation immunities")
	TEST_ASSERT_EQUAL(H.injure(INJURY_BLUNT, 20), 0, "injure() lands nothing in godmode")
	H.disable_godmode()
	TEST_ASSERT(!om_has(H, EFFECT_IMMUNE_PARALYZE), "the implied immunities end with it")
	TEST_ASSERT(H.injure(INJURY_BLUNT, 1) > 0, "and harm lands again")

/// Voluntary sleep is a hold: no dose wearing off or ending wakes the mob; choosing to wake does. A hold has no
/// duration: status_units() and status_remaining() read the timed doses only.
/datum/unit_test/life_om/voluntary_sleep

/datum/unit_test/life_om/voluntary_sleep/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_suspend(H, H)
	H.set_voluntary_sleep(TRUE)
	TEST_ASSERT(H.sleeping_voluntarily(), "sleeping by choice")
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "the hold is the sleep status")
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_SLEEPING), 0, "a hold has no units (no hidden floor)")
	TEST_ASSERT_EQUAL(H.status_remaining(EFFECT_SLEEPING), 0, "nor a remaining time")
	H.status_at_least(EFFECT_SLEEPING, 1)
	life_test_advance(LIFE_CYCLE_SECONDS * 3)
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "a dose wearing off doesn't wake a voluntary sleeper")
	H.status_set(EFFECT_SLEEPING, 0)
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "nor does ending the dose")
	H.set_voluntary_sleep(FALSE)
	TEST_ASSERT(!H.has_status(EFFECT_SLEEPING), "choosing to wake ends it")
	TEST_ASSERT(!H.alerts?["asleep"], "and its alert")

/// A status change raises CHANGE_MOB_STATUS once, and a change that doesn't change the value raises nothing.
/datum/unit_test/life_om/status_raises_once

/datum/unit_test/life_om/status_raises_once/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_suspend(H, H)
	sched.test_raises = list()
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT_EQUAL(life_test_status_raises(sched, H), 1, "starting a stun raises the status channel once")
	H.status_at_least(EFFECT_SLURRING, 3)
	sched.test_raises = list()
	H.status_at_least(EFFECT_STUNNED, 4)
	H.status_adjust(EFFECT_STUNNED, -1)
	H.status_at_least(EFFECT_SLURRING, 5)
	H.status_at_least(EFFECT_STUNNED, 1)
	TEST_ASSERT_EQUAL(life_test_status_raises(sched, H), 0, "extending or shortening an active status raises nothing")
	H.status_set(EFFECT_STUNNED, 0)
	TEST_ASSERT_EQUAL(life_test_status_raises(sched, H), 1, "ending it raises once")
	sched.test_raises = null

/// Life never wakes itself: a frame on a mob with running statuses raises no status change, so a sleeping mouse
/// parks like an idle one.
/datum/unit_test/life_om/no_self_wake

/datum/unit_test/life_om/no_self_wake/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	M.status_set(EFFECT_SLEEPING, 100)
	M.status_at_least(EFFECT_CONFUSED, 100)
	sched.run_pass(1e9)
	sched.test_raises = list()
	seq_run_frame_now(M, LIFE_SEQ)
	TEST_ASSERT_EQUAL(life_test_status_raises(sched, M), 0, "a frame raises no status change on its own mob")
	sched.test_raises = null
	TEST_ASSERT(life_test_settle(M), "a sleeping, confused mouse parks; still busy: [life_test_busy(M)]")
	TEST_ASSERT(M.has_status(EFFECT_SLEEPING), "and stays asleep while parked")

/// Parking hysteresis: a mob parks only after LIFE_PARK_AFTER frames in a row end with every step asleep; a wake in
/// between starts the count again.
/datum/unit_test/life_om/park_hysteresis

/datum/unit_test/life_om/park_hysteresis/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	var/datum/seq_state/S = life_test_state(M)
	changed(M, CHANGE_EXPLICIT)
	TEST_ASSERT(!life_test_parked(M), "a change wakes it")
	var/frames = 0
	while(S.asleep < S.table.n && frames < 6)
		seq_run_frame_now(M, LIFE_SEQ)
		sched.run_pass(1e9)
		frames++
	TEST_ASSERT(S.asleep >= S.table.n, "its steps sleep again; still busy: [life_test_busy(M)]")
	TEST_ASSERT(!life_test_parked(M), "one idle frame doesn't park it")
	TEST_ASSERT_EQUAL(S.idle_frames, 1, "one idle frame counted")
	seq_run_frame_now(M, LIFE_SEQ)
	TEST_ASSERT(life_test_parked(M), "it parks after [LIFE_PARK_AFTER] idle frames in a row")

/// Clientless mobs get correct sight flags: the vision reaction runs for every mob when an input changes (a mutation,
/// stat), not per frame and not on movement.
/datum/unit_test/life_om/npc_vision_follows_inputs

/datum/unit_test/life_om/npc_vision_follows_inputs/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT(!H.client, "a clientless mob")
	TEST_ASSERT(H.life_vision_wanted(), "vision runs for clientless mobs too")
	sched.run_pass(1e9)
	TEST_ASSERT(!(H.sight & SEE_MOBS), "no x-ray sight to begin with")
	H.add_mutation(XRAY)
	life_test_advance(1)
	TEST_ASSERT(H.sight & SEE_MOBS, "gaining the x-ray mutation gives an NPC x-ray sight, with no frame and no client")
	TEST_ASSERT_EQUAL(H.see_in_dark, 8, "and darksight")
	// A sentinel the vision pass would overwrite: walking must leave it alone.
	H.see_in_dark = 77
	for(var/i in 1 to 5)
		H.forceMove(get_step(H, pick(GLOB.cardinal)) || H.loc)
		sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(H.see_in_dark, 77, "walking around doesn't recompute sight")
	H.see_in_dark = 8
	H.remove_mutation(XRAY)
	life_test_advance(1)
	TEST_ASSERT(!(H.sight & SEE_MOBS), "losing the mutation takes it away")
	H.death()
	life_test_advance(1)
	TEST_ASSERT(H.sight & SEE_TURFS, "the dead see everything (stat raises the vision channel)")

/// Relevance follows every loc change: nullspace, forceMove, and moves inside containers.
/datum/unit_test/life_om/relevance_follows_loc

/datum/unit_test/life_om/relevance_follows_loc/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/turf/T = H.loc
	H.set_low_priority(TRUE)
	TEST_ASSERT_EQUAL(H.life_z, T.z, "a low-priority mob joins its z-level's presence")
	H.moveToNullspace()
	TEST_ASSERT_EQUAL(H.life_z, 0, "nullspace leaves it")
	TEST_ASSERT(!(H in life_z_presence(T.z).members), "and the presence forgets it")
	H.forceMove(T)
	TEST_ASSERT_EQUAL(H.life_z, T.z, "forceMove() back joins again")
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	H.forceMove(C)
	TEST_ASSERT_EQUAL(H.life_z, T.z, "inside a container on the same z-level it stays")
	H.forceMove(T)
	H.set_low_priority(FALSE)
	TEST_ASSERT_EQUAL(H.life_z, 0, "a mob that isn't low priority keeps its own relevance")

/// Changes to `E` logged on `sched.test_raises` that carry CHANGE_MOB_STATUS.
/proc/life_test_status_raises(datum/om/scheduler/sched, datum/E)
	. = 0
	for(var/list/entry as anything in sched.test_raises)
		if(entry[1] == E && (entry[2] & CHANGE_MOB_STATUS))
			.++

// --- Human sleep rules ------------------------------------------------------------------------------------------------

/// A healthy, placed human's event-driven steps have nothing to do: they sleep after a frame until their reads or
/// rewakes.
/datum/unit_test/life_om/human_idle_rules

/datum/unit_test/life_om/human_idle_rules/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	seq_run_frame_now(H, LIFE_SEQ)
	for(var/key in list("life_germs", "life_fall", "life_pulse", "life_stasis_sleep"))
		TEST_ASSERT(key in life_test_steps(H), "a human's table has [key]")
		TEST_ASSERT(life_test_asleep(H, key), "[key] should sleep on a healthy human")

/// Germ creep is charged for the biological time since the last roll, so sleeping between rolls loses nothing; stasis
/// (a stopped biology clock) charges nothing.
/datum/unit_test/life_om/germs_catch_up_on_bio_time

/datum/unit_test/life_om/germs_catch_up_on_bio_time/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.germ_level = 0
	H.germs_rolled_at = om_clock_now(H, CLOCK_BIO) - 20 * LIFE_CYCLE
	H.life_germs()
	TEST_ASSERT(H.germ_level >= 5 && H.germ_level <= 7, "20 cycles at 30% should give 6 germs, gave [H.germ_level]")
	var/datum/stasis_source = new
	om_hold(H, EFFECT_CLOCK_BIO_INHIBIT, stasis_source, 1)
	var/level = H.germ_level
	life_test_advance(LIFE_CYCLE_SECONDS * 20)
	H.life_germs()
	TEST_ASSERT(H.germ_level - level <= 1, "a stopped biology clock charges at most the one roll, gained [H.germ_level - level]")
	qdel(stasis_source)

#undef LIFE_SEQ

#endif

/// Takes a test mob back out of its z-level's living players (a no-op once it has left).
/proc/life_test_drop_living_player(z, mob/living/H)
	if(!(H in GLOB.living_players_by_zlevel[z]))
		return
	GLOB.living_players_by_zlevel[z] -= H
	life_z_occupancy_changed(z)

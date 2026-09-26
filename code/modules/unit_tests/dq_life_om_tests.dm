// Mob Life on object-model pipelines (doc/rewrite/life_on_om.md): content (families, variants,
// plans, facts) and the scheduling the core pipeline runner owns for Life: cadence and catch-up,
// idle and wake by channel, parking, rewakes, suspension, relevance, stasis on the biology clock,
// statuses as contributions, the derive and present pipelines, and one test per bug the Codex
// prototype had.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Runs one breath's gas exchange for a human through its breathing stage.
/proc/life_test_breath(mob/living/carbon/human/H, datum/gas_mixture/breath)
	var/datum/om/stage/life/breathing/carbon/breathing = om_stage_for(H, /datum/om/stage/life/breathing)
	breathing.exchange(H, breath)

/// Takes one breath (source, exchange, exhale) through a carbon's breathing stage.
/proc/life_test_breathe(mob/living/carbon/C)
	var/datum/om/stage/life/breathing/carbon/breathing = om_stage_for(C, /datum/om/stage/life/breathing)
	breathing.breathe(C)

/// Runs a human's environment exchange (heat and pressure) against a gas mixture.
/proc/life_test_environment(mob/living/carbon/human/H, datum/gas_mixture/environment)
	var/datum/om/stage/life/environment/environment_stage = om_stage_for(H, /datum/om/stage/life/environment)
	environment_stage.exchange(H, environment)

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

/// `L`'s state in pipeline `P`.
/proc/life_test_pipe(mob/living/L, P = /datum/om/pipeline/life)
	RETURN_TYPE(/datum/om/frame)
	return om_pipe_state(L, P, TRUE)

/// The types of `L`'s plan in pipeline `P`, in run order.
/proc/life_test_stage_types(mob/living/L, P = /datum/om/pipeline/life)
	. = list()
	for(var/datum/om/stage/T as anything in life_test_pipe(L, P).plan.stages)
		. += T.type

/// Frames the life pipeline ran on `L`.
/proc/life_test_frames(mob/living/L)
	return life_test_pipe(L).frames

/proc/life_test_parked(mob/living/L)
	return om_pipe_parked(L, /datum/om/pipeline/life)

/// TRUE when every type in `expected` appears in `actual`, in the same relative order.
/proc/life_test_in_order(list/actual, list/expected)
	var/last = 0
	for(var/path in expected)
		var/index = actual.Find(path)
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

/// Runs frames until the mob parks, at most `frames` times. Returns TRUE if it did. On a test
/// scheduler, each frame is followed by a pass so the changes it raised are delivered before the
/// next frame, as they are live.
/proc/life_test_settle(mob/living/L, frames = 6)
	var/datum/om/scheduler/sched = om_scheduler()
	for(var/i in 1 to frames)
		if(life_test_parked(L))
			return TRUE
		om_run_frame_now(L, /datum/om/pipeline/life)
		if(!isnull(sched.manual_time))
			sched.run_pass(1e9)
	return life_test_parked(L)

/// Names of the stages that would keep this mob awake, for failure messages.
/proc/life_test_busy(mob/living/L)
	var/list/names = list()
	for(var/datum/om/stage/T as anything in life_test_pipe(L).plan.stages)
		if(!T.idle(L))
			names += "[T.type]"
	return jointext(names, ", ")

/// TRUE when stage family `stage_type` is idle on `L`.
/proc/life_test_idle(mob/living/L, stage_type)
	return om_stage_idle(L, /datum/om/pipeline/life, stage_type)

/// Sets stage family `stage_type` idle on `L` (tests only: a real idle comes from its rule).
/proc/life_test_set_idle(mob/living/L, stage_type)
	var/datum/om/frame/S = life_test_pipe(L)
	var/i = om_plan_position(S, stage_type)
	if(i && !(S.bits[OM_PIPE_WORD(i)] & OM_PIPE_BIT(i)))
		S.bits[OM_PIPE_WORD(i)] |= OM_PIPE_BIT(i)
		S.asleep++

/// The rewake sub-key of stage `stage_type` in its pipeline.
/proc/life_test_rewake_key(stage_type)
	var/datum/om/stage/T = om_registry().stage_by_type[stage_type]
	return OM_DL_STAGE - 1 + T.pos

/// TRUE when behaviour `B` is started on `E` (attached, requirements met, not suspended).
/proc/life_test_started(datum/E, B)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return FALSE
	var/i = rec.att.Find(om_registry().behaviour(B))
	return i && (rec.att_state[i] & OM_ATT_STARTED)

// --- Test-only extra stages (added per mob with om_stage_add(); never in a plan otherwise) --------

/datum/om/stage/life/trait/test_counter
	order = LIFE_PHASE_TAIL + 900
	name = "test counter"
	/// Runs of this stage, per mob.
	var/list/runs = list()
	/// dt of the last frame it ran in.
	var/last_dt = 0

/datum/om/stage/life/trait/test_counter/perform(mob/living/self, datum/om/frame/life/ctx)
	runs["[REF(self)]"] = (runs["[REF(self)]"] || 0) + 1
	last_dt = ctx.dt

/// Idle after every run, with a rewake.
/datum/om/stage/life/trait/test_timer
	order = LIFE_PHASE_TAIL + 901
	name = "test timer"
	var/list/runs = list()

/datum/om/stage/life/trait/test_timer/perform(mob/living/self, datum/om/frame/life/ctx)
	runs["[REF(self)]"] = (runs["[REF(self)]"] || 0) + 1

/datum/om/stage/life/trait/test_timer/idle(mob/living/self)
	return TRUE

/datum/om/stage/life/trait/test_timer/rewake_delay(mob/living/self)
	return 3 SECONDS

/// Raises a health change on its mob during the frame.
/datum/om/stage/life/trait/test_raiser
	order = LIFE_PHASE_INPUT + 1
	name = "test raiser"

/datum/om/stage/life/trait/test_raiser/perform(mob/living/self, datum/om/frame/life/ctx)
	om_changed(self, CHANGE_MOB_HEALTH)

/datum/om/stage/life/trait/test_raiser/idle(mob/living/self)
	return TRUE

/// Idles after every run; wakes on health changes only.
/datum/om/stage/life/trait/test_sleeper
	order = LIFE_PHASE_TAIL + 902
	name = "test sleeper"
	wake_on = CHANGE_MOB_HEALTH
	var/list/runs = list()

/datum/om/stage/life/trait/test_sleeper/perform(mob/living/self, datum/om/frame/life/ctx)
	runs["[REF(self)]"] = (runs["[REF(self)]"] || 0) + 1

/datum/om/stage/life/trait/test_sleeper/idle(mob/living/self)
	return TRUE

/// Deletes its mob during the frame.
/datum/om/stage/life/trait/test_deleter
	order = LIFE_PHASE_TAIL + 899
	name = "test deleter"

/datum/om/stage/life/trait/test_deleter/perform(mob/living/self, datum/om/frame/life/ctx)
	qdel(self)

/// A ghost that counts its upkeep runs.
/mob/observer/dead/life_test
	var/upkeeps = 0

/mob/observer/dead/life_test/upkeep()
	upkeeps++
	return ..()

// --- Base: every scheduling test runs on its own test scheduler -----------------------------------

/datum/unit_test/life_om
	abstract_type = /datum/unit_test/life_om
	var/datum/om/scheduler/sched

/datum/unit_test/life_om/Run()
	sched = om_test_begin()
	try
		run_life()
	catch(var/exception/e)
		TEST_FAIL("runtime in life test: [e] ([e.file]:[e.line])")
	om_test_end()

/datum/unit_test/life_om/proc/run_life()
	return

/// The life pipeline's counters on this test's scheduler.
/datum/unit_test/life_om/proc/life_stats()
	RETURN_TYPE(/list)
	return sched.stat_for(om_registry().behaviour(/datum/om/pipeline/life).id)

// --- Content: families, variants, plans ----------------------------------------------------------

/// Every variant's `of` extends its parent variant's, so a variant's ..() reaches the variant for
/// the nearest ancestor mob type, as the old handle_* override chains did.
/datum/unit_test/dq_life_stage_variants_mirror_mob_paths

/datum/unit_test/dq_life_stage_variants_mirror_mob_paths/Run()
	var/datum/om/registry/reg = om_registry()
	var/checked = 0
	for(var/path in subtypesof(/datum/om/stage/life))
		var/datum/om/stage/life/S = reg.stage_by_type[path]
		if(om_stage_is_category(path, reg))
			continue
		TEST_ASSERT_NOTNULL(S.family, "[path] has no family")
		if(path == S.family)
			continue
		var/datum/om/stage/life/P = reg.stage_by_type[type2parent(path)]
		TEST_ASSERT(ispath(S.of, P.of), "[path] serves [S.of], which is not a [P.of] like its parent [P.type]")
		checked++
	TEST_ASSERT(checked > 50, "expected many life stage variants, checked [checked]")

/// A human runs the living core, carbon germs and the human tail in the legacy order; canmove
/// runs in the derive pipeline and the HUD in the present one.
/datum/unit_test/dq_life_human_plan_order

/datum/unit_test/dq_life_human_plan_order/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/types = life_test_stage_types(H)
	var/list/expected = list(
		/datum/om/stage/life/type_pre/carbon/human,
		/datum/om/stage/life/upkeep,
		/datum/om/stage/life/instability/carbon/human,
		/datum/om/stage/life/modifiers,
		/datum/om/stage/life/light,
		/datum/om/stage/life/breathing/carbon/human,
		/datum/om/stage/life/mutations/carbon/human,
		/datum/om/stage/life/radiation/carbon/human,
		/datum/om/stage/life/blood/carbon/human,
		/datum/om/stage/life/random_events/carbon/human,
		/datum/om/stage/life/afk,
		/datum/om/stage/life/chemicals/carbon/human,
		/datum/om/stage/life/diseases/carbon,
		/datum/om/stage/life/environment/carbon/human,
		/datum/om/stage/life/ambience,
		/datum/om/stage/life/movement,
		/datum/om/stage/life/status/carbon/human,
		/datum/om/stage/life/disabilities/carbon/human,
		/datum/om/stage/life/addictions/carbon,
		/datum/om/stage/life/tf_holder,
		/datum/om/stage/life/vr_derez,
		/datum/om/stage/life/germs,
		/datum/om/stage/life/voice,
		/datum/om/stage/life/stasis_sleep,
		/datum/om/stage/life/fall,
		/datum/om/stage/life/changeling,
		/datum/om/stage/life/organs,
		/datum/om/stage/life/thermoregulation,
		/datum/om/stage/life/weight,
		/datum/om/stage/life/shock,
		/datum/om/stage/life/pain,
		/datum/om/stage/life/medical,
		/datum/om/stage/life/heartbeat,
		/datum/om/stage/life/nif,
		/datum/om/stage/life/phobias,
		/datum/om/stage/life/npc,
		/datum/om/stage/life/defib_timer,
		/datum/om/stage/life/species_components,
		/datum/om/stage/life/visible_name,
		/datum/om/stage/life/pulse,
	)
	TEST_ASSERT(life_test_in_order(types, expected), "human stages are missing or out of order: [jointext(types, ", ")]")
	TEST_ASSERT(!(/datum/om/stage/life/robot_power in types), "a human must not get robot stages")
	TEST_ASSERT(!(/datum/om/stage/life/canmove in types), "canmove is not in the frame")
	TEST_ASSERT(/datum/om/stage/life/canmove in life_test_stage_types(H, /datum/om/pipeline/life_derive), "canmove is a derivation")
	var/list/present = life_test_stage_types(H, /datum/om/pipeline/life_present)
	TEST_ASSERT(life_test_in_order(present, list(/datum/om/stage/life/hud/carbon/human, /datum/om/stage/life/vision/carbon/human, /datum/om/stage/life/hud_refresh)), "the human HUD is presentation: [jointext(present, ", ")]")

/// Every human of a type shares one plan; a cyborg's plan comes from the robot set only.
/datum/unit_test/dq_life_plan_is_shared

/datum/unit_test/dq_life_plan_is_shared/Run()
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(life_test_pipe(first).plan, life_test_pipe(second).plan, "two plain humans should share one plan")

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/list/types = life_test_stage_types(R)
	var/list/expected = list(
		/datum/om/stage/life/robot_cycle,
		/datum/om/stage/life/modifiers/silicon/robot,
		/datum/om/stage/life/robot_senses,
		/datum/om/stage/life/instability/silicon/robot,
		/datum/om/stage/life/robot_power,
		/datum/om/stage/life/robot_body,
		/datum/om/stage/life/robot_interface,
		/datum/om/stage/life/robot_alarms,
	)
	TEST_ASSERT(life_test_in_order(types, expected), "robot stages are missing or out of order: [jointext(types, ", ")]")
	TEST_ASSERT_EQUAL(length(types), length(expected), "a robot should run only the robot set: [jointext(types, ", ")]")
	TEST_ASSERT(/datum/om/stage/life/canmove/silicon/robot in life_test_stage_types(R, /datum/om/pipeline/life_derive), "a robot derives canmove with its own variant")

/// A simple mob's subtype code runs as its own variant after the simple mob core.
/datum/unit_test/dq_life_simple_mob_variants

/datum/unit_test/dq_life_simple_mob_variants/Run()
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/life)
	var/datum/om/stage/post = P.resolve(/datum/om/stage/life/type_post, /mob/living/simple_mob/animal/passive/chicken)
	TEST_ASSERT_EQUAL(post?.type, /datum/om/stage/life/type_post/simple_mob/animal/passive/chicken, "a chicken should run its own post-core code")
	var/datum/om/stage/special = P.resolve(/datum/om/stage/life/special, /mob/living/simple_mob/slime/xenobio/amber)
	TEST_ASSERT_EQUAL(special?.type, /datum/om/stage/life/special/slime/xenobio/amber, "an amber slime should run its own special behaviour")
	TEST_ASSERT_NULL(P.resolve(/datum/om/stage/life/special, /mob/living/carbon/human), "humans have no simple mob special behaviour")

/// The "alive" fact skips breathing for a dead body; a living body breathes on its cadence.
/datum/unit_test/dq_life_alive_fact_skips_stages

/datum/unit_test/dq_life_alive_fact_skips_stages/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/cycle_before = H.breath_cycle
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT_NOTEQUAL(H.breath_cycle, cycle_before, "a living human's breathing stage should advance its breath cadence")

	H.death()
	TEST_ASSERT_EQUAL(H.stat, DEAD, "the human should be dead for the fact check")
	om_pipe_set_all(life_test_pipe(H), FALSE)
	cycle_before = H.breath_cycle
	var/life_tick_before = H.life_tick
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a dead human must not run the alive-only breathing stage")
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "a dead human still runs the rest of its frame")
	TEST_ASSERT(life_test_idle(H, /datum/om/stage/life/breathing), "a stage its run_if skips for a reason a channel reports (death) idles")

/// The human pre code aborts the whole frame while transforming, as the old early return did, and
/// an aborted frame idles nothing.
/datum/unit_test/dq_life_transforming_human_aborts

/datum/unit_test/dq_life_transforming_human_aborts/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/om/frame/S = life_test_pipe(H)
	om_pipe_set_all(S, FALSE)
	var/life_tick_before = H.life_tick
	var/cycle_before = H.breath_cycle
	H.transforming = TRUE
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before, "a transforming human must not tick")
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a transforming human must not breathe")
	TEST_ASSERT(!S.asleep, "an aborted frame idles nothing")
	H.transforming = FALSE
	life_test_place(H)
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "the human should tick again once the transformation ends")

/// A transforming simple mob still runs its upkeep (the stages before the living core):
/// transformation is a fact, not a suspension (Codex bug: it halted all upkeep).
/datum/unit_test/dq_life_transforming_keeps_upkeep

/datum/unit_test/dq_life_transforming_keeps_upkeep/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_place(M), "no floor to place the test mouse on")
	om_stage_add(M, /datum/om/stage/life/trait/test_counter)
	var/datum/om/stage/life/trait/test_counter/counter = om_registry().stage_by_type[/datum/om/stage/life/trait/test_counter]
	M.transforming = TRUE
	om_run_frame_now(M, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(counter.runs["[REF(M)]"], 1, "trait stages (before the living core) run while transforming")
	TEST_ASSERT(!om_value_of(M, EFFECT_SUSPENDED), "transforming is not a suspension")
	M.transforming = FALSE

/// A component-provided trait stage joins the plan while the component is attached.
/datum/unit_test/dq_life_trait_stage_follows_component

/datum/unit_test/dq_life_trait_stage_follows_component/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!(/datum/om/stage/life/trait/photosynth in life_test_stage_types(H)), "a plain human has no photosynthesis stage")
	var/datum/component/photosynth/P = H.AddComponent(/datum/component/photosynth)
	TEST_ASSERT_NOTNULL(P, "the photosynthesis component should attach")
	var/list/types = life_test_stage_types(H)
	TEST_ASSERT(/datum/om/stage/life/trait/photosynth in types, "attaching the component should add its trait stage")
	TEST_ASSERT(life_test_in_order(types, list(/datum/om/stage/life/type_pre/carbon/human, /datum/om/stage/life/trait/photosynth, /datum/om/stage/life/upkeep)), "trait stages run where the old Life signal fired")
	qdel(P)
	TEST_ASSERT(!(/datum/om/stage/life/trait/photosynth in life_test_stage_types(H)), "removing the component should remove its trait stage")

/// Loose organs never join Life: no pipeline attaches to them (Codex bug: they rotted).
/datum/unit_test/dq_life_loose_organs_have_no_life

/datum/unit_test/dq_life_loose_organs_have_no_life/Run()
	var/obj/item/organ/internal/heart/heart = allocate(/obj/item/organ/internal/heart)
	TEST_ASSERT(!om_attached(heart, /datum/om/pipeline/life), "a loose organ has no life pipeline")
	TEST_ASSERT(!om_type_has_decl(heart.type), "organs have no object-model declaration")

// --- Scheduling ----------------------------------------------------------------------------

/// One frame per LIFE_CYCLE, carrying LIFE_CYCLE_SECONDS of dt-scaled time.
/datum/unit_test/life_om/cadence

/datum/unit_test/life_om/cadence/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT(om_attached(H, /datum/om/pipeline/life), "a living mob carries the life pipeline")
	om_stage_add(H, /datum/om/stage/life/trait/test_counter)
	scheduler_advance(LIFE_CYCLE_SECONDS)
	var/before = life_test_frames(H)
	scheduler_advance(LIFE_CYCLE_SECONDS * 10)
	var/frames = life_test_frames(H) - before
	TEST_ASSERT(frames >= 9 && frames <= 11, "expected 10 frames in 10 cycles, got [frames]")
	var/datum/om/stage/life/trait/test_counter/counter = om_registry().stage_by_type[/datum/om/stage/life/trait/test_counter]
	TEST_ASSERT_EQUAL(counter.last_dt, LIFE_CYCLE_SECONDS, "a frame covers one cycle of dt")

/// Skipped ticks: after a long gap the frame runs at most LIFE_MAX_CATCHUP times in one pass,
/// never skips the mob, and counts the dropped frames as breaches.
/datum/unit_test/life_om/catch_up_is_bounded

/datum/unit_test/life_om/catch_up_is_bounded/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_stage_add(H, /datum/om/stage/life/trait/test_counter)
	scheduler_advance(LIFE_CYCLE_SECONDS * 2)
	var/before = life_test_frames(H)
	var/list/S = life_stats()
	var/breaches_before = S[OM_STAT_BREACHES]
	sched.jump(LIFE_CYCLE_SECONDS * 20)
	sched.run_pass(1e9)
	var/frames = life_test_frames(H) - before
	TEST_ASSERT(frames >= 1, "a mob is never skipped after skipped ticks")
	TEST_ASSERT(frames <= LIFE_MAX_CATCHUP, "catch-up is capped at [LIFE_MAX_CATCHUP] frames per pass, ran [frames]")
	TEST_ASSERT(S[OM_STAT_BREACHES] > breaches_before, "dropped frames are counted as breaches")
	before = life_test_frames(H)
	scheduler_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT((life_test_frames(H) - before) <= 1, "after catching up, one frame per cycle again")

/// A healthy idle mob parks (off the ring); a change wakes it whole; the frame after a long nap
/// covers at most one cycle (Codex bug: the whole nap was passed as seconds).
/datum/unit_test/life_om/parking

/datum/unit_test/life_om/parking/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "an idle healthy mouse should park; still busy: [life_test_busy(M)]")
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/life)
	TEST_ASSERT(M in P.parked_on(sched), "a parked mob is listed")
	TEST_ASSERT_NULL(P.missed_wake(M), "a freshly parked mob has no missed wake")
	// Only rewakes bring a parked mob back (the simple mob environment's is 15 s); without them
	// it runs no frames.
	om_cancel_all_after(M, P)
	var/before = life_test_frames(M)
	scheduler_advance(LIFE_CYCLE_SECONDS * 20)
	TEST_ASSERT_EQUAL(life_test_frames(M), before, "a parked mob with no rewake runs no frames")
	TEST_ASSERT(M.injure(INJURY_BLUNT, 1) > 0, "the injury should land")
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_parked(M), "injure() unparks a mob")
	TEST_ASSERT(!life_test_pipe(M).asleep, "a parked mob wakes whole")
	before = life_test_frames(M)
	sched.run_pass(1e9)
	scheduler_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT((life_test_frames(M) - before) <= 1, "the first frame after a nap covers at most one cycle, ran [life_test_frames(M) - before]")

/// An idle stage wakes only on its own channels; a change raised during a frame keeps a later
/// stage awake.
/datum/unit_test/life_om/channels_wake_stages

/datum/unit_test/life_om/channels_wake_stages/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_stage_add(H, /datum/om/stage/life/trait/test_sleeper)
	var/datum/om/stage/life/trait/test_sleeper/S = om_registry().stage_by_type[/datum/om/stage/life/trait/test_sleeper]
	om_run_frame_now(H, /datum/om/pipeline/life)
	// Keep ring frames out of the way: a human's own frame raises health changes.
	om_park(H, /datum/om/pipeline/life)
	scheduler_advance(0.1)
	// The frame's own changes may have woken it: idle it again for the channel checks.
	life_test_set_idle(H, S.type)
	TEST_ASSERT(life_test_idle(H, S.type), "an idle stage idles after its run")
	om_changed(H, CHANGE_MOB_EQUIPMENT)
	scheduler_advance(0.1)
	TEST_ASSERT(life_test_idle(H, S.type), "a channel the stage doesn't declare leaves it idle")
	om_changed(H, CHANGE_MOB_HEALTH)
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_idle(H, S.type), "its declared channel wakes it")
	var/runs = S.runs["[REF(H)]"]
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(S.runs["[REF(H)]"], runs + 1, "a woken stage runs in the next frame")
	om_unpark(H, /datum/om/pipeline/life)

	// A stage early in the frame raises the channel; the later stage idles at its run and is woken
	// right back by the delivered change.
	om_stage_add(H, /datum/om/stage/life/trait/test_raiser)
	om_run_frame_now(H, /datum/om/pipeline/life)
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_idle(H, S.type), "a change raised during the frame wakes the later stage")

/// A rewake unparks a parked mob partially: only the stage whose rewake is due.
/datum/unit_test/life_om/rewake_unparks_partially

/datum/unit_test/life_om/rewake_unparks_partially/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	om_stage_add(M, /datum/om/stage/life/trait/test_timer)
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/life)
	var/key = life_test_rewake_key(/datum/om/stage/life/trait/test_timer)
	TEST_ASSERT(om_deadline_pending(M, P, key), "the test stage's rewake is pending")
	var/waited = 0
	while(life_test_parked(M) && waited < 60)
		sched.manual_time += 1
		sched.run_pass(1e9)
		waited++
	TEST_ASSERT(!life_test_parked(M), "the rewake unparked the mob")
	var/datum/om/frame/S = life_test_pipe(M)
	var/awake = 0
	for(var/i in 1 to S.plan.n)
		if(!(S.bits[OM_PIPE_WORD(i)] & OM_PIPE_BIT(i)))
			awake++
			var/datum/om/stage/T = S.plan.stages[i]
			TEST_ASSERT_EQUAL(T.type, /datum/om/stage/life/trait/test_timer, "only the rewoken stage wakes, not [T.type]")
	TEST_ASSERT_EQUAL(awake, 1, "exactly one stage woke")
	TEST_ASSERT_EQUAL(S.idle_frames, LIFE_PARK_AFTER - 1, "a rewake counts as an idle frame already, so it parks again at once")

/// A rewake wakes an idle stage by deadline and never runs a frame on an awake mob (Codex bug:
/// +20-30% frames).
/datum/unit_test/life_om/rewakes_do_not_run_frames

/datum/unit_test/life_om/rewakes_do_not_run_frames/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_stage_add(H, /datum/om/stage/life/trait/test_timer)
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/life)
	var/key = life_test_rewake_key(/datum/om/stage/life/trait/test_timer)
	om_run_frame_now(H, P)
	TEST_ASSERT(life_test_idle(H, /datum/om/stage/life/trait/test_timer), "the idle stage idles")
	TEST_ASSERT(om_deadline_pending(H, P, key), "with a rewake pending")
	var/frames = life_test_frames(H)
	// Advance past the rewake (3 s) but not a whole cycle.
	var/waited = 0
	while(om_deadline_pending(H, P, key) && waited < 40)
		sched.manual_time += 1
		sched.run_pass(1e9)
		waited++
	TEST_ASSERT(!life_test_idle(H, /datum/om/stage/life/trait/test_timer), "the rewake woke the stage")
	TEST_ASSERT(life_test_frames(H) - frames <= 1, "the rewake ran no extra frame")

/// Deleting a mob during its frame stops the frame at once; its deadlines are skipped.
/datum/unit_test/life_om/deletion_mid_frame

/datum/unit_test/life_om/deletion_mid_frame/run_life()
	var/mob/living/carbon/human/H = new(run_loc_floor_bottom_left)
	om_stage_add(H, /datum/om/stage/life/trait/test_timer)
	om_stage_add(H, /datum/om/stage/life/trait/test_deleter)
	om_stage_add(H, /datum/om/stage/life/trait/test_counter)
	var/datum/om/stage/life/trait/test_counter/counter = om_registry().stage_by_type[/datum/om/stage/life/trait/test_counter]
	om_after(H, 1 SECONDS, /datum/om/pipeline/life, life_test_rewake_key(/datum/om/stage/life/trait/test_timer))
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT(QDELETED(H), "the deleter stage deleted the mob")
	TEST_ASSERT(!counter.runs["[REF(H)]"], "no stage runs on a deleted mob")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(length(sched.errors), 0, "no scheduler errors after deleting a mob with a pending deadline: [jointext(sched.errors, "; ")]")

/// Death wakes every stage; a dead mob parks too; revival brings it back.
/datum/unit_test/life_om/death_and_revive

/datum/unit_test/life_om/death_and_revive/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	M.death()
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_parked(M), "death is a stat change: it unparks the mob")
	var/before = life_test_frames(M)
	om_run_frame_now(M, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(life_test_frames(M), before + 1, "a dead mob still runs its frame")
	TEST_ASSERT(life_test_settle(M), "a dead mob parks: its alive-only stages idle on the stat channel; still busy: [life_test_busy(M)]")
	M.revive()
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_parked(M), "revival wakes the mob")
	TEST_ASSERT_NOTEQUAL(M.stat, DEAD, "the mouse is alive again")

/// Suspension (absorbed prey, bodies kept for reforming) runs no frame until resumed.
/datum/unit_test/life_om/suspension

/datum/unit_test/life_om/suspension/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_stage_add(H, /datum/om/stage/life/trait/test_counter)
	scheduler_advance(LIFE_CYCLE_SECONDS)
	om_suspend(H, H)
	TEST_ASSERT(om_value_of(H, EFFECT_SUSPENDED), "suspended")
	var/before = life_test_frames(H)
	scheduler_advance(LIFE_CYCLE_SECONDS * 5)
	TEST_ASSERT_EQUAL(life_test_frames(H), before, "a suspended mob runs no frame")
	om_unsuspend(H, H)
	scheduler_advance(LIFE_CYCLE_SECONDS * 2)
	TEST_ASSERT(life_test_frames(H) > before, "a resumed mob runs again")

/// Relevance replaces the per-frame z-level test: a low-priority mob on a z-level without living
/// players parks by relevance; one that isn't low priority holds its own relevance.
/datum/unit_test/life_om/relevance_parks_low_priority

/datum/unit_test/life_om/relevance_parks_low_priority/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_stage_add(H, /datum/om/stage/life/trait/test_counter)
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
	scheduler_advance(LIFE_CYCLE_SECONDS)
	var/before = life_test_frames(H)
	scheduler_advance(LIFE_CYCLE_SECONDS * 3)
	TEST_ASSERT_EQUAL(life_test_frames(H), before, "and runs no frame, with nothing tested per frame")
	GLOB.living_players_by_zlevel[z] += H
	life_z_occupancy_changed(z)
	TEST_ASSERT_EQUAL(om_relevance(H), RELEVANCE_NEAR, "a living player arriving makes the z-level's low-priority mobs relevant")
	scheduler_advance(LIFE_CYCLE_SECONDS * 2)
	TEST_ASSERT(life_test_frames(H) > before, "so they run again")
	GLOB.living_players_by_zlevel[z] -= H
	life_z_occupancy_changed(z)
	TEST_ASSERT_EQUAL(om_relevance(H), RELEVANCE_NONE, "and the last one leaving parks them")
	H.set_low_priority(FALSE)
	TEST_ASSERT(!(H in P.members), "a mob that isn't low priority leaves the presence")

/// Stasis runs biology on the biology clock: deep stasis (0.9) one frame in ten, total stasis
/// never; the frame itself keeps running.
/datum/unit_test/life_om/stasis_clock

/datum/unit_test/life_om/stasis_clock/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.set_stasis(/datum/modifier/stasis/deep, src)
	TEST_ASSERT(abs(om_clock_rate_of(H, CLOCK_BIO) - 0.1) < 0.001, "deep stasis holds the biology clock at 0.1, got [om_clock_rate_of(H, CLOCK_BIO)]")
	var/biology = 0
	var/frames_before = life_test_frames(H)
	for(var/i in 1 to 20)
		om_run_frame_now(H, /datum/om/pipeline/life)
		if(!H.body.stasis_paused)
			biology++
	TEST_ASSERT_EQUAL(biology, 2, "deep stasis runs biology on 2 frames in 20")
	TEST_ASSERT_EQUAL(life_test_frames(H), frames_before + 20, "the frame itself keeps running in stasis")
	H.set_stasis(/datum/modifier/stasis/total, src)
	TEST_ASSERT_EQUAL(om_clock_rate_of(H, CLOCK_BIO), 0, "total stasis stops the biology clock")
	biology = 0
	for(var/i in 1 to 10)
		om_run_frame_now(H, /datum/om/pipeline/life)
		if(!H.body.stasis_paused)
			biology++
	TEST_ASSERT_EQUAL(biology, 0, "total stasis never runs biology")
	H.set_stasis(null, src)
	TEST_ASSERT_EQUAL(om_clock_rate_of(H, CLOCK_BIO), 1, "leaving stasis restores the clock")
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT(!H.body.stasis_paused, "biology runs every frame again")

/// Stun, weaken and paralysis are timed statuses: durations in LIFE_CYCLE units, exact set and
/// adjust semantics, and canmove follows at once.
/datum/unit_test/life_om/statuses_are_contributions

/datum/unit_test/life_om/statuses_are_contributions/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	// Statuses end in real time on their own: no frame is needed (or wanted: a test human's
	// own frames can knock it out and hide canmove).
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
	scheduler_advance(LIFE_CYCLE_SECONDS + 0.1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_STUNNED), 1, "one unit per LIFE_CYCLE of real time")
	scheduler_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "the stun ends on its own")
	TEST_ASSERT(H.canmove, "canmove comes back when it ends (stat [H.stat], sleeping [H.has_status(EFFECT_SLEEPING)], lying [H.lying], resting [H.resting], paralysed [H.has_status(EFFECT_PARALYZED)], weakened [H.has_status(EFFECT_WEAKENED)], buckled [H.buckled])")

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

/// The derive and present pipelines: presentation doesn't start for clientless mobs; a status
/// change runs the canmove derivation in the same pass, with no frame.
/datum/unit_test/life_om/derive_and_present

/datum/unit_test/life_om/derive_and_present/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT(om_attached(H, /datum/om/pipeline/life_present), "every living mob carries the present pipeline")
	TEST_ASSERT(!life_test_started(H, /datum/om/pipeline/life_present), "a clientless mob does not start it")
	TEST_ASSERT(life_test_started(H, /datum/om/pipeline/life_derive), "the derive pipeline runs for every mob")
	var/frames = life_test_frames(H)
	H.status_set(EFFECT_SLEEPING, 2)
	H.canmove = TRUE
	om_changed(H, CHANGE_MOB_STATUS)
	sched.run_pass(1e9)
	TEST_ASSERT(!H.canmove, "a status change ran the canmove derivation without a frame")
	TEST_ASSERT_EQUAL(life_test_frames(H), frames, "no life frame ran for it")
	H.status_set(EFFECT_SLEEPING, 0)

/// Ghosts, AI eyes and the blob overmind run their upkeep on their own behaviour.
/datum/unit_test/life_om/observer_upkeep

/datum/unit_test/life_om/observer_upkeep/run_life()
	var/mob/observer/dead/life_test/G = allocate(/mob/observer/dead/life_test)
	TEST_ASSERT(om_attached(G, /datum/om/behaviour/observer_upkeep), "observers carry the upkeep behaviour")
	scheduler_advance(OBSERVER_UPKEEP_INTERVAL / 10 * 3)
	TEST_ASSERT(G.upkeeps >= 2, "observer upkeep runs on its cadence, ran [G.upkeeps]")

/// The stage profiler samples by a scheduler-wide frame counter, so every mob is sampled at the same
/// rate (Codex bug: sampling bias from a run list that restarted each cycle), and a sampled frame
/// records the stages it ran.
/datum/unit_test/life_om/profiler_is_uniform

/datum/unit_test/life_om/profiler_is_uniform/run_life()
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(A) && life_test_place(B), "no floor to place the test humans on")
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/life)
	var/stride = P.profile_stride
	if(!stride)
		TEST_NOTICE(src, "built without the stage profiler (OM_NO_STAGE_PROFILE)")
		return
	var/key = "type:[A.type]"
	var/frames_before = om_pipeline_frames(list(A, B), P)
	var/calls_before = sched.stage_calls[key] || 0
	for(var/i in 1 to stride * 2)
		om_pipe_set_all(life_test_pipe(A), FALSE)
		om_pipe_set_all(life_test_pipe(B), FALSE)
		om_run_frame_now(A, P)
		om_run_frame_now(B, P)
	var/frames = om_pipeline_frames(list(A, B), P) - frames_before
	var/sampled = ((sched.stage_calls[key] || 0) - calls_before) / stride
	TEST_ASSERT_EQUAL(frames, stride * 4, "every frame counted")
	TEST_ASSERT(abs(sampled - frames / stride) <= 1, "one frame in [stride] is sampled: [sampled] of [frames]")
	TEST_ASSERT((sched.stage_calls["[/datum/om/stage/life/upkeep]"] || 0) > 0, "a sampled frame records the stages it ran")

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
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_parked(M), "adding a reagent should wake a parked mob")

/// A stun wakes the mob; once it wears off the mob parks again.
/datum/unit_test/life_om/stun_wakes_then_parks

/datum/unit_test/life_om/stun_wakes_then_parks/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	M.status_at_least(EFFECT_STUNNED, 3)
	TEST_ASSERT_EQUAL(M.status_units(EFFECT_STUNNED), 3, "the stun should land")
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_parked(M), "a stun should wake a parked mob")
	scheduler_advance(LIFE_CYCLE_SECONDS * 3 + 1)
	TEST_ASSERT_EQUAL(M.status_units(EFFECT_STUNNED), 0, "the stun should have worn off")
	scheduler_advance(LIFE_CYCLE_SECONDS * 4)
	TEST_ASSERT(life_test_parked(M), "the mouse should park again once the stun wears off; still busy: [life_test_busy(M)]")

/// A client logging in wakes the whole mob.
/datum/unit_test/life_om/client_login_wakes

/datum/unit_test/life_om/client_login_wakes/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	// /mob/living/Login() calls this hook; a unit test has no client to log in with.
	M.on_client_changed("login")
	scheduler_advance(0.1)
	TEST_ASSERT(!life_test_parked(M), "a login should wake a parked mob")
	TEST_ASSERT(!life_test_pipe(M).asleep, "a login wakes every stage")

/// The pipeline audit finds a change made without raising its channel, logs it and wakes the mob.
/datum/unit_test/life_om/audit_catches_missed_wake

/datum/unit_test/life_om/audit_catches_missed_wake/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	TEST_ASSERT(!length(om_pipeline_audit(sched, 400, 0, TRUE)), "the audit must not flag a mob that is correctly parked")
	// A deliberately missed wake: write state an idle stage reads (healing ears) without raising
	// a channel.
	M.ear_damage = 50
	TEST_ASSERT(life_test_parked(M), "a direct write must not wake the mob (that is the bug the audit catches)")
	var/list/S = life_stats()
	var/missed_before = S[OM_STAT_MISSED]
	var/list/found = om_pipeline_audit(sched, 400, 0, TRUE)
	TEST_ASSERT(length(found), "the audit should find the stage with pending work")
	TEST_ASSERT_EQUAL(S[OM_STAT_MISSED], missed_before + 1, "the audit should count the missed wake")
	TEST_ASSERT(!life_test_parked(M), "the audit should wake the mob")
	M.ear_damage = 0

// --- Statuses, immunity and the frame's own changes (doc/rewrite/life_on_om.md §7) --------------

/// Every former counter is a timed status: it ends by deadline, in its own units per cycle, with
/// no frame running; the magnitude statuses read back in points.
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
	scheduler_advance(LIFE_CYCLE_SECONDS + 0.1)
	for(var/id in one_per_cycle)
		TEST_ASSERT_EQUAL(H.status_units(id), 1, "[id]: one unit wears off per cycle")
	scheduler_advance(LIFE_CYCLE_SECONDS)
	for(var/id in one_per_cycle)
		TEST_ASSERT(!H.has_status(id), "[id]: ends on its own after two cycles")
	TEST_ASSERT_EQUAL(life_test_frames(H), frames_before, "no frame ran: nothing counts statuses down")

	// Hallucination wore off two points per cycle.
	H.status_at_least(EFFECT_HALLUCINATING, 10)
	scheduler_advance(LIFE_CYCLE_SECONDS * 2 + 0.1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_HALLUCINATING), 6, "hallucination: 2 points per cycle")

	// Dizziness: 3 points per cycle, 15 while resting, capped at 1000.
	H.status_adjust(EFFECT_DIZZY, 5000)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 1000, "dizziness is capped at 1000 points")
	TEST_ASSERT_NOTNULL(H.GetComponent(/datum/component/dizzy_shake), "the shake follows the status (its on_start hook)")
	H.status_set(EFFECT_DIZZY, 30)
	scheduler_advance(LIFE_CYCLE_SECONDS + 0.1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 27, "dizziness: 3 points per cycle")
	H.resting = TRUE
	H.status_rate_check(EFFECT_DIZZY)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 27, "a rate change keeps the points left")
	scheduler_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 12, "dizziness: 15 points per cycle while resting")
	H.resting = FALSE
	H.status_end(EFFECT_DIZZY)
	TEST_ASSERT_NULL(H.GetComponent(/datum/component/dizzy_shake), "the shake ends with the status (its on_end hook)")

	// Alerts follow the status, with no stage maintaining them.
	H.status_at_least(EFFECT_CONFUSED, 1)
	TEST_ASSERT(H.alerts?["confused"], "the confused alert starts with the status")
	scheduler_advance(LIFE_CYCLE_SECONDS + 0.1)
	TEST_ASSERT(!H.alerts?["confused"], "and ends with it")

/// Immunity is an effect: it blocks the statuses that name it, gaining it ends them, and every
/// source holds its own (mob type declarations, mutations, godmode).
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
	H.AddElement(/datum/element/godmode)
	TEST_ASSERT(om_has(H, EFFECT_GODMODE), "the godmode element holds EFFECT_GODMODE")
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "godmode blocks stuns")
	H.RemoveElement(/datum/element/godmode)
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
	H.AddElement(/datum/element/godmode)
	TEST_ASSERT(om_has(H, EFFECT_GODMODE), "the element holds the effect")
	TEST_ASSERT(om_has(H, EFFECT_IMMUNE_PARALYZE), "godmode implies the incapacitation immunities")
	TEST_ASSERT_EQUAL(H.injure(INJURY_BLUNT, 20), 0, "injure() lands nothing in godmode")
	H.RemoveElement(/datum/element/godmode)
	TEST_ASSERT(!om_has(H, EFFECT_IMMUNE_PARALYZE), "the implied immunities end with it")
	TEST_ASSERT(H.injure(INJURY_BLUNT, 1) > 0, "and harm lands again")

/// Voluntary sleep is a hold: no dose wearing off or ending wakes the mob; choosing to wake does.
/// A hold has no duration: status_units() and status_remaining() read the timed doses only.
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
	scheduler_advance(LIFE_CYCLE_SECONDS * 3)
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "a dose wearing off doesn't wake a voluntary sleeper")
	H.status_set(EFFECT_SLEEPING, 0)
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "nor does ending the dose")
	H.set_voluntary_sleep(FALSE)
	TEST_ASSERT(!H.has_status(EFFECT_SLEEPING), "choosing to wake ends it")
	TEST_ASSERT(!H.alerts?["asleep"], "and its alert")

/// A status change raises CHANGE_MOB_STATUS once, and a change that doesn't change the value
/// raises nothing.
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

/// The status row's veto signal: a handler answering COMPONENT_NO_STUN blocks the increase.
/datum/unit_test/life_om/status_signal_veto
	var/vetoes = 0

/datum/unit_test/life_om/status_signal_veto/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	om_suspend(H, H)
	RegisterSignal(H, COMSIG_LIVING_STATUS_STUN, PROC_REF(veto))
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "a vetoed increase doesn't land")
	TEST_ASSERT_EQUAL(vetoes, 1, "the row's signal was sent once")
	H.status_at_least(EFFECT_SLURRING, 2)
	TEST_ASSERT(H.has_status(EFFECT_SLURRING), "a status without a signal isn't vetoed")
	UnregisterSignal(H, COMSIG_LIVING_STATUS_STUN)
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(H.has_status(EFFECT_STUNNED), "without the veto it lands")

/datum/unit_test/life_om/status_signal_veto/proc/veto(datum/source, amount)
	SIGNAL_HANDLER
	vetoes++
	return COMPONENT_NO_STUN

/// Life never wakes itself: a frame on a mob with running statuses raises no status change, so a
/// sleeping mouse parks like an idle one.
/datum/unit_test/life_om/no_self_wake

/datum/unit_test/life_om/no_self_wake/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	M.status_set(EFFECT_SLEEPING, 100)
	M.status_at_least(EFFECT_CONFUSED, 100)
	sched.run_pass(1e9)
	sched.test_raises = list()
	om_run_frame_now(M, /datum/om/pipeline/life)
	TEST_ASSERT_EQUAL(life_test_status_raises(sched, M), 0, "a frame raises no status change on its own mob")
	sched.test_raises = null
	TEST_ASSERT(life_test_settle(M), "a sleeping, confused mouse parks; still busy: [life_test_busy(M)]")
	TEST_ASSERT(M.has_status(EFFECT_SLEEPING), "and stays asleep while parked")

/// Parking hysteresis: a mob parks only after LIFE_PARK_AFTER frames in a row end with every stage
/// idle; a wake in between starts the count again.
/datum/unit_test/life_om/park_hysteresis

/datum/unit_test/life_om/park_hysteresis/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should park first; still busy: [life_test_busy(M)]")
	var/datum/om/frame/S = life_test_pipe(M)
	om_changed(M, CHANGE_EXPLICIT)
	sched.run_pass(1e9)
	TEST_ASSERT(!life_test_parked(M), "a change wakes it")
	var/frames = 0
	while(S.asleep < S.plan.n && frames < 6)
		om_run_frame_now(M, /datum/om/pipeline/life)
		sched.run_pass(1e9)
		frames++
	TEST_ASSERT(S.asleep >= S.plan.n, "its stages idle again; still busy: [life_test_busy(M)]")
	TEST_ASSERT(!life_test_parked(M), "one idle frame doesn't park it")
	TEST_ASSERT_EQUAL(S.idle_frames, 1, "one idle frame counted")
	om_changed(M, CHANGE_MOB_HEALTH)
	sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(S.idle_frames, 0, "a wake between idle frames starts the count again")
	frames = 0
	while(!life_test_parked(M) && frames < 6)
		om_run_frame_now(M, /datum/om/pipeline/life)
		sched.run_pass(1e9)
		frames++
	TEST_ASSERT(life_test_parked(M), "it parks after idle frames in a row")
	TEST_ASSERT(frames >= LIFE_PARK_AFTER, "and not before [LIFE_PARK_AFTER] of them, took [frames]")

/// Clientless mobs get correct sight flags: the vision pipeline runs for every mob when an input
/// changes (a mutation, stat), not per frame and not on movement.
/datum/unit_test/life_om/npc_vision_follows_inputs

/datum/unit_test/life_om/npc_vision_follows_inputs/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT(!H.client, "a clientless mob")
	TEST_ASSERT(life_test_started(H, /datum/om/pipeline/life_vision), "vision runs for clientless mobs too")
	sched.run_pass(1e9)
	TEST_ASSERT(!(H.sight & SEE_MOBS), "no x-ray sight to begin with")
	H.add_mutation(XRAY)
	scheduler_advance(1)
	TEST_ASSERT(H.sight & SEE_MOBS, "gaining the x-ray mutation gives an NPC x-ray sight, with no frame and no client")
	TEST_ASSERT_EQUAL(H.see_in_dark, 8, "and darksight")
	var/datum/om/frame/V = life_test_pipe(H, /datum/om/pipeline/life_vision)
	var/runs = V.frames
	for(var/i in 1 to 5)
		H.forceMove(get_step(H, pick(GLOB.cardinal)) || H.loc)
		sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(V.frames, runs, "walking around doesn't recompute sight")
	H.remove_mutation(XRAY)
	scheduler_advance(1)
	TEST_ASSERT(!(H.sight & SEE_MOBS), "losing the mutation takes it away")
	H.death()
	scheduler_advance(1)
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

#endif

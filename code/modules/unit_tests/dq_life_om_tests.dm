// Mob Life on the object model (doc/rewrite/life_on_om.md): content (families, variants,
// composition, gates) and the scheduling that replaced SSmobs: cadence and catch-up, sleep and
// wake by channel, hibernation, timers, suspension, stasis on the biology clock, statuses as
// contributions, wake-only systems, and one test per bug the Codex prototype had (§12).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Runs one breath's gas exchange for a human through its breathing system.
/proc/life_test_breath(mob/living/carbon/human/H, datum/gas_mixture/breath)
	var/datum/life_system/breathing/carbon/breathing = H.life_system_for(/datum/life_system/breathing)
	breathing.exchange(H, breath)

/// Takes one breath (source, exchange, exhale) through a carbon's breathing system.
/proc/life_test_breathe(mob/living/carbon/C)
	var/datum/life_system/breathing/carbon/breathing = C.life_system_for(/datum/life_system/breathing)
	breathing.breathe(C)

/// Runs a human's environment exchange (heat and pressure) against a gas mixture.
/proc/life_test_environment(mob/living/carbon/human/H, datum/gas_mixture/environment)
	var/datum/life_system/environment/environment_system = H.life_system_for(/datum/life_system/environment)
	environment_system.exchange(H, environment)

/// Puts a test mob on a floor: the living core stops at `if(!loc)`, and the test map may lack
/// the unit test landmark that allocate() uses.
/proc/life_test_place(mob/living/L)
	if(isturf(L.loc))
		return TRUE
	var/turf/simulated/floor/T = locate() in world
	if(!T)
		return FALSE
	L.forceMove(T)
	return isturf(L.loc)

/// The types of a composition's systems, in run order.
/proc/life_test_system_types(mob/living/L)
	var/datum/life_composition/comp = L.life_composition || L.recompose_life()
	. = list()
	for(var/datum/life_system/S as anything in comp.ordered)
		. += S.type

/// TRUE when every type in `expected` appears in `actual`, in the same relative order.
/proc/life_test_in_order(list/actual, list/expected)
	var/last = 0
	for(var/path in expected)
		var/index = actual.Find(path)
		if(!index || index < last)
			return FALSE
		last = index
	return TRUE

/// A mouse that can hibernate: placed on a floor, its AI asleep, and its environment limits
/// opened so the test floor's air can't hurt it.
/proc/life_test_idle_mouse(mob/living/simple_mob/M)
	if(!life_test_place(M))
		return FALSE
	// Simple mobs skip frames on a z-level without living players; the test world has none.
	M.low_priority = FALSE
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

/// Runs frames until the mob hibernates, at most `frames` times. Returns TRUE if it did. On a
/// test scheduler, each frame is followed by a pass so the changes it raised are delivered
/// before the next frame, as they are live.
/proc/life_test_settle(mob/living/L, frames = 6)
	var/datum/om/scheduler/sched = om_scheduler()
	for(var/i in 1 to frames)
		if(L.life_hibernating)
			return TRUE
		L.life_frame()
		if(!isnull(sched.manual_time))
			sched.run_pass(1e9)
	return L.life_hibernating

/// Names of the systems that would keep this mob awake, for failure messages.
/proc/life_test_busy(mob/living/L)
	var/list/names = list()
	var/datum/life_composition/comp = L.life_composition || L.recompose_life()
	for(var/i in comp.sleepers)
		var/datum/life_system/S = comp.ordered[i]
		if(L.life_system_wants_run(S))
			names += "[S.type]"
	return jointext(names, ", ")

/// TRUE when behaviour `B` is started on `E` (attached, requirements met, not suspended).
/proc/life_test_started(datum/E, B)
	var/datum/om/rec/rec = E.om_rec
	if(!rec)
		return FALSE
	var/i = rec.att.Find(om_registry().behaviour(B))
	return i && (rec.att_state[i] & OM_ATT_STARTED)

// --- Test-only extra systems (added per mob with add_life_system(); never composed otherwise) ----

/datum/life_system/trait/test_counter
	name = "test counter"
	order = 900
	phase = LIFE_PHASE_TAIL
	/// Runs of this system, per mob.
	var/list/runs = list()

/datum/life_system/trait/test_counter/tick(mob/living/self, datum/life_context/ctx)
	runs["[REF(self)]"] = (runs["[REF(self)]"] || 0) + 1

/datum/life_system/trait/test_counter/idle(mob/living/self)
	return FALSE

/// Idle after every run, with a rewake timer.
/datum/life_system/trait/test_timer
	name = "test timer"
	order = 901
	phase = LIFE_PHASE_TAIL
	var/list/runs = list()

/datum/life_system/trait/test_timer/tick(mob/living/self, datum/life_context/ctx)
	runs["[REF(self)]"] = (runs["[REF(self)]"] || 0) + 1

/datum/life_system/trait/test_timer/idle(mob/living/self)
	return TRUE

/datum/life_system/trait/test_timer/rewake_delay(mob/living/self)
	return 3 SECONDS

/// Raises a health change on its mob during the frame.
/datum/life_system/trait/test_raiser
	name = "test raiser"
	order = 1
	phase = LIFE_PHASE_INPUT

/datum/life_system/trait/test_raiser/tick(mob/living/self, datum/life_context/ctx)
	om_changed(self, CHANGE_MOB_HEALTH)

/datum/life_system/trait/test_raiser/idle(mob/living/self)
	return TRUE

/// Sleeps after every run; wakes on health changes only.
/datum/life_system/trait/test_sleeper
	name = "test sleeper"
	order = 902
	phase = LIFE_PHASE_TAIL
	wake_on = LIFE_WAKE_ON_BODY
	var/list/runs = list()

/datum/life_system/trait/test_sleeper/tick(mob/living/self, datum/life_context/ctx)
	runs["[REF(self)]"] = (runs["[REF(self)]"] || 0) + 1

/datum/life_system/trait/test_sleeper/idle(mob/living/self)
	return TRUE

/// Deletes its mob during the frame.
/datum/life_system/trait/test_deleter
	name = "test deleter"
	order = 899
	phase = LIFE_PHASE_TAIL

/datum/life_system/trait/test_deleter/tick(mob/living/self, datum/life_context/ctx)
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

/// The life behaviour's counters on this test's scheduler.
/datum/unit_test/life_om/proc/life_stats()
	RETURN_TYPE(/list)
	return sched.stat_for(om_registry().behaviour(/datum/om/behaviour/life).id)

// --- Content: families, variants, composition, gates ----------------------------------------------

/// Every variant's mob type extends its parent variant's, so a variant's ..() reaches the
/// variant for the nearest ancestor mob type, as the old handle_* override chains did.
/datum/unit_test/dq_life_system_variants_mirror_mob_paths

/datum/unit_test/dq_life_system_variants_mirror_mob_paths/Run()
	build_life_system_registry()
	var/checked = 0
	for(var/path in subtypesof(/datum/life_system))
		var/datum/life_system/S = get_life_system(path)
		if(is_life_system_category(path))
			continue
		TEST_ASSERT_NOTNULL(S.family, "[path] has no family")
		if(path == S.family)
			continue
		var/datum/life_system/P = get_life_system(type2parent(path))
		var/parent = P.type
		TEST_ASSERT(ispath(S.mob_type, P.mob_type), "[path] serves [S.mob_type], which is not a [P.mob_type] like its parent [parent]")
		checked++
	TEST_ASSERT(checked > 50, "expected many life system variants, checked [checked]")

/// A human runs the living core, carbon germs and the human tail in the legacy order.
/datum/unit_test/dq_life_human_composition_order

/datum/unit_test/dq_life_human_composition_order/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/types = life_test_system_types(H)
	var/list/expected = list(
		/datum/life_system/type_pre/carbon/human,
		/datum/life_system/upkeep,
		/datum/life_system/instability/carbon/human,
		/datum/life_system/gate/transforming,
		/datum/life_system/modifiers,
		/datum/life_system/gate/placed,
		/datum/life_system/light,
		/datum/life_system/gate/alive,
		/datum/life_system/breathing/carbon/human,
		/datum/life_system/mutations/carbon/human,
		/datum/life_system/radiation/carbon/human,
		/datum/life_system/blood/carbon/human,
		/datum/life_system/random_events/carbon/human,
		/datum/life_system/afk,
		/datum/life_system/chemicals/carbon/human,
		/datum/life_system/diseases/carbon,
		/datum/life_system/environment/carbon/human,
		/datum/life_system/ambience,
		/datum/life_system/movement,
		/datum/life_system/status/carbon/human,
		/datum/life_system/disabilities/carbon/human,
		/datum/life_system/addictions/carbon,
		/datum/life_system/canmove,
		/datum/life_system/hud/carbon/human,
		/datum/life_system/vision/carbon/human,
		/datum/life_system/tf_holder,
		/datum/life_system/vr_derez,
		/datum/life_system/germs,
		/datum/life_system/hud_refresh,
		/datum/life_system/voice,
		/datum/life_system/stasis_sleep,
		/datum/life_system/fall,
		/datum/life_system/gate/human_vitals,
		/datum/life_system/changeling,
		/datum/life_system/organs,
		/datum/life_system/thermoregulation,
		/datum/life_system/weight,
		/datum/life_system/shock,
		/datum/life_system/pain,
		/datum/life_system/medical,
		/datum/life_system/heartbeat,
		/datum/life_system/nif,
		/datum/life_system/phobias,
		/datum/life_system/npc,
		/datum/life_system/defib_timer,
		/datum/life_system/species_components,
		/datum/life_system/visible_name,
		/datum/life_system/pulse,
	)
	TEST_ASSERT(life_test_in_order(types, expected), "human systems are missing or out of order: [jointext(types, ", ")]")
	TEST_ASSERT(!(/datum/life_system/robot_power in types), "a human must not get robot systems")
	var/datum/life_composition/comp = H.life_composition
	TEST_ASSERT(get_life_system(/datum/life_system/canmove) in comp.derive, "canmove is a wake-only derivation")
	TEST_ASSERT(get_life_system(/datum/life_system/hud/carbon/human) in comp.present, "the human HUD is wake-only presentation")

/// Every human of a type shares one composition; a cyborg composes from the robot set only.
/datum/unit_test/dq_life_composition_is_shared

/datum/unit_test/dq_life_composition_is_shared/Run()
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(first.recompose_life(), second.recompose_life(), "two plain humans should share one composition")

	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/list/types = life_test_system_types(R)
	var/list/expected = list(
		/datum/life_system/robot_cycle,
		/datum/life_system/modifiers/silicon/robot,
		/datum/life_system/robot_senses,
		/datum/life_system/instability/silicon/robot,
		/datum/life_system/robot_power,
		/datum/life_system/robot_body,
		/datum/life_system/robot_interface,
		/datum/life_system/robot_alarms,
		/datum/life_system/canmove/silicon/robot,
	)
	TEST_ASSERT(life_test_in_order(types, expected), "robot systems are missing or out of order: [jointext(types, ", ")]")
	TEST_ASSERT_EQUAL(length(types), length(expected), "a robot should run only the robot set: [jointext(types, ", ")]")

/// A simple mob's subtype code runs as its own variant after the simple mob core.
/datum/unit_test/dq_life_simple_mob_variants

/datum/unit_test/dq_life_simple_mob_variants/Run()
	var/datum/life_system/post = resolve_life_system(/datum/life_system/type_post, /mob/living/simple_mob/animal/passive/chicken)
	TEST_ASSERT_EQUAL(post?.type, /datum/life_system/type_post/simple_mob/animal/passive/chicken, "a chicken should run its own post-core code")
	var/datum/life_system/special = resolve_life_system(/datum/life_system/special, /mob/living/simple_mob/slime/xenobio/amber)
	TEST_ASSERT_EQUAL(special?.type, /datum/life_system/special/slime/xenobio/amber, "an amber slime should run its own special behaviour")
	TEST_ASSERT_NULL(resolve_life_system(/datum/life_system/special, /mob/living/carbon/human), "humans have no simple mob special behaviour")

/// The alive gate blocks breathing for a dead body; a living body breathes on its cadence.
/datum/unit_test/dq_life_alive_gate_blocks_segment

/datum/unit_test/dq_life_alive_gate_blocks_segment/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/cycle_before = H.breath_cycle
	H.life_frame()
	TEST_ASSERT_NOTEQUAL(H.breath_cycle, cycle_before, "a living human's breathing system should advance its breath cadence")

	H.death()
	TEST_ASSERT_EQUAL(H.stat, DEAD, "the human should be dead for the gate check")
	cycle_before = H.breath_cycle
	var/life_tick_before = H.life_tick
	H.life_frame()
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a dead human must not run the alive-only breathing system")
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "a dead human still runs the rest of its frame")

/// The human pre code halts the whole frame while transforming, as the old early return did,
/// and a halted frame puts nothing to sleep.
/datum/unit_test/dq_life_transforming_human_halts

/datum/unit_test/dq_life_transforming_human_halts/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/life_tick_before = H.life_tick
	var/cycle_before = H.breath_cycle
	H.transforming = TRUE
	H.life_frame()
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before, "a transforming human must not tick")
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a transforming human must not breathe")
	TEST_ASSERT(!H.life_asleep_total, "a halted frame puts nothing to sleep")
	H.transforming = FALSE
	H.life_frame()
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "the human should tick again once the transformation ends")

/// A transforming simple mob still runs its upkeep (the systems before the transforming gate):
/// transformation is a gate, not a suspension (Codex bug: it halted all upkeep).
/datum/unit_test/dq_life_transforming_keeps_upkeep

/datum/unit_test/dq_life_transforming_keeps_upkeep/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_place(M), "no floor to place the test mouse on")
	M.add_life_system(/datum/life_system/trait/test_counter)
	var/datum/life_system/trait/test_counter/counter = get_life_system(/datum/life_system/trait/test_counter)
	M.transforming = TRUE
	M.life_frame()
	TEST_ASSERT_EQUAL(counter.runs["[REF(M)]"], 1, "trait systems (before the living segment) run while transforming")
	TEST_ASSERT(!M.life_asleep_total, "nothing sleeps in a frame the transforming gate stopped")
	TEST_ASSERT(!M.life_suspended(), "transforming is not a suspension")
	M.transforming = FALSE

/// A component-provided trait system joins the composition while the component is attached.
/datum/unit_test/dq_life_trait_system_follows_component

/datum/unit_test/dq_life_trait_system_follows_component/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.recompose_life()
	TEST_ASSERT(!(/datum/life_system/trait/photosynth in life_test_system_types(H)), "a plain human has no photosynthesis system")
	var/datum/component/photosynth/P = H.AddComponent(/datum/component/photosynth)
	TEST_ASSERT_NOTNULL(P, "the photosynthesis component should attach")
	var/list/types = life_test_system_types(H)
	TEST_ASSERT(/datum/life_system/trait/photosynth in types, "attaching the component should add its trait system")
	TEST_ASSERT(life_test_in_order(types, list(/datum/life_system/type_pre/carbon/human, /datum/life_system/trait/photosynth, /datum/life_system/upkeep)), "trait systems run where the old Life signal fired")
	qdel(P)
	TEST_ASSERT(!(/datum/life_system/trait/photosynth in life_test_system_types(H)), "removing the component should remove its trait system")

/// The per-system profiler accumulates sampled cost by system type; organs run once a frame.
/datum/unit_test/dq_life_system_profiler

/datum/unit_test/dq_life_system_profiler/Run()
	var/datum/life_system/S = get_life_system(/datum/life_system/upkeep)
	var/key = "[S.type]"
	var/calls_before = SSmobs.profile_system_calls[key] || 0
	SSmobs.record_system_cost(S, 1)
	TEST_ASSERT_EQUAL(SSmobs.profile_system_calls[key], calls_before + SSmobs.profile_sample_stride, "a sampled run should count stride calls")
	TEST_ASSERT(SSmobs.profile_system_cost[key] > 0, "a sampled run should add cost")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/upkeep_calls = SSmobs.profile_system_calls[key]
	var/organ_key = "[/datum/life_system/organs]"
	var/organ_calls = SSmobs.profile_system_calls[organ_key] || 0
	H.life_frame(TRUE)
	TEST_ASSERT_EQUAL(SSmobs.profile_system_calls[key], upkeep_calls + SSmobs.profile_sample_stride, "a profiled frame should record each system it ran")
	TEST_ASSERT_EQUAL(SSmobs.profile_system_calls[organ_key], organ_calls + SSmobs.profile_sample_stride, "a living human processes its organs once per frame")

/// Loose organs never join Life: no behaviour attaches to them (Codex bug: they rotted).
/datum/unit_test/dq_life_loose_organs_have_no_life

/datum/unit_test/dq_life_loose_organs_have_no_life/Run()
	var/obj/item/organ/internal/heart/heart = allocate(/obj/item/organ/internal/heart)
	TEST_ASSERT(!om_attached(heart, /datum/om/behaviour/life), "a loose organ has no life behaviour")
	TEST_ASSERT(!om_type_has_decl(heart.type), "organs have no object-model declaration")

// --- Scheduling ----------------------------------------------------------------------------

/// One frame per LIFE_CYCLE, carrying LIFE_CYCLE_SECONDS of dt-scaled time.
/datum/unit_test/life_om/cadence

/datum/unit_test/life_om/cadence/run_life()
	TEST_ASSERT(life_runlevel_active(), "unit tests run in a game runlevel (Life does not run in the lobby)")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT(om_attached(H, /datum/om/behaviour/life), "a living mob carries the life behaviour")
	scheduler_advance(LIFE_CYCLE_SECONDS)
	var/before = H.life_frame_count
	scheduler_advance(LIFE_CYCLE_SECONDS * 10)
	var/frames = H.life_frame_count - before
	TEST_ASSERT(frames >= 9 && frames <= 11, "expected 10 frames in 10 cycles, got [frames]")
	var/datum/life_context/ctx = new(LIFE_CYCLE_SECONDS)
	TEST_ASSERT_EQUAL(ctx.seconds, LIFE_CYCLE_SECONDS, "a frame covers one cycle of dt")

/// Skipped ticks: after a long gap the frame runs at most LIFE_MAX_CATCHUP times in one pass,
/// never skips the mob, and counts the dropped frames as breaches.
/datum/unit_test/life_om/catch_up_is_bounded

/datum/unit_test/life_om/catch_up_is_bounded/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	scheduler_advance(LIFE_CYCLE_SECONDS * 2)
	var/before = H.life_frame_count
	var/list/S = life_stats()
	var/breaches_before = S[OM_STAT_BREACHES]
	sched.jump(LIFE_CYCLE_SECONDS * 20)
	sched.run_pass(1e9)
	var/frames = H.life_frame_count - before
	TEST_ASSERT(frames >= 1, "a mob is never skipped after skipped ticks")
	TEST_ASSERT(frames <= LIFE_MAX_CATCHUP, "catch-up is capped at [LIFE_MAX_CATCHUP] frames per pass, ran [frames]")
	TEST_ASSERT(S[OM_STAT_BREACHES] > breaches_before, "dropped frames are counted as breaches")
	before = H.life_frame_count
	scheduler_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT((H.life_frame_count - before) <= 1, "after catching up, one frame per cycle again")

/// A healthy idle mob hibernates (off the ring); a change wakes it whole; the frame after a long
/// nap covers at most one cycle (Codex bug: the whole nap was passed as seconds).
/datum/unit_test/life_om/hibernation

/datum/unit_test/life_om/hibernation/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "an idle healthy mouse should hibernate; still busy: [life_test_busy(M)]")
	TEST_ASSERT(M in GLOB.life_hibernating_mobs, "a hibernating mob is listed")
	TEST_ASSERT_NULL(M.life_missed_wake(), "a freshly hibernated mob has no missed wake")
	// Only rewake timers bring a hibernating mob back (the simple mob environment's is 15 s);
	// between them it runs no frames.
	LAZYCLEARLIST(M.life_timers)
	M.life_arm_timer()
	var/before = M.life_frame_count
	scheduler_advance(LIFE_CYCLE_SECONDS * 20)
	TEST_ASSERT_EQUAL(M.life_frame_count, before, "a hibernating mob with no timer runs no frames")
	TEST_ASSERT(M.injure(INJURY_BLUNT, 1) > 0, "the injury should land")
	scheduler_advance(0.1)
	TEST_ASSERT(!M.life_hibernating, "injure() wakes a hibernating mob")
	TEST_ASSERT(!M.life_asleep_total, "a hibernating mob wakes whole")
	before = M.life_frame_count
	sched.run_pass(1e9)
	scheduler_advance(LIFE_CYCLE_SECONDS)
	TEST_ASSERT((M.life_frame_count - before) <= 1, "the first frame after a nap covers at most one cycle, ran [M.life_frame_count - before]")

/// A sleeping system wakes only on its own channels; a change raised during a frame keeps a
/// later system awake.
/datum/unit_test/life_om/channels_wake_systems

/datum/unit_test/life_om/channels_wake_systems/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.add_life_system(/datum/life_system/trait/test_sleeper)
	var/datum/life_system/trait/test_sleeper/S = get_life_system(/datum/life_system/trait/test_sleeper)
	var/index = H.recompose_life().ordered.Find(S)
	H.life_frame()
	// Keep ring frames out of the way: a human's own frame raises health changes.
	om_sleep(H, /datum/om/behaviour/life)
	scheduler_advance(0.1)
	// The frame's own changes may have woken it: put it back to sleep for the channel checks.
	H.life_put_asleep(index)
	TEST_ASSERT(H.life_is_asleep(index), "an idle system sleeps after its run")
	om_changed(H, CHANGE_MOB_EQUIPMENT)
	scheduler_advance(0.1)
	TEST_ASSERT(H.life_is_asleep(index), "a channel the system doesn't declare leaves it asleep")
	om_changed(H, CHANGE_MOB_HEALTH)
	scheduler_advance(0.1)
	TEST_ASSERT(!H.life_is_asleep(index), "its declared channel wakes it")
	var/runs = S.runs["[REF(H)]"]
	H.life_frame()
	TEST_ASSERT_EQUAL(S.runs["[REF(H)]"], runs + 1, "a woken system runs in the next frame")
	om_resume(H, /datum/om/behaviour/life)

	// A system early in the frame raises the channel; the later system sleeps at the frame's
	// end and is woken right back by the delivered change.
	H.add_life_system(/datum/life_system/trait/test_raiser)
	index = H.recompose_life().ordered.Find(S)
	H.life_frame()
	scheduler_advance(0.1)
	TEST_ASSERT(!H.life_is_asleep(index), "a change raised during the frame wakes the later system")

/// A timer wakes a hibernating mob partially: only the systems whose timers are due.
/datum/unit_test/life_om/timer_wakes_partially

/datum/unit_test/life_om/timer_wakes_partially/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	M.add_life_system(/datum/life_system/trait/test_timer)
	var/datum/life_system/trait/test_timer/S = get_life_system(/datum/life_system/trait/test_timer)
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	TEST_ASSERT(LAZYACCESS(M.life_timers, S), "the test system's timer is pending")
	var/due = M.life_timers[S]
	while(sched.now() <= due && M.life_hibernating)
		sched.manual_time += 1
		sched.run_pass(1e9)
	TEST_ASSERT(!M.life_hibernating, "the timer woke the mob")
	var/datum/life_composition/comp = M.life_composition
	var/awake = 0
	for(var/i in comp.sleepers)
		if(!M.life_is_asleep(i))
			awake++
			TEST_ASSERT_EQUAL(comp.ordered[i], S, "only the timed system wakes, not [comp.ordered[i]]")
	TEST_ASSERT_EQUAL(awake, 1, "exactly one system woke")

/// A rewake timer wakes an idle system by deadline, and the deadline never runs a frame on an
/// awake mob (Codex bug: +20-30% frames).
/datum/unit_test/life_om/timers_do_not_run_frames

/datum/unit_test/life_om/timers_do_not_run_frames/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.add_life_system(/datum/life_system/trait/test_timer)
	var/datum/life_system/trait/test_timer/S = get_life_system(/datum/life_system/trait/test_timer)
	var/index = H.recompose_life().ordered.Find(S)
	scheduler_advance(LIFE_CYCLE_SECONDS * 2)
	TEST_ASSERT(H.life_is_asleep(index), "the idle system sleeps")
	TEST_ASSERT(LAZYACCESS(H.life_timers, S), "with a timer pending")
	var/frames = H.life_frame_count
	var/datum/om/rec/rec = H.om_rec
	// Stop just after the timer is due and before the next frame.
	var/due = H.life_timers[S]
	var/slot_frames = frames
	sched.run_pass(1e9)
	while(sched.now() < due + 1)
		sched.manual_time += 1
		sched.run_pass(1e9)
		if(H.life_frame_count != slot_frames)
			// A frame came from the ring in the meantime: that's allowed, but track it.
			slot_frames = H.life_frame_count
	TEST_ASSERT(!H.life_is_asleep(index), "the timer woke the system")
	TEST_ASSERT(rec && !LAZYACCESS(H.life_timers, S), "the timer is consumed")
	TEST_ASSERT(slot_frames - frames <= 1, "the timer ran no extra frame")

/// Deleting a mob during its frame stops the frame at once; its deadlines are skipped.
/datum/unit_test/life_om/deletion_mid_frame

/datum/unit_test/life_om/deletion_mid_frame/run_life()
	var/mob/living/carbon/human/H = new(run_loc_floor_bottom_left)
	H.add_life_system(/datum/life_system/trait/test_timer)
	H.add_life_system(/datum/life_system/trait/test_deleter)
	H.add_life_system(/datum/life_system/trait/test_counter)
	var/datum/life_system/trait/test_counter/counter = get_life_system(/datum/life_system/trait/test_counter)
	var/datum/life_system/trait/test_timer/timer = get_life_system(/datum/life_system/trait/test_timer)
	H.life_wake_later(timer, 1 SECONDS)
	H.life_frame()
	TEST_ASSERT(QDELETED(H), "the deleter system deleted the mob")
	TEST_ASSERT(!counter.runs["[REF(H)]"], "no system runs on a deleted mob")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(length(sched.errors), 0, "no scheduler errors after deleting a mob with a pending deadline: [jointext(sched.errors, "; ")]")

/// Death wakes every system; the dead segments block; revival resumes the live ones.
/datum/unit_test/life_om/death_and_revive

/datum/unit_test/life_om/death_and_revive/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	M.death()
	scheduler_advance(0.1)
	TEST_ASSERT(!M.life_hibernating || M.stat == DEAD, "death is a stat change")
	var/before = M.life_frame_count
	M.life_frame()
	TEST_ASSERT_EQUAL(M.life_frame_count, before + 1, "a dead mob still runs its frame")
	M.revive()
	scheduler_advance(0.1)
	TEST_ASSERT(!M.life_hibernating, "revival wakes the mob")
	TEST_ASSERT_NOTEQUAL(M.stat, DEAD, "the mouse is alive again")

/// Suspension (absorbed prey, bodies kept for reforming) runs no frame until resumed.
/datum/unit_test/life_om/suspension

/datum/unit_test/life_om/suspension/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	scheduler_advance(LIFE_CYCLE_SECONDS)
	H.suspend_life()
	TEST_ASSERT(H.life_suspended(), "suspended")
	var/before = H.life_frame_count
	scheduler_advance(LIFE_CYCLE_SECONDS * 5)
	TEST_ASSERT_EQUAL(H.life_frame_count, before, "a suspended mob runs no frame")
	H.resume_life()
	scheduler_advance(LIFE_CYCLE_SECONDS * 2)
	TEST_ASSERT(H.life_frame_count > before, "a resumed mob runs again")

/// Stasis runs biology on the biology clock: deep stasis (0.9) one frame in ten, total stasis
/// never; the frame itself keeps running.
/datum/unit_test/life_om/stasis_clock

/datum/unit_test/life_om/stasis_clock/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.set_stasis(/datum/modifier/stasis/deep, src)
	TEST_ASSERT(abs(om_clock_rate_of(H, CLOCK_BIO) - 0.1) < 0.001, "deep stasis holds the biology clock at 0.1, got [om_clock_rate_of(H, CLOCK_BIO)]")
	var/biology = 0
	var/frames_before = H.life_frame_count
	for(var/i in 1 to 20)
		H.life_frame()
		if(!H.body.stasis_paused)
			biology++
	TEST_ASSERT_EQUAL(biology, 2, "deep stasis runs biology on 2 frames in 20")
	TEST_ASSERT_EQUAL(H.life_frame_count, frames_before + 20, "the frame itself keeps running in stasis")
	H.set_stasis(/datum/modifier/stasis/total, src)
	TEST_ASSERT_EQUAL(om_clock_rate_of(H, CLOCK_BIO), 0, "total stasis stops the biology clock")
	biology = 0
	for(var/i in 1 to 10)
		H.life_frame()
		if(!H.body.stasis_paused)
			biology++
	TEST_ASSERT_EQUAL(biology, 0, "total stasis never runs biology")
	H.set_stasis(null, src)
	TEST_ASSERT_EQUAL(om_clock_rate_of(H, CLOCK_BIO), 1, "leaving stasis restores the clock")
	H.life_frame()
	TEST_ASSERT(!H.body.stasis_paused, "biology runs every frame again")

/// Stun, weaken and paralysis are timed contributions: durations in LIFE_CYCLE units, exact
/// set and adjust semantics, and canmove follows at once.
/datum/unit_test/life_om/statuses_are_contributions

/datum/unit_test/life_om/statuses_are_contributions/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	// Statuses end in real time on their own: no frame is needed (or wanted: a test human's
	// own frames can knock it out and hide canmove).
	H.suspend_life()
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(H.has_status(EFFECT_STUNNED), "status_at_least() applies EFFECT_STUNNED")
	TEST_ASSERT(om_has(H, EFFECT_STUNNED), "as a contribution")
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_STUNNED), 2, "two units left")
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

/// Wake-only presentation is not started for clientless mobs; a status change runs the canmove
/// derivation in the same pass.
/datum/unit_test/life_om/wake_only_systems

/datum/unit_test/life_om/wake_only_systems/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT(om_attached(H, /datum/om/behaviour/life_present), "every living mob carries the present behaviour")
	TEST_ASSERT(!life_test_started(H, /datum/om/behaviour/life_present), "a clientless mob does not start it")
	TEST_ASSERT(life_test_started(H, /datum/om/behaviour/life_derive), "the derive behaviour runs for every mob")
	H.status_set(EFFECT_SLEEPING, 2)
	H.canmove = TRUE
	om_changed(H, CHANGE_MOB_STATUS)
	scheduler_advance(0.1)
	TEST_ASSERT(!H.canmove, "a status change ran the canmove derivation without a frame")
	H.status_set(EFFECT_SLEEPING, 0)

/// Ghosts, AI eyes and the blob overmind run their upkeep on their own behaviour.
/datum/unit_test/life_om/observer_upkeep

/datum/unit_test/life_om/observer_upkeep/run_life()
	var/mob/observer/dead/life_test/G = allocate(/mob/observer/dead/life_test)
	TEST_ASSERT(om_attached(G, /datum/om/behaviour/observer_upkeep), "observers carry the upkeep behaviour")
	scheduler_advance(OBSERVER_UPKEEP_INTERVAL / 10 * 3)
	TEST_ASSERT(G.upkeeps >= 2, "observer upkeep runs on its cadence, ran [G.upkeeps]")

/// The frame sampler samples by a global frame counter, so every mob is sampled at the same rate
/// (Codex bug: sampling bias from a run list that restarted each cycle).
/datum/unit_test/life_om/sampler_is_uniform

/datum/unit_test/life_om/sampler_is_uniform/run_life()
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(A) && life_test_place(B), "no floor to place the test humans on")
	var/key = "[A.type]"
	var/calls_before = SSmobs.profile_type_calls[key] || 0
	var/frames_before = GLOB.life_frames
	scheduler_advance(LIFE_CYCLE_SECONDS * SSmobs.profile_sample_stride)
	var/frames = GLOB.life_frames - frames_before
	var/sampled = ((SSmobs.profile_type_calls[key] || 0) - calls_before) / SSmobs.profile_sample_stride
	TEST_ASSERT(frames >= SSmobs.profile_sample_stride, "enough frames ran to sample: [frames]")
	TEST_ASSERT(abs(sampled - frames / SSmobs.profile_sample_stride) <= 1, "one frame in [SSmobs.profile_sample_stride] is sampled: [sampled] of [frames]")

// --- Hibernation producers and the audit ----------------------------------------------------------

/// A reagent entering a hibernating mob wakes it.
/datum/unit_test/life_om/reagent_wakes

/datum/unit_test/life_om/reagent_wakes/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	if(!M.reagents)
		M.create_reagents(30)
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	M.reagents.add_reagent(REAGENT_ID_WATER, 5)
	scheduler_advance(0.1)
	TEST_ASSERT(!M.life_hibernating, "adding a reagent should wake a hibernating mob")

/// A stun wakes the mob; once it wears off the mob hibernates again.
/datum/unit_test/life_om/stun_wakes_then_rehibernates

/datum/unit_test/life_om/stun_wakes_then_rehibernates/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	M.status_at_least(EFFECT_STUNNED, 3)
	TEST_ASSERT_EQUAL(M.status_units(EFFECT_STUNNED), 3, "the stun should land")
	scheduler_advance(0.1)
	TEST_ASSERT(!M.life_hibernating, "a stun should wake a hibernating mob")
	scheduler_advance(LIFE_CYCLE_SECONDS * 3 + 1)
	TEST_ASSERT_EQUAL(M.status_units(EFFECT_STUNNED), 0, "the stun should have worn off")
	scheduler_advance(LIFE_CYCLE_SECONDS * 4)
	TEST_ASSERT(M.life_hibernating, "the mouse should hibernate again once the stun wears off; still busy: [life_test_busy(M)]")

/// A client logging in wakes the whole mob.
/datum/unit_test/life_om/client_login_wakes

/datum/unit_test/life_om/client_login_wakes/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	// /mob/living/Login() calls this hook; a unit test has no client to log in with.
	M.on_client_changed("login")
	scheduler_advance(0.1)
	TEST_ASSERT(!M.life_hibernating, "a login should wake a hibernating mob")
	TEST_ASSERT(!M.life_asleep_total, "a login wakes every system")

/// The hibernation audit finds a change made without raising its channel, logs it and wakes
/// the mob.
/datum/unit_test/life_om/audit_catches_missed_wake

/datum/unit_test/life_om/audit_catches_missed_wake/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	TEST_ASSERT_NULL(SSmobs.audit_mob(M), "the audit must not flag a mob that is correctly asleep")
	// A deliberately missed wake: write state a sleeping system reads (healing ears) without
	// raising a channel.
	M.ear_damage = 50
	TEST_ASSERT(M.life_hibernating, "a direct write must not wake the mob (that is the bug the audit catches)")
	var/missed_before = SSmobs.hibernation_audit_missed
	var/datum/life_system/S = SSmobs.audit_mob(M, expected = TRUE)
	TEST_ASSERT_NOTNULL(S, "the audit should find the system with pending work")
	TEST_ASSERT_EQUAL(SSmobs.hibernation_audit_missed, missed_before + 1, "the audit should count the missed wake")
	TEST_ASSERT(!M.life_hibernating, "the audit should wake the mob")
	M.ear_damage = 0

// --- Statuses, immunity and the frame's own changes (doc/rewrite/life_on_om.md §7) --------------

/// Every former counter is a timed status: it ends by deadline, in its own units per cycle, with
/// no frame running; the magnitude statuses read back in points.
/datum/unit_test/life_om/statuses_expire_by_deadline

/datum/unit_test/life_om/statuses_expire_by_deadline/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.suspend_life()
	var/frames_before = H.life_frame_count
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
	TEST_ASSERT_EQUAL(H.life_frame_count, frames_before, "no frame ran: nothing counts statuses down")

	// Hallucination wore off two points per cycle.
	H.status_at_least(EFFECT_HALLUCINATING, 10)
	scheduler_advance(LIFE_CYCLE_SECONDS * 2 + 0.1)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_HALLUCINATING), 6, "hallucination: 2 points per cycle")

	// Dizziness: 3 points per cycle, 15 while resting, capped at 1000.
	H.status_adjust(EFFECT_DIZZY, 5000)
	TEST_ASSERT_EQUAL(H.status_units(EFFECT_DIZZY), 1000, "dizziness is capped at 1000 points")
	TEST_ASSERT_NOTNULL(H.GetComponent(/datum/component/dizzy_shake), "the shake follows the status")
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
	TEST_ASSERT_NULL(H.GetComponent(/datum/component/dizzy_shake), "the shake ends with the status")

	// Alerts follow the status, with no system maintaining them.
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
	H.suspend_life()
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

	// Godmode holds all three; removing it releases only its own holds.
	var/datum/other = new /datum
	om_hold(H, EFFECT_IMMUNE_WEAKEN, other)
	H.AddElement(/datum/element/godmode)
	H.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(!H.has_status(EFFECT_STUNNED), "godmode blocks stuns")
	H.RemoveElement(/datum/element/godmode)
	TEST_ASSERT(!H.status_immune(EFFECT_STUNNED), "ending godmode ends its stun immunity")
	TEST_ASSERT(H.status_immune(EFFECT_WEAKENED), "but not another source's immunity (the old flags were cleared wholesale)")
	qdel(other)

	// Mob types declare theirs (an unbrained test AI deletes itself, so its table is checked).
	var/mob/living/simple_mob/animal/sif/leech/leech = allocate(/mob/living/simple_mob/animal/sif/leech)
	TEST_ASSERT(leech.status_immune(EFFECT_STUNNED) && leech.status_immune(EFFECT_WEAKENED) && leech.status_immune(EFFECT_PARALYZED), "leeches are immune to incapacitation by declaration")
	leech.status_at_least(EFFECT_STUNNED, 2)
	TEST_ASSERT(!leech.has_status(EFFECT_STUNNED), "so a stun doesn't land")
	var/list/ai_table = om_registry().type_table(/mob/living/silicon/ai).self_effects
	TEST_ASSERT((EFFECT_IMMUNE_WEAKEN in ai_table) && !(EFFECT_IMMUNE_STUN in ai_table), "the AI can be stunned but not knocked down")
	TEST_ASSERT(EFFECT_IMMUNE_DIZZY in om_registry().type_table(/mob/living/silicon/robot).self_effects, "silicons don't get dizzy")

/// Voluntary sleep is a hold: no dose wearing off or ending wakes the mob; choosing to wake does.
/datum/unit_test/life_om/voluntary_sleep

/datum/unit_test/life_om/voluntary_sleep/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.suspend_life()
	H.set_voluntary_sleep(TRUE)
	TEST_ASSERT(H.sleeping_voluntarily(), "sleeping by choice")
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "the hold is the sleep status")
	TEST_ASSERT(H.status_units(EFFECT_SLEEPING) >= 1, "a held status reads at least one unit")
	H.status_at_least(EFFECT_SLEEPING, 1)
	scheduler_advance(LIFE_CYCLE_SECONDS * 3)
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "a dose wearing off doesn't wake a voluntary sleeper")
	H.status_set(EFFECT_SLEEPING, 0)
	TEST_ASSERT(H.has_status(EFFECT_SLEEPING), "nor does ending the dose")
	H.set_voluntary_sleep(FALSE)
	TEST_ASSERT(!H.has_status(EFFECT_SLEEPING), "choosing to wake ends it")
	TEST_ASSERT(!H.alerts?["asleep"], "and its alert")

/// A status change raises CHANGE_MOB_STATUS once (the effect's own channel; the old setters raised
/// it a second time), and a change that doesn't change the value raises nothing.
/datum/unit_test/life_om/status_raises_once

/datum/unit_test/life_om/status_raises_once/run_life()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	H.suspend_life()
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

/// Life never wakes itself: a frame on a mob with running statuses raises no status change (the
/// old statuses system decremented counters and woke the mob every frame), so a sleeping mouse
/// hibernates like an idle one.
/datum/unit_test/life_om/no_self_wake

/datum/unit_test/life_om/no_self_wake/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	M.status_set(EFFECT_SLEEPING, 100)
	M.status_at_least(EFFECT_CONFUSED, 100)
	sched.run_pass(1e9)
	sched.test_raises = list()
	M.life_frame()
	TEST_ASSERT_EQUAL(life_test_status_raises(sched, M), 0, "a frame raises no status change on its own mob")
	sched.test_raises = null
	TEST_ASSERT(life_test_settle(M), "a sleeping, confused mouse hibernates; still busy: [life_test_busy(M)]")
	TEST_ASSERT(M.has_status(EFFECT_SLEEPING), "and stays asleep while hibernating")

/// Hibernation hysteresis: a mob hibernates only after LIFE_HIBERNATE_IDLE_FRAMES frames in a row
/// end with nothing awake; a wake in between starts the count again.
/datum/unit_test/life_om/hibernate_hysteresis

/datum/unit_test/life_om/hibernate_hysteresis/run_life()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	om_changed(M, CHANGE_EXPLICIT)
	sched.run_pass(1e9)
	TEST_ASSERT(!M.life_hibernating, "a change wakes it")
	var/frames = 0
	while(!M.life_all_asleep() && frames < 6)
		M.life_frame()
		sched.run_pass(1e9)
		frames++
	TEST_ASSERT(M.life_all_asleep(), "its systems go back to sleep; still busy: [life_test_busy(M)]")
	TEST_ASSERT(!M.life_hibernating, "one idle frame doesn't hibernate it")
	TEST_ASSERT_EQUAL(M.life_idle_frames, 1, "one idle frame counted")
	om_changed(M, CHANGE_MOB_HEALTH)
	sched.run_pass(1e9)
	TEST_ASSERT_EQUAL(M.life_idle_frames, 0, "a wake between idle frames starts the count again")
	frames = 0
	while(!M.life_hibernating && frames < 6)
		M.life_frame()
		sched.run_pass(1e9)
		frames++
	TEST_ASSERT(M.life_hibernating, "it hibernates after idle frames in a row")
	TEST_ASSERT(frames >= LIFE_HIBERNATE_IDLE_FRAMES, "and not before [LIFE_HIBERNATE_IDLE_FRAMES] of them, took [frames]")

/// Changes to `E` logged on `sched.test_raises` that carry CHANGE_MOB_STATUS.
/proc/life_test_status_raises(datum/om/scheduler/sched, datum/E)
	. = 0
	for(var/list/entry as anything in sched.test_raises)
		if(entry[1] == E && (entry[2] & CHANGE_MOB_STATUS))
			.++

#endif

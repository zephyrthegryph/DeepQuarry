// Unit tests for the Life scheduler (doc/mob_life_architecture.md §4 and §9): life system
// families and variants, composition, segments and halts, trait systems, life_wake(), the
// per-system profiler, and hibernation with its producers and audit.

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

/// The names of a composition's systems, in run order.
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
		/datum/life_system/statuses,
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
		/datum/life_system/statuses/silicon/robot,
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
	H.Life()
	TEST_ASSERT_NOTEQUAL(H.breath_cycle, cycle_before, "a living human's breathing system should advance its breath cadence")

	H.death()
	TEST_ASSERT_EQUAL(H.stat, DEAD, "the human should be dead for the gate check")
	cycle_before = H.breath_cycle
	var/life_tick_before = H.life_tick
	H.Life()
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a dead human must not run the alive-only breathing system")
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "a dead human still runs the rest of its cycle")

/// The human pre code halts the whole cycle while transforming, as the old early return did.
/datum/unit_test/dq_life_transforming_human_halts

/datum/unit_test/dq_life_transforming_human_halts/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/life_tick_before = H.life_tick
	var/cycle_before = H.breath_cycle
	H.transforming = TRUE
	H.Life()
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before, "a transforming human must not tick")
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a transforming human must not breathe")
	H.transforming = FALSE
	H.Life()
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "the human should tick again once the transformation ends")

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

/// life_wake() sets awake bits; a sleeping system is skipped; a mob with nothing awake
/// hibernates and life_wake() brings it back whole.
/datum/unit_test/dq_life_wake_and_hibernation

/datum/unit_test/dq_life_wake_and_hibernation/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	TEST_ASSERT_EQUAL(H.life_awake, LIFE_SYS_ALL, "every system starts awake")
	H.life_awake &= ~LIFE_SYS_BREATHING
	var/cycle_before = H.breath_cycle
	H.Life()
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a sleeping breathing system must not run")
	H.life_wake(LIFE_SYS_BREATHING, "test")
	TEST_ASSERT(H.life_awake & LIFE_SYS_BREATHING, "life_wake() should set the breathing bit")
	H.Life()
	TEST_ASSERT_NOTEQUAL(H.breath_cycle, cycle_before, "a woken breathing system runs again")

	H.life_awake = NONE
	H.Life()
	TEST_ASSERT(H.life_hibernating, "a mob with no awake systems hibernates (MOB_HIBERNATION_ENABLED)")
	TEST_ASSERT(H in SSmobs.hibernating_mobs, "a hibernating mob is parked in SSmobs")
	H.life_wake(LIFE_SYS_BREATHING, "test")
	TEST_ASSERT(!H.life_hibernating, "life_wake() unparks the mob")
	TEST_ASSERT(!(H in SSmobs.hibernating_mobs), "a woken mob leaves the parked list")
	TEST_ASSERT_EQUAL(H.life_awake, LIFE_SYS_ALL, "a hibernating mob wakes whole")

/// The per-system profiler accumulates sampled cost by system type.
/datum/unit_test/dq_life_system_profiler

/datum/unit_test/dq_life_system_profiler/Run()
	var/datum/life_system/S = get_life_system(/datum/life_system/upkeep)
	var/key = "[S.type]"
	var/calls_before = SSmobs.profile_system_calls[key] || 0
	SSmobs.record_system_cost(S, 1)
	TEST_ASSERT_EQUAL(SSmobs.profile_system_calls[key], calls_before + SSmobs.profile_sample_stride, "a sampled run should count stride calls")
	TEST_ASSERT(SSmobs.profile_system_cost[key] > 0, "a sampled run should add cost")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/upkeep_calls = SSmobs.profile_system_calls[key]
	H.Life(LIFE_NOMINAL_SECONDS, TRUE)
	TEST_ASSERT_EQUAL(SSmobs.profile_system_calls[key], upkeep_calls + SSmobs.profile_sample_stride, "a profiled Life should record each system it ran")

// --- Hibernation (doc/mob_life_architecture.md §4.9) --------------------------------------

/// A mouse that can hibernate: placed on a floor, its AI asleep, and its environment limits
/// opened so the test floor's air can't hurt it.
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

/// Runs Life() until the mob hibernates, at most `cycles` times. Returns TRUE if it did.
/proc/life_test_settle(mob/living/L, cycles = 6)
	for(var/i in 1 to cycles)
		if(L.life_hibernating)
			return TRUE
		L.Life()
	return L.life_hibernating

/// Names of the systems that would keep this mob awake, for failure messages.
/proc/life_test_busy(mob/living/L)
	var/list/names = list()
	var/datum/life_composition/comp = L.life_composition || L.recompose_life()
	for(var/datum/life_system/S as anything in comp.ordered)
		if(S.bit != LIFE_SYS_GATE && L.life_system_wants_run(S))
			names += "[S.type]"
	return jointext(names, ", ")

/// A healthy idle mob puts every system to sleep and leaves the SSmobs run.
/datum/unit_test/dq_life_idle_mob_hibernates

/datum/unit_test/dq_life_idle_mob_hibernates/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "an idle healthy mouse should hibernate; still busy: [life_test_busy(M)]; awake bits [M.life_awake]")
	TEST_ASSERT(M in SSmobs.hibernating_mobs, "a hibernating mob is parked in SSmobs")
	TEST_ASSERT_NULL(M.life_missed_wake(), "a freshly hibernated mob has no missed wake")

/// injure() wakes a hibernating mob.
/datum/unit_test/dq_life_injure_wakes

/datum/unit_test/dq_life_injure_wakes/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	TEST_ASSERT(M.injure(INJURY_BLUNT, 1) > 0, "the injury should land")
	TEST_ASSERT(!M.life_hibernating, "injure() should wake a hibernating mob")
	TEST_ASSERT(M.life_awake & LIFE_SYS_BODY, "injure() should wake the body systems")
	M.Life()
	TEST_ASSERT(!M.life_hibernating, "an injured mob stays awake while its body has afflictions")

/// A reagent entering a hibernating mob wakes it.
/datum/unit_test/dq_life_reagent_wakes

/datum/unit_test/dq_life_reagent_wakes/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	if(!M.reagents)
		M.create_reagents(30)
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	M.reagents.add_reagent(REAGENT_ID_WATER, 5)
	TEST_ASSERT(!M.life_hibernating, "adding a reagent should wake a hibernating mob")
	TEST_ASSERT(M.life_awake & LIFE_SYS_METABOLISM, "a reagent should wake metabolism")

/// A stun wakes the mob; once it wears off the mob hibernates again.
/datum/unit_test/dq_life_stun_wakes_then_rehibernates

/datum/unit_test/dq_life_stun_wakes_then_rehibernates/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	M.status_flags |= CANSTUN
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	M.Stun(3)
	TEST_ASSERT_EQUAL(M.stunned, 3, "the stun should land")
	TEST_ASSERT(!M.life_hibernating, "Stun() should wake a hibernating mob")
	M.Life()
	TEST_ASSERT(!M.life_hibernating, "a stunned mob stays awake while the stun runs")
	TEST_ASSERT(life_test_settle(M, 12), "the mouse should hibernate again once the stun wears off; still busy: [life_test_busy(M)]; stunned [M.stunned]")
	TEST_ASSERT_EQUAL(M.stunned, 0, "the stun should have worn off")

/// A client logging in wakes the whole mob.
/datum/unit_test/dq_life_client_login_wakes

/datum/unit_test/dq_life_client_login_wakes/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	// /mob/living/Login() calls this hook; a unit test has no client to log in with.
	M.on_client_changed("login")
	TEST_ASSERT(!M.life_hibernating, "a login should wake a hibernating mob")
	TEST_ASSERT_EQUAL(M.life_awake, LIFE_SYS_ALL, "a login wakes every system")

/// The hibernation audit finds a change made without life_wake(), logs it and wakes the mob.
/datum/unit_test/dq_life_audit_catches_missed_wake

/datum/unit_test/dq_life_audit_catches_missed_wake/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_idle_mouse(M), "no floor to place the test mouse on")
	TEST_ASSERT(life_test_settle(M), "the mouse should hibernate first; still busy: [life_test_busy(M)]")
	TEST_ASSERT_NULL(SSmobs.audit_mob(M), "the audit must not flag a mob that is correctly asleep")
	// A deliberately missed wake: write the counter directly instead of calling Stun().
	M.stunned = 3
	TEST_ASSERT(M.life_hibernating, "a direct write must not wake the mob (that is the bug the audit catches)")
	var/missed_before = SSmobs.hibernation_audit_missed
	var/datum/life_system/S = SSmobs.audit_mob(M, expected = TRUE)
	TEST_ASSERT_NOTNULL(S, "the audit should find the system with pending work")
	TEST_ASSERT_EQUAL(S.bit, LIFE_SYS_STATUS, "the statuses system should be the one flagged, got [S?.type]")
	TEST_ASSERT_EQUAL(SSmobs.hibernation_audit_missed, missed_before + 1, "the audit should count the missed wake")
	TEST_ASSERT(!M.life_hibernating, "the audit should wake the mob")

#endif

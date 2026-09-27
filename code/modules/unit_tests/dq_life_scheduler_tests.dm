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
		/datum/life_system/chemicals/carbon/human,
		/datum/life_system/diseases/carbon,
		/datum/life_system/environment/carbon/human,
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
	var/datum/object_model/archetype/A = om_archetype_for(H.type, H)
	TEST_ASSERT(/datum/object_model/behaviour/living_afk in A.behaviours, "human archetype has the AFK behaviour")
	TEST_ASSERT(/datum/object_model/behaviour/living_ambience in A.behaviours, "human archetype has the ambience behaviour")
	TEST_ASSERT(/datum/object_model/behaviour/living_life_frame in A.behaviours, "human archetype has the scheduled Life frame")

/datum/unit_test/dq_life_scheduled_frame

/datum/unit_test/dq_life_scheduled_frame/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(H)
	TEST_ASSERT_NOTNULL(R, "living mob has a behaviour runtime")
	var/before = H.life_tick
	R.wake(/datum/object_model/behaviour/living_life_frame)
	R.run_ready()
	TEST_ASSERT_EQUAL(H.life_tick, before + 1, "scheduled frame runs the ordered Life cycle")
	var/path = /datum/object_model/behaviour/living_life_frame
	TEST_ASSERT(R.run_shared[path], "active Life joins the shared cadence")
	if(H.life_timer_at)
		TEST_ASSERT_EQUAL(R.run_due?[path], H.life_timer_at, "only a requested deferred wake arms an owner deadline")
	else
		TEST_ASSERT_NULL(R.run_due?[path], "ordinary cadence does not arm an owner deadline")
	H.life_awake = NONE
	om_behaviour_wake(H, /datum/object_model/behaviour/living_life_frame)
	R.run_ready()
	TEST_ASSERT(H.life_hibernating, "the scheduled frame hibernates when no systems remain awake")
	TEST_ASSERT(!R.run_shared[path], "hibernation leaves the shared cadence")
	if(H.life_timer_at)
		TEST_ASSERT_EQUAL(R.run_due[/datum/object_model/behaviour/living_life_frame], H.life_timer_at, "hibernation retains only the requested deferred wake")
	else
		TEST_ASSERT_NULL(R.run_due[/datum/object_model/behaviour/living_life_frame], "hibernation removes the frame deadline")
	R.run_last[/datum/object_model/behaviour/living_life_frame] = world.time - 30 SECONDS
	H.life_wake(LIFE_SYS_BREATHING, "test")
	TEST_ASSERT(R.run_pending[/datum/object_model/behaviour/living_life_frame], "producer wake requeues a hibernating frame")
	TEST_ASSERT_NULL(R.run_last[/datum/object_model/behaviour/living_life_frame], "waking after a nap discards elapsed sleep time")

/// Ordinary Life cadence is shared; only explicit owner deadlines allocate wheel tokens.
/datum/unit_test/dq_life_shared_cadence

/datum/unit_test/dq_life_shared_cadence/Run()
	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human)
	var/path = /datum/object_model/behaviour/living_life_frame
	var/datum/object_model/behaviour_runtime/RA = om_behaviour_start(A)
	var/datum/object_model/behaviour_runtime/RB = om_behaviour_start(B)
	var/datum/reactor_shared_cadence/G = SSreactor.shared_cadence_groups[path]
	TEST_ASSERT_NOTNULL(G, "Life has a shared cadence group")
	TEST_ASSERT(RA.run_shared[path] && RB.run_shared[path], "both mobs join the cadence group")
	TEST_ASSERT((RA in G.member_slots) && (RB in G.member_slots), "both runtimes share the same group")
	TEST_ASSERT_NULL(RA.run_timer_id, "first mob has no recurring wheel token")
	TEST_ASSERT_NULL(RB.run_timer_id, "second mob has no recurring wheel token")
	RA.schedule_at(path, world.time + 1 SECONDS)
	TEST_ASSERT(isnum(RA.run_timer_id), "exact per-mob deadline still uses the native wheel")
	TEST_ASSERT_NULL(RB.run_timer_id, "another mob remains without a wheel token")

/// A hibernating mob's deferred system wake shares the scheduled frame's one deadline.
/datum/unit_test/dq_life_scheduled_deferred_wake

/datum/unit_test/dq_life_scheduled_deferred_wake/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(H)
	var/path = /datum/object_model/behaviour/living_life_frame
	if(R.run_pending)
		R.run_pending -= path
	H.life_awake = NONE
	H.life_hibernate("test")
	TEST_ASSERT(H.life_hibernating, "test mob entered hibernation")
	H.life_wake_in(LIFE_SYS_BREATHING, 5 SECONDS)
	var/first_due = H.life_timer_at
	H.life_wake_in(LIFE_SYS_STATUS, 10 SECONDS)
	TEST_ASSERT_EQUAL(H.life_timer_at, first_due, "later system wake leaves the earlier deadline armed")
	TEST_ASSERT_EQUAL(R.run_due[path], first_due, "deferred wake is armed on the behavior runtime")
	TEST_ASSERT_EQUAL(H.life_timer_bits & (LIFE_SYS_BREATHING | LIFE_SYS_STATUS), LIFE_SYS_BREATHING | LIFE_SYS_STATUS, "both system bits retain separate deadlines")
	R.cancel_deadline(path)
	H.life_timer_due[3] = world.time
	H.life_timer_at = world.time
	R.schedule_at(path, world.time)
	R.run_timer_fired()
	TEST_ASSERT(R.run_pending[path], "expired deadline queues a scheduled Life frame")
	var/previous_cycle = H.life_cycle
	R.run_ready()
	TEST_ASSERT_EQUAL(H.life_cycle, previous_cycle + 1, "due wake runs exactly one Life frame")
	TEST_ASSERT_EQUAL(H.life_timer_bits & (LIFE_SYS_BREATHING | LIFE_SYS_STATUS), LIFE_SYS_STATUS, "due wake keeps the later system asleep")
	TEST_ASSERT(H.life_timer_at > world.time, "later system retains its own deadline")

/// Producer wakes must not shift an already earlier scheduled frame or accumulate nap time.
/datum/unit_test/dq_life_scheduled_wake_deadline

/datum/unit_test/dq_life_scheduled_wake_deadline/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(H)
	var/path = /datum/object_model/behaviour/living_life_frame
	if(R.run_pending)
		R.run_pending -= path
	var/early_due = world.time + 1 SECONDS
	R.cancel_deadline(path)
	R.schedule_at(path, early_due)
	om_behaviour_wake(H, path)
	TEST_ASSERT_EQUAL(R.run_due[path], early_due, "change wake preserves an earlier Life deadline")
	if(!R.run_last)
		R.run_last = list()
	R.run_last[path] = world.time - 30 SECONDS
	H.life_hibernate("test")
	H.life_wake(LIFE_SYS_BREATHING, "test")
	TEST_ASSERT_NULL(R.run_last[path], "producer wake clears elapsed hibernation time")
	TEST_ASSERT_EQUAL(R.run_due[path], early_due, "producer wake retains the earlier deadline")

/// The reactor may fire while the mobs subsystem is paused by the master scheduler.
/datum/unit_test/dq_life_scheduled_runlevel_gate

/datum/unit_test/dq_life_scheduled_runlevel_gate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(H)
	var/path = /datum/object_model/behaviour/living_life_frame
	var/previous_can_fire = SSmobs.can_fire
	SSmobs.can_fire = FALSE
	var/previous_cycle = H.life_cycle
	R.wake(path)
	R.run_ready()
	var/blocked_cycle = H.life_cycle
	var/blocked_shared = R.run_shared[path]
	SSmobs.can_fire = previous_can_fire
	TEST_ASSERT_EQUAL(blocked_cycle, previous_cycle, "paused mobs subsystem prevents reactor Life runs")
	TEST_ASSERT(blocked_shared, "paused frame remains on the shared cadence")
	var/previous_runlevel = Master.current_runlevel
	Master.current_runlevel = 1 // RUNLEVEL_LOBBY, outside SSmobs' GAME/POSTGAME mask.
	om_behaviour_wake(H, path)
	R.run_ready()
	var/lobby_cycle = H.life_cycle
	var/lobby_shared = R.run_shared[path]
	Master.current_runlevel = previous_runlevel
	TEST_ASSERT_EQUAL(lobby_cycle, previous_cycle, "reactor Life does not run in the lobby")
	TEST_ASSERT(lobby_shared, "lobby-blocked frame remains on the shared cadence")

/// Exercise the actual Rust timer-wheel callback and DM behavior executor together.
/datum/unit_test/dq_life_scheduled_native_deadline

/datum/unit_test/dq_life_scheduled_native_deadline/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(H)
	var/path = /datum/object_model/behaviour/living_life_frame
	if(R.run_pending)
		R.run_pending -= path
	R.cancel_deadline(path)
	var/previous_cycle = H.life_cycle
	R.schedule_at(path, world.time + 2 * world.tick_lag)
	var/token = R.run_timer_id
	TEST_ASSERT(isnum(token), "scheduled Life has a native wheel token")
	react_test_ticks(6)
	TEST_ASSERT_EQUAL(H.life_cycle, previous_cycle + 1, "native deadline executes exactly one Life frame")

/// A deferred native wake and shared cadence slice may land on the same tick.
/datum/unit_test/dq_life_shared_native_collision

/datum/unit_test/dq_life_shared_native_collision/Run()
	var/path = /datum/object_model/behaviour/living_life_frame
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(first), "no floor to place the first test human on")
	var/datum/object_model/behaviour_runtime/first_runtime = om_behaviour_start(first)
	TEST_ASSERT(first_runtime.run_shared[path], "first human joined shared Life cadence")
	var/first_before = first.life_cycle
	first_runtime.schedule_at(path, world.time)
	var/first_token = first_runtime.run_timer_id
	first_runtime.run_shared_frame(path)
	TEST_ASSERT_EQUAL(first.life_cycle, first_before, "shared slice defers to the due native deadline")
	REACT_CANCEL(first_runtime, first_token)
	first_runtime.run_timer_fired()
	first_runtime.run_ready()
	TEST_ASSERT_EQUAL(first.life_cycle, first_before + 1, "native deadline runs exactly one frame after shared slice")

	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(second), "no floor to place the second test human on")
	var/datum/object_model/behaviour_runtime/second_runtime = om_behaviour_start(second)
	TEST_ASSERT(second_runtime.run_shared[path], "second human joined shared Life cadence")
	var/second_before = second.life_cycle
	second_runtime.schedule_at(path, world.time)
	var/second_token = second_runtime.run_timer_id
	REACT_CANCEL(second_runtime, second_token)
	second_runtime.run_timer_fired()
	second_runtime.run_ready()
	second_runtime.run_shared_frame(path)
	TEST_ASSERT_EQUAL(second.life_cycle, second_before + 1, "shared slice skips a frame already run by the native deadline")

/// The legacy nonliving roster keeps its original quota as it shrinks.
/datum/unit_test/dq_life_legacy_slice_budget

/datum/unit_test/dq_life_legacy_slice_budget/Run()
	var/list/old_legacy = SSmobs.legacy_mobs
	var/list/old_current = SSmobs.currentrun
	var/old_budget = SSmobs.legacy_slice_budget
	var/old_remaining = SSmobs.slice_budget_remaining
	var/old_slices_left = SSmobs.legacy_slices_left
	var/old_profile_index = SSmobs.profile_run_index
	var/old_cycle = SSmobs.life_cycle
	var/list/fixture = list()
	for(var/i in 1 to 64)
		fixture += i
	SSmobs.legacy_mobs = fixture
	SSmobs.currentrun = list()
	SSmobs.legacy_slices_left = 0
	var/fixed_quota = TRUE
	for(var/slice in 1 to SSmobs.life_slices)
		SSmobs.prepare_legacy_slice()
		if(SSmobs.slice_budget_remaining != 8)
			fixed_quota = FALSE
		SSmobs.currentrun.len = max(0, length(SSmobs.currentrun) - SSmobs.slice_budget_remaining)
	var/remaining_after_eight = length(SSmobs.currentrun)
	var/cycles_after_eight = SSmobs.life_cycle - old_cycle

	SSmobs.legacy_mobs = old_legacy
	SSmobs.currentrun = old_current
	SSmobs.legacy_slice_budget = old_budget
	SSmobs.slice_budget_remaining = old_remaining
	SSmobs.legacy_slices_left = old_slices_left
	SSmobs.profile_run_index = old_profile_index
	SSmobs.life_cycle = old_cycle
	TEST_ASSERT(fixed_quota, "each legacy slice retains the roster's original quota")
	TEST_ASSERT_EQUAL(remaining_after_eight, 0, "eight slices drain all 64 legacy entries")
	TEST_ASSERT_EQUAL(cycles_after_eight, 1, "eight slices are one logical legacy Life cycle")

/// Mob registration keeps living Life out of the legacy scan; observers retain it.
/datum/unit_test/dq_life_mob_partition_registration

/datum/unit_test/dq_life_mob_partition_registration/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/observer/O = allocate(/mob/observer)
	TEST_ASSERT(H in GLOB.mob_list, "living mob remains in the global mob registry")
	TEST_ASSERT(O in GLOB.mob_list, "observer remains in the global mob registry")
	TEST_ASSERT(H in SSmobs.pending_living, "living mob awaits scheduled Life startup")
	TEST_ASSERT(!(H in SSmobs.legacy_mobs), "living mob is excluded from legacy Life scan")
	TEST_ASSERT(O in SSmobs.legacy_mobs, "observer remains in legacy Life scan")
	TEST_ASSERT(!(O in SSmobs.pending_living), "observer is not queued for scheduled Life")
	SSmobs.pending_living -= H
	SSmobs.pending_living.Insert(1, H)
	SSmobs.start_pending_living()
	TEST_ASSERT(!(H in SSmobs.pending_living), "scheduled startup consumes the living pending entry")
	TEST_ASSERT_NOTNULL(H.om_state?.behaviour_runtime, "scheduled startup creates the living behavior runtime")
	TEST_ASSERT(!(H in SSmobs.legacy_mobs), "scheduled startup does not re-add living mobs to the legacy scan")
	SSmobs.unregister_mob(H)
	SSmobs.unregister_mob(O)
	var/living_registered = (H in SSmobs.pending_living) || (H in SSmobs.legacy_mobs) || (H in SSmobs.currentrun)
	var/observer_registered = (O in SSmobs.pending_living) || (O in SSmobs.legacy_mobs) || (O in SSmobs.currentrun)
	SSmobs.register_mob(H)
	SSmobs.register_mob(O)
	TEST_ASSERT(!living_registered, "unregistration removes living mob from every mobs subsystem queue")
	TEST_ASSERT(!observer_registered, "unregistration removes observer from every mobs subsystem queue")
	TEST_ASSERT(!(H in SSmobs.pending_living), "re-registering an active living runtime does not queue duplicate startup")
	TEST_ASSERT(O in SSmobs.legacy_mobs, "re-registering an observer restores the legacy queue")

/// A faster biology clock repeats affliction work without replaying the real frame.
/datum/unit_test/dq_life_biology_clock_catchup

/datum/unit_test/dq_life_biology_clock_catchup/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/dq_test_progressor, chest, 10)
	TEST_ASSERT_NOTNULL(A, "test affliction was not created")
	var/datum/source = allocate(/datum)
	var/domain = /datum/object_model/clock_domain/biology
	TEST_ASSERT(om_clock_set(H, domain, source, 2), "2x biology clock source was accepted")
	var/datum/object_model/clock_state/C = om_clock_for(H, domain)
	H.body.stasis_last_virtual = C.settle()
	C.last_world -= LIFE_NOMINAL_SECONDS SECONDS
	var/real_before = H.life_cycle
	var/biology_before = H.biological_cycle
	H.Life()
	TEST_ASSERT_EQUAL(H.life_cycle, real_before + 1, "2x clock runs one real Life frame")
	TEST_ASSERT_EQUAL(H.biological_cycle, biology_before + 2, "2x clock runs two biology steps")
	TEST_ASSERT(A.severity > 10 + 2 * AFFLICTION_BASE_PROGRESSION, "two biology steps progress the affliction twice")
	TEST_ASSERT(om_clock_set(H, domain, source, 0), "0x biology clock source was accepted")
	var/paused_severity = A.severity
	biology_before = H.biological_cycle
	real_before = H.life_cycle
	H.Life()
	TEST_ASSERT_EQUAL(H.life_cycle, real_before + 1, "0x biology still runs the real Life frame")
	TEST_ASSERT_EQUAL(H.biological_cycle, biology_before, "0x biology stops local progression")
	TEST_ASSERT_EQUAL(A.severity, paused_severity, "0x biology holds the affliction")
	TEST_ASSERT(om_clock_set(H, domain, source), "biology clock source was removed")
	H.Life()
	TEST_ASSERT_EQUAL(H.biological_cycle, biology_before + 1, "normal biology resumes one step per frame")
	TEST_ASSERT(A.severity > paused_severity, "affliction progresses after the clock resumes")

/// Species catch-up advances physiology while leaving visual state for the real frame.
/datum/unit_test/dq_life_species_biology_only

/datum/unit_test/dq_life_species_biology_only/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/species/spider/S = allocate(/datum/species/spider)
	H.bodytemperature = 150
	H.shock_stage = 0
	H.eye_blurry = 0
	S.environment_biology(H)
	TEST_ASSERT_EQUAL(H.shock_stage, 8, "extra spider biology advances cold shock")
	TEST_ASSERT_EQUAL(H.eye_blurry, 0, "extra spider biology does not replay blurry vision")
	S.environment_effects(H)
	TEST_ASSERT_EQUAL(H.shock_stage, 16, "normal environment frame retains cold shock")
	TEST_ASSERT_EQUAL(H.eye_blurry, 5, "normal environment frame updates blurry vision")

/// Simple mob catch-up keeps HUD and status alerts on the real frame.
/datum/unit_test/dq_life_simple_biology_only

/datum/unit_test/dq_life_simple_biology_only/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(life_test_place(M), "no floor to place the test mouse on")
	var/datum/life_system/simple_vitals/vitals = get_life_system(/datum/life_system/simple_vitals)
	var/datum/life_system/simple_healing/healing = get_life_system(/datum/life_system/simple_healing)
	var/datum/life_system/environment/simple_mob/environment = get_life_system(/datum/life_system/environment/simple_mob)
	TEST_ASSERT(vitals.biology_catchup && healing.biology_catchup && environment.biology_catchup, "simple physiology systems opt into catch-up")
	var/datum/life_context/ctx = new(LIFE_NOMINAL_SECONDS, FALSE)
	M.heal_countdown = 2
	M.nutrition = 200
	M.injure(INJURY_BLUNT, 5)
	healing.tick_biology(M, ctx)
	TEST_ASSERT_EQUAL(M.heal_countdown, 1, "first biology step advances passive healing countdown")
	healing.tick_biology(M, ctx)
	TEST_ASSERT_EQUAL(M.heal_countdown, 0, "second biology step advances passive healing countdown")
	vitals.tick_biology(M, ctx)
	TEST_ASSERT_EQUAL(ctx.core_result, M.stat < DEAD, "simple vitals biology gate follows the mob's actual status")
	TEST_ASSERT_EQUAL(!!(ctx.blocked & LIFE_SEG_SIMPLE), M.stat >= DEAD, "simple vitals biology gate blocks later systems only for a dead mob")

/// Disease stages advance on local biology steps without extra contagion rolls.
/datum/disease/dq_life_clock_test
	max_stages = 4
	stage_prob = 100
	disease_flags = NONE
	infectivity = 0

/datum/unit_test/dq_life_disease_biology_only

/datum/unit_test/dq_life_disease_biology_only/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/disease/dq_life_clock_test/D = allocate(/datum/disease/dq_life_clock_test)
	D.affected_mob = H
	H.addDisease(D)
	var/datum/life_system/diseases/carbon/S = get_life_system(/datum/life_system/diseases/carbon)
	TEST_ASSERT(S.biology_catchup, "disease system opts into local biology")
	S.tick_biology(H, new /datum/life_context(LIFE_NOMINAL_SECONDS, FALSE))
	TEST_ASSERT_EQUAL(D.stage, 2, "first local biology step advances disease stage")
	S.tick_biology(H, new /datum/life_context(LIFE_NOMINAL_SECONDS, FALSE))
	TEST_ASSERT_EQUAL(D.stage, 3, "second local biology step advances disease stage")

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
	H.set_transforming(TRUE)
	TEST_ASSERT(om_set_suspended(H, /datum/object_model/schedule_set/biology), "transformation holds the biology schedule")
	H.Life()
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before, "a transforming human must not tick")
	TEST_ASSERT_EQUAL(H.breath_cycle, cycle_before, "a transforming human must not breathe")
	H.set_transforming(FALSE)
	TEST_ASSERT(!om_set_suspended(H, /datum/object_model/schedule_set/biology), "ending transformation resumes the biology schedule")
	H.Life()
	TEST_ASSERT_EQUAL(H.life_tick, life_tick_before + 1, "the human should tick again once the transformation ends")

/// Independent transformation owners cannot release one another's schedule hold.
/datum/unit_test/dq_life_transforming_sources_stack

/datum/unit_test/dq_life_transforming_sources_stack/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/first = new
	var/datum/second = new
	H.set_transforming(TRUE, first)
	H.set_transforming(TRUE, second)
	H.set_transforming(FALSE, first)
	TEST_ASSERT(H.transforming, "a second transformation source keeps the mob held")
	TEST_ASSERT(om_set_suspended(H, /datum/object_model/schedule_set/biology), "biology remains suspended until every source releases")
	qdel(second)
	TEST_ASSERT(!H.transforming, "deleting the final source clears the transformation flag")
	TEST_ASSERT(!om_set_suspended(H, /datum/object_model/schedule_set/biology), "deleting the final source resumes biology")
	qdel(first)

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

/// Extra virtual biology steps advance physiology without replaying frame presentation.
/datum/unit_test/dq_life_biology_content_split

/datum/unit_test/dq_life_biology_content_split/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/datum/life_context/ctx = new(LIFE_NOMINAL_SECONDS, FALSE)
	ctx.biological_step = TRUE
	var/datum/life_system/pre = get_life_system(/datum/life_system/type_pre/carbon/human)
	var/datum/life_system/voice = get_life_system(/datum/life_system/voice)
	TEST_ASSERT(pre.biology_catchup, "human pre declares a biological catch-up hook")
	TEST_ASSERT(!voice.biology_catchup, "voice remains a real-frame system")
	H.blinded = 7
	var/before = H.life_tick
	pre.tick_biology(H, ctx)
	pre.tick_biology(H, ctx)
	TEST_ASSERT_EQUAL(H.life_tick, before + 2, "two virtual biology steps advance human life cadence twice")
	TEST_ASSERT_EQUAL(H.blinded, 7, "extra biology steps do not repeat blindness presentation reset")
	H.voice = "test voice"
	voice.tick_biology(H, ctx)
	TEST_ASSERT_EQUAL(H.voice, "test voice", "a default no-op hook does not repeat presentation")
	qdel(ctx)

#endif

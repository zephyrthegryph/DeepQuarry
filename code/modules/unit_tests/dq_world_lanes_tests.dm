// Fold wave F1 (doc/rewrite/completion_plan.md §3.6): SSmachines, SSmobs and SSplants are gone.
// Their world-level work runs as cadence behaviours on the OM global owner
// (code/datums/om/world_lanes.dm), their state lives on /datum/world_service singletons, and the
// growing-plant list is a registry. These tests prove the lanes are attached, run on their
// cadence, yield and resume, and that the per-object work still starts and parks.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The machine and mob lanes are attached to the live scheduler's global owner at the old
/// subsystems' cadence, and a real SSbehaviours pass runs them.
/datum/unit_test/dq_world_lanes_attached_and_run

/datum/unit_test/dq_world_lanes_attached_and_run/Run()
	var/datum/om/global_owner/owner = om_global_owner()
	TEST_ASSERT(om_attached(owner, /datum/om/behaviour/world/machines), "the machine lane is not on the global owner")
	TEST_ASSERT(om_attached(owner, /datum/om/behaviour/world/mobs), "the mob lane is not on the global owner")
	var/datum/om/behaviour/world/machines/M = om_registry().behaviour(/datum/om/behaviour/world/machines)
	var/datum/om/behaviour/world/mobs/B = om_registry().behaviour(/datum/om/behaviour/world/mobs)
	TEST_ASSERT_EQUAL(M.every, 2 SECONDS, "the machine lane lost SSmachines' 2 s cadence")
	TEST_ASSERT_EQUAL(B.every, 2 SECONDS, "the mob lane lost SSmobs' 2 s cadence")
	TEST_ASSERT_EQUAL(MACHINE_SERVICE_INTERVAL, 2 SECONDS, "machine timing no longer matches the lane")

	// A direct tick is one step.
	var/machine_steps = GLOB.machine_service.steps
	var/mob_steps = GLOB.mob_service.steps
	M.tick(owner, 2)
	B.tick(owner, 2)
	TEST_ASSERT(GLOB.machine_service.steps > machine_steps || GLOB.machine_service.resuming, "a machine lane tick did not step the machine service")
	TEST_ASSERT_EQUAL(GLOB.mob_service.steps, mob_steps + 1, "a mob lane tick did not step the mob service")

	// Outside a direct call, the scheduler must run them on its own, on cadence.
	if(!(Kernel.current_runlevel & (RUNLEVEL_GAME | RUNLEVEL_POSTGAME)))
		return
	machine_steps = GLOB.machine_service.steps
	mob_steps = GLOB.mob_service.steps
	var/deadline = REALTIMEOFDAY + 15 SECONDS
	while((GLOB.machine_service.steps <= machine_steps || GLOB.mob_service.steps <= mob_steps) && REALTIMEOFDAY < deadline)
		sleep(world.tick_lag)
	TEST_ASSERT(GLOB.machine_service.steps > machine_steps, "the scheduler never ran the machine lane")
	TEST_ASSERT(GLOB.mob_service.steps > mob_steps, "the scheduler never ran the mob lane")

/// A service whose step yields `yields` times before it completes.
/datum/world_service/dq_yield_probe
	name = "yield probe"
	var/yields = 0
	var/resumed_calls = 0

/datum/world_service/dq_yield_probe/service_step(resumed)
	if(resumed)
		resumed_calls++
	if(yields > 0)
		yields--
		return FALSE
	return TRUE

/// A yielding step stays in flight (resuming) and only counts as one completed step.
/datum/unit_test/dq_world_lanes_yield_resume

/datum/unit_test/dq_world_lanes_yield_resume/Run()
	var/datum/world_service/dq_yield_probe/S = new
	S.yields = 2
	TEST_ASSERT(!S.run_step(), "a yielding step reported completion")
	TEST_ASSERT(S.resuming, "a yielded step is not marked resuming")
	TEST_ASSERT(!S.run_step(), "the second slice should still yield")
	TEST_ASSERT(S.run_step(), "the last slice did not complete")
	TEST_ASSERT(!S.resuming, "a completed step is still resuming")
	TEST_ASSERT_EQUAL(S.steps, 1, "three slices of one step counted as more than one step")
	TEST_ASSERT_EQUAL(S.resumed_calls, 2, "the resumed slices were not told they resume")
	qdel(S)

/// The machine service's gas wake finishes the whole batch when unbudgeted, and its step
/// completes (gas wakes, pump commit, power) with a clean pump queue.
/datum/unit_test/dq_world_lanes_machine_step

/datum/unit_test/dq_world_lanes_machine_step/Run()
	var/datum/world_service/machines/S = GLOB.machine_service
	TEST_ASSERT(S.wake_dirty_gas_subscribers(), "an unbudgeted gas wake yielded")
	TEST_ASSERT_NULL(S.pending_dirty_gas_mixtures, "a completed gas wake kept its batch")
	var/was_resuming = S.resuming
	S.resuming = FALSE
	TEST_ASSERT(S.service_step(FALSE) || TICK_CHECK, "the machine step yielded with budget to spare")
	S.resuming = was_resuming
	TEST_ASSERT_EQUAL(length(S.pending_pump_transfers), 0, "the machine step left pump transfers uncommitted")

/// The mob service drains its death queue each step (the database insert runs off the lane).
/datum/unit_test/dq_world_lanes_mob_deaths

/datum/unit_test/dq_world_lanes_mob_deaths/Run()
	var/datum/world_service/mobs/S = GLOB.mob_service
	var/list/saved = S.death_list
	S.death_list = list(list("name" = "dq test"))
	S.service_step(FALSE)
	TEST_ASSERT_EQUAL(length(S.death_list), 0, "the mob step did not drain the death queue")
	S.death_list = saved

/// Growing plants join the growing-plant registry and the plant lane; removed, they leave both.
/datum/unit_test/dq_world_lanes_plants_registry

/datum/unit_test/dq_world_lanes_plants_registry/Run()
	TEST_ASSERT(GLOB.plant_service.initialized, "the plant service never initialized (SSplanets boot)")
	TEST_ASSERT(length(GLOB.plant_service.seeds), "the plant service has no seeds")
	// A seed with its growth stages resolved (a plant divides its health by them).
	var/datum/seed/grow_seed
	for(var/name in GLOB.plant_service.seeds)
		var/datum/seed/S = GLOB.plant_service.seeds[name]
		S.update_growth_stages()
		if(S.growth_stages > 0 && S.get_trait(TRAIT_ENDURANCE) > 0)
			grow_seed = S
			break
	TEST_ASSERT_NOTNULL(grow_seed, "no seed has growth stages")
	var/obj/effect/plant/P = allocate(/obj/effect/plant, run_loc_floor_bottom_left, grow_seed)
	GLOB.plant_service.add_plant(P)
	TEST_ASSERT(P in REGISTRY_MEMBERS(REGISTRY_GROWING_PLANTS), "add_plant() did not join the growing registry")
	TEST_ASSERT(P.periodic_pipe == PERIODIC_PLANTS, "add_plant() did not start the plant lane")
	GLOB.plant_service.remove_plant(P)
	TEST_ASSERT(!(P in REGISTRY_MEMBERS(REGISTRY_GROWING_PLANTS)), "remove_plant() left the growing registry")
	TEST_ASSERT_NULL(P.periodic_pipe, "remove_plant() did not stop the plant lane")

#endif

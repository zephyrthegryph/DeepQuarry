// Fold wave F1 (doc/rewrite/completion_plan.md §3.6): SSmachines, SSmobs and SSplants are gone.
// Their world-level work runs as kernel work items of systems (SSmachines, SSmobs), and the
// growing-plant list is a registry. These tests prove the steps finish, drain their queues, and
// that the per-object work still starts and parks.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The machine service's gas wake finishes the whole batch when unbudgeted, and its step
/// completes (gas wakes, pump commit, power) with a clean pump queue.
/datum/unit_test/dq_world_lanes_machine_step

/datum/unit_test/dq_world_lanes_machine_step/Run()
	var/datum/system/machines/S = SSmachines
	TEST_ASSERT(S.wake_dirty_gas_subscribers(), "an unbudgeted gas wake yielded")
	TEST_ASSERT_NULL(S.pending_dirty_gas_mixtures, "a completed gas wake kept its batch")
	TEST_ASSERT(S.step_machines(FALSE) || TICK_CHECK, "the machine step yielded with budget to spare")
	TEST_ASSERT_EQUAL(length(S.pending_pump_transfers), 0, "the machine step left pump transfers uncommitted")

/// The mob service drains its death queue each step (the database insert runs off the lane).
/datum/unit_test/dq_world_lanes_mob_deaths

/datum/unit_test/dq_world_lanes_mob_deaths/Run()
	var/datum/system/mobs/S = SSmobs
	var/list/saved = S.death_list
	S.death_list = list(list("name" = "dq test"))
	S.report_step(0)
	TEST_ASSERT_EQUAL(length(S.death_list), 0, "the mob step did not drain the death queue")
	S.death_list = saved

/// Growing plants join the growing-plant registry and the plant lane; removed, they leave both.
/datum/unit_test/dq_world_lanes_plants_registry

/datum/unit_test/dq_world_lanes_plants_registry/Run()
	TEST_ASSERT(SSplants.initialized, "the plant service never initialized (SSplanets boot)")
	TEST_ASSERT(length(SSplants.seeds), "the plant service has no seeds")
	// A seed with its growth stages resolved (a plant divides its health by them).
	var/datum/seed/grow_seed
	for(var/name in SSplants.seeds)
		var/datum/seed/S = SSplants.seeds[name]
		S.update_growth_stages()
		if(S.growth_stages > 0 && S.get_trait(TRAIT_ENDURANCE) > 0)
			grow_seed = S
			break
	TEST_ASSERT_NOTNULL(grow_seed, "no seed has growth stages")
	var/obj/effect/plant/P = allocate(/obj/effect/plant, run_loc_floor_bottom_left, grow_seed)
	SSplants.add_plant(P)
	TEST_ASSERT(P in REGISTRY_MEMBERS(REGISTRY_GROWING_PLANTS), "add_plant() did not join the growing registry")
	TEST_ASSERT(P.growing && every_running(P), "add_plant() did not arm the plant every()")
	SSplants.remove_plant(P)
	TEST_ASSERT(!(P in REGISTRY_MEMBERS(REGISTRY_GROWING_PLANTS)), "remove_plant() left the growing registry")
	TEST_ASSERT(!P.growing && !every_running(P), "remove_plant() did not park the plant every()")

#endif

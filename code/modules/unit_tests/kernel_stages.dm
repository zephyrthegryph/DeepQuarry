// Stages and per-entity loops on the kernel: the periodic cadences and the hotspot burn are kernel work now, and every
// stage still on the object-model engine can be adapted into a work item the kernel's graph validator accepts.

/// How far from the burning tile the hotspot test restores air and floor heat (the burn's hot gas and fire spread past the first few tiles).
#define KERNEL_HOTSPOT_TEST_REACH 8

/// A hotspot burns as a kernel work item (every SSair tick) in the game run level, and leaves the membership when it
/// is deleted.
/datum/unit_test/kernel_hotspot_work

/// Puts out whatever the hotspot test's burn spread around `T` and cools the floors it heated. The test is the only thing burning in the world.
/proc/kernel_hotspot_test_cleanup(turf/T)
	for(var/obj/effect/hotspot/fire in world)
		qdel(fire)
	for(var/turf/open/near in range(KERNEL_HOTSPOT_TEST_REACH, T))
		near.active_hotspot = null
		heat_set_solid(near, T20C)

/datum/unit_test/kernel_hotspot_work/Run()
	var/datum/controller/kernel/K = kernel()
	var/turf/simulated/T
	for(var/turf/simulated/sim_turf in world)
		if(sim_turf.air)
			T = sim_turf
			break
	TEST_ASSERT_NOTNULL(T, "no simulated turf for the hotspot test")
	if(T.active_hotspot)
		qdel(T.active_hotspot)
		T.active_hotspot = null
	// The world's first simulated turf is also where the atmos tests look for clear floor. The burn heats its air, its neighbours' and its floor,
	// and spreads fire to the tiles around it that goes on burning after this hotspot is gone. None of that is for a later test to inherit: the air
	// goes back through the atmos snapshot at teardown, the fire and the floors' heat in the deferred cleanup.
	for(var/turf/open/near in range(KERNEL_HOTSPOT_TEST_REACH, T))
		dq_atmos_test_snapshot_air(near)
	defer_cleanup(null, GLOBAL_PROC_REF(kernel_hotspot_test_cleanup), T)
	var/datum/gas_mixture/air = T.return_air()
	air.adjust_gas(/datum/gas/plasma, 20)
	air.adjust_gas(/datum/gas/oxygen, 50)
	heat_set(air, PLASMA_MINIMUM_BURN_TEMPERATURE + 300, HEAT_SOURCE_OTHER)
	T.hotspot_expose(PLASMA_MINIMUM_BURN_TEMPERATURE + 300, CELL_VOLUME, soh = TRUE)
	var/obj/effect/hotspot/H = T.active_hotspot
	TEST_ASSERT_NOTNULL(H, "no hotspot to burn")
	var/datum/work_item/W = K.work_by_key["/obj/effect/hotspot:burn_tick"]
	TEST_ASSERT(W, "the hotspot's every() registered a kernel work item")
	TEST_ASSERT_EQUAL(W.interval, 0.5 SECONDS, "the burn keeps SSair's cadence")
	TEST_ASSERT_EQUAL(W.lane, LANE_SIMULATION, "the burn is simulation work")
	TEST_ASSERT(W.members && member_is(W.members, H), "a hotspot joins the work item's membership when it appears")
	var/runs_before = W.member_runs
	sleep(2 SECONDS)
	if(!QDELETED(H))
		TEST_ASSERT(W.member_runs > runs_before, "the kernel stepped the hotspot")
		TEST_ASSERT(!H.just_spawned, "the hotspot's first step ran")
		qdel(H)
	T.active_hotspot = null
	TEST_ASSERT(!member_is(W.members, H), "a deleted hotspot left the membership")

/// Every stage still on the object-model engine adapts into a kernel work item, and the adapted graph (the stages'
/// after-edges within a phase) passes the same validator the boot DAG and the live work graph use: nothing missing,
/// no cycle, no edge into a later phase. This is the gate a pipeline passes before its stages move off the engine.
/datum/unit_test/kernel_stage_adapter_graph

/datum/unit_test/kernel_stage_adapter_graph/Run()
	var/datum/definition_registry/reg = definition_registry()
	var/adapted = 0
	var/with_reads = 0
	var/declared_reads = 0
	var/list/items = list()
	var/list/deps = list()
	var/list/missing = list()
	var/list/by_family = list()
	for(var/stage_type in reg.stage_by_type)
		var/datum/work_stage/T = reg.stage_by_type[stage_type]
		if(!T.pipeline || !T.family)
			continue
		var/datum/work_item/stage/W = stage_work_item(stage_type, null, 1 SECONDS)
		TEST_ASSERT(istype(W), "[stage_type] adapts")
		adapted++
		if(length(T.declared_reads()))
			declared_reads++
		if(length(W.reads))
			with_reads++
		TEST_ASSERT(W.phase == KERNEL_PHASE_P, "[stage_type] lands in phase P")
		items += W
		by_family["[T.pipeline]:[T.family]"] = W
	// The pipelines have all left the engine (intended_changes.md): an empty registry is the finished state, and the checks below are vacuous until a stage returns.
	log_test("kernel_stage_adapter_graph: [adapted] stage(s) still on the engine")
	TEST_ASSERT_EQUAL(with_reads, declared_reads, "declared reads carry over to the adapters (no stage left in the registry declares any once the AI stages are gone)")
	// The stage after-edges, within a pipeline, as work-item edges.
	for(var/datum/work_item/stage/W as anything in items)
		var/datum/work_stage/T = reg.stage_by_type[W.stage_type]
		var/list/edges = list()
		for(var/family in T.after)
			var/datum/work_item/stage/target = by_family["[T.pipeline]:[family]"]
			if(!target)
				missing += "[W.stage_type]: after [family], which is no family of [T.pipeline]"
				continue
			if(target != W)
				edges += target
		deps[W] = edges
	var/datum/graph_check/G = graph_validate(items, deps, missing)
	TEST_ASSERT_EQUAL(length(G.errors), 0, "the adapted stage graph has errors: [jointext(G.errors.Copy(1, min(length(G.errors), 6) + 1), "; ")]")
	TEST_ASSERT_EQUAL(length(G.order), length(items), "every adapted stage is ordered")

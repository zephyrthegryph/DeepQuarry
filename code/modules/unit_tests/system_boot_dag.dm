/// The boot DAG over mixed nodes: subsystems and systems (code/controllers/kernel/boot.dm).

// Fixtures: abstract_type names each type itself, so the kernel never instantiates or registers them.
/datum/system/test_boot_a
	abstract_type = /datum/system/test_boot_a
	needs = list(/datum/controller/subsystem/garbage)

/datum/system/test_boot_b
	abstract_type = /datum/system/test_boot_b
	needs = list(/datum/system/test_boot_a)

/datum/system/test_boot_c
	abstract_type = /datum/system/test_boot_c
	needs = list(/datum/system/test_boot_b, /datum/controller/subsystem/garbage)

/datum/system/test_boot_missing
	abstract_type = /datum/system/test_boot_missing
	needs = list(/datum/system/test_boot_a, /datum/system/test_boot_nonexistent)

/// Named by a need above; deliberately not a node in any graph.
/datum/system/test_boot_nonexistent
	abstract_type = /datum/system/test_boot_nonexistent

/datum/system/test_boot_cycle_x
	abstract_type = /datum/system/test_boot_cycle_x
	needs = list(/datum/system/test_boot_cycle_y)

/datum/system/test_boot_cycle_y
	abstract_type = /datum/system/test_boot_cycle_y
	needs = list(/datum/system/test_boot_cycle_x)

/datum/unit_test/system_boot_dag

/datum/unit_test/system_boot_dag/Run()
	var/datum/controller/subsystem/garbage/ss = SSgarbage
	var/datum/system/a = new /datum/system/test_boot_a
	var/datum/system/b = new /datum/system/test_boot_b
	var/datum/system/c = new /datum/system/test_boot_c
	TEST_ASSERT_NULL(system_table()[/datum/system/test_boot_a], "an abstract fixture must not register itself")

	// Mixed nodes: a subsystem and systems sort in one DAG, each after what it needs.
	var/list/type_to_node = list(
		/datum/controller/subsystem/garbage = ss,
		/datum/system/test_boot_a = a,
		/datum/system/test_boot_b = b,
		/datum/system/test_boot_c = c,
	)
	var/list/errors = list()
	var/list/systems = list(c, b, a)
	var/list/deps = kernel_system_deps(systems, type_to_node, errors)
	TEST_ASSERT_EQUAL(length(errors), 0, "resolvable needs raise no boot error: [jointext(errors, "; ")]")
	deps[ss] = list()
	var/list/nodes = list(ss) + systems
	var/list/order = boot_dependency_order(nodes, deps)
	TEST_ASSERT_EQUAL(length(order), 4, "every acyclic mixed node is ordered")
	TEST_ASSERT(order.Find(ss) < order.Find(a), "a system boots after the subsystem it needs")
	TEST_ASSERT(order.Find(a) < order.Find(b), "b after a")
	TEST_ASSERT(order.Find(b) < order.Find(c), "c after b")
	TEST_ASSERT_EQUAL(kernel_system_stage(c, deps), ss.init_stage, "a system boots in the stage of its latest subsystem need")

	// A need that names no node is a boot error, and the edge is dropped.
	var/datum/system/missing = new /datum/system/test_boot_missing
	errors = list()
	var/list/missing_deps = kernel_system_deps(list(missing), type_to_node, errors)
	TEST_ASSERT_EQUAL(length(errors), 1, "a missing need is one boot error")
	TEST_ASSERT_EQUAL(length(missing_deps[missing]), 1, "the resolvable need survives")

	// A cycle among systems is reported and leaves the cycle unordered.
	var/datum/system/x = new /datum/system/test_boot_cycle_x
	var/datum/system/y = new /datum/system/test_boot_cycle_y
	var/list/cycle_types = list(
		/datum/system/test_boot_cycle_x = x,
		/datum/system/test_boot_cycle_y = y,
	)
	var/list/cycle_deps = kernel_system_deps(list(x, y), cycle_types, list())
	var/list/cycle = list()
	var/list/cycle_order = boot_dependency_order(list(x, y), cycle_deps, cycle)
	TEST_ASSERT_EQUAL(length(cycle_order), 0, "cycle members are left out of the order")
	TEST_ASSERT(length(cycle) >= 3, "the cycle is reported as a closed path")

	// The live boot.
	TEST_ASSERT_NULL(Master.boot_dependency_cycle, "boot dependency cycle: [Master.boot_dependency_cycle]")
	TEST_ASSERT_EQUAL(length(Master.boot_errors), 0, "boot errors: [jointext(Master.boot_errors, "; ")]")
	var/list/registered = kernel_systems()
	TEST_ASSERT(length(registered) > 0, "the kernel registers the world services")
	for(var/datum/system/S as anything in registered)
		if(!S.boots_in_dag())
			continue
		TEST_ASSERT(S.initialized, "[S.type] boots in the DAG but never initialized")
		for(var/need in S.needs)
			if(ispath(need, /datum/controller/subsystem))
				var/datum/controller/subsystem/needed
				for(var/datum/controller/subsystem/candidate as anything in Master.subsystems)
					if(candidate.type == need)
						needed = candidate
						break
				TEST_ASSERT(needed, "[S.type] needs subsystem [need], which is not in the MC")
				TEST_ASSERT(needed.initialized, "[S.type] initialized before its need [need]")
			else
				TEST_ASSERT(ispath(need, /datum/system), "[S.type] needs [need], which is not a system")
				var/datum/system/dep = system_table()[need]
				TEST_ASSERT(dep?.initialized, "[S.type] needs [need], which never initialized")
	// A subsystem may depend on a system: SSatoms declares the two boots it used to do by hand.
	TEST_ASSERT(/datum/world_service/planets in SSatoms.dependencies, "SSatoms declares the planet service as a dependency")
	TEST_ASSERT(GLOB.planet_service.initialized && GLOB.transcore_service.initialized, "the services SSatoms depends on booted")
	for(var/datum/controller/subsystem/dependent as anything in Master.subsystems)
		for(var/dependency in dependent.dependencies)
			if(ispath(dependency, /datum/system))
				var/datum/system/booted = system_table()[dependency]
				TEST_ASSERT(booted?.initialized, "[dependent.type] depends on [dependency], which never initialized")
	// The hand roster and the registry agree: every roster service is a registered system.
	for(var/datum/world_service/W as anything in world_services())
		TEST_ASSERT_EQUAL(system_table()[W.type], W, "[W.type] is in world_services() but not the registry")
	// Members that joined during boot were released in the bulk pass.
	TEST_ASSERT(GLOB.machine_service.members_ready, "the boot pass runs on_members_ready() for the machine service")
	TEST_ASSERT(!GLOB.machine_first_wakes_bulk, "machine first wakes were flushed by on_members_ready()")

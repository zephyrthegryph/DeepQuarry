/// The boot DAG over mixed nodes: subsystems and systems (code/controllers/kernel/boot.dm).

// Fixtures: abstract_type names each type itself, so the kernel never instantiates or registers them.
/datum/system/test_boot_a
	abstract_type = /datum/system/test_boot_a
	needs = list(/datum/system/garbage)

/datum/system/test_boot_b
	abstract_type = /datum/system/test_boot_b
	needs = list(/datum/system/test_boot_a)

/datum/system/test_boot_c
	abstract_type = /datum/system/test_boot_c
	needs = list(/datum/system/test_boot_b, /datum/system/garbage)

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
	var/datum/system/garbage/ss = SSgarbage
	var/datum/system/a = new /datum/system/test_boot_a
	var/datum/system/b = new /datum/system/test_boot_b
	var/datum/system/c = new /datum/system/test_boot_c
	TEST_ASSERT_NULL(system_table()[/datum/system/test_boot_a], "an abstract fixture must not register itself")

	// Mixed nodes: a subsystem and systems sort in one DAG, each after what it needs.
	var/list/type_to_node = list(
		/datum/system/garbage = ss,
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
	TEST_ASSERT_EQUAL(kernel_system_stage(c, deps), ss.init_stage, "a system boots in the stage of its latest need")

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
	TEST_ASSERT_NULL(Kernel.boot_dependency_cycle, "boot dependency cycle: [Kernel.boot_dependency_cycle]")
	TEST_ASSERT_EQUAL(length(Kernel.boot_errors), 0, "boot errors: [jointext(Kernel.boot_errors, "; ")]")
	var/list/registered = kernel_systems()
	TEST_ASSERT(length(registered) > 0, "the kernel registers the world services")
	for(var/datum/system/S as anything in registered)
		if(!S.boots_in_dag())
			continue
		TEST_ASSERT(S.initialized, "[S.type] boots in the DAG but never initialized")
		for(var/need in S.needs)
			TEST_ASSERT(ispath(need, /datum/system), "[S.type] needs [need], which is not a system")
			var/datum/system/dep = system_table()[need]
			TEST_ASSERT(dep?.initialized, "[S.type] needs [need], which never initialized")
	// SSatoms declares the system boots it used to do by hand.
	TEST_ASSERT(/datum/system/planets in SSatoms.needs, "SSatoms declares the planet system as a need")
	TEST_ASSERT(SSplanets.initialized && SStranscore.initialized, "the services SSatoms needs booted")
	TEST_ASSERT(SSmachines in registered, "the machine service is in the derived list")
	TEST_ASSERT(SSmobs in registered, "the mob service is in the derived list")
	// Members that joined during boot were released in the bulk pass.
	TEST_ASSERT(SSmachines.members_ready, "the boot pass runs on_members_ready() for the machine service")

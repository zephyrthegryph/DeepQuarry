/// Boot on declared dependencies (code/controllers/boot_dependencies.dm).
/datum/unit_test/mc_boot_dependencies

/datum/unit_test/mc_boot_dependencies/Run()
	// Synthetic graph: a <- b <- c, a <- d; order must respect every edge.
	var/list/nodes = list("a", "b", "c", "d")
	var/list/deps = list("a" = list(), "b" = list("a"), "c" = list("b"), "d" = list("a"))
	var/list/cycle = list()
	var/list/order = boot_dependency_order(nodes, deps, cycle)
	TEST_ASSERT_EQUAL(length(order), 4, "every acyclic node is ordered")
	TEST_ASSERT_EQUAL(length(cycle), 0, "no cycle reported for an acyclic graph")
	TEST_ASSERT(order.Find("a") < order.Find("b"), "a before b")
	TEST_ASSERT(order.Find("b") < order.Find("c"), "b before c")
	TEST_ASSERT(order.Find("a") < order.Find("d"), "a before d")
	// Historical MC order (newest ready node first) is kept: a, d, b, c.
	TEST_ASSERT_EQUAL(jointext(order, ","), "a,d,b,c", "boot order unchanged from the MC's Kahn order")

	// Cycle x -> y -> z -> x, plus an independent w.
	nodes = list("w", "x", "y", "z")
	deps = list("w" = list(), "x" = list("z"), "y" = list("x"), "z" = list("y"))
	cycle = list()
	order = boot_dependency_order(nodes, deps, cycle)
	TEST_ASSERT_EQUAL(jointext(order, ","), "w", "only the acyclic node is ordered")
	TEST_ASSERT_EQUAL(length(cycle), 4, "cycle reported as a closed path")
	TEST_ASSERT_EQUAL(cycle[1], cycle[length(cycle)], "cycle path closes on itself")
	for(var/name in list("x", "y", "z"))
		TEST_ASSERT(name in cycle, "[name] named in the cycle")

	// The live boot: no cycle, and every declared dependency initialised first.
	TEST_ASSERT_NULL(Master.boot_dependency_cycle, "subsystem dependency cycle at boot: [Master.boot_dependency_cycle]")
	var/list/type_to_subsystem = list()
	for(var/datum/controller/subsystem/subsystem as anything in Master.subsystems)
		type_to_subsystem[subsystem.type] = subsystem
	for(var/datum/controller/subsystem/subsystem as anything in Master.subsystems)
		for(var/dependency_type in subsystem.dependencies)
			var/datum/controller/subsystem/dependency = type_to_subsystem[dependency_type]
			if(!dependency)
				continue
			TEST_ASSERT(dependency.init_order < subsystem.init_order, "[subsystem.type] initialised before its dependency [dependency_type]")

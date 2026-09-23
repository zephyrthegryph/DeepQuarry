// Profiling scenarios live in code/modules/benchmarks/ (the `bench` target).

/datum/unit_test/dq_lightweight_performance_diagnostics

/datum/unit_test/dq_lightweight_performance_diagnostics/Run()
	TEST_ASSERT(SSprofiler.can_fire, "Compact performance diagnostics were disabled with full AUTO_PROFILE")
	var/list/garbage = SSgarbage.performance_diagnostics()
	var/list/shuttles = SSshuttles.performance_diagnostics()
	var/list/radiation = SSradiation.performance_diagnostics()
	TEST_ASSERT(islist(garbage["queues"]), "Garbage diagnostics omitted queue depths")
	TEST_ASSERT(islist(garbage["top_destroy_types_ms"]), "Garbage diagnostics omitted Destroy cost attribution")
	TEST_ASSERT(islist(shuttles["work"]), "Shuttle diagnostics omitted work counters")
	TEST_ASSERT(islist(shuttles["top_type_cost_ms"]), "Shuttle diagnostics omitted type costs")
	TEST_ASSERT(islist(radiation["queue"]), "Radiation diagnostics omitted queue depth")
	TEST_ASSERT(islist(radiation["top_source_cost_ms"]), "Radiation diagnostics omitted source attribution")
	var/sequence_before = SSprofiler.diagnostic_sequence
	SSprofiler.fire()
	TEST_ASSERT_EQUAL(SSprofiler.diagnostic_sequence, sequence_before + 1, "Compact performance snapshot did not complete")

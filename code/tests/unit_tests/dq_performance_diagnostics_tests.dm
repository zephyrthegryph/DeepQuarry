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
	SSprofiler.sample_now()
	TEST_ASSERT_EQUAL(SSprofiler.diagnostic_sequence, sequence_before + 1, "Compact performance snapshot did not complete")

/// A sample is built over several turns (a stage, or a few ms of a table walk, each), and what it writes is one valid JSON record with the sections the readers expect.
/datum/unit_test/dq_profiler_sample_runs_in_turns

/datum/unit_test/dq_profiler_sample_runs_in_turns/Run()
	var/sequence_before = SSprofiler.diagnostic_sequence
	rel_clear(SSprofiler, nameof(SSprofiler.building))
	SSprofiler.sample(SSprofiler.wait)
	var/datum/profile_sample/S = SSprofiler.building
	TEST_ASSERT_NOTNULL(S, "the first turn leaves the sample unfinished")
	TEST_ASSERT_EQUAL(SSprofiler.diagnostic_sequence, sequence_before, "and nothing is recorded yet")
	var/guard = 0
	while(SSprofiler.building && guard++ < 500)
		SSprofiler.sample_continue()
	TEST_ASSERT(!SSprofiler.building, "the turns end")
	TEST_ASSERT_EQUAL(SSprofiler.diagnostic_sequence, sequence_before + 1, "with one record")
	TEST_ASSERT(SSprofiler.last_turns >= PROFILE_STAGE_WRITE, "taking at least a turn a stage ([SSprofiler.last_turns] turns)")
	var/list/record = json_decode(SSprofiler.last_record)
	TEST_ASSERT(islist(record), "the record is JSON")
	for(var/section in list("sequence", "subsystems", "atmos_arena", "rust_allocator", "rust_metrics", "attribution", "ledger", "players", "tick_usage"))
		TEST_ASSERT(!isnull(record[section]), "with its [section] section")
	TEST_ASSERT_EQUAL(record["sequence"], sequence_before + 1, "numbered in order")
	var/list/outside = record["ledger"]["outside"]
	TEST_ASSERT(!isnull(outside["post_recent_ms"]), "and the ledger's outside section carries the window since the sample before")

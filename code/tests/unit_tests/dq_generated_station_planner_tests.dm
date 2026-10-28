/datum/unit_test/dq_generated_station_planner_many_seeds

/datum/unit_test/dq_generated_station_planner_many_seeds/Run()
	var/datum/generated_station_planner/planner = new
	var/static/list/widths = list(80, 88, 96, 104)
	var/static/list/heights = list(80, 88, 96, 104)
	var/list/styles_seen = list()
	var/list/factions_seen = list()
	var/list/security_tiers_seen = list()
	var/datum/generated_station_prng/seed_stream = new(20260716)
	// Rust owns the exhaustive layout sweep; DM samples the serialized FFI
	// boundary broadly enough to cover every metadata/layout variant without
	// turning a focused integration test into hundreds of native jobs.
	for(var/sample in 1 to 32)
		var/seed = ((seed_stream.next() + sample) % 2147483646) + 1
		var/width = widths[((sample * 7) % length(widths)) + 1]
		var/height = heights[((sample * 11) % length(heights)) + 1]
		var/datum/generated_station_spec/spec = planner.plan(seed, width, height)
		var/config = "sample=[sample] seed=[seed] size=[width]x[height] style=[spec?.architecture_style] faction=[spec?.faction_id] security=[spec?.security_tier]"
		TEST_ASSERT_NOTNULL(spec, "Rust planner returned no station specification ([config]): [planner.error_message]")
		if(!spec)
			continue
		var/datum/generated_station_validation_result/result = spec.validate()
		if(!result.is_valid())
			for(var/datum/generated_station_validation_issue/issue in result.issues)
				TEST_FAIL("Generated station plan failed its data contract ([config]): [issue.code] at [issue.subject_id]: [issue.message]")
		TEST_ASSERT(result.is_valid(), "Generated station plan failed its data-contract validation ([config])")
		TEST_ASSERT_EQUAL(length(spec.departments), 7, "Generated station omitted a catalog department ([config])")
		styles_seen[spec.architecture_style] = TRUE
		factions_seen[spec.faction_id] = TRUE
		security_tiers_seen["[spec.security_tier]"] = TRUE
		var/list/territory_owners = list()
		for(var/datum/generated_station_layout_node/a in spec.layout_nodes)
			for(var/tile_key in a.territory)
				TEST_ASSERT(!territory_owners[tile_key], "Generated station assigned one tile to multiple departments ([config]; [tile_key] belongs to [territory_owners[tile_key]] and [a.id])")
				territory_owners[tile_key] = a.id
		qdel(result)
		qdel(spec)
	TEST_ASSERT_EQUAL(length(styles_seen), 3, "Pseudo-random plan sweep did not cover every architecture style")
	TEST_ASSERT_EQUAL(length(factions_seen), 4, "Pseudo-random plan sweep did not cover every faction: [json_encode(factions_seen)]")
	TEST_ASSERT_EQUAL(length(security_tiers_seen), 3, "Pseudo-random plan sweep did not cover every security tier")
	qdel(seed_stream)
	qdel(planner)

/datum/unit_test/dq_generated_station_planner_is_deterministic

/datum/unit_test/dq_generated_station_planner_is_deterministic/Run()
	var/datum/generated_station_planner/planner = new
	var/datum/generated_station_prng/seed_stream = new(20260717)
	var/seed = ((seed_stream.next() + 1) % 2147483646) + 1
	var/datum/generated_station_spec/first = planner.plan(seed, 88, 92)
	var/datum/generated_station_spec/second = planner.plan(seed, 88, 92)
	TEST_ASSERT_EQUAL(first.architecture_style, second.architecture_style, "Same seed changed architectural style")
	TEST_ASSERT_EQUAL(first.faction_id, second.faction_id, "Same seed changed station faction")
	TEST_ASSERT_EQUAL(first.security_tier, second.security_tier, "Same seed changed security tier")
	TEST_ASSERT(first.security_tier >= 1 && first.security_tier <= 3, "Planner emitted an invalid security tier")
	TEST_ASSERT_EQUAL(length(first.layout_nodes), length(second.layout_nodes), "Same seed produced a different node count")
	for(var/i in 1 to length(first.layout_nodes))
		var/datum/generated_station_layout_node/a = first.layout_nodes[i]
		var/datum/generated_station_layout_node/b = second.layout_nodes[i]
		TEST_ASSERT_EQUAL("[a.id]:[a.x],[a.y],[a.width],[a.height]", "[b.id]:[b.x],[b.y],[b.width],[b.height]", "Same seed produced different rectangle placement")
	qdel(first)
	qdel(second)
	qdel(seed_stream)
	qdel(planner)

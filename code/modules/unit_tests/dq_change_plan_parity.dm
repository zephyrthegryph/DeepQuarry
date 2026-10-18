// The change graph, step 2 (doc/rewrite/proposals/change_graph.md section 11): the generated plan answers "who reads this key" exactly as
// today's tables do, for every atom type, before step 3 moves the dispatch onto it and deletes them.
//
// Today's tables: GLOB.generated_draw_reads (derived_generated_draw_reads(): the nearest type up the chain with a row) and
// GLOB.generated_draw_hop_reads (the same walk). The plan: plan_of(), the nearest generated row. Keys: change_key_id() round-trips every name.

/datum/unit_test/dq_change_plan_parity

/// The nearest row of `table` for `type` (today's walk).
/proc/dq_plan_parity_nearest(list/table, type)
	var/path = type
	while(path)
		var/list/row = table?["[path]"]
		if(row)
			return row
		var/datum/typed = path
		path = initial(typed.parent_type)
	return null

/datum/unit_test/dq_change_plan_parity/Run()
	var/list/bad = list()
	var/checked = 0
	for(var/type in typesof(/atom))
		checked++
		var/list/plan = plan_of(type)
		var/list/plan_draw = list()
		var/list/plan_hop = list()
		for(var/key in plan)
			if(plan[key] & PLAN_DRAW)
				plan_draw += key
			if(plan[key] & PLAN_DRAW_HOP)
				plan_hop += key
		var/list/today_draw = dq_plan_parity_nearest(GLOB.generated_draw_reads, type) || list()
		var/list/today_hop = dq_plan_parity_nearest(GLOB.generated_draw_hop_reads, type) || list()
		if(length(plan_draw ^ today_draw))
			bad += "[type] draw: plan [json_encode(plan_draw - today_draw)] today [json_encode(today_draw - plan_draw)]"
		if(length(plan_hop ^ today_hop))
			bad += "[type] hop: plan [json_encode(plan_hop - today_hop)] today [json_encode(today_hop - plan_hop)]"
		if(length(bad) > 40)
			break
	log_test("change plan parity: [checked] atom types, [length(GLOB.generated_plans)] plan rows, [length(GLOB.generated_key_names)] build keys, [length(GLOB.generated_plan_fallbacks)] fallback types, [length(bad)] disagreement(s)")
	TEST_ASSERT(!length(bad), "the plan and today's draw tables disagree:\n[jointext(bad, "\n")]")
	// Keys: every build-time name is its CGK id, and a runtime-only key interns above the build range once.
	for(var/i in 1 to length(GLOB.generated_key_names))
		TEST_ASSERT_EQUAL(change_key_id(GLOB.generated_key_names[i]), i, "build key [GLOB.generated_key_names[i]] round-trips")
	var/runtime_id = change_key_id("dq_plan_parity_runtime_only_key")
	TEST_ASSERT(runtime_id > length(GLOB.generated_key_names), "a runtime-only key interns above the build range")
	TEST_ASSERT_EQUAL(change_key_id("dq_plan_parity_runtime_only_key"), runtime_id, "and keeps its id")
	TEST_ASSERT_EQUAL(change_key_name(runtime_id), "dq_plan_parity_runtime_only_key", "and names itself")
	GLOB.runtime_key_ids -= "dq_plan_parity_runtime_only_key"

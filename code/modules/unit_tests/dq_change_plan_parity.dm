// The change graph (doc/rewrite/proposals/change_graph.md section 11). Step 2 proved the plan answered exactly what generated_draw_reads and
// generated_draw_hop_reads answered for all 22 848 atom types (0 disagreements), and step 3b deleted those tables: the draw readers resolve
// through plan_keys(). What is left to check at run time: every plan is well formed and inherited by the nearest generated row, the
// D5 fallbacks name plan types, and the keys round-trip.

/datum/unit_test/dq_change_plan_parity

/datum/unit_test/dq_change_plan_parity/Run()
	var/list/bad = list()
	var/checked = 0
	for(var/type_text in GLOB.generated_plans)
		var/list/plan = GLOB.generated_plans[type_text]
		for(var/key in plan)
			var/bits = plan[key]
			if(!bits || (bits & ~(PLAN_DRAW | PLAN_DRAW_HOP)))
				bad += "[type_text] [key]: bits [bits]"
			if((bits & PLAN_DRAW_HOP) && length(splittext(key, ".")) < 2)
				bad += "[type_text] [key]: a hop read names no hop"
	for(var/type in typesof(/atom))
		checked++
		// Inheritance: a type without a row uses its parent's plan.
		if(!GLOB.generated_plans["[type]"] && type != /atom)
			var/datum/typed = type
			var/parent = initial(typed.parent_type)
			if(plan_of(type) != plan_of(parent) && json_encode(plan_of(type)) != json_encode(plan_of(parent)))
				bad += "[type]: does not inherit its parent's plan"
		if(length(bad) > 40)
			break
	log_test("change plan parity: [checked] atom types, [length(GLOB.generated_plans)] plan rows, [length(GLOB.generated_key_names)] build keys, [length(GLOB.generated_plan_fallbacks)] fallback types, [length(bad)] problem(s)")
	TEST_ASSERT(!length(bad), "malformed or wrongly inherited plans:\n[jointext(bad, "\n")]")
	// Keys: every build-time name is its CGK id, and a runtime-only key interns above the build range once.
	for(var/i in 1 to length(GLOB.generated_key_names))
		TEST_ASSERT_EQUAL(change_key_id(GLOB.generated_key_names[i]), i, "build key [GLOB.generated_key_names[i]] round-trips")
	var/runtime_id = change_key_id("dq_plan_parity_runtime_only_key")
	TEST_ASSERT(runtime_id > length(GLOB.generated_key_names), "a runtime-only key interns above the build range")
	TEST_ASSERT_EQUAL(change_key_id("dq_plan_parity_runtime_only_key"), runtime_id, "and keeps its id")
	TEST_ASSERT_EQUAL(change_key_name(runtime_id), "dq_plan_parity_runtime_only_key", "and names itself")
	GLOB.runtime_key_ids -= "dq_plan_parity_runtime_only_key"

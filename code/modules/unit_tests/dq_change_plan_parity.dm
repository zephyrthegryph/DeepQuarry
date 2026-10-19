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

/// A drawn fixture with no capabilities: its draw reads `lit`; `spare` is read by nothing that refreshes on the draw bit.
/obj/dq_plan_lamp
	icon = 'icons/obj/lighting.dmi'
	icon_state = "lamp0"
	var/lit = FALSE
	var/spare = 0

/obj/dq_plan_lamp/draw(datum/look/look)
	..()
	if(lit)
		look.state("lamp1")

/// Step 3c: a write the plan says no draw or verb output reads skips the redraw; one it reads still redraws.
/datum/unit_test/dq_change_plan_narrows_redraw

/datum/unit_test/dq_change_plan_narrows_redraw/Run()
	var/obj/dq_plan_lamp/L = allocate(/obj/dq_plan_lamp, test_floor())
	refresh_flush()
	TEST_ASSERT("lit" in plan_keys(/obj/dq_plan_lamp, PLAN_DRAW), "the generated plan holds the draw's read: [json_encode(plan_of(/obj/dq_plan_lamp))]")
	TEST_ASSERT(!derived_is_exact(L), "the fixture declares no dependencies (the plan is what narrows it)")
	state_changed(L, CHANGE_EXPLICIT, nameof(/obj/dq_plan_lamp::spare))
	TEST_ASSERT(!(L.refresh_queued & DEP_DRAW), "a write nothing drawn reads queues no redraw (queued: [L.refresh_queued])")
	refresh_flush()
	state_changed(L, CHANGE_EXPLICIT, nameof(/obj/dq_plan_lamp::lit))
	TEST_ASSERT(L.refresh_queued & DEP_DRAW, "a write the draw reads queues the redraw")
	refresh_flush()
	// The verb tables are well formed: type text -> a list of var names.
	for(var/table in list(GLOB.generated_plan_hidden_verbs, GLOB.generated_plan_granted_verbs))
		for(var/type_text in table)
			TEST_ASSERT(islist(table[type_text]), "[type_text]: a verb plan row is a list")

/// Step 5: a machine whose look is look layers and capabilities is narrowed by what those read; a var they read still redraws.
/datum/unit_test/dq_change_plan_narrows_layers

/datum/unit_test/dq_change_plan_narrows_layers/Run()
	var/obj/machinery/floodlight/M = allocate(/obj/machinery/floodlight, test_floor())
	refresh_flush()
	var/list/presented = plan_presentation_reads(M)
	log_test("narrows layers: [M.type] presentation reads [json_encode(presented)], derived exact [derived_is_exact(M)], activations [length(M.rx?.activations)]; [GLOB.plan_spared_writes] write(s) spared a redraw so far this round; stat layer asked [GLOB.stat_input_queries] time(s), [GLOB.stat_input_noops] for nothing")
	if(derived_is_exact(M))
		return // a type with declared dependencies is narrowed by its derived table, not here
	TEST_ASSERT(!isnull(presented), "the floodlight's layers and capabilities have known reads")
	TEST_ASSERT(!plan_spares_draw(M, "stat") || !("stat" in presented), "a var the layers read is never spared")
	TEST_ASSERT(plan_spares_draw(M, nameof(/atom::desc)), "a var nothing drawn reads is spared")

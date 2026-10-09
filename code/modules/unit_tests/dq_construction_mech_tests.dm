// Mech/fighter/micro-mech chassis construction: every blueprint walks its full parts phase and ladder forward to the finished
// mecha, and its reversible steps go back with the same materials and state. Driven with clicks; state is read from the chassis.
//
// Helpers reused from dq_construction_tests.dm: dq_materials_on, dq_materials_equal, dq_fast_tool, dq_fueled_welder.

/// The chassis type whose blueprint is `blueprint_path`, or null.
/datum/unit_test/proc/mech_chassis_type_for(blueprint_path)
	for(var/obj/item/mecha_parts/path as anything in subtypesof(/obj/item/mecha_parts))
		if(initial(path.blueprint) == blueprint_path)
			return path
	return null

/// A snapshot of dq_materials_on() as text, for a failure message.
/proc/dq_materials_text(list/materials)
	var/list/parts = list()
	for(var/type in materials)
		parts += "[type] x[materials[type]]"
	return jointext(parts, ", ")

/// One of each tool quality the mecha ladders use, sitting on `T`, zero-speed and fuelled.
/datum/unit_test/proc/mech_make_tools(turf/T)
	. = list()
	.[TOOL_WELDER] = dq_fueled_welder(T)
	.[TOOL_WRENCH] = dq_fast_tool(/obj/item/tool/wrench, T)
	.[TOOL_SCREWDRIVER] = dq_fast_tool(/obj/item/tool/screwdriver, T)
	.[TOOL_WIRECUTTER] = dq_fast_tool(/obj/item/tool/wirecutters, T)
	.[TOOL_CROWBAR] = dq_fast_tool(/obj/item/tool/crowbar, T)

/// The actor takes `held` into the active hand, ready to click.
/datum/unit_test/proc/mech_take(mob/living/carbon/human/actor, obj/item/held)
	if(actor.get_active_hand() != held)
		if(actor.get_active_hand())
			actor.drop_item()
		actor.put_in_active_hand(held)
	actor.next_click = 0

/// The actor uses `held` on `target` and the time it takes passes.
/datum/unit_test/proc/mech_use(mob/living/carbon/human/actor, atom/target, obj/item/held)
	mech_take(actor, held)
	test_click(actor, target, held)
	test_time(10 SECONDS)

/// The actor takes the stage they stand at back with `held`, picking the undo from the chassis's menu: the tool that undoes a step is often the one that
/// builds the next, and a click gives that build first (a player takes the way back from the menu then).
/datum/unit_test/proc/mech_undo(mob/living/carbon/human/actor, atom/target, obj/item/held)
	mech_take(actor, held)
	test_menu(actor, target, "construction.undo:[stage_key(graph_current(target))]")
	test_time(10 SECONDS)

/// What a step keyed `key` needs held: a tool from `tools`, or the item/stack made fresh on `T`.
/datum/unit_test/proc/mech_held_for(key, list/tools, turf/T)
	if(istext(key))
		return tools[key]
	if(ispath(key, /obj/item/stack))
		return allocate(key, T, ispath(key, /obj/item/stack/cable_coil) ? 4 : 5)
	return allocate(key, T)

/// Attaches every part of `blueprint` to `chassis`.
/datum/unit_test/proc/mech_attach_all_parts(mob/living/carbon/human/actor, obj/item/mecha_parts/chassis, datum/mecha_blueprint/blueprint, turf/T)
	for(var/part_type in blueprint.mecha_parts)
		var/before = chassis.parts_mask
		mech_use(actor, chassis, allocate(part_type, T))
		TEST_ASSERT(chassis.parts_mask != before, "[blueprint.id]: attaching [part_type] succeeds")

/// Builds a fresh chassis for `blueprint_path`, attaches its parts, and returns it (a finished shell).
/datum/unit_test/proc/mech_fresh_shell(mob/living/carbon/human/actor, blueprint_path, turf/T)
	var/chassis_type = mech_chassis_type_for(blueprint_path)
	if(!chassis_type)
		return null
	var/obj/item/mecha_parts/chassis = allocate(chassis_type, T)
	mech_attach_all_parts(actor, chassis, mecha_blueprint_of(blueprint_path), T)
	return chassis

/// Walks the first `steps` forward steps (all of them when null). Returns the number taken.
/datum/unit_test/proc/mech_walk_forward(mob/living/carbon/human/actor, obj/item/mecha_parts/chassis, datum/mecha_blueprint/blueprint, list/tools, turf/T, steps)
	var/count = length(blueprint.ladder)
	var/taken = 0
	for(var/i in 1 to (isnull(steps) ? count : steps))
		if(QDELETED(chassis))
			break
		var/list/row = blueprint.ladder[count - i + 1]
		var/stage_before = graph_current(chassis)
		mech_use(actor, chassis, mech_held_for(row["key"], tools, T))
		if(!QDELETED(chassis) && graph_current(chassis) == stage_before)
			break
		taken++
	return taken

// ---- Full builds: parts, then every forward ladder step, to the finished mecha ----

/datum/unit_test/proc/mech_full_build(blueprint_path)
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode()
	var/list/tools = mech_make_tools(T)
	var/datum/mecha_blueprint/blueprint = mecha_blueprint_of(blueprint_path)
	var/obj/item/mecha_parts/chassis = mech_fresh_shell(H, blueprint_path, T)
	TEST_ASSERT(chassis, "[blueprint_path]: a chassis exists")
	if(!chassis)
		return
	TEST_ASSERT_EQUAL(chassis.icon_state, "[blueprint.icon_prefix]0", "[blueprint_path]: the shell is finished once every part is attached")
	TEST_ASSERT_EQUAL(graph_current(chassis), STAGE_MECHA_SHELL, "[blueprint_path]: the finished shell stands at the first stage")
	mech_walk_forward(H, chassis, blueprint, tools, T)
	TEST_ASSERT(QDELETED(chassis), "[blueprint_path]: the chassis is gone")
	TEST_ASSERT(own(locate_on(T, blueprint.result)), "[blueprint_path]: the finished mecha spawned")
	own_turf_contents(T)

/datum/unit_test/dq_construction_mech_ripley_full_build/Run()
	mech_full_build(/datum/mecha_blueprint/ripley)

/datum/unit_test/dq_construction_mech_gygax_full_build/Run()
	mech_full_build(/datum/mecha_blueprint/gygax)

/datum/unit_test/dq_construction_mech_pinnace_full_build/Run()
	mech_full_build(/datum/mecha_blueprint/fighter/pinnace)

/datum/unit_test/dq_construction_mech_polecat_full_build/Run()
	mech_full_build(/datum/mecha_blueprint/micro/polecat)

// ---- Round trips: forward some steps, then the same steps back, same materials and state ----

/datum/unit_test/proc/mech_round_trip(blueprint_path, steps_down)
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode()
	var/list/tools = mech_make_tools(T)
	var/datum/mecha_blueprint/blueprint = mecha_blueprint_of(blueprint_path)
	var/obj/item/mecha_parts/chassis = mech_fresh_shell(H, blueprint_path, T)
	TEST_ASSERT(chassis, "[blueprint_path]: a chassis exists")
	if(!chassis)
		return
	// What the forward steps will consume is staged first, so the snapshot counts it as the player's own supplies.
	var/count = length(blueprint.ladder)
	var/list/held_for_step = list()
	for(var/i in 1 to steps_down)
		held_for_step += mech_held_for(blueprint.ladder[count - i + 1]["key"], tools, T)
	var/list/materials_before = dq_materials_on(T)
	var/before_icon = chassis.icon_state
	var/before_stage = graph_current(chassis)
	for(var/i in 1 to steps_down)
		var/stage_before = graph_current(chassis)
		mech_use(H, chassis, held_for_step[i])
		TEST_ASSERT(graph_current(chassis) != stage_before, "[blueprint_path]: forward step [i] advances")
	for(var/i in 1 to steps_down)
		var/stage_before = graph_current(chassis)
		var/list/row = blueprint.ladder[count - (steps_down - i)]
		mech_undo(H, chassis, tools[row["backkey"]])
		TEST_ASSERT(graph_current(chassis) != stage_before, "[blueprint_path]: backward step [i] retreats")
	H.drop_item() // the last tool used lies where the snapshot found it
	TEST_ASSERT_EQUAL(graph_current(chassis), before_stage, "[blueprint_path]: the stage round-trips")
	TEST_ASSERT_EQUAL(chassis.icon_state, before_icon, "[blueprint_path]: the icon_state round-trips")
	var/list/materials_after = dq_materials_on(T)
	TEST_ASSERT(dq_materials_equal(materials_after, materials_before), "[blueprint_path]: the same materials came back ([dq_materials_text(materials_before)] -> [dq_materials_text(materials_after)])")
	own_turf_contents(T)

/datum/unit_test/dq_construction_mech_ripley_round_trip/Run()
	mech_round_trip(/datum/mecha_blueprint/ripley, 5)

/datum/unit_test/dq_construction_mech_gygax_round_trip/Run()
	mech_round_trip(/datum/mecha_blueprint/gygax, 6)

/datum/unit_test/dq_construction_mech_pinnace_round_trip/Run()
	mech_round_trip(/datum/mecha_blueprint/fighter/pinnace, 5)

/datum/unit_test/dq_construction_mech_polecat_round_trip/Run()
	mech_round_trip(/datum/mecha_blueprint/micro/polecat, 6)

// ---- Parts phase ----

/// The ladder does not start until every part is on, and a part already on is not taken twice.
/datum/unit_test/dq_construction_mech_parts_phase/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode()
	var/list/tools = mech_make_tools(T)
	var/datum/mecha_blueprint/blueprint = mecha_blueprint_of(/datum/mecha_blueprint/ripley)
	var/obj/item/mecha_parts/chassis = allocate(mech_chassis_type_for(/datum/mecha_blueprint/ripley), T)
	var/first_type = blueprint.mecha_parts[1]
	mech_use(H, chassis, allocate(first_type, T))
	var/mask = chassis.parts_mask
	TEST_ASSERT(mask, "the first part is on")
	var/obj/item/duplicate = allocate(first_type, T)
	mech_use(H, chassis, duplicate)
	TEST_ASSERT_EQUAL(chassis.parts_mask, mask, "a second copy of a part already on is not taken")
	TEST_ASSERT(!QDELETED(duplicate), "and is kept")
	mech_use(H, chassis, tools[TOOL_WRENCH])
	TEST_ASSERT_EQUAL(graph_current(chassis), STAGE_MECHA_SHELL, "no ladder step starts before every part is on")

// ---- Every blueprint: one step forward then straight back, down the whole ladder ----

/datum/unit_test/dq_construction_mech_all_blueprints_round_trip/Run()
	for(var/datum/mecha_blueprint/path as anything in subtypesof(/datum/mecha_blueprint))
		if(!initial(path.id))
			continue
		test_driver_begin()
		var/turf/T = test_floor()
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
		H.enable_godmode()
		var/list/tools = mech_make_tools(T)
		var/datum/mecha_blueprint/blueprint = mecha_blueprint_of(path)
		var/obj/item/mecha_parts/chassis = mech_fresh_shell(H, path, T)
		TEST_ASSERT(chassis, "[path]: a chassis exists")
		if(!chassis)
			continue
		var/count = length(blueprint.ladder)
		for(var/i in 1 to count - 1)
			var/list/row = blueprint.ladder[count - i + 1]
			var/stage_before = graph_current(chassis)
			var/icon_before = chassis.icon_state
			mech_use(H, chassis, mech_held_for(row["key"], tools, T))
			TEST_ASSERT(graph_current(chassis) != stage_before, "[path]: forward step [i] advances (key [row["key"]], at [stage_key(stage_before)])")
			mech_undo(H, chassis, tools[row["backkey"]])
			TEST_ASSERT_EQUAL(graph_current(chassis), stage_before, "[path]: step [i] goes back to its stage")
			TEST_ASSERT_EQUAL(chassis.icon_state, icon_before, "[path]: icon_state round-trips at step [i]")
			mech_use(H, chassis, mech_held_for(row["key"], tools, T))
		own_turf_contents(T)

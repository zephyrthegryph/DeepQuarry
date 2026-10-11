/obj/item/unit_test_interaction_tool
	name = "interaction test tool"
	tool_qualities = list(TOOL_CROWBAR, TOOL_WRENCH)

/atom/movable/unit_test_interaction_target
	var/primary_crowbar_calls = 0
	var/primary_wrench_calls = 0
	var/secondary_wrench_calls = 0
	var/attackby_calls = 0
	var/crowbar_result = NONE
	var/wrench_result = ITEM_INTERACT_SUCCESS

/// The fixture's tool ops answer as their *_result says: SUCCESS commits, BLOCKING refuses (the handler never runs), anything else declines.
/atom/movable/unit_test_interaction_target/proc/crowbar_refusal(datum/act/op/A)
	return read_once(crowbar_result) == ITEM_INTERACT_BLOCKING ? "blocked" : null

/// A declining hook (NONE, SKIP_TO_ATTACK) is no candidate: the tool goes on to its next quality, then to attackby.
/atom/movable/unit_test_interaction_target/proc/crowbar_answers(datum/act/op/A)
	return read_once(crowbar_result) & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING)

/atom/movable/unit_test_interaction_target/proc/wrench_answers(datum/act/op/A)
	return read_once(wrench_result) & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING)

/atom/movable/unit_test_interaction_target/proc/crowbar_used(datum/act/op/A)
	primary_crowbar_calls++
	return crowbar_result == ITEM_INTERACT_SUCCESS ? OP_OK : OP_DECLINE

/atom/movable/unit_test_interaction_target/proc/wrench_used(datum/act/op/A)
	primary_wrench_calls++
	return wrench_result == ITEM_INTERACT_SUCCESS ? OP_OK : OP_DECLINE

/// Secondary tool use reaches the declared ops pinned to the right-click gesture.
CAPABILITIES(/atom/movable/unit_test_interaction_target)
	op("use_crowbar", tool(TOOL_CROWBAR), wait(0), when(PROC_REF(crowbar_answers)), needs(req(PROC_REF(crowbar_refusal))), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), when(PROC_REF(wrench_answers)), then(PROC_REF(wrench_used)))
	op("unit_test_secondary_wrench", tool(TOOL_WRENCH), gesture(GESTURE_RIGHT), wait(0), label("Test secondary wrench"), then(PROC_REF(note_secondary_wrench)))

/atom/movable/unit_test_interaction_target/proc/note_secondary_wrench(datum/act/op/A)
	secondary_wrench_calls++
	return OP_OK

/atom/movable/unit_test_interaction_target/attackby(obj/item/tool, mob/user, attack_modifier, click_parameters)
	attackby_calls++
	return ..()

/datum/unit_test/modern_tool_interaction_dispatch
	var/tool_acted_calls = 0
	var/quality_acted_calls = 0
	var/last_acted_quality

/datum/unit_test/modern_tool_interaction_dispatch/proc/on_tool_acted(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/item_tool_acted/event = N
	tool_acted_calls++
	last_acted_quality = event.tool_quality

/datum/unit_test/modern_tool_interaction_dispatch/proc/on_quality_acted(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/tool_atom_acted/event = N
	if(event.tool_quality == TOOL_WRENCH && !event.secondary)
		quality_acted_calls++

/datum/unit_test/modern_tool_interaction_dispatch/Run()
	var/atom/movable/unit_test_interaction_target/target = new
	var/obj/item/unit_test_interaction_tool/tool = new
	observe(tool, /datum/notice/item_tool_acted, src, then(PROC_REF(on_tool_acted)))
	observe(tool, /datum/notice/tool_atom_acted, src, then(PROC_REF(on_quality_acted)))

	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	target.forceMove(user.loc)
	user.put_in_hands(tool)
	var/primary_result = target.item_interaction(user, tool, list())
	TEST_ASSERT(primary_result & ITEM_INTERACT_SUCCESS, "Primary tool interaction did not report success.")
	TEST_ASSERT_EQUAL(target.primary_crowbar_calls, 0, "A declining first quality has no op to run.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 1, "A later quality was not attempted after the first declined.")
	TEST_ASSERT_EQUAL(target.attackby_calls, 0, "A successful focused interaction incorrectly fell through to attackby().")
	TEST_ASSERT_EQUAL(tool_acted_calls, 1, "A successful tool interaction did not emit the generic success signal exactly once.")
	TEST_ASSERT_EQUAL(quality_acted_calls, 1, "A successful tool interaction did not emit its quality-specific success signal exactly once.")
	TEST_ASSERT_EQUAL(last_acted_quality, TOOL_WRENCH, "The generic tool success signal reported the wrong successful quality.")

	var/secondary_result = target.item_interaction_secondary(user, tool, list())
	TEST_ASSERT(secondary_result & ITEM_INTERACT_SUCCESS, "Secondary tool use did not run the declared right-click op.")
	TEST_ASSERT_EQUAL(target.secondary_wrench_calls, 1, "Secondary dispatch did not reach the declared op.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 1, "Secondary dispatch incorrectly invoked the primary hook.")

	target.primary_crowbar_calls = 0
	target.primary_wrench_calls = 0
	target.crowbar_result = ITEM_INTERACT_BLOCKING
	var/blocking_result = tool.resolve_attackby(target, user)
	TEST_ASSERT(blocking_result & ITEM_INTERACT_BLOCKING, "A blocking focused hook did not propagate its result.")
	TEST_ASSERT_EQUAL(target.primary_crowbar_calls, 0, "A refused tool op ran its handler.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 0, "Dispatcher continued to a later tool quality after a blocking result.")
	TEST_ASSERT_EQUAL(target.attackby_calls, 0, "A blocking focused interaction incorrectly fell through to attackby().")

	target.primary_crowbar_calls = 0
	target.crowbar_result = ITEM_INTERACT_SUCCESS
	var/success_result = tool.resolve_attackby(target, user)
	TEST_ASSERT(success_result & ITEM_INTERACT_SUCCESS, "A successful first-quality hook did not propagate its result.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 0, "Dispatcher continued to a later tool quality after success.")
	TEST_ASSERT_EQUAL(target.attackby_calls, 0, "A successful first-quality interaction incorrectly fell through to attackby().")

	target.crowbar_result = NONE
	target.wrench_result = NONE
	tool.resolve_attackby(target, user)
	TEST_ASSERT_EQUAL(target.attackby_calls, 1, "An entirely declined modern interaction did not fall through to attackby exactly once.")

	target.crowbar_result = ITEM_INTERACT_SKIP_TO_ATTACK
	var/previous_attackby_calls = target.attackby_calls
	var/skip_result = tool.resolve_attackby(target, user)
	TEST_ASSERT_EQUAL(target.attackby_calls, previous_attackby_calls + 1, "SKIP_TO_ATTACK did not enter the attackby fallback exactly once.")
	TEST_ASSERT(!(skip_result & ITEM_INTERACT_SKIP_TO_ATTACK), "SKIP_TO_ATTACK leaked past the attackby fallback instead of returning attackby's result.")

	unobserve(tool, /datum/notice/item_tool_acted, src)
	unobserve(tool, /datum/notice/tool_atom_acted, src)
	qdel(target)
	qdel(tool)

/obj/machinery/unit_test_integrity_lifecycle
	max_integrity = 100
	integrity_failure = 0.5
	var/break_calls = 0
	var/fix_calls = 0

/obj/machinery/unit_test_integrity_lifecycle/atom_break(damage_flag)
	. = ..()
	break_calls++

/obj/machinery/unit_test_integrity_lifecycle/atom_fix()
	. = ..()
	fix_calls++

/datum/unit_test/machinery_integrity_break_fix_lifecycle

/datum/unit_test/machinery_integrity_break_fix_lifecycle/Run()
	var/obj/machinery/unit_test_integrity_lifecycle/machine = new
	machine.take_damage(60, BRUTE, MELEE, sound_effect = FALSE)
	TEST_ASSERT_EQUAL(machine.break_calls, 1, "Crossing machinery integrity_failure did not invoke atom_break exactly once.")
	machine.repair_damage(60)
	TEST_ASSERT_EQUAL(machine.fix_calls, 1, "Repairing machinery above integrity_failure did not invoke atom_fix exactly once.")
	qdel(machine)

/obj/machinery/unit_test_destruction_salvage
	var/destroy_saw_component_parts = FALSE
	var/destroy_saw_circuit = FALSE

/obj/machinery/unit_test_destruction_salvage/on_destroy(force)
	destroy_saw_component_parts = !isnull(component_parts)
	destroy_saw_circuit = !isnull(circuit)
	..()

/datum/unit_test/machinery_destruction_detaches_salvage

/datum/unit_test/machinery_destruction_detaches_salvage/Run()
	var/turf/salvage_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(salvage_turf, "No mapped turf was available for the machinery salvage lifecycle test.")
	var/obj/machinery/unit_test_destruction_salvage/machine = allocate(/obj/machinery/unit_test_destruction_salvage, salvage_turf)
	var/obj/item/part = allocate(/obj/item, machine)
	var/obj/item/circuitboard/board = allocate(/obj/item/circuitboard, machine)
	own_clear(machine, nameof(machine.component_parts), OWN_DELETE)
	rel_add(machine, nameof(machine.component_parts), part)
	rel_set(machine, nameof(machine.circuit), board)

	machine.deconstruct(FALSE)

	TEST_ASSERT_EQUAL(part.loc, salvage_turf, "Structural destruction did not preserve a machine component as turf salvage.")
	TEST_ASSERT_EQUAL(board.loc, salvage_turf, "Structural destruction did not preserve the circuit as turf salvage.")
	TEST_ASSERT(!machine.destroy_saw_component_parts, "Destroy retained stale component_parts bookkeeping after salvage was detached.")
	TEST_ASSERT(!machine.destroy_saw_circuit, "Destroy retained a stale circuit reference after salvage was detached.")

/datum/unit_test/machine_component_qdel_detaches_owner

/datum/unit_test/machine_component_qdel_detaches_owner/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/machinery/machine = allocate(/obj/machinery, test_turf)
	var/obj/item/stock_parts/capacitor/part = new(machine)
	own_clear(machine, nameof(machine.component_parts), OWN_DELETE)
	rel_add(machine, nameof(machine.component_parts), part)
	qdel(part)
	TEST_ASSERT(!(part in machine.component_parts), "A deleted stock part remained strongly retained by machine.component_parts.")
	qdel(machine)

/datum/unit_test/alarm_release_atom_clears_sources_and_camera_cache

/datum/unit_test/alarm_release_atom_clears_sources_and_camera_cache/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/obj/source = allocate(/obj, test_turf)
	var/datum/alarm_handler/handler = new
	handler.triggerAlarm(test_turf, source)
	var/datum/alarm/alarm = handler.alarms[1]
	alarm.cameras = list(source)
	handler.release_atom(source)
	TEST_ASSERT(!alarm.source_entry(source), "Released alarm source remained an alarm source entry.")
	TEST_ASSERT(!(source in alarm.cameras), "Released alarm source remained in an alarm camera cache.")
	qdel(source)
	qdel(handler)

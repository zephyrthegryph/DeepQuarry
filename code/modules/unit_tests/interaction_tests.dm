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

/atom/movable/unit_test_interaction_target/crowbar_act(mob/user, obj/item/tool)
	primary_crowbar_calls++
	return crowbar_result

/atom/movable/unit_test_interaction_target/wrench_act(mob/user, obj/item/tool)
	primary_wrench_calls++
	return wrench_result

/atom/movable/unit_test_interaction_target/wrench_act_secondary(mob/user, obj/item/tool)
	secondary_wrench_calls++
	return ITEM_INTERACT_BLOCKING

/atom/movable/unit_test_interaction_target/attackby(obj/item/tool, mob/user, attack_modifier, click_parameters)
	attackby_calls++
	return ..()

/datum/unit_test/modern_tool_interaction_dispatch
	var/tool_acted_calls = 0
	var/quality_acted_calls = 0
	var/last_acted_quality

/datum/unit_test/modern_tool_interaction_dispatch/proc/on_tool_acted(datum/source, atom/target, mob/user, tool_quality, list/modifiers)
	SIGNAL_HANDLER
	tool_acted_calls++
	last_acted_quality = tool_quality

/datum/unit_test/modern_tool_interaction_dispatch/proc/on_quality_acted(datum/source, atom/target, mob/user, list/modifiers)
	SIGNAL_HANDLER
	quality_acted_calls++

/datum/unit_test/modern_tool_interaction_dispatch/Run()
	var/atom/movable/unit_test_interaction_target/target = new
	var/obj/item/unit_test_interaction_tool/tool = new
	RegisterSignal(tool, COMSIG_ITEM_TOOL_ACTED, PROC_REF(on_tool_acted))
	RegisterSignal(tool, COMSIG_TOOL_ATOM_ACTED_PRIMARY(TOOL_WRENCH), PROC_REF(on_quality_acted))

	var/primary_result = target.item_interaction(null, tool, list())
	TEST_ASSERT(primary_result & ITEM_INTERACT_SUCCESS, "Primary tool interaction did not report success.")
	TEST_ASSERT_EQUAL(target.primary_crowbar_calls, 1, "The first quality was not attempted exactly once.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 1, "A later quality was not attempted after the first declined.")
	TEST_ASSERT_EQUAL(target.attackby_calls, 0, "A successful focused interaction incorrectly fell through to attackby().")
	TEST_ASSERT_EQUAL(tool_acted_calls, 1, "A successful tool interaction did not emit the generic success signal exactly once.")
	TEST_ASSERT_EQUAL(quality_acted_calls, 1, "A successful tool interaction did not emit its quality-specific success signal exactly once.")
	TEST_ASSERT_EQUAL(last_acted_quality, TOOL_WRENCH, "The generic tool success signal reported the wrong successful quality.")

	var/secondary_result = target.item_interaction_secondary(null, tool, list())
	TEST_ASSERT(secondary_result & ITEM_INTERACT_BLOCKING, "Secondary tool interaction did not preserve blocking semantics.")
	TEST_ASSERT_EQUAL(target.secondary_wrench_calls, 1, "Secondary dispatch did not reach its dedicated hook.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 1, "Secondary dispatch incorrectly invoked the primary hook.")

	target.primary_crowbar_calls = 0
	target.primary_wrench_calls = 0
	target.crowbar_result = ITEM_INTERACT_BLOCKING
	var/blocking_result = tool.resolve_attackby(target, null)
	TEST_ASSERT(blocking_result & ITEM_INTERACT_BLOCKING, "A blocking focused hook did not propagate its result.")
	TEST_ASSERT_EQUAL(target.primary_crowbar_calls, 1, "Blocking dispatch did not invoke the first declared quality exactly once.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 0, "Dispatcher continued to a later tool quality after a blocking result.")
	TEST_ASSERT_EQUAL(target.attackby_calls, 0, "A blocking focused interaction incorrectly fell through to attackby().")

	target.primary_crowbar_calls = 0
	target.crowbar_result = ITEM_INTERACT_SUCCESS
	var/success_result = tool.resolve_attackby(target, null)
	TEST_ASSERT(success_result & ITEM_INTERACT_SUCCESS, "A successful first-quality hook did not propagate its result.")
	TEST_ASSERT_EQUAL(target.primary_wrench_calls, 0, "Dispatcher continued to a later tool quality after success.")
	TEST_ASSERT_EQUAL(target.attackby_calls, 0, "A successful first-quality interaction incorrectly fell through to attackby().")

	target.crowbar_result = NONE
	target.wrench_result = NONE
	tool.resolve_attackby(target, null)
	TEST_ASSERT_EQUAL(target.attackby_calls, 1, "An entirely declined modern interaction did not fall through to attackby exactly once.")

	target.crowbar_result = ITEM_INTERACT_SKIP_TO_ATTACK
	var/previous_attackby_calls = target.attackby_calls
	var/skip_result = tool.resolve_attackby(target, null)
	TEST_ASSERT_EQUAL(target.attackby_calls, previous_attackby_calls + 1, "SKIP_TO_ATTACK did not enter the attackby fallback exactly once.")
	TEST_ASSERT(!(skip_result & ITEM_INTERACT_SKIP_TO_ATTACK), "SKIP_TO_ATTACK leaked past the attackby fallback instead of returning attackby's result.")

	UnregisterSignal(tool, list(COMSIG_ITEM_TOOL_ACTED, COMSIG_TOOL_ATOM_ACTED_PRIMARY(TOOL_WRENCH)))
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

/obj/machinery/unit_test_destruction_salvage/Destroy()
	destroy_saw_component_parts = !isnull(component_parts)
	destroy_saw_circuit = !isnull(circuit)
	return ..()

/datum/unit_test/machinery_destruction_detaches_salvage

/datum/unit_test/machinery_destruction_detaches_salvage/Run()
	var/turf/salvage_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(salvage_turf, "No mapped turf was available for the machinery salvage lifecycle test.")
	var/obj/machinery/unit_test_destruction_salvage/machine = allocate(/obj/machinery/unit_test_destruction_salvage, salvage_turf)
	var/obj/item/part = new(machine)
	var/obj/item/circuitboard/board = new(machine)
	machine.component_parts = list(part)
	machine.circuit = board

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
	machine.component_parts = list(part)
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
	TEST_ASSERT(!(source in alarm.sources_assoc), "Released alarm source remained an associative-list key.")
	TEST_ASSERT(!(source in alarm.cameras), "Released alarm source remained in an alarm camera cache.")
	qdel(source)
	qdel(handler)

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

/datum/unit_test/idle_powernets_hibernate_and_mutations_wake

/datum/unit_test/idle_powernets_hibernate_and_mutations_wake/Run()
	var/datum/powernet/network = new
	TEST_ASSERT(network in SSmachines.active_powernets, "A new powernet did not start its initial accounting window.")
	network.reset()
	TEST_ASSERT_EQUAL(network.reset(), PROCESS_KILL, "An empty powernet did not hibernate after two idle accounting windows.")
	STOP_PROCESSING_POWERNET(network)
	network.mark_accounting_dirty()
	TEST_ASSERT(network in SSmachines.active_powernets, "A powernet mutation did not wake its accounting window.")
	qdel(network)

/datum/unit_test/stable_power_supply_is_persistent_and_hibernates

/datum/unit_test/stable_power_supply_is_persistent_and_hibernates/Run()
	var/datum/powernet/network = new
	var/obj/machinery/power/source = allocate(/obj/machinery/power, run_loc_floor_bottom_left)
	network.add_machine(source)
	TEST_ASSERT(network.register_power_supply(source, 5000), "Initial source rate was not registered.")
	var/process_result
	for(var/i in 1 to 4)
		process_result = network.reset()
		if(process_result == PROCESS_KILL)
			STOP_PROCESSING_POWERNET(network)
			break
	TEST_ASSERT_EQUAL(process_result, PROCESS_KILL, "A powered but unchanged network did not hibernate.")
	TEST_ASSERT_EQUAL(network.avail, 5000, "Hibernation discarded the persistent source rate.")
	TEST_ASSERT(!network.register_power_supply(source, 5000), "Republishing an identical source rate dirtied the network.")
	TEST_ASSERT(!(network in SSmachines.active_powernets), "Identical source output woke a settled network.")
	TEST_ASSERT(network.register_power_supply(source, 4900), "A small source-rate change was not retained.")
	TEST_ASSERT(!(network in SSmachines.active_powernets), "Sub-threshold generator jitter woke a healthy settled network.")
	TEST_ASSERT_EQUAL(network.avail, 4900, "A sleeping network did not expose its latest live supply total.")
	TEST_ASSERT(network.register_power_supply(source, 4700), "A cumulative source-rate change was not registered.")
	TEST_ASSERT(!(network in SSmachines.active_powernets), "A healthy source-rate change unnecessarily woke an ordinary grid.")
	TEST_ASSERT_EQUAL(network.avail, 4700, "A batched source-rate change was not visible to the sleeping grid.")
	network.unregister_power_supply(source)
	TEST_ASSERT_EQUAL(network.registered_supply_total, 0, "Removing a source retained phantom supply.")
	qdel(source)
	if(!QDELETED(network))
		qdel(network)

/datum/unit_test/cable_split_is_bounded_and_preserves_components

/datum/unit_test/cable_split_is_bounded_and_preserves_components/Run()
	var/datum/powernet/network = new
	var/obj/structure/cable/left = new(locate(2, 2, 1))
	var/obj/structure/cable/bridge = new(locate(3, 2, 1))
	var/obj/structure/cable/right = new(locate(4, 2, 1))
	left.d1 = 0
	left.d2 = EAST
	bridge.d1 = WEST
	bridge.d2 = EAST
	right.d1 = 0
	right.d2 = WEST
	network.begin_topology_batch()
	network.add_cable(left)
	network.add_cable(bridge)
	network.add_cable(right)
	network.end_topology_batch()
	network.cables -= bridge
	bridge.powernet = null
	SSmachines.queue_powernet_topology(network)
	TEST_ASSERT(network.topology_pending, "A severed cable did not fail its old grid safe while rebuilding.")
	var/datum/powernet_topology_job/job = SSmachines.powernet_topology_jobs_by_net[network]
	TEST_ASSERT_NOTNULL(job, "A severed cable did not queue a targeted topology transaction.")
	var/guard = 0
	while(!job.complete && guard++ < 100)
		job.process_slice()
	TEST_ASSERT(job.complete, "The bounded topology transaction did not complete.")
	TEST_ASSERT_NOTNULL(left.powernet, "The left component lost its powernet.")
	TEST_ASSERT_NOTNULL(right.powernet, "The right component lost its powernet.")
	TEST_ASSERT(left.powernet != right.powernet, "A bridge cut still delivered power across the severed edge.")
	TEST_ASSERT(left.powernet == network || right.powernet == network, "The largest unchanged component did not preserve the existing powernet identity.")
	SSmachines.powernet_topology_jobs -= job
	SSmachines.powernet_topology_jobs_by_net.Remove(network)
	qdel(job)
	qdel(left)
	qdel(bridge)
	qdel(right)

/datum/unit_test/registered_smes_settles_only_used_energy

/datum/unit_test/registered_smes_settles_only_used_energy/Run()
	var/turf/simulated/floor/test_floor = locate() in world
	TEST_ASSERT_NOTNULL(test_floor, "No floor was available for the storage transaction test.")
	var/datum/powernet/network = new
	var/obj/machinery/power/smes/storage = allocate(/obj/machinery/power/smes, test_floor)
	network.add_machine(storage)
	storage.charge = 100000
	network.register_power_supply(storage, 1000, TRUE)
	network.avail = 1000
	network.smes_avail = 1000
	var/starting_charge = storage.charge
	network.load = 0
	network.last_storage_settlement = world.time - max(SSmachines.wait, 1)
	network.settle_registered_storage()
	TEST_ASSERT_EQUAL(storage.charge, starting_charge, "An unloaded stable SMES lost its full offered output.")
	network.load = 500
	network.last_storage_settlement = world.time - max(SSmachines.wait, 1)
	network.settle_registered_storage()
	TEST_ASSERT_EQUAL(storage.charge, starting_charge - 500 * SMESRATE, "SMES storage did not debit exactly the power the network used.")
	network.unregister_power_supply(storage)
	var/obj/machinery/power/terminal/terminal = allocate(/obj/machinery/power/terminal, test_floor)
	network.add_machine(terminal)
	terminal.master = storage
	network.register_storage_demand(storage, terminal, 400)
	var/list/demand = LAZYACCESS(network.registered_storage_demands, terminal)
	demand[3] = 400
	network.registered_storage_input_total = 400
	starting_charge = storage.charge
	network.load = 400
	network.avail = 1000
	network.last_storage_settlement = world.time - max(SSmachines.wait, 1)
	network.settle_registered_storage()
	TEST_ASSERT_EQUAL(storage.charge, starting_charge + 400 * SMESRATE, "SMES storage did not credit its persistent allocated input over elapsed time.")
	qdel(terminal)
	qdel(storage)
	if(!QDELETED(network))
		qdel(network)

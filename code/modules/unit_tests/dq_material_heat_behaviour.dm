// Behaviour pins for material science heat (doc/rewrite/temperature.md §7): an assembly's material service and a processed batch hold heat
// and trade it with the air around them and the gas inside them. Written against material science's own DM heat model first (green there),
// then kept green once the heat moved onto Rust heat bodies and heat links. Each test logs what it measured; the numbers are in
// doc/rewrite/intended_changes.md ("Material science heat").
//
// material_heat_elapse() is the one driver both models answer to: the service's own sample sees `seconds` pass, and the native world steps
// the same seconds (the heat links).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Lets `seconds` pass for a material service (its sample) and for the native world (gas, solids and heat links).
/proc/material_heat_elapse(datum/material_service/service, seconds)
	for(var/i in 1 to seconds)
		service.last_update -= 1 SECONDS
		service.advance()
		heat_test_world_seconds(1)

/// The heat a service holds, J: its temperature over its capacity plus its phase buffer.
/proc/material_heat_service_energy(datum/material_service/service)
	return material_service_temperature(service) * service.thermal_mass() + material_service_buffer(service)

/// A clear floor with standard room air, isolated in a sealed two-tile room.
/proc/material_heat_room()
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	if(!pair)
		return null
	dq_atmos_test_isolate_pair(pair[1], pair[2])
	for(var/turf/open/T as anything in pair)
		dq_atmos_test_snapshot_air(T)
		dq_atmos_test_fill_standard_air(T, T20C)
		heat_set_solid(T, T20C)
		GLOB.body_heat_room_solids |= T
	SSair.run_gas_frames(1)
	return pair

/datum/unit_test/dq_material_heat
	abstract_type = /datum/unit_test/dq_material_heat

/datum/unit_test/dq_material_heat/Run()
	run_material_heat()
	body_heat_room_restore()

/datum/unit_test/dq_material_heat/proc/run_material_heat()
	return

/// A hot cell's assembly gives its heat to the room's air, and the air gains what the assembly lost.
/datum/unit_test/dq_material_heat/service_cools_into_the_air

/datum/unit_test/dq_material_heat/service_cools_into_the_air/run_material_heat()
	var/list/room = material_heat_room()
	TEST_ASSERT_NOTNULL(room, "no room for the cell")
	var/turf/open/T = room[1]
	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/material_service/service = cell.enable_material_service()
	TEST_ASSERT_NOTNULL(service, "the cell has no material service")
	service.add_heat((400 - material_service_temperature(service)) * service.thermal_mass())
	var/service_before = material_heat_service_energy(service)
	var/air_before = heat_bt_air_energy(room)
	material_heat_elapse(service, 30)
	var/t_after = material_service_temperature(service)
	var/lost = service_before - material_heat_service_energy(service)
	var/gained = heat_bt_air_energy(room) - air_before
	log_test("hot cell: 400 K -> [round(t_after, 0.1)] K in 30 s; assembly lost [round(lost)] J, air gained [round(gained)] J")
	TEST_ASSERT(t_after < 399, "the hot assembly cooled ([t_after] K)")
	TEST_ASSERT(t_after > T20C, "the assembly did not pass the air's temperature ([t_after] K)")
	TEST_ASSERT(gained > 0, "the air took the heat ([gained] J)")
	// The floor under the air takes some of what the air got; the air cannot have gained more than the assembly lost.
	TEST_ASSERT(gained <= lost * 1.01 + 1, "the air gained more than the assembly lost ([gained] J of [lost] J)")

/// A canister's shell and the gas inside it: whatever passes between them is conserved (before: a stock canister's shell passed nothing
/// to its contents in 30 s, its shell conductance being nil).
/datum/unit_test/dq_material_heat/service_and_contents_conserve

/datum/unit_test/dq_material_heat/service_and_contents_conserve/run_material_heat()
	var/list/room = material_heat_room()
	TEST_ASSERT_NOTNULL(room, "no room for the canister")
	var/obj/machinery/portable_atmospherics/canister/vessel = allocate(/obj/machinery/portable_atmospherics/canister, room[1])
	vessel.air_contents.adjust_moles(/datum/gas/nitrogen, 200)
	heat_set(vessel.air_contents, 600, HEAT_SOURCE_OTHER)
	var/datum/material_service/service = vessel.enable_material_service()
	TEST_ASSERT_NOTNULL(service, "the canister has no material service")
	var/shell_before = material_service_temperature(service)
	var/gas_before = vessel.air_contents.return_temperature()
	var/energy_before = material_heat_service_energy(service) + vessel.air_contents.thermal_energy() + heat_bt_air_energy(room)
	material_heat_elapse(service, 30)
	var/shell_after = material_service_temperature(service)
	var/gas_after = vessel.air_contents.return_temperature()
	var/energy_after = material_heat_service_energy(service) + vessel.air_contents.thermal_energy() + heat_bt_air_energy(room)
	log_test("canister: shell [round(shell_before, 0.1)] -> [round(shell_after, 0.1)] K, contents [round(gas_before, 0.1)] -> [round(gas_after, 0.1)] K in 30 s; energy [round(energy_before)] -> [round(energy_after)] J")
	TEST_ASSERT(gas_after <= gas_before, "the contents did not warm ([gas_before] -> [gas_after] K)")
	TEST_ASSERT(energy_after <= energy_before + max(1, energy_before * 0.0001), "shell, contents and room made heat ([energy_before] -> [energy_after] J)")

/// A thermoelectric conductor turns part of the heat leaving a hot cell into charge.
/datum/unit_test/dq_material_heat/thermoelectric_cell_charges

/datum/unit_test/dq_material_heat/thermoelectric_cell_charges/run_material_heat()
	var/list/room = material_heat_room()
	TEST_ASSERT_NOTNULL(room, "no room for the cell")
	var/obj/item/cell/cell = allocate(/obj/item/cell, room[1])
	var/datum/material/conductor_type = /datum/material/engineering_test_conductor
	cell.apply_material_construction(list(MATERIAL_ROLE_CONDUCTOR = initial(conductor_type.name)), material_template_path_for_application(MATERIAL_APPLICATION_CELL), 2000)
	var/datum/material_service/service = material_service_of(cell) || cell.enable_material_service()
	TEST_ASSERT_NOTNULL(service, "the cell has no material service")
	cell.charge = 0
	service.add_heat((500 - material_service_temperature(service)) * service.thermal_mass())
	material_heat_elapse(service, 30)
	log_test("thermoelectric cell: charge [round(cell.charge, 0.01)] after 30 s from 500 K, assembly at [round(material_service_temperature(service), 0.1)] K")
	TEST_ASSERT(cell.charge > 0, "the heat flow made no charge")

/// A batch heats by exactly the energy given over its capacity.
/datum/unit_test/dq_material_heat/batch_takes_heat

/datum/unit_test/dq_material_heat/batch_takes_heat/run_material_heat()
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 4)
	var/t0 = material_batch_temperature(batch)
	var/capacity = batch.thermal_capacity()
	var/rise = batch.add_batch_heat(capacity * 100)
	log_test("batch: [round(t0, 0.1)] K + [round(capacity * 100)] J at [round(capacity, 0.1)] J/K -> [round(material_batch_temperature(batch), 0.1)] K")
	TEST_ASSERT(abs(rise - 100) < 0.1, "the batch rose [rise] K for 100 K worth of heat")
	TEST_ASSERT(abs(material_batch_temperature(batch) - t0 - 100) < 0.1, "the batch reads [material_batch_temperature(batch)] K")
	qdel(batch)

/// Hot processed stock cools toward the room's air and stops glowing (before: 8 % of the gap per 2 s step, snapped at 5 K).
/datum/unit_test/dq_material_heat/hot_stock_cools

/datum/unit_test/dq_material_heat/hot_stock_cools/run_material_heat()
	var/list/room = material_heat_room()
	TEST_ASSERT_NOTNULL(room, "no room for the stock")
	var/datum/material_batch/batch = new
	batch.add_material(MAT_STEEL, 6)
	material_batch_set_temperature(batch, 900)
	var/obj/item/stack/material/processed_alloy/stock = processed_spawn_stack(room[1], batch, 6)
	stock.update_thermal_processing()
	TEST_ASSERT(stock.hot, "900 K stock glows")
	var/list/seen = list()
	var/steps = 0
	while(stock.hot && steps < 200)
		steps++
		heat_test_world_seconds(2)
		stock.processed_alloy_step(null)
		if(steps in list(1, 10, 30))
			seen += "step [steps]: [round(material_batch_temperature(stock.physical_batch()), 0.1)] K"
	log_test("hot stock: [jointext(seen, ", ")]; stopped glowing after [steps] steps of 2 s")
	TEST_ASSERT(!stock.hot, "the stock was still hot after [steps] steps")
	TEST_ASSERT(steps >= 30 && steps <= 120, "the stock cooled at the old pace (8 % of the gap per 2 s: 61 steps), took [steps]")
	qdel(batch)

#endif

// The heat network (code/domains/heat/, verdigris/ffi/src/heat_net.rs): one conserved transfer primitive and declared edges that live with their
// scope.

/// Total energy of gas mixtures, J.
/proc/heat_test_energy(list/mixtures)
	. = 0
	for(var/datum/gas_mixture/M as anything in mixtures)
		. += M.heat_capacity() * M.return_temperature()

/// Heat network tests that make time pass: the kernel on the test clock, so declared hooks run at its drain points.
/datum/unit_test/dq_heat_net
	abstract_type = /datum/unit_test/dq_heat_net

/datum/unit_test/dq_heat_net/Run()
	test_driver_begin()
	run_heat()
	test_driver_end()

/datum/unit_test/dq_heat_net/proc/run_heat()
	return

/// heat_move() between two gases conserves; from outside it adds exactly what it says and books it; it never passes the floor.
/datum/unit_test/dq_heat_net_move_conserves

/datum/unit_test/dq_heat_net_move_conserves/Run()
	var/datum/gas_mixture/a = new(CELL_VOLUME)
	a.adjust_gas(GAS_N2, 50)
	var/datum/gas_mixture/b = new(CELL_VOLUME)
	b.adjust_gas(GAS_N2, 50)
	heat_set(a, 400, HEAT_SOURCE_AUTHORITY)
	heat_set(b, 300, HEAT_SOURCE_AUTHORITY)
	TEST_ASSERT(abs(a.return_temperature() - 400) < 0.01, "heat_set: [a.return_temperature()] K")
	var/before = heat_test_energy(list(a, b))
	var/moved = heat_move(a, b, 10000)
	TEST_ASSERT(abs(moved - 10000) < 1, "moved [moved] J")
	TEST_ASSERT(abs(heat_test_energy(list(a, b)) - before) < 1, "a move between two gases conserves: [before] -> [heat_test_energy(list(a, b))]")
	var/added = heat_add(a, 5000, HEAT_SOURCE_REACTION)
	TEST_ASSERT(abs(heat_test_energy(list(a, b)) - before - added) < 1, "an external source adds what it reports")
	heat_move(a, b, 1e12)
	TEST_ASSERT(a.return_temperature() >= TCMB - 0.01, "a move never takes a gas below TCMB ([a.return_temperature()] K)")
	TEST_ASSERT(abs(heat_test_energy(list(a, b)) - before - added) < 10, "and still conserves")
	var/list/books = vg_heat_books()
	TEST_ASSERT(books[12] == 0, "no unbalanced step")

/// A type-level heat_link() under when(): the edge exists while the condition holds and relaxes the pair exactly; it ends when the condition does.
/datum/unit_test/dq_heat_net/link_scoped_by_condition

/datum/unit_test/dq_heat_net/link_scoped_by_condition/run_heat()
	var/obj/machinery/heat_fixture/plate/P = allocate(/obj/machinery/heat_fixture/plate)
	heat_set(P.gas, 500)
	TEST_ASSERT_EQUAL(length(heat_entries_of(P)), 0, "off: no edge")
	P.set_heat_on(TRUE)
	test_drain()
	TEST_ASSERT_EQUAL(length(heat_entries_of(P)), 1, "on: one edge")
	var/list/ids = vg_heat_reservoir_links(HEAT_TARGET_MIXTURE, P.gas)
	TEST_ASSERT_EQUAL(length(ids), 1, "the gas lists its edge")
	var/start = P.gas.return_temperature()
	vg_world_run_steps(10)
	TEST_ASSERT(P.gas.return_temperature() < start - 1, "the hot gas cools into the room ([start] -> [P.gas.return_temperature()])")
	P.set_heat_on(FALSE)
	test_drain()
	TEST_ASSERT_EQUAL(length(heat_entries_of(P)), 0, "off again: the edge ended with the condition")
	TEST_ASSERT_EQUAL(length(vg_heat_reservoir_links(HEAT_TARGET_MIXTURE, P.gas)), 0, "and Rust has no edge left")

/// A while_slotted heat_link(HEAT_HOLDER, ...): the occupant's heat body exchanges with the pod's gas while inside, and conserves.
/datum/unit_test/dq_heat_net/link_scoped_by_slot

/datum/unit_test/dq_heat_net/link_scoped_by_slot/run_heat()
	var/obj/machinery/heat_fixture/pod/pod = allocate(/obj/machinery/heat_fixture/pod)
	var/obj/item/occupant = new /obj/item(null) // in nullspace: its body exchanges with the pod's gas alone
	pod.set_heat_on(TRUE)
	test_drain()
	heat_set(pod.gas, 200)
	heat_set(occupant, 350)
	activations_slot_enter(occupant, pod, "heat_pod")
	TEST_ASSERT_EQUAL(length(heat_entries_of(pod)), 1, "inside: linked")
	var/list/body = heat_reservoir_of(occupant)
	var/c_body = vg_heat_reservoir_state(body[1], body[2])[2]
	var/e0 = heat_test_energy(list(pod.gas)) + c_body * occupant.get_temperature()
	vg_world_run_steps(20)
	var/e1 = heat_test_energy(list(pod.gas)) + c_body * occupant.get_temperature()
	TEST_ASSERT(occupant.get_temperature() < 349, "the occupant cooled ([occupant.get_temperature()] K)")
	TEST_ASSERT(abs(e1 - e0) < max(1, abs(e0) * 1e-5), "body and gas conserve: [e0] -> [e1]")
	activations_slot_exit(occupant, pod, "heat_pod")
	TEST_ASSERT_EQUAL(length(heat_entries_of(pod)), 0, "out: the link ended with the slot")
	qdel(occupant)

/// A heat_pump(): cools one gas into the other, the hot side gains the heat plus the work, and its power is read back.
/datum/unit_test/dq_heat_net/pump_books_its_work

/datum/unit_test/dq_heat_net/pump_books_its_work/run_heat()
	var/obj/machinery/heat_fixture/chiller/C = allocate(/obj/machinery/heat_fixture/chiller)
	heat_set(C.cold, 290)
	heat_set(C.gas, 300)
	C.set_heat_on(TRUE)
	test_drain()
	var/e0 = heat_test_energy(list(C.cold, C.gas))
	vg_world_run_steps(4)
	var/e1 = heat_test_energy(list(C.cold, C.gas))
	TEST_ASSERT(C.cold.return_temperature() < 289, "the cold side cooled ([C.cold.return_temperature()] K)")
	var/power = heat_entries_power(C)
	TEST_ASSERT(power < 0 && power >= -2000.5, "it drew up to its 2 kW ([power] W)")
	TEST_ASSERT(e1 > e0, "the pair gained the pump's work ([e0] -> [e1])")
	TEST_ASSERT_EQUAL(stat_value(C, STAT_POWER_DRAW), 2000, "the pump's rating is its power_draw contribution")

/// A heat_engine(): heat flows hot to cold and the work leaves; never more than Carnot.
/datum/unit_test/dq_heat_net/engine_obeys_carnot

/datum/unit_test/dq_heat_net/engine_obeys_carnot/run_heat()
	var/obj/machinery/heat_fixture/engine/E = allocate(/obj/machinery/heat_fixture/engine)
	heat_set(E.gas, 600)
	heat_set(E.cold, 300)
	E.set_heat_on(TRUE)
	test_drain()
	var/e0 = heat_test_energy(list(E.cold, E.gas))
	vg_world_run_steps(1)
	var/e1 = heat_test_energy(list(E.cold, E.gas))
	var/power = heat_entries_power(E)
	TEST_ASSERT(power > 0, "it made power ([power] W)")
	var/hot_lost = (600 - E.gas.return_temperature()) * E.gas.heat_capacity()
	TEST_ASSERT(e0 - e1 <= 0.5 * hot_lost + 1, "the work out ([e0 - e1] J) is within Carnot of the heat taken ([hot_lost] J)")

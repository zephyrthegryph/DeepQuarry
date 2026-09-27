/datum/unit_test/dq_wires_owned_transfer
	needs_test_block = FALSE

/datum/unit_test/dq_wires_owned_transfer/Run()
	var/obj/first = new
	var/obj/second = new
	var/datum/wires/unit_test/wiring = new(first)
	TEST_ASSERT(first.set_wires(wiring), "wire setter accepts its matching holder")
	TEST_ASSERT_EQUAL(om_owner(wiring), first, "the original atom owns its wiring")
	TEST_ASSERT(second.set_wires(wiring), "wire setter transfers existing wiring")
	TEST_ASSERT_NULL(first.wires, "transfer clears the previous holder's reference")
	TEST_ASSERT_EQUAL(second.wires, wiring, "the new holder references its wiring")
	TEST_ASSERT_EQUAL(wiring.holder, second, "wiring points at its new holder")
	TEST_ASSERT_EQUAL(om_owner(wiring), second, "ownership moves with the wiring")
	qdel(first)
	TEST_ASSERT(!QDELETED(wiring), "deleting the former holder keeps transferred wiring")
	qdel(second)
	TEST_ASSERT(QDELETED(wiring), "deleting the current holder deletes its wiring")

/datum/unit_test/dq_wires_owned_replacement
	needs_test_block = FALSE

/datum/unit_test/dq_wires_owned_replacement/Run()
	var/obj/holder = new
	var/datum/wires/unit_test/old_wiring = new(holder)
	holder.wires = old_wiring // Existing direct assignments remain supported.
	TEST_ASSERT_EQUAL(om_owner(old_wiring), holder, "constructor attaches directly assigned wiring")
	var/datum/wires/unit_test/new_wiring = new(holder)
	TEST_ASSERT(holder.set_wires(new_wiring), "setter replaces existing wiring")
	TEST_ASSERT(QDELETED(old_wiring), "replacement deletes obsolete wiring")
	TEST_ASSERT_EQUAL(holder.wires, new_wiring, "new wiring stays installed")
	qdel(holder)
	TEST_ASSERT(QDELETED(new_wiring), "holder deletion cascades to installed wiring")

/datum/unit_test/dq_wires_owned_atom_cleanup

/datum/unit_test/dq_wires_owned_atom_cleanup/Run()
	var/turf/T = test_floor()
	TEST_ASSERT_NOTNULL(T, "wired atom test needs a turf")
	var/obj/item/radio/radio = new(T)
	var/datum/wires/radio_wires = radio.wires
	TEST_ASSERT_EQUAL(om_owner(radio_wires), radio, "radio owns its wiring")
	qdel(radio)
	TEST_ASSERT(QDELETED(radio_wires), "radio deletion cleans wiring without local Destroy boilerplate")
	var/obj/machinery/door/airlock/door = new(T)
	var/datum/wires/door_wires = door.wires
	TEST_ASSERT_EQUAL(om_owner(door_wires), door, "airlock owns its wiring")
	qdel(door)
	TEST_ASSERT(QDELETED(door_wires), "airlock deletion cleans wiring without local Destroy boilerplate")

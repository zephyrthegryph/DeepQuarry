// The relations the machinery files declare in CAPABILITIES (ref_one / ref_many by id, links for a pair), proven one at a time: the
// holder finds its targets by id when both exist, a pair writes both sides, and either end dying clears the other.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/obj/machinery/button/remote/airlock/dq_keyed
	id = "dq_keyed_airlock"

/obj/machinery/door/airlock/dq_keyed
	id_tag = "dq_keyed_airlock"

/obj/machinery/button/remote/shields/dq_keyed
	id = "dq_keyed_shield"

/obj/machinery/shield_gen/dq_keyed
	id = "dq_keyed_shield"

/obj/machinery/button/doorbell/dq_keyed
	id = "dq_keyed_bell"

/obj/machinery/doorbell_chime/dq_keyed
	id_tag = "dq_keyed_bell"

/obj/machinery/button/flasher/dq_keyed
	id = "dq_keyed_flash"

/obj/machinery/flasher/dq_keyed
	id = "dq_keyed_flash"

/obj/machinery/button/holosign/dq_keyed
	id = "dq_keyed_holo"

/obj/machinery/holosign/dq_keyed
	id = "dq_keyed_holo"

/obj/machinery/button/neonsign/dq_keyed
	id = "dq_keyed_neon"

/obj/machinery/neonsign/dq_keyed
	id = "dq_keyed_neon"

/obj/machinery/button/ignition/dq_keyed
	id = "dq_keyed_ignite"

/obj/machinery/sparker/dq_keyed
	id = "dq_keyed_ignite"

/obj/machinery/igniter/dq_keyed
	id = "dq_keyed_ignite"

/obj/machinery/computer/pod/dq_keyed
	id = "dq_keyed_pod"

/obj/machinery/mass_driver/dq_keyed
	id = "dq_keyed_pod"

/obj/machinery/door/blast/dq_keyed
	id = "dq_keyed_pod"

/datum/unit_test/proc/dq_keyed_found(list/held, datum/target, what)
	TEST_ASSERT_EQUAL(length(held), 1, "[what]: the holder found one target by id")
	TEST_ASSERT_EQUAL(held[1], target, "[what]: and it is the one with the same id")

/// A remote button finds the airlock whose id_tag is its id, and the shield generator whose id is its id.
/datum/unit_test/dq_relation_keyed_remote_buttons

/datum/unit_test/dq_relation_keyed_remote_buttons/Run()
	var/turf/floor = test_floor()
	var/obj/machinery/button/remote/airlock/dq_keyed/button = allocate(/obj/machinery/button/remote/airlock/dq_keyed, floor)
	var/obj/machinery/door/airlock/dq_keyed/door = allocate(/obj/machinery/door/airlock/dq_keyed, floor)
	dq_keyed_found(button.controlled_airlocks, door, "airlock button")
	qdel(door)
	TEST_ASSERT_EQUAL(length(button.controlled_airlocks), 0, "a deleted airlock leaves the button")
	var/obj/machinery/button/remote/shields/dq_keyed/shield_button = allocate(/obj/machinery/button/remote/shields/dq_keyed, floor)
	var/obj/machinery/shield_gen/dq_keyed/gen = allocate(/obj/machinery/shield_gen/dq_keyed, floor)
	dq_keyed_found(shield_button.controlled_shields, gen, "shield button")

/// The id-keyed buttons of the signs, the flasher, the doorbell and the igniters.
/datum/unit_test/dq_relation_keyed_sign_buttons

/datum/unit_test/dq_relation_keyed_sign_buttons/Run()
	var/turf/floor = test_floor()
	var/obj/machinery/button/doorbell/dq_keyed/bell = allocate(/obj/machinery/button/doorbell/dq_keyed, floor)
	var/obj/machinery/doorbell_chime/dq_keyed/chime = allocate(/obj/machinery/doorbell_chime/dq_keyed, floor)
	dq_keyed_found(bell.chimes, chime, "doorbell")
	var/obj/machinery/button/flasher/dq_keyed/flash_button = allocate(/obj/machinery/button/flasher/dq_keyed, floor)
	var/obj/machinery/flasher/dq_keyed/flasher = allocate(/obj/machinery/flasher/dq_keyed, floor)
	dq_keyed_found(flash_button.controlled_flashers, flasher, "flasher")
	var/obj/machinery/button/holosign/dq_keyed/holo_button = allocate(/obj/machinery/button/holosign/dq_keyed, floor)
	var/obj/machinery/holosign/dq_keyed/holo = allocate(/obj/machinery/holosign/dq_keyed, floor)
	dq_keyed_found(holo_button.controlled_signs, holo, "holosign")
	var/obj/machinery/button/neonsign/dq_keyed/neon_button = allocate(/obj/machinery/button/neonsign/dq_keyed, floor)
	var/obj/machinery/neonsign/dq_keyed/neon = allocate(/obj/machinery/neonsign/dq_keyed, floor)
	dq_keyed_found(neon_button.controlled_signs, neon, "neon sign")
	var/obj/machinery/button/ignition/dq_keyed/ignition = allocate(/obj/machinery/button/ignition/dq_keyed, floor)
	var/obj/machinery/sparker/dq_keyed/sparker = allocate(/obj/machinery/sparker/dq_keyed, floor)
	var/obj/machinery/igniter/dq_keyed/igniter = allocate(/obj/machinery/igniter/dq_keyed, floor)
	dq_keyed_found(ignition.controlled_sparkers, sparker, "sparker")
	dq_keyed_found(ignition.controlled_igniters, igniter, "igniter")

/// The pod computer finds its mass driver (one) and its blast doors and drivers (many) by id.
/datum/unit_test/dq_relation_keyed_pod_computer

/datum/unit_test/dq_relation_keyed_pod_computer/Run()
	var/turf/floor = test_floor()
	var/obj/machinery/computer/pod/dq_keyed/computer = allocate(/obj/machinery/computer/pod/dq_keyed, floor)
	var/obj/machinery/mass_driver/dq_keyed/driver = allocate(/obj/machinery/mass_driver/dq_keyed, floor)
	var/obj/machinery/door/blast/dq_keyed/door = allocate(/obj/machinery/door/blast/dq_keyed, floor)
	TEST_ASSERT_EQUAL(computer.connected, driver, "the computer's one driver is the one with its id")
	dq_keyed_found(computer.pod_drivers, driver, "pod drivers")
	dq_keyed_found(computer.pod_doors, door, "pod doors")
	qdel(driver)
	TEST_ASSERT_NULL(computer.connected, "a deleted driver leaves the computer")
	TEST_ASSERT_EQUAL(length(computer.pod_drivers), 0, "and its list")

/// A pair writes both sides and a deleted end clears the other.
/datum/unit_test/dq_relation_links_pairs

/datum/unit_test/dq_relation_links_pairs/Run()
	var/turf/floor = test_floor()
	var/obj/machinery/clonepod/pod = allocate(/obj/machinery/clonepod, floor)
	var/obj/machinery/computer/cloning/console = allocate(/obj/machinery/computer/cloning, floor)
	rel_set(pod, nameof(pod.connected), console)
	TEST_ASSERT(pod in console.pods, "a pod linked to a cloning console is one of its pods")
	qdel(console)
	TEST_ASSERT_NULL(pod.connected, "a deleted console leaves the pod")

	var/obj/machinery/optable/table = allocate(/obj/machinery/optable, floor)
	var/obj/machinery/computer/operating/operating = allocate(/obj/machinery/computer/operating, floor)
	rel_set(operating, nameof(operating.table), table)
	TEST_ASSERT_EQUAL(table.computer, operating, "the table names its computer back")
	qdel(table)
	TEST_ASSERT_NULL(operating.table, "a deleted table leaves the computer")

	var/obj/structure/cable/cable = allocate(/obj/structure/cable, floor)
	var/datum/material_power_overlay/overlay = new
	rel_set(cable, nameof(cable.material_overlay), overlay)
	TEST_ASSERT(cable in overlay.cables, "the overlay lists the cable")
	rel_set(cable, nameof(cable.material_overlay), null)
	TEST_ASSERT(!(cable in overlay.cables), "unlinking the cable takes it off the overlay")
	qdel(overlay)

/// A devour waits out the swallow time as an op on the prey: nothing happens before it ends, the prey is in the belly at the end, and the
/// prey leaving ends it.
/datum/unit_test/dq_vore_devour_is_an_op_with_a_wait

/datum/unit_test/dq_vore_devour_is_an_op_with_a_wait/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	var/obj/belly/belly = pred.vore_organs[1]
	TEST_ASSERT(attempt_to_devour_prey(pred, prey, pred, belly, 3 SECONDS), "the devour starts")
	TEST_ASSERT_NOTNULL(op_pending_of(pred), "the swallow is a pending op of the pred")
	test_time(2 SECONDS)
	TEST_ASSERT(prey.loc != belly, "the prey is not eaten before the swallow time")
	test_time(1.5 SECONDS)
	TEST_ASSERT_EQUAL(prey.loc, belly, "the prey is in the belly when the time is up")
	TEST_ASSERT_NULL(op_pending_of(pred), "and nothing is left pending")
	belly.release_all_contents(TRUE, TRUE)

	TEST_ASSERT(attempt_to_devour_prey(pred, prey, pred, belly, 3 SECONDS), "a second devour starts")
	prey.forceMove(get_step(pred, pred.dir) || pred.loc)
	prey.forceMove(locate(pred.x + 1, pred.y, pred.z))
	test_time(4 SECONDS)
	TEST_ASSERT(prey.loc != belly, "a prey that left the pred's reach is not eaten")

#endif

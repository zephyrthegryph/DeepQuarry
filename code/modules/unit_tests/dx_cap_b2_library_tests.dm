// B2 library capabilities: occupant_pod (code/library/containers/occupant_pod.dm), cap_access and the holder-interface move
// (code/datums/capabilities/library/{parts,access}.dm).

// ---- occupant_pod (code/library/containers/occupant_pod.dm) ----

/// A transport pod that counts what its pod tells it instead of asking for launch.
/obj/machinery/transportpod/dx_b2
	var/entered = 0
	var/exited = 0

CAPABILITIES(/obj/machinery/transportpod/dx_b2)
	on_notice(/datum/notice/pod_left, then(PROC_REF(count_exit)))

/obj/machinery/transportpod/dx_b2/ask_to_launch(datum/act/A)
	entered++

/obj/machinery/transportpod/dx_b2/proc/count_exit(datum/act/A)
	exited++

/// Entering and leaving by every path: the reads, the notices, the refusals, the ops and the destroy spill.
/datum/unit_test/dx_cap_occupant/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/transportpod/dx_b2/pod = allocate(/obj/machinery/transportpod/dx_b2, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NULL(occupant_of(pod), "nobody inside")
	TEST_ASSERT(!occupant_pod_occupied(pod), "the pod's state agrees")
	TEST_ASSERT(occupant_enter(pod, H, H), "occupant_enter() puts them in")
	TEST_ASSERT_EQUAL(H.loc, pod, "inside the pod")
	TEST_ASSERT_EQUAL(occupant_of(pod), H, "occupant_of() reads the ledger slot")
	TEST_ASSERT(occupant_pod_occupied(pod), "OCCUPANT_POD_OCCUPIED is set")
	TEST_ASSERT_EQUAL(pod.entered, 1, "pod_entered was heard once")
	TEST_ASSERT(!occupant_enter(pod, H2, H2), "a full pod refuses a second")
	test_menu(H2, pod, "occupant_pod.eject")
	test_time(1)
	TEST_ASSERT_EQUAL(H.loc, T, "the eject op lets them out onto the pod's turf")
	TEST_ASSERT_EQUAL(pod.exited, 1, "pod_left was heard once")
	test_menu(H2, pod, "occupant_pod.climb_in")
	test_time(1)
	TEST_ASSERT_EQUAL(occupant_of(pod), H2, "Move Inside puts the actor in")
	// A raw ledger move (legacy code) still reaches the pod.
	pod.slot_remove(H2, T)
	TEST_ASSERT_EQUAL(pod.exited, 2, "a raw slot_remove() is heard too")
	TEST_ASSERT(!occupant_pod_occupied(pod), "and empties the pod")
	occupant_enter(pod, H, H)
	qdel(pod)
	TEST_ASSERT(!QDELETED(H), "destroying the pod keeps its occupant")
	TEST_ASSERT_EQUAL(H.loc, T, "spilled onto the turf")
	test_driver_end()

/// The converted pod declares the capability.
/datum/unit_test/dx_cap_occupant_transportpod/Run()
	var/obj/machinery/transportpod/pod = allocate(/obj/machinery/transportpod, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(occupant_pod_of(pod), "the pod declares occupant_pod()")

// ---- cap_access ----

/// The drone console's open op needs a credential (`extend("ui_open", needs(req_access()))`): none refuses, a held card with the access passes, a
/// map edit of the console's req_access wins over the default, and the window's status asks the same providers.
/datum/unit_test/dx_cap_access_console/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/computer/drone_control/C = allocate(/obj/machinery/computer/drone_control, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(op_known_anywhere(null, C, null, "ui_open"), "the console's open op is declared")
	var/datum/op_result/denied = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(denied?.outcome, ACT_REFUSED, "no credential: refused")
	TEST_ASSERT(!access_allowed(C, H), "access_allowed() agrees")
	var/obj/item/card/id/card = allocate(/obj/item/card/id, T)
	card.access = list(ACCESS_ENGINE_EQUIP)
	TEST_ASSERT_EQUAL(access_credential(C, H, card, list(ACCESS_ENGINE_EQUIP), null, list(/obj/item/card/id)), card, "a held card is the provider")
	TEST_ASSERT(access_allowed(C, H, card), "access_allowed() takes the held card")
	dq_test_wear_id(H, card)
	TEST_ASSERT_EQUAL(access_credential(C, H, null, list(ACCESS_ENGINE_EQUIP), null, list(/obj/item/card/id)), H, "a worn ID makes the actor the provider")
	var/datum/op_result/opened = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(opened?.outcome, ACT_COMMITTED, "an empty hand with a worn ID opens it (reason=[opened?.reason])")
	C.req_access = list(ACCESS_CAPTAIN)
	var/datum/op_result/wrong = own(test_click(H, C, null))
	TEST_ASSERT_EQUAL(wrong?.outcome, ACT_REFUSED, "the instance's own req_access wins")
	TEST_ASSERT_EQUAL(access_credential(C, H, null, null, null), H, "nothing required: the actor is the provider")

/// The lock asks the same providers (cap_lock_credential() over access_credential()).
/datum/unit_test/dx_cap_access_lock_shares_providers/Run()
	var/list/needs = access_needs(null, list(ACCESS_ENGINE_EQUIP), null)
	TEST_ASSERT_EQUAL(needs[1][1], ACCESS_ENGINE_EQUIP, "a non-obj holder takes the defaults")
	TEST_ASSERT(access_grants(null, null, null), "nothing required grants")
	TEST_ASSERT(!access_grants(list(ACCESS_ENGINE_EQUIP), null, list()), "no access refuses")
	TEST_ASSERT(access_grants(null, list(ACCESS_ENGINE_EQUIP, ACCESS_CAPTAIN), list(ACCESS_CAPTAIN)), "one of")

// ---- the holder-interface move ----

/// The overridable holder procs live on their capabilities, not on /atom: an atom has none of them, and a holder that
/// needs different behaviour has a capability subtype (the APC's power channels, the airlock's door parts).
/datum/unit_test/dx_holder_interface_on_capabilities/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/I = allocate(/obj/item, T)
	for(var/name in list("power_channel_mode", "set_power_channel_mode", "power_channel_load", "power_breaker", "set_power_breaker", "power_nightshift", "set_power_nightshift", "power_nightshift_lit", "power_channels_lit", "slot_refusal", "slot_inserted", "slot_ejected", "set_bolted", "is_electrified", "electrified_left", "electric_shock", "cap_pry_reason", "cap_pry_name", "cap_pry_force", "door_safeties_on", "emag_message", "emag_committed", "cap_panel_toggle", "wall_mount_orient", "gas_at_port", "wires_type_for", "cap_writable_write"))
		TEST_ASSERT(!hascall(I, name), "/atom has no holder proc [name]")
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, T)
	TEST_ASSERT(set_bolted(door, TRUE, TRUE), "bolting through the airlock's mechanism")
	TEST_ASSERT(is_bolted(door), "bolted")

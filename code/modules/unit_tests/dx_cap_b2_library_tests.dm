// B2 library capabilities: cap_parts, cap_occupant, cap_access, service_panel, and the holder-interface move
// (code/datums/capabilities/library/{parts,occupant,access}.dm, presets.dm service_panel()).

// ---- cap_parts ----

/// The cell charger's efficiency is derived from its capacitors: right at init, and again when the parts relation
/// changes (the parts capability's on_change reaction), with no RefreshParts() override.
/datum/unit_test/dx_cap_parts_derived/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/cell_charger/C = allocate(/obj/machinery/cell_charger, T)
	TEST_ASSERT_NOTNULL(cap_of(C, /datum/capability/parts), "the charger declares cap_parts()")
	var/rating = part_rating(C, /obj/item/stock_parts/capacitor)
	TEST_ASSERT(rating >= 1, "its capacitor counts (latent or real): [rating]")
	TEST_ASSERT_EQUAL(C.efficiency, C.active_power_usage * (1 + (rating - 1) * 0.5), "efficiency derived from the parts at init")
	C.materialize_parts()
	var/obj/item/stock_parts/capacitor/old = locate() in C.component_parts
	TEST_ASSERT_NOTNULL(old, "a real capacitor once materialized")
	own_take_member(C, nameof(C.component_parts), old)
	qdel(old)
	var/obj/item/stock_parts/capacitor/better = allocate(/obj/item/stock_parts/capacitor, T)
	better.rating = 3
	better.move_into(C, CONTAINER_SLOT_INTERNALS)
	own_add(C, nameof(C.component_parts), better)
	rx_drain()
	TEST_ASSERT_EQUAL(part_rating(C, /obj/item/stock_parts/capacitor), 3, "the rating follows the relation")
	TEST_ASSERT_EQUAL(C.efficiency, C.active_power_usage * 2, "efficiency re-derived from the relation change")
	TEST_ASSERT_NOTNULL(cap_test_entry(C, "parts:rped"), "the RPED goes through the parts capability's op")

/// part_rating()'s aggregates and part_stat()'s formula.
/datum/unit_test/dx_cap_parts_aggregates/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/storage/box/B = allocate(/obj/item/storage/box, T)
	for(var/r in list(1, 2, 4))
		var/obj/item/stock_parts/capacitor/P = allocate(/obj/item/stock_parts/capacitor, T)
		P.rating = r
		P.forceMove(B)
	TEST_ASSERT_EQUAL(part_rating(B, /obj/item/stock_parts/capacitor), 7, "sum")
	TEST_ASSERT_EQUAL(part_rating(B, /obj/item/stock_parts/capacitor, PART_RATING_MIN), 1, "min")
	TEST_ASSERT_EQUAL(part_rating(B, /obj/item/stock_parts/capacitor, PART_RATING_MAX), 4, "max")
	TEST_ASSERT_EQUAL(part_rating(B, /obj/item/stock_parts/capacitor, PART_RATING_COUNT), 3, "count")
	TEST_ASSERT_EQUAL(part_rating(B, /obj/item/stock_parts/manipulator), 0, "none: 0")

// ---- cap_occupant ----

/// A transport pod that counts its occupant hooks instead of asking for launch.
/obj/machinery/transportpod/dx_b2
	var/entered = 0
	var/exited = 0

/obj/machinery/transportpod/dx_b2/capabilities()
	. = ..()
	. = replace(., "occupant:[OCCUPANT_SLOT_TRANSPORTPOD]", cap_occupant(OCCUPANT_SLOT_TRANSPORTPOD, types = /mob/living/carbon/human, on_enter = PROC_REF(occupant_entered), on_exit = PROC_REF(occupant_left), self_name = "Enter Pod", eject_name = "Eject Pod"))

/obj/machinery/transportpod/dx_b2/occupant_entered(mob/living/O)
	entered++

/obj/machinery/transportpod/dx_b2/proc/occupant_left(mob/living/O)
	exited++

/// Entering and leaving by every path: the reads, the hooks, the refusals, the ops and the destroy spill.
/datum/unit_test/dx_cap_occupant/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/transportpod/dx_b2/pod = allocate(/obj/machinery/transportpod/dx_b2, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(length(occupants(pod)), 0, "occupants() is an empty list, never null")
	TEST_ASSERT_NULL(occupant_of(pod), "nobody inside")
	TEST_ASSERT(occupant_enter(pod, H, H), "occupant_enter() puts them in")
	TEST_ASSERT_EQUAL(H.loc, pod, "inside the pod")
	TEST_ASSERT_EQUAL(occupant_of(pod), H, "occupant_of() reads the ledger slot")
	TEST_ASSERT_EQUAL(pod.entered, 1, "on_enter ran once")
	TEST_ASSERT(!occupant_enter(pod, H2, H2), "a full pod refuses a second")
	TEST_ASSERT_NOTNULL(test_op(H2, pod, "enter_[OCCUPANT_SLOT_TRANSPORTPOD]_self"), "and its climb-in op says why")
	TEST_ASSERT(perform_op(H2, pod, "eject_[OCCUPANT_SLOT_TRANSPORTPOD]"), "the eject op lets them out")
	TEST_ASSERT_EQUAL(H.loc, T, "out on the pod's turf")
	TEST_ASSERT_EQUAL(pod.exited, 1, "on_exit ran once")
	TEST_ASSERT(perform_op(H2, pod, "enter_[OCCUPANT_SLOT_TRANSPORTPOD]_self"), "the climb-in op")
	TEST_ASSERT_EQUAL(occupant_of(pod), H2, "the second is inside")
	// A raw ledger move (legacy code) still reaches the capability.
	pod.slot_remove(H2, T)
	TEST_ASSERT_EQUAL(pod.exited, 2, "a raw slot_remove() runs on_exit too")
	TEST_ASSERT_EQUAL(length(occupants(pod)), 0, "empty again")
	occupant_enter(pod, H, H)
	qdel(pod)
	TEST_ASSERT(!QDELETED(H), "destroying the pod keeps its occupant")
	TEST_ASSERT_EQUAL(H.loc, T, "spilled onto the turf")

/// The converted pod declares the capability and draws from it.
/datum/unit_test/dx_cap_occupant_transportpod/Run()
	var/obj/machinery/transportpod/pod = allocate(/obj/machinery/transportpod, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(occupant_cap(pod, OCCUPANT_SLOT_TRANSPORTPOD), "the pod has cap_occupant()")
	TEST_ASSERT_NOTNULL(op_entry_named(null, pod, "eject_[OCCUPANT_SLOT_TRANSPORTPOD]"), "its eject op")

// ---- cap_access ----

/// The drone console's open op needs a credential: none refuses, a held card with the access passes, a map edit of
/// the console's req_access wins over the default, and the window's status asks the same providers.
/datum/unit_test/dx_cap_access_console/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/computer/drone_control/C = allocate(/obj/machinery/computer/drone_control, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NOTNULL(cap_of(C, /datum/capability/require/access), "the console declares cap_access()")
	TEST_ASSERT_NOTNULL(test_op(H, C, "open_console"), "no credential: refused")
	TEST_ASSERT(!access_allowed(C, H), "access_allowed() agrees")
	var/obj/item/card/id/card = allocate(/obj/item/card/id, T)
	card.access = list(ACCESS_ENGINE_EQUIP)
	TEST_ASSERT_EQUAL(access_credential(C, H, card, list(ACCESS_ENGINE_EQUIP), null, list(/obj/item/card/id)), card, "a held card is the provider")
	TEST_ASSERT(access_allowed(C, H, card), "access_allowed() takes the held card")
	dq_test_wear_id(H, card)
	TEST_ASSERT_EQUAL(access_credential(C, H, null, list(ACCESS_ENGINE_EQUIP), null, list(/obj/item/card/id)), H, "a worn ID makes the actor the provider")
	TEST_ASSERT_NULL(test_op(H, C, "open_console"), "an empty hand with a worn ID opens it")
	C.req_access = list(ACCESS_CAPTAIN)
	TEST_ASSERT_NOTNULL(test_op(H, C, "open_console"), "the instance's own req_access wins")
	TEST_ASSERT_EQUAL(access_credential(C, H, null, null, null), H, "nothing required: the actor is the provider")

/// The lock asks the same providers (cap_lock_credential() over access_credential()).
/datum/unit_test/dx_cap_access_lock_shares_providers/Run()
	var/list/needs = access_needs(null, list(ACCESS_ENGINE_EQUIP), null)
	TEST_ASSERT_EQUAL(needs[1][1], ACCESS_ENGINE_EQUIP, "a non-obj holder takes the defaults")
	TEST_ASSERT(access_grants(null, null, null), "nothing required grants")
	TEST_ASSERT(!access_grants(list(ACCESS_ENGINE_EQUIP), null, list()), "no access refuses")
	TEST_ASSERT(access_grants(null, list(ACCESS_ENGINE_EQUIP, ACCESS_CAPTAIN), list(ACCESS_CAPTAIN)), "one of")

// ---- service_panel ----

/obj/cap_fixture/service_panel/capabilities()
	. = ..()
	. += service_panel(/datum/wires/cap_fixture, access = list(ACCESS_ENGINE_EQUIP), emag_say = "Zap.")

/// The bundle: panel, wires behind it, the access contract on opening the panel (waived when emagged), the emag.
/datum/unit_test/dx_cap_service_panel/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/cap_fixture/service_panel/A = allocate(/obj/cap_fixture/service_panel, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	for(var/path in list(/datum/capability/panel, /datum/capability/wires, /datum/capability/emag))
		TEST_ASSERT_NOTNULL(cap_of(A, path), "service_panel() gives [path]")
	var/obj/item/tool/screwdriver/driver = allocate(/obj/item/tool/screwdriver, T)
	H.put_in_active_hand(driver)
	TEST_ASSERT_NOTNULL(test_op(H, A, "open_maintenance_panel"), "the panel needs the access")
	cap_set(A, CAP_EMAGGED, TRUE)
	TEST_ASSERT_NULL(test_op(H, A, "open_maintenance_panel"), "an emagged panel opens for anyone")
	var/obj/machinery/vending/V = allocate(/obj/machinery/vending/coffee, T)
	TEST_ASSERT_NOTNULL(cap_of(V, /datum/capability/wires), "the vendor's service panel has its wires")
	TEST_ASSERT_NOTNULL(cap_of(V, /datum/capability/emag), "and its emag")

// ---- the holder-interface move ----

/// The overridable holder procs live on their capabilities, not on /atom: an atom has none of them, and a holder that
/// needs different behaviour has a capability subtype (the APC's power channels, the airlock's door parts).
/datum/unit_test/dx_holder_interface_on_capabilities/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/I = allocate(/obj/item, T)
	for(var/name in list("power_channel_mode", "set_power_channel_mode", "power_channel_load", "power_breaker", "set_power_breaker", "power_nightshift", "set_power_nightshift", "power_nightshift_lit", "power_channels_lit", "slot_refusal", "slot_inserted", "slot_ejected", "set_bolted", "is_electrified", "electrified_left", "electric_shock", "cap_pry_reason", "cap_pry_name", "cap_pry_force", "door_safeties_on", "emag_message", "emag_committed", "cap_panel_toggle", "wall_mount_orient", "gas_at_port", "wires_type_for", "cap_writable_write"))
		TEST_ASSERT(!hascall(I, name), "/atom has no holder proc [name]")
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, T)
	TEST_ASSERT(istype(cap_of(door, /datum/capability/bolts), /datum/capability/bolts/airlock), "the airlock's bolts subtype")
	TEST_ASSERT(set_bolted(door, TRUE, TRUE), "bolting through the airlock's mechanism")
	TEST_ASSERT(is_bolted(door), "bolted")

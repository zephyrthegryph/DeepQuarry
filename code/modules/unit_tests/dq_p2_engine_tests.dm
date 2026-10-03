// The gate of the phase-2 engine pieces: the hit bridge (receive_damage() starts the engine's hit action for a holder that hooks it: instead takes the hit
// over, needs refuses it, adjusts changes the packet, on_notice hears it after the sink; a holder nothing hooks allocates nothing; the legacy damage reactions
// still run) and ruined() in a state-graph dismantle. The fixtures are code/tests/engine/p2_fixtures.dm.

/// Base: the kernel on its injected clock around the test, a clean driver after.
/datum/unit_test/dq_p2_engine
	abstract_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/dq_p2_engine/Run()
	test_driver_begin()
	run_gate()
	test_driver_end()

/datum/unit_test/dq_p2_engine/proc/run_gate()
	return

/// Delivers `amount` blunt damage as the entry `entry` to `target` and returns what receive_damage() answered.
/datum/unit_test/dq_p2_engine/proc/deliver(atom/target, entry, amount = 40, armor_flag = null)
	var/datum/damage_packet/packet = damage_packet(null, null, null, null, DAMAGE_PACKET_SILENT, 0, 0, armor_flag, entry, 1)
	packet.add(DAMAGE_BLUNT, amount)
	. = target.receive_damage(packet)
	packet.release()

// ---------------------------------------------------------------------------------------------------------------------
// instead() takes an EMP over; the unhooked sibling takes the damage as before.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/hit_instead_takes_over

/datum/unit_test/dq_p2_engine/hit_instead_takes_over/run_gate()
	var/obj/p2_hit/taker/hooked = allocate(/obj/p2_hit/taker)
	var/obj/p2_hit/plain/plain = allocate(/obj/p2_hit/plain)
	var/answered_hooked = deliver(hooked, DAMAGE_ENTRY_EMP)
	var/outcome = GLOB.act_last_outcome
	var/integrity_after_emp = hooked.get_integrity()
	var/answered_plain = deliver(plain, DAMAGE_ENTRY_EMP)
	var/hooked_projectile = deliver(hooked, DAMAGE_ENTRY_PROJECTILE) // the hook is on the emp hit only: a projectile lands
	TEST_ASSERT_EQUAL(hooked.took, 1, "the instead handler ran once")
	TEST_ASSERT_EQUAL(answered_hooked, 0, "a taken-over hit applies nothing")
	TEST_ASSERT_EQUAL(integrity_after_emp, hooked.max_integrity, "the sink did not run: integrity is unchanged")
	TEST_ASSERT_EQUAL(outcome, ACT_REPLACED, "the hit ended replaced")
	TEST_ASSERT(hooked_projectile > 0 && hooked.get_integrity() < hooked.max_integrity, "a projectile on the same type is not taken over")
	TEST_ASSERT(answered_plain > 0, "the unhooked sibling took the damage")
	TEST_ASSERT_EQUAL(plain.get_integrity(), plain.max_integrity - answered_plain, "its integrity went down by what landed")

// ---------------------------------------------------------------------------------------------------------------------
// adjusts() halves a hit (through the generic hit, for an entry with its own subtype); needs() refuses one.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/hit_adjusts_halves

/datum/unit_test/dq_p2_engine/hit_adjusts_halves/run_gate()
	var/obj/p2_hit/halver/H = allocate(/obj/p2_hit/halver)
	var/obj/p2_hit/plain/plain = allocate(/obj/p2_hit/plain)
	var/full = deliver(plain, DAMAGE_ENTRY_PROJECTILE)
	var/halved = deliver(H, DAMAGE_ENTRY_PROJECTILE) // a hook of /datum/act/hit applies to the projectile hit
	var/halved_direct = deliver(H, 0) // a direct delivery is the generic hit itself
	TEST_ASSERT(full > 0, "the plain one took damage")
	TEST_ASSERT_EQUAL(halved, full * 0.5, "adjusts(packet.amounts, scale = 0.5) halved the projectile")
	TEST_ASSERT_EQUAL(halved_direct, full * 0.5, "and the direct hit")

/datum/unit_test/dq_p2_engine/hit_needs_refuses

/datum/unit_test/dq_p2_engine/hit_needs_refuses/run_gate()
	var/obj/p2_hit/halver/H = allocate(/obj/p2_hit/halver)
	var/answered = deliver(H, 0, 40, FIRE)
	TEST_ASSERT_EQUAL(answered, 0, "a refused hit lands nothing")
	TEST_ASSERT_EQUAL(H.get_integrity(), H.max_integrity, "integrity is unchanged")
	TEST_ASSERT_EQUAL(GLOB.act_last_outcome, ACT_REFUSED, "the fire hit ended refused")

// ---------------------------------------------------------------------------------------------------------------------
// on_notice(/datum/notice/hit/blob) fires after the sink.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/hit_notice_after_sink

/datum/unit_test/dq_p2_engine/hit_notice_after_sink/run_gate()
	var/obj/p2_hit/listener/L = allocate(/obj/p2_hit/listener)
	deliver(L, DAMAGE_ENTRY_EMP) // another entry: not heard
	var/heard_after_emp = L.heard
	var/landed = deliver(L, DAMAGE_ENTRY_BLOB)
	TEST_ASSERT_EQUAL(heard_after_emp, 0, "a notice of another hit kind is not delivered")
	TEST_ASSERT_EQUAL(L.heard, 1, "the blob hit's notice was delivered")
	TEST_ASSERT(landed > 0, "the hit landed")
	TEST_ASSERT_EQUAL(L.integrity_when_heard, L.get_integrity(), "the listener saw the integrity after the sink, not before it")
	TEST_ASSERT(L.integrity_when_heard < L.max_integrity, "which is below the maximum")

// ---------------------------------------------------------------------------------------------------------------------
// A holder with no hooks allocates nothing.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/hit_unhooked_allocates_nothing

/datum/unit_test/dq_p2_engine/hit_unhooked_allocates_nothing/run_gate()
	var/obj/p2_hit/plain/plain = allocate(/obj/p2_hit/plain)
	var/acts = GLOB.act_taken
	var/notices = GLOB.notice_taken
	for(var/entry in list(0, DAMAGE_ENTRY_PROJECTILE, DAMAGE_ENTRY_EMP, DAMAGE_ENTRY_EXPLOSION, DAMAGE_ENTRY_BLOB, DAMAGE_ENTRY_WEAPON, DAMAGE_ENTRY_SHOCK, DAMAGE_ENTRY_THROWN))
		deliver(plain, entry, 1)
	deliver(plain, 0, 1, FIRE)
	TEST_ASSERT_EQUAL(GLOB.act_taken, acts, "no act context was taken for an unhooked holder")
	TEST_ASSERT_EQUAL(GLOB.notice_taken, notices, "and no notice")
	TEST_ASSERT(plain.get_integrity() < plain.max_integrity, "yet the hits landed")

// ---------------------------------------------------------------------------------------------------------------------
// The legacy DAMAGE_REACTION rows still run, alone and beside a new hook (the hook first).
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/hit_legacy_rows_still_run

/datum/unit_test/dq_p2_engine/hit_legacy_rows_still_run/run_gate()
	var/obj/p2_hit/legacy/L = allocate(/obj/p2_hit/legacy)
	var/answered = deliver(L, DAMAGE_ENTRY_EMP)
	var/ran = L.legacy
	var/integrity_after_block = L.get_integrity()
	L.legacy_blocks = FALSE
	var/landed = deliver(L, DAMAGE_ENTRY_EMP)
	TEST_ASSERT_EQUAL(ran, 1, "the legacy before_op row ran")
	TEST_ASSERT_EQUAL(answered, 0, "and its block stopped the hit")
	TEST_ASSERT_EQUAL(integrity_after_block, L.max_integrity, "integrity is unchanged")
	TEST_ASSERT(landed > 0, "a row that does not block lets the hit land")

/datum/unit_test/dq_p2_engine/hit_hook_then_legacy_row

/datum/unit_test/dq_p2_engine/hit_hook_then_legacy_row/run_gate()
	var/obj/p2_hit/both/B = allocate(/obj/p2_hit/both)
	var/obj/p2_hit/plain/plain = allocate(/obj/p2_hit/plain)
	var/full = deliver(plain, DAMAGE_ENTRY_EMP)
	var/answered = deliver(B, DAMAGE_ENTRY_EMP)
	TEST_ASSERT_EQUAL(B.legacy, 1, "the legacy row ran")
	TEST_ASSERT_EQUAL(answered, full * 0.5, "after the hook halved the packet")

// ---------------------------------------------------------------------------------------------------------------------
// ruined() in dismantle: the ruined parts replace the ordinary ones; the ledger is refunded either way.
// ---------------------------------------------------------------------------------------------------------------------

/// The cable units on `where`'s turf (a refunded stack may merge into the one already there).
/datum/unit_test/dq_p2_engine/proc/coil_units(atom/where)
	. = 0
	for(var/obj/item/stack/cable_coil/C in get_turf(where))
		. += C.amount

/// Wires the frame (the build edge spends five cable units), dismantles it with a crowbar and returns the cable units that came back.
/datum/unit_test/dq_p2_engine/proc/wire_and_dismantle(obj/p2_frame/F, mob/living/simple_mob/e0_fixture/M)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar)
	var/turf/floor = get_turf(F)
	var/units = coil_units(floor)
	var/datum/op_result/wired = test_click(M, F, coil)
	TEST_ASSERT_EQUAL(wired?.key, "construction.build:door_wired", "the frame was wired")
	var/units_wired = coil_units(floor)
	TEST_ASSERT_EQUAL(units_wired, units - 5, "the edge spent five units")
	var/datum/op_result/taken = test_click(M, F, crowbar)
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(taken?.key, "construction.dismantle", "the crowbar click is the dismantle")
	TEST_ASSERT_EQUAL(taken?.outcome, ACT_COMMITTED, "and it commits")
	return coil_units(floor) - units_wired

/datum/unit_test/dq_p2_engine/dismantle_ordinary_yields_the_frame

/datum/unit_test/dq_p2_engine/dismantle_ordinary_yields_the_frame/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/p2_frame/F = allocate(/obj/p2_frame)
	var/turf/floor = get_turf(F)
	var/refunded = wire_and_dismantle(F, M)
	TEST_ASSERT(!isnull(locate(/obj/item/p2_frame_item) in floor), "an intact frame dismantles to the frame item")
	TEST_ASSERT(isnull(locate(/obj/item/p2_scrap) in floor), "and no scrap")
	TEST_ASSERT(QDELETED(F), "the frame is gone")
	TEST_ASSERT_EQUAL(refunded, 5, "the five cable units of the ledger came back")
	own_turf_contents(floor)

/datum/unit_test/dq_p2_engine/dismantle_ruined_yields_scrap

/datum/unit_test/dq_p2_engine/dismantle_ruined_yields_scrap/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/p2_frame/F = allocate(/obj/p2_frame)
	F.wrecked = TRUE
	var/turf/floor = get_turf(F)
	var/refunded = wire_and_dismantle(F, M)
	TEST_ASSERT(!isnull(locate(/obj/item/p2_scrap) in floor), "a ruined frame dismantles to scrap")
	TEST_ASSERT(isnull(locate(/obj/item/p2_frame_item) in floor), "and not the frame item")
	TEST_ASSERT(QDELETED(F), "the frame is gone")
	TEST_ASSERT_EQUAL(refunded, 5, "the ledger is refunded exactly as for an ordinary dismantle")
	own_turf_contents(floor)

// ---------------------------------------------------------------------------------------------------------------------
// gesture(G) alone is enough: a drag op answers a drag, a use op a click, and the two do not clash.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/pinned_gesture_answers_its_own_intents

/datum/unit_test/dq_p2_engine/pinned_gesture_answers_its_own_intents/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/p2_dragtarget/T = allocate(/obj/p2_dragtarget, get_turf(H))
	var/obj/item/pen = allocate(/obj/item/pen, get_turf(H))
	TEST_ASSERT(assert_resolves(H, T, pen, GESTURE_CLICK, "use"), "a click with the item is the use")
	TEST_ASSERT(assert_resolves(H, T, pen, GESTURE_DRAG, "drag"), "a drag of the item is the drag op")
	test_click(H, T, pen, GESTURE_DRAG)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.dragged, 1, "the drag ran")
	TEST_ASSERT_EQUAL(T.used, 0, "and the use did not")
	test_click(H, T, pen)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.used, 1, "a click runs the use")
	TEST_ASSERT_EQUAL(T.dragged, 1, "and not the drag")

// ---------------------------------------------------------------------------------------------------------------------
// A legacy entry interaction answers the shape of input its handler did: attack_hand an empty hand, attackby a held item used on something else.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/legacy_entries_fit_the_input

/datum/unit_test/dq_p2_engine/legacy_entries_fit_the_input/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/p2_legacy_target/T = allocate(/obj/p2_legacy_target)
	var/obj/item/p2_op_item/I = allocate(/obj/item/p2_op_item)
	H.drop_item()
	H.put_in_active_hand(I)
	test_click(H, T, I)
	TEST_ASSERT_EQUAL(T.touched, 0, "an item in hand is not given the touch of an empty hand")
	TEST_ASSERT_EQUAL(T.used_with, 1, "the entry for an item used on it ran")
	H.drop_item()
	test_click(H, T, null)
	TEST_ASSERT_EQUAL(T.touched, 1, "an empty hand touches it")
	TEST_ASSERT_EQUAL(T.used_with, 1, "and uses no item on it")
	own_turf_contents(get_turf(T))

// ---------------------------------------------------------------------------------------------------------------------
// A turf is something an op can be done at: the surface of a turf is the turf (its loc is an area, which nobody touches).
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/an_op_at_a_turf_is_reached

/datum/unit_test/dq_p2_engine/an_op_at_a_turf_is_reached/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/p2_op_item/I = allocate(/obj/item/p2_op_item)
	H.drop_item()
	H.put_in_active_hand(I)
	var/turf/own = get_turf(H)
	test_click(H, own, I)
	TEST_ASSERT_EQUAL(I.tapped, 1, "the turf the actor stands on is reached")
	var/turf/near = get_step(own, EAST)
	test_click(H, near, I)
	TEST_ASSERT_EQUAL(I.tapped, 2, "and the one beside it")
	var/turf/far = locate(own.x + 6, own.y, own.z)
	test_click(H, far, I)
	TEST_ASSERT_EQUAL(I.tapped, 2, "but not one six tiles away")

// ---------------------------------------------------------------------------------------------------------------------
// without(CAP_X) of a bundle drops what the bundle brought, a capability of its own included, with everything that one brought.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/without_drops_a_bundles_nested_capability

/datum/unit_test/dq_p2_engine/without_drops_a_bundles_nested_capability/run_gate()
	var/obj/p2_bundled/whole = allocate(/obj/p2_bundled)
	var/obj/p2_bundled/stripped/bare = allocate(/obj/p2_bundled/stripped)
	TEST_ASSERT_NOTNULL(cap_of(whole, CAP_REAGENT_CONTAINER), "the bundle brings its nested capability")
	TEST_ASSERT_NOTNULL(op_plan_for(whole, "reagent_container.set_amount"), "and its ops")
	TEST_ASSERT_NULL(cap_of(bare, CAP_REAGENT_CONTAINER), "a subtype without the bundle has no nested capability")
	TEST_ASSERT_NULL(op_plan_for(bare, "reagent_container.set_amount"), "and none of its ops")
	TEST_ASSERT_NULL(bare.reagents, "and no holder made by it")

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
// A player's click and drag run their ops with the click's parameters readable (an item put on a table aligns to where it was clicked), and a player's
// drag of an item onto something with ops of its own reaches the op that answers a drag.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/a_players_click_carries_its_parameters

/datum/unit_test/dq_p2_engine/a_players_click_carries_its_parameters/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/p2_dragtarget/T = allocate(/obj/p2_dragtarget, get_step(H, NORTH))
	var/obj/item/pen = allocate(/obj/item/pen, get_turf(H))
	H.put_in_active_hand(pen)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, T, null, "mapwindow.map", "icon-x=5;icon-y=7;left=1"))
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.used, 1, "the click ran the use op")
	TEST_ASSERT(findtext(T.seen_params, "icon-x=5"), "the op saw where the click landed")
	TEST_ASSERT_NULL(dq_interaction_click_params(H), "and the parameters are gone when it is done")

/datum/unit_test/dq_p2_engine/a_players_drag_reaches_an_op

/datum/unit_test/dq_p2_engine/a_players_drag_reaches_an_op/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/p2_dragtarget/T = allocate(/obj/p2_dragtarget, get_step(H, NORTH))
	var/obj/item/pen = allocate(/obj/item/pen, get_step(H, EAST))
	var/datum/input_adapter/adapter = H.input_adapter()
	adapter.drag(H, pen, T, null, null, null, null, "icon-x=3;icon-y=4;left=1")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.dragged, 1, "the drag op ran")
	TEST_ASSERT_EQUAL(T.used, 0, "and the use op did not")
	TEST_ASSERT(findtext(T.seen_params, "icon-x=3"), "it saw where the drag was dropped")
	TEST_ASSERT_NULL(dq_interaction_click_params(H), "and the parameters are gone when it is done")

/datum/unit_test/dq_p2_engine/a_drag_onto_a_thing_without_ops_is_left_to_it

/datum/unit_test/dq_p2_engine/a_drag_onto_a_thing_without_ops_is_left_to_it/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/p2_dragtarget/T = allocate(/obj/p2_dragtarget, get_step(H, NORTH))
	var/obj/item/pen = allocate(/obj/item/pen, get_step(H, EAST))
	var/obj/item/other = allocate(/obj/item/pen, get_step(H, WEST))
	var/datum/input_adapter/adapter = H.input_adapter()
	adapter.drag(H, pen, other, null, null, null, null, "left=1")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.dragged, 0, "a drag onto another thing does not reach the target")

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

// ---------------------------------------------------------------------------------------------------------------------
// An item that does no harm reaches its own afterattack when it is clicked on a person next to the clicker (attack() did nothing: its answer is a
// failure, not a verdict that the click was used); an item whose attack() used the click does not.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/a_harmless_item_reaches_afterattack_on_a_mob

/datum/unit_test/dq_p2_engine/a_harmless_item_reaches_afterattack_on_a_mob/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human)
	var/obj/item/p2_afterattacker/plain = allocate(/obj/item/p2_afterattacker)
	var/obj/item/p2_afterattacker/attacker/using = allocate(/obj/item/p2_afterattacker/attacker)
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		var/before = plain.reached
		H.drop_item()
		H.put_in_active_hand(plain)
		H.set_use_stance(stance)
		H.next_click = 0
		input_submit(new /datum/input_event/click(H, other, null, null, "left=1"))
		TEST_ASSERT_EQUAL(plain.reached - before, 1, "in the [stance] stance a click on a person reaches the harmless item's afterattack")
	H.set_use_stance(I_HELP)
	H.drop_item()
	H.put_in_active_hand(using)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, other, null, null, "left=1"))
	TEST_ASSERT_EQUAL(using.reached, 0, "an item whose attack() used the click does not reach afterattack")
	H.set_use_stance(I_HELP)

// ---------------------------------------------------------------------------------------------------------------------
// asks(when =): the step is skipped, with no prompt, while its condition does not hold, and asks as ever while it does.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/asks_when_skips_the_prompt_until_it_holds

/datum/unit_test/dq_p2_engine/asks_when_skips_the_prompt_until_it_holds/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/p2_asker/T = allocate(/obj/p2_asker)
	test_ui(H, T, "ask")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.ran, 1, "while the condition does not hold the op runs at once, with no question")
	TEST_ASSERT_NULL(T.asked_value, "and there is no answer")
	T.want = TRUE
	test_ui(H, T, "ask")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.ran, 1, "while it holds the op waits for the answer")
	test_answer(H, 7)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(T.ran, 2, "and runs once it is answered")
	TEST_ASSERT_EQUAL(T.asked_value, 7, "with the answer in hand")

// ---------------------------------------------------------------------------------------------------------------------
// A subtype's own interface() replaces the window it inherits (without("ui_open") drops the inherited open op).
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/a_subtype_window_replaces_the_inherited_one

/datum/unit_test/dq_p2_engine/a_subtype_window_replaces_the_inherited_one/run_gate()
	var/obj/p2_windowed/first = allocate(/obj/p2_windowed)
	var/obj/p2_windowed/second/second = allocate(/obj/p2_windowed/second)
	TEST_ASSERT_EQUAL(first.ui_interface(), "P2First", "a holder opens the window it declares")
	TEST_ASSERT_EQUAL(second.ui_interface(), "P2Second", "its subtype opens its own")
	TEST_ASSERT_NOTNULL(op_plan_for(second, "ui_open"), "and still has one open op")


// ---------------------------------------------------------------------------------------------------------------------
// every() takes a PROC_REF for its interval and asks it before every run.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/every_asks_a_proc_for_its_gap

/datum/unit_test/dq_p2_engine/every_asks_a_proc_for_its_gap/run_gate()
	var/obj/p2_pulse/P = allocate(/obj/p2_pulse)
	test_time(12)
	// gaps 2, 4, 2, 4: runs at 2, 6, 8 and 12
	TEST_ASSERT_EQUAL(P.pulses, 4, "four runs in twelve deciseconds")
	TEST_ASSERT(P.gaps_asked >= 4, "the gap is asked again before each run")

// ---------------------------------------------------------------------------------------------------------------------
// req(silent = TRUE): refuses like any requirement but tells the actor nothing.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/a_silent_requirement_refuses_without_a_message

/datum/unit_test/dq_p2_engine/a_silent_requirement_refuses_without_a_message/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/p2_silent/T = allocate(/obj/p2_silent)
	var/datum/op_result/quiet = test_ui(H, T, "press")
	TEST_ASSERT_EQUAL(quiet?.outcome, ACT_REFUSED, "the press is refused while the guard fails")
	TEST_ASSERT_EQUAL(quiet?.reason, /datum/msg/req_silent, "with the silent reason")
	TEST_ASSERT(!reason_text(quiet?.reason), "which has no text to tell the actor")
	var/datum/op_result/loud = test_ui(H, T, "press_loud")
	TEST_ASSERT_EQUAL(loud?.outcome, ACT_REFUSED, "the same guard without silent is refused too")
	TEST_ASSERT(!!reason_text(loud?.reason), "and says why")
	TEST_ASSERT_EQUAL(T.pressed, 0, "neither ran the handler")
	T.open = TRUE
	test_ui(H, T, "press")
	TEST_ASSERT_EQUAL(T.pressed, 1, "once the guard holds the press runs")

// ---------------------------------------------------------------------------------------------------------------------
// A window hosted by a datum: ui_data() and the window's buttons work without an atom to reach.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/a_datum_hosts_a_window

/datum/unit_test/dq_p2_engine/a_datum_hosts_a_window/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/p2_panel/P = new
	var/list/data = list()
	present_tgui_data(P, H, data)
	TEST_ASSERT_EQUAL(data["pressed"], 0, "the datum's ui_data() output is the window's data")
	TEST_ASSERT_EQUAL(data["viewer"], "[H]", "with the viewer on the act")
	TEST_ASSERT_EQUAL(P.ui_interface(H), "P2Panel", "and the window it declares is the one it opens")
	var/datum/op_result/pressed = test_ui(H, P, "panel_press")
	TEST_ASSERT_EQUAL(pressed?.outcome, ACT_COMMITTED, "a button on it runs as an op")
	TEST_ASSERT_EQUAL(P.pressed, 1, "and its handler ran")
	qdel(P)

// ---------------------------------------------------------------------------------------------------------------------
// open_request(ask_flags =, rights =, usable_state =): the answer is re-checked when it arrives; a failure ends the request cancelled.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/request_rechecks_drop_an_answer_that_no_longer_holds

/datum/unit_test/dq_p2_engine/request_rechecks_drop_an_answer_that_no_longer_holds/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/p2_asker_item/I = allocate(/obj/item/p2_asker_item)
	// held: the subject must still be in the asker's hands
	open_request(I, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, ask_flags = ASK_HELD)
	test_answer(H, TRUE)
	TEST_ASSERT_EQUAL(I.handled, 1, "the handler runs when the request ends")
	TEST_ASSERT_NULL(I.seen_answer, "but an item that is not in the asker's hands drops the answer")
	H.put_in_active_hand(I)
	open_request(I, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, ask_flags = ASK_HELD)
	test_answer(H, TRUE)
	TEST_ASSERT_EQUAL(I.handled, 2, "again")
	TEST_ASSERT_EQUAL(I.seen_answer, TRUE, "and the answer stands while it is held")
	// conscious: the answerer must still be awake
	open_request(I, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, ask_flags = ASK_CONSCIOUS)
	H.set_stat(UNCONSCIOUS)
	test_answer(H, TRUE)
	TEST_ASSERT_NULL(I.seen_answer, "an answerer who fell unconscious has no answer")
	H.set_stat(CONSCIOUS)
	open_request(I, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, ask_flags = ASK_CONSCIOUS)
	test_answer(H, TRUE)
	TEST_ASSERT_EQUAL(I.seen_answer, TRUE, "an awake one does")
	// inside: the answerer must be directly inside the subject
	open_request(I, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, ask_flags = ASK_INSIDE)
	test_answer(H, TRUE)
	TEST_ASSERT_NULL(I.seen_answer, "an answerer outside the subject has no answer")
	// rights: the answerer's player must hold them
	open_request(I, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, rights = R_ADMIN)
	test_answer(H, TRUE)
	TEST_ASSERT_NULL(I.seen_answer, "a player with no admin rights has no answer")
	// no flags: nothing is re-checked
	open_request(I, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H)
	test_answer(H, TRUE)
	TEST_ASSERT_EQUAL(I.seen_answer, TRUE, "a request that names no re-check keeps every answer")

// ---------------------------------------------------------------------------------------------------------------------
// The choice ring's options: require_near drops an answer given out of reach of the anchor.
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/a_radial_prompt_drops_an_answer_out_of_reach

/datum/unit_test/dq_p2_engine/a_radial_prompt_drops_an_answer_out_of_reach/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/p2_asker_item/I = allocate(/obj/item/p2_asker_item)
	var/obj/item/p2_asker_item/far = allocate(/obj/item/p2_asker_item, run_loc_floor_top_right)
	open_request(I, /datum/prompt/choice, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, choices = list("a", "b"), radial = TRUE, require_near = TRUE, anchor = far)
	test_answer(H, "a")
	TEST_ASSERT_NULL(I.seen_answer, "an anchor out of reach drops the answer")
	open_request(I, /datum/prompt/choice, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, choices = list("a", "b"), radial = TRUE, require_near = TRUE, anchor = I)
	test_answer(H, "b")
	TEST_ASSERT_EQUAL(I.seen_answer, "b", "an anchor in reach keeps it")
	open_request(I, /datum/prompt/choice, TYPE_PROC_REF(/obj/item/p2_asker_item, answered), answerer = H, choices = list("a", "b"), radial = TRUE, anchor = far)
	test_answer(H, "a")
	TEST_ASSERT_EQUAL(I.seen_answer, "a", "without require_near the distance does not matter")

// ---------------------------------------------------------------------------------------------------------------------
// The hand gate: a hand() op on a machine is refused for an actor who is down and for a machine that does not work, unless it says ungated().
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_engine/a_machines_hand_op_keeps_the_hand_gate

/datum/unit_test/dq_p2_engine/a_machines_hand_op_keeps_the_hand_gate/run_gate()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/p2_hand_machine/M = allocate(/obj/machinery/p2_hand_machine)
	test_click(H, M)
	TEST_ASSERT_EQUAL(M.touched + M.touched_ungated, 1, "an awake actor's touch of a working machine runs one op")
	M.touched = 0
	M.touched_ungated = 0
	H.set_stat(UNCONSCIOUS)
	test_click(H, M)
	TEST_ASSERT_EQUAL(M.touched + M.touched_ungated, 0, "an unconscious actor's touch runs nothing")
	H.set_stat(CONSCIOUS)
	H.status_set(STAT_STUNNED, 5)
	test_click(H, M)
	TEST_ASSERT_EQUAL(M.touched + M.touched_ungated, 0, "a stunned actor's touch runs nothing")
	H.status_set(STAT_STUNNED, 0)
	H.set_stat(CONSCIOUS)
	M.set_stat(NOPOWER)
	test_click(H, M)
	TEST_ASSERT_EQUAL(M.touched, 0, "an unpowered machine refuses its hand op")
	var/obj/machinery/p2_hand_machine/ungated/U = allocate(/obj/machinery/p2_hand_machine/ungated)
	U.set_stat(NOPOWER)
	test_click(H, U)
	TEST_ASSERT_EQUAL(U.touched_ungated, 1, "but an op that says ungated() still runs on an unpowered machine")
	H.status_set(STAT_STUNNED, 5)
	test_click(H, U)
	TEST_ASSERT_EQUAL(U.touched_ungated, 1, "though not for a stunned actor")

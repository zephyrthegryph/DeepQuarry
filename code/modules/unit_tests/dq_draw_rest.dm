// The last legacy providers drawn from tracked state: cash piles, paper and its stamps, the telecube, a device assembly beside its parts, a slot
// machine's phases, the holographic sword's blade, a window's silicate sheen and a jar's water.

/// A pile of cash is named and drawn from its worth: a round sum shows its note, any other the scattered notes; nobody asks for the redraw.
/datum/unit_test/dq_draw_rest_cash_follows_worth

/datum/unit_test/dq_draw_rest_cash_follows_worth/Run()
	var/turf/T = test_floor()
	var/obj/item/spacecash/C = allocate(/obj/item/spacecash, T)
	refresh_flush()
	var/base_layers = length(C.overlays)
	C.set_worth(20)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.icon_state, "spacecash20", "a round sum shows its note")
	TEST_ASSERT(findtext(C.name, "20"), "and is named for it: [C.name]")
	C.set_worth(33)
	refresh_flush()
	var/heap_layers = length(C.overlays)
	TEST_ASSERT(heap_layers >= base_layers + 3, "an odd sum is a heap of notes: [json_encode(dq_overlay_states(C))]")
	TEST_ASSERT(findtext(C.name, "33"), "named for the new sum: [C.name]")
	C.set_worth(5)
	refresh_flush()
	TEST_ASSERT_EQUAL(C.icon_state, "spacecash5", "back to a single note")
	TEST_ASSERT(length(C.overlays) < heap_layers, "the heap is gone")

/// A charge card keeps its own look whatever it holds.
/datum/unit_test/dq_draw_rest_ewallet_keeps_its_card

/datum/unit_test/dq_draw_rest_ewallet_keeps_its_card/Run()
	var/turf/T = test_floor()
	var/obj/item/spacecash/ewallet/E = allocate(/obj/item/spacecash/ewallet, T)
	var/start_state = E.icon_state
	var/start_name = E.name
	E.set_worth(500)
	refresh_flush()
	TEST_ASSERT_EQUAL(E.icon_state, start_state, "the card keeps its state")
	TEST_ASSERT_EQUAL(E.name, start_name, "and its name")

/// A paper is blank, written or crumpled, and its stamps are marks it holds: a stamp is one overlay, clearing the sheet takes them off.
/datum/unit_test/dq_draw_rest_paper_follows_its_marks

/datum/unit_test/dq_draw_rest_paper_follows_its_marks/Run()
	var/turf/T = test_floor()
	var/obj/item/paper/P = allocate(/obj/item/paper, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "paper", "a blank sheet")
	P.info = "words"
	changed(P)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "paper_words", "a written sheet")
	P.add_stamp_mark("paper_stamp-ok", 1, -1)
	refresh_flush()
	TEST_ASSERT(("paper_stamp-ok" in dq_overlay_states(P)), "a stamp is an overlay: [json_encode(dq_overlay_states(P))]")
	P.set_crumpled(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(P.icon_state, "scrap", "a crumpled sheet is a scrap, with no call")
	P.clearpaper()
	refresh_flush()
	TEST_ASSERT(!("paper_stamp-ok" in dq_overlay_states(P)), "clearing the sheet takes the stamps off")

/// A bundle with no pages draws nothing and raises nothing.
/datum/unit_test/dq_draw_rest_paper_bundle_stacks_sheets

/datum/unit_test/dq_draw_rest_paper_bundle_stacks_sheets/Run()
	var/turf/T = test_floor()
	var/obj/item/paper_bundle/B = allocate(/obj/item/paper_bundle, T)
	refresh_flush()
	TEST_ASSERT(!QDELETED(B), "a bundle with no pages draws and survives (a runtime fails the test)")

/// A telecube shows ready or charging with no call: its readiness is tracked.
/datum/unit_test/dq_draw_rest_telecube_follows_ready

/datum/unit_test/dq_draw_rest_telecube_follows_ready/Run()
	var/turf/T = test_floor()
	var/obj/item/telecube/C = allocate(/obj/item/telecube, T)
	refresh_flush()
	TEST_ASSERT(("cube-ready" in dq_overlay_states(C)), "ready: [json_encode(dq_overlay_states(C))]")
	C.set_ready(FALSE)
	refresh_flush()
	var/list/charging = dq_overlay_states(C)
	TEST_ASSERT(("cube-charging" in charging), "charging: [json_encode(charging)]")
	TEST_ASSERT(!("cube-ready" in charging), "and not ready")

/// A holder shows its parts' states and layers: a timer that starts counting lights its layer on the holder with no call.
/datum/unit_test/dq_draw_rest_assembly_holder_follows_its_parts

/datum/unit_test/dq_draw_rest_assembly_holder_follows_its_parts/Run()
	var/turf/T = test_floor()
	var/obj/item/assembly_holder/timer_igniter/H = allocate(/obj/item/assembly_holder/timer_igniter, T)
	refresh_flush()
	var/list/idle = dq_overlay_states(H)
	TEST_ASSERT(!("timer_timing_l" in idle) && !("timer_timing_r" in idle), "idle: [json_encode(idle)]")
	var/obj/item/assembly/timer/tmr = istype(H.a_left, /obj/item/assembly/timer) ? H.a_left : H.a_right
	tmr.set_timing(TRUE)
	refresh_flush()
	var/list/counting = dq_overlay_states(H)
	TEST_ASSERT(("timer_timing_l" in counting) || ("timer_timing_r" in counting), "counting: [json_encode(counting)]")

/// A slot machine's sprite follows its phase and power, and a broken one is cracked.
/datum/unit_test/dq_draw_rest_slot_machine_follows_phase

/datum/unit_test/dq_draw_rest_slot_machine_follows_phase/Run()
	var/turf/T = test_floor()
	var/obj/machinery/slot_machine/S = allocate(/obj/machinery/slot_machine, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "slotmachine", "idle")
	S.set_slot_phase("rolling")
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "slotmachine_rolling", "rolling")
	S.set_slot_phase(null)
	S.set_ispowered(0)
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "slotmachine_off", "unpowered")

/// The holographic sword shows its blade only while switched on.
/datum/unit_test/dq_draw_rest_esword_blade_follows_active

/datum/unit_test/dq_draw_rest_esword_blade_follows_active/Run()
	var/turf/T = test_floor()
	var/obj/item/holo/esword/red/S = allocate(/obj/item/holo/esword/red, T)
	refresh_flush()
	TEST_ASSERT(!("esword_blade" in dq_overlay_states(S)), "off: no blade")
	S.set_active(TRUE)
	refresh_flush()
	TEST_ASSERT(("esword_blade" in dq_overlay_states(S)), "on: [json_encode(dq_overlay_states(S))]")

/// Silicate lays a sheen over a window, and a glass jar draws its water; both with no redraw call.
/datum/unit_test/dq_draw_rest_window_and_jar_follow_state

/datum/unit_test/dq_draw_rest_window_and_jar_follow_state/Run()
	var/turf/T = test_floor()
	var/obj/structure/window/basic/W = allocate(/obj/structure/window/basic, T)
	refresh_flush()
	var/before = length(W.overlays)
	W.set_silicate(50)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(W.overlays), before + 1, "a sheen of silicate is one more layer")
	var/obj/item/glass_jar/fish/J = allocate(/obj/item/glass_jar/fish, T)
	refresh_flush()
	var/dry = length(J.underlays)
	J.set_filled(TRUE)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(J.underlays), dry + 1, "water is one more underlay")

/// A jar draws and names what it holds: a creature put in is seen through the glass, and taking it out clears the sheen with no call.
/datum/unit_test/dq_draw_rest_jar_shows_its_creature

/datum/unit_test/dq_draw_rest_jar_shows_its_creature/Run()
	var/turf/T = test_floor()
	var/obj/item/glass_jar/J = allocate(/obj/item/glass_jar, T)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	refresh_flush()
	var/empty_name = J.name
	M.forceMove(J)
	J.set_contains(JAR_ANIMAL)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(J.underlays), 1, "the creature is an underlay")
	TEST_ASSERT(J.name != empty_name && findtext(J.name, "mouse"), "and names the jar: [J.name]")
	M.forceMove(T)
	J.set_contains(JAR_NOTHING)
	refresh_flush()
	TEST_ASSERT_EQUAL(length(J.underlays), 0, "taking it out clears the glass")
	TEST_ASSERT_EQUAL(J.name, empty_name, "and the name")

/// A net is empty or full as its contents change: the creature scooped in shows through the mesh.
/datum/unit_test/dq_draw_rest_net_follows_its_catch

/datum/unit_test/dq_draw_rest_net_follows_its_catch/Run()
	var/turf/T = test_floor()
	var/obj/item/material/fishing_net/N = allocate(/obj/item/material/fishing_net, T)
	var/mob/living/simple_mob/animal/passive/fish/F = allocate(/mob/living/simple_mob/animal/passive/fish, T)
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, N.empty_state, "empty")
	F.forceMove(N)
	changed(N) // what a net holds is not a published slot: the catch asks for the redraw
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, N.contain_state, "full once a fish is in, no call")
	F.forceMove(T)
	changed(N)
	refresh_flush()
	TEST_ASSERT_EQUAL(N.icon_state, N.empty_state, "empty again")

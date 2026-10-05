// Behaviour tests for the console base, /obj/machinery/computer (rewrite/machines-full): what a person and the world observe of any console,
// written against the legacy code first: the screwdriver disconnects the monitor into a frame, a broken one drops its glass, any other item is
// the hand's use, its screen lights only with power, consoles side by side join up, a pulse may break it, and the area lists it for an APC's
// overload. State is read through the adapters below (only their bodies change with the conversion).

/// A plain console with a board, and the hand's use counted.
/obj/machinery/computer/mfc_probe
	circuit = /obj/item/circuitboard/stationalert_all
	var/mfc_hand_uses = 0

/obj/machinery/computer/mfc_probe/attack_hand(mob/user)
	mfc_hand_uses++
	return TRUE

/// The consoles an APC's overload of `A` reaches.
/proc/mfc_area_consoles(area/A)
	return area_members(A, POWER_ROLE_COMPUTER)

/datum/unit_test/dq_hc_computers/mfc
	abstract_type = /datum/unit_test/dq_hc_computers/mfc

/datum/unit_test/dq_hc_computers/mfc/proc/probe(turf/T)
	return hc_console(/obj/machinery/computer/mfc_probe, T)

/// A screwdriver disconnects the monitor: the console becomes a frame with its board.
/datum/unit_test/dq_hc_computers/mfc/screwdriver_disconnects_the_monitor
/datum/unit_test/dq_hc_computers/mfc/screwdriver_disconnects_the_monitor/run_gate()
	var/obj/machinery/computer/mfc_probe/C = probe()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/tool/screwdriver/S = dq_fast_tool(/obj/item/tool/screwdriver, hc_side())
	H.put_in_active_hand(S)
	hci_click(H, C, S)
	test_time(5 SECONDS)
	TEST_ASSERT(QDELETED(C), "the console is taken apart")
	var/obj/structure/frame/F = locate_on(hc_spot(), /obj/structure/frame)
	TEST_ASSERT_NOTNULL(F, "into a frame")
	TEST_ASSERT(istype(F?.circuit, /obj/item/circuitboard/stationalert_all), "holding its board")
	TEST_ASSERT_NULL(locate_on(hc_spot(), /obj/item/material/shard), "a whole monitor drops no glass")
	LAZYADD(hc_made, F)

/// A broken console's glass falls out when it is disconnected.
/datum/unit_test/dq_hc_computers/mfc/broken_monitor_drops_its_glass
/datum/unit_test/dq_hc_computers/mfc/broken_monitor_drops_its_glass/run_gate()
	var/obj/machinery/computer/mfc_probe/C = probe()
	C.atom_break()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/tool/screwdriver/S = dq_fast_tool(/obj/item/tool/screwdriver, hc_side())
	H.put_in_active_hand(S)
	hci_click(H, C, S)
	test_time(5 SECONDS)
	TEST_ASSERT(QDELETED(C), "the console is taken apart")
	var/obj/item/material/shard/G = locate_on(hc_spot(), /obj/item/material/shard)
	TEST_ASSERT_NOTNULL(G, "and the broken glass falls out")
	LAZYADD(hc_made, G)
	LAZYADD(hc_made, locate_on(hc_spot(), /obj/structure/frame))

/// Any other item is the hand's use of the console.
/datum/unit_test/dq_hc_computers/mfc/an_item_is_the_hands_use
/datum/unit_test/dq_hc_computers/mfc/an_item_is_the_hands_use/run_gate()
	var/obj/machinery/computer/mfc_probe/C = probe()
	var/mob/living/carbon/human/H = hc_actor()
	var/obj/item/pen/P = allocate(/obj/item/pen, hc_side())
	H.put_in_active_hand(P)
	hci_click(H, C, P)
	test_time(1 SECOND)
	TEST_ASSERT(C.mfc_hand_uses >= 1, "a pen on the console uses it as a hand would")

/// The screen lights the room only while the console has power.
/datum/unit_test/dq_hc_computers/mfc/screen_lights_only_with_power
/datum/unit_test/dq_hc_computers/mfc/screen_lights_only_with_power/run_gate()
	var/obj/machinery/computer/mfc_probe/C = probe()
	C.power_change()
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(C.light_range, C.light_range_on, "a powered console lights its screen")
	var/area/A = get_area(C)
	var/requires = A.requires_power
	var/equip = A.power_equip
	A.requires_power = TRUE
	A.power_equip = FALSE
	C.power_change()
	test_time(1 SECOND)
	TEST_ASSERT(!C.light_range, "an unpowered one is dark")
	A.requires_power = requires
	A.power_equip = equip
	C.power_change()

/// Two consoles side by side, facing the same way, join up into one desk.
/datum/unit_test/dq_hc_computers/mfc/neighbours_join_up
/datum/unit_test/dq_hc_computers/mfc/neighbours_join_up/run_gate()
	var/turf/left = hc_spot()
	var/obj/machinery/computer/mfc_probe/A = probe(left)
	var/obj/machinery/computer/mfc_probe/B = probe(get_step(left, EAST))
	A.set_dir(SOUTH)
	B.set_dir(SOUTH)
	A.update_icon()
	B.update_icon()
	test_time(1 SECOND)
	TEST_ASSERT(findtext(A.icon_state, "computer_") && findtext(B.icon_state, "computer_"), "both draw the joined desk ([A.icon_state], [B.icon_state])")

/// A strong pulse breaks some consoles (one in five), never all of them.
/datum/unit_test/dq_hc_computers/mfc/a_pulse_may_break_it
/datum/unit_test/dq_hc_computers/mfc/a_pulse_may_break_it/run_gate()
	var/broken = 0
	for(var/i in 1 to 40)
		var/obj/machinery/computer/mfc_probe/C = probe()
		C.emp_act(1)
		if(C.has_stat(BROKEN))
			broken++
		qdel(C)
	TEST_ASSERT(broken >= 1 && broken < 40, "some consoles broke, not all ([broken] of 40)")
	for(var/obj/effect/overlay/O in hc_spot()) // the sparks of the ones that broke
		qdel(O)

/// A blob hits a console as a medium blast, not as a blunt blow.
/datum/unit_test/dq_hc_computers/mfc/a_blob_hits_like_a_blast
/datum/unit_test/dq_hc_computers/mfc/a_blob_hits_like_a_blast/run_gate()
	var/obj/machinery/computer/mfc_probe/C = probe()
	C.blob_act(null)
	TEST_ASSERT(QDELETED(C) || C.has_stat(BROKEN) || C.get_integrity() < C.max_integrity, "the blob damaged it")

/// The area lists its consoles for an APC's overload, and the list follows a console that moves.
/datum/unit_test/dq_hc_computers/mfc/the_area_lists_its_consoles
/datum/unit_test/dq_hc_computers/mfc/the_area_lists_its_consoles/run_gate()
	var/obj/machinery/computer/mfc_probe/C = probe()
	TEST_ASSERT(C in mfc_area_consoles(get_area(C)), "the console's area lists it")
	qdel(C)
	TEST_ASSERT(!(C in mfc_area_consoles(get_area(hc_spot()))), "a deleted console leaves the list")

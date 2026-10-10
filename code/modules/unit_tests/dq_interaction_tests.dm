// Interaction framework (roadmap I2): the resolver's surviving entry points exercised on real converted types.

// ---- Fixtures ----

/// A plain object other tests build probes on.
/obj/dq_interaction_probe
	name = "interaction probe"

/// An interaction id as snapshots record it: a generated id's collision suffix (an md5) is dropped, since which of two
/// same-named generated interactions gets the plain id depends on which type was declared first, i.e. on which tests ran before.
/proc/dq_snapshot_id(id)
	var/static/regex/suffix = regex(@"^(gen_.+)_[0-9a-f]{32}$")
	if(suffix.Find(id))
		return suffix.group[1]
	return id

// ---- Tests ----

/// A lattice deletes itself off open space, so the structures snapshot can't hold it: build one
/// over space next to the test floor, offer it rods, and let the rods make it a catwalk.
/datum/unit_test/dq_interaction_lattice_item

/datum/unit_test/dq_interaction_lattice_item/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/neighbor = get_step(T, EAST)
	TEST_ASSERT_NOTNULL(neighbor, "no turf beside the test floor")
	var/old_type = neighbor.type
	var/turf/space/gap = neighbor.ChangeTurf(/turf/space)
	var/obj/structure/lattice/lattice = allocate(/obj/structure/lattice, gap)
	TEST_ASSERT(!QDELETED(lattice), "a lattice over space should stay")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/stack/rods/rods = allocate(/obj/item/stack/rods, T, 5)
	test_op_handler(lattice, "interaction_item", H, rods) // the lattice's rods op (CAPABILITIES): its effect, as the engine runs it
	var/obj/structure/catwalk/catwalk = locate_within(gap, /obj/structure/catwalk)
	TEST_ASSERT_NOTNULL(own(catwalk), "rods should turn the lattice into a catwalk")
	TEST_ASSERT_EQUAL(rods.get_amount(), 4, "the upgrade should use one rod")
	qdel(catwalk)
	gap.ChangeTurf(old_type)

/// Use through the input inbox (a player's click), end to end, on a real converted machine.
/datum/unit_test/dq_interaction_use_end_to_end

/datum/unit_test/dq_interaction_use_end_to_end/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/machinery/autolathe/lathe = allocate(/obj/machinery/autolathe, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)

	TEST_ASSERT(H.put_in_active_hand(crowbar), "the human holds a crowbar")
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, lathe, null, null, "left=1"))
	test_time(1)
	TEST_ASSERT(!QDELETED(lathe), "a crowbar on a closed panel is blocked, not a deconstruction")
	var/start_integrity = lathe.get_integrity()
	TEST_ASSERT_EQUAL(start_integrity, lathe.max_integrity, "and it didn't fall through to hitting the machine")

	H.drop_from_inventory(crowbar, T)
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the human holds a screwdriver")
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, lathe, null, null, "left=1"))
	test_time(1)
	TEST_ASSERT(panel_open(lathe), "Use with a screwdriver opens the panel")

	H.drop_from_inventory(screwdriver, T)
	TEST_ASSERT(H.put_in_active_hand(crowbar), "the human holds the crowbar again")
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, lathe, null, null, "left=1"))
	test_time(1)
	TEST_ASSERT(QDELETED(lathe), "Use with a crowbar on an open panel deconstructs")
	for(var/obj/structure/frame/frame in turf_contents_of_type(T, /obj/structure/frame))
		qdel(frame)
	for(var/obj/item/item in turf_contents_of_type(T, /obj/item))
		if(!(item in allocated))
			qdel(item)
	test_driver_end()

/// The old Emote Beyond verb (`set src in oview(7)`): offered within sight of the helm, not past it.
/datum/unit_test/dq_interaction_ship_emote_beyond

/datum/unit_test/dq_interaction_ship_emote_beyond/Run()
	set_global(nameof(GLOB.test_prompts), list())
	test_driver_begin()
	var/turf/T = test_floor()
	var/obj/machinery/computer/ship/navigation/helm = allocate(/obj/machinery/computer/ship/navigation, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.enable_godmode()
	var/list/emote_row
	for(var/list/row as anything in op_menu(H, helm, null))
		if(row["key"] == "ship_emote_beyond")
			emote_row = row
	TEST_ASSERT(emote_row, "the real native menu offers Emote Beyond within sight of the helm")
	TEST_ASSERT(emote_row["enabled"], "the in-view conscious actor may use the actual menu operation")
	var/datum/op_result/asked = test_menu(H, helm, "ship_emote_beyond")
	TEST_ASSERT_EQUAL(asked?.key, "ship_emote_beyond", "actual menu dispatch reaches the native emote operation")
	TEST_ASSERT(SSrequests.open_for(H), "the real actor receives the emote message question")
	test_answer(H, null, outcome = REQ_CANCELLED)
	TEST_ASSERT_EQUAL(asked?.outcome, ACT_REFUSED, "canceling ends the original native operation without an emote")
	var/turf/far = locate(T.x + 8, T.y, T.z)
	TEST_ASSERT(far, "the test map supplies a real position beyond the seven-tile view")
	H.forceMove(far)
	var/datum/op_result/denied = test_menu(H, helm, "ship_emote_beyond")
	TEST_ASSERT_EQUAL(denied?.outcome, ACT_REFUSED, "past seven tiles the actual native menu operation refuses")
	TEST_ASSERT_EQUAL(reason_text(denied?.reason), "too far away", "the original view refusal remains explicit")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "the far actor is never asked for an emote")
	test_driver_end()

/// i6b: a robot's crowbar and welder answer per stance outside combat mode, and strike in it.
/datum/unit_test/dq_interaction_robot_tool_stances

/datum/unit_test/dq_interaction_robot_tool_stances/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	R.locked = FALSE
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB))
		H.set_use_stance(stance)
		H.put_in_active_hand(crowbar)
		R.opened = FALSE
		TEST_ASSERT(R.crowbar_act(H, crowbar) & ITEM_INTERACT_SUCCESS, "stance [stance]: the crowbar works the chassis")
		TEST_ASSERT(R.opened, "stance [stance]: the crowbar opens the cover")
		H.drop_from_inventory(crowbar)
		H.put_in_active_hand(welder)
		R.injure(INJURY_BLUNT, 20)
		var/before = R.injury_load(INJURY_CATEGORY_PHYSICAL)
		TEST_ASSERT(before > 0, "stance [stance]: the robot is dented")
		TEST_ASSERT(R.welder_act(H, welder) & ITEM_INTERACT_SUCCESS, "stance [stance]: the welder works the chassis")
		TEST_ASSERT(R.injury_load(INJURY_CATEGORY_PHYSICAL) < before, "stance [stance]: the weld repairs dents")
		H.drop_from_inventory(welder)
	R.opened = FALSE
	H.set_use_stance(I_HURT)
	H.put_in_active_hand(crowbar)
	TEST_ASSERT(!(R.crowbar_act(H, crowbar) & (ITEM_INTERACT_SUCCESS | ITEM_INTERACT_BLOCKING)), "combat mode: no op answers the crowbar, so it goes on to strike")
	TEST_ASSERT(!R.opened, "combat mode: the cover stays shut")
	H.set_use_stance(I_HELP)

/// The Menu lists the target's ops (op_menu()): what the actor can do as available, the rest as blocked with the reason, keyed by op key.
/datum/unit_test/dq_interaction_menu_lists_ops

/datum/unit_test/dq_interaction_menu_lists_ops/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	var/list/rows = op_menu(H, C, null)
	TEST_ASSERT(length(rows), "a closet has ops for a human")
	var/list/data = interaction_menu_data(H, C)
	var/list/listed = list()
	for(var/list/entry as anything in data["available"])
		listed[entry["id"]] = "ok"
	for(var/list/entry as anything in data["blocked"])
		listed[entry["id"]] = entry["reason"]
	TEST_ASSERT_EQUAL(length(listed), length(rows), "every op row is listed once: [json_encode(listed)]")
	for(var/list/row as anything in rows)
		TEST_ASSERT_EQUAL(listed[row["key"]], row["enabled"] ? "ok" : row["reason"], "[row["key"]] is listed as the op menu says")

// The right-click Menu is sane (doc/rewrite/interactions.md section 7): it lists only what a player can choose for the target in front of
// them, each choice once. A playtest found a wall offering two "Touch" lines (the wall's own and the inherited turf one) and every target
// offering the held item's own entries ("Move To Top", "Toggle Digestable"), a drag-only "Crawl" and an unlabelled catch-all ("Turf item").
// And the airlock's remote window opens for a silicon with the data its interface reads, and each of its buttons acts.

/// The labels of the Menu's lines (available and blocked) for `user` on `target`.
/proc/dq_menu_sanity_labels(mob/user, atom/target)
	var/list/data = interaction_menu_data(user, target)
	. = list()
	for(var/list/entry as anything in data["available"])
		. += entry["name"]
	for(var/list/entry as anything in data["blocked"])
		. += entry["name"]

/// A wall near the test room.
/proc/dq_menu_sanity_wall(turf/near)
	for(var/turf/simulated/wall/W in range(6, near))
		return W

/// A wall's Menu has one Touch.
/datum/unit_test/dq_ops_menu_wall_one_touch

/datum/unit_test/dq_ops_menu_wall_one_touch/Run()
	var/turf/T = test_floor()
	var/turf/simulated/wall/W = dq_menu_sanity_wall(T)
	TEST_ASSERT(W, "a wall near the test room")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/labels = dq_menu_sanity_labels(H, W)
	var/touches = 0
	for(var/label in labels)
		if(label == "Touch")
			touches++
	TEST_ASSERT_EQUAL(touches, 1, "one Touch on a wall: [json_encode(labels)]")
	// the Touch line is the wall's own (the turf's is the fallback it shadows)
	var/key
	for(var/list/row as anything in op_menu(H, W, null))
		if(row["label"] == "Touch")
			key = row["key"]
	TEST_ASSERT_EQUAL(key, "wall_touch", "the wall's own Touch is the one listed")

/// No common target's Menu lists a line twice, the held item's own entries, a drag-only op or an unlabelled catch-all.
/datum/unit_test/dq_ops_menu_no_internal_ops

/datum/unit_test/dq_ops_menu_no_internal_ops/Run()
	var/turf/T = test_floor()
	var/turf/simulated/wall/W = dq_menu_sanity_wall(T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	var/obj/machinery/door/airlock/D = allocate(/obj/machinery/door/airlock, T)
	var/obj/item/tool/crowbar/floor_item = allocate(/obj/item/tool/crowbar, T)
	var/list/targets = list(T, W, other, C, D, floor_item)
	var/list/helds = list(null, /obj/item/card/id, /obj/item/stack/cable_coil, /obj/item/tool/screwdriver)
	var/list/banned = list("Move To Top", "Toggle Digestable", "Read ID Card", "Make Cable Restraints", "Crawl", "Turf item", "Wall item", "Ui open")
	for(var/held_type in helds)
		if(H.get_active_hand())
			qdel(H.get_active_hand())
		if(held_type)
			H.put_in_active_hand(allocate(held_type, T))
		for(var/atom/target as anything in targets)
			var/list/labels = dq_menu_sanity_labels(H, target)
			var/list/seen = list()
			for(var/label in labels)
				TEST_ASSERT(!seen[label], "[target.type] holding [held_type || "nothing"] lists \"[label]\" once: [json_encode(labels)]")
				seen[label] = TRUE
				if(target == floor_item && (label in list("Move To Top", "Toggle Digestable")))
					continue // an item on the floor: its own entries are its own Menu
				TEST_ASSERT(!(label in banned), "[target.type] holding [held_type || "nothing"] does not list \"[label]\": [json_encode(labels)]")
	// the held item's own entries stay on the held item's own Menu
	if(H.get_active_hand())
		qdel(H.get_active_hand())
	var/obj/item/tool/wrench/own = allocate(/obj/item/tool/wrench, T)
	H.put_in_active_hand(own)
	TEST_ASSERT("Move To Top" in dq_menu_sanity_labels(H, own), "the item's own Menu keeps Move To Top: [json_encode(dq_menu_sanity_labels(H, own))]")

/// An AI's click opens the airlock's remote window; its data carries what AiAirlock.tsx reads, and its buttons act.
/datum/unit_test/dq_p2_door/ops_menu_airlock_window

/datum/unit_test/dq_p2_door/ops_menu_airlock_window/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/silicon/ai/AI = make_ai()
	var/datum/op_result/clicked = test_click(AI, D, null)
	TEST_ASSERT_EQUAL(clicked?.key, "ui_open", "an AI's click on an airlock is its window")
	TEST_ASSERT(clicked?.outcome != ACT_REFUSED, "and it is not refused ([clicked?.outcome])")
	TEST_ASSERT_EQUAL(D.ui_interface(AI), "AiAirlock", "the AI's window is the remote control one")
	var/list/data = D.tgui_data(AI, null, null)
	for(var/key in list("power", "wires", "electrified", "electrified_left", "emergency", "id_scanner", "lights", "bolted", "safe", "speed", "opened", "welded"))
		TEST_ASSERT(key in data, "the window's data has [key]: [json_encode(data)]")
	var/list/power = data["power"]
	TEST_ASSERT(islist(power) && ("main" in power) && ("backup_timeleft" in power), "power is a section: [json_encode(power)]")
	// the buttons: each toggle flips what the window shows
	var/list/flips = list("bolt-toggle" = "bolted", "light-toggle" = "lights", "safe-toggle" = "safe", "speed-toggle" = "speed", "emergency-toggle" = "emergency", "idscan-toggle" = "id_scanner")
	for(var/action in flips)
		var/field = flips[action]
		var/before = !!D.tgui_data(AI, null, null)[field]
		var/datum/op_result/pressed = p2_door_ui(AI, D, action)
		settle()
		TEST_ASSERT(istype(pressed) && pressed.outcome != ACT_REFUSED, "[action] runs ([istype(pressed) ? pressed.outcome : pressed])")
		TEST_ASSERT_NOTEQUAL(!!D.tgui_data(AI, null, null)[field], before, "[action] flips [field]")
		p2_door_ui(AI, D, action)
		settle()
	var/datum/op_result/opened = p2_door_ui(AI, D, "open-close")
	settle()
	TEST_ASSERT(istype(opened) && opened.outcome != ACT_REFUSED, "open-close runs")
	TEST_ASSERT(D.tgui_data(AI, null, null)["opened"], "open-close opens the door")
	p2_door_ui(AI, D, "shock-temp")
	settle()
	TEST_ASSERT(D.tgui_data(AI, null, null)["electrified"], "shock-temp electrifies")
	p2_door_ui(AI, D, "shock-restore")
	settle()
	TEST_ASSERT(!D.tgui_data(AI, null, null)["electrified"], "shock-restore clears it")
	// a human's click is not the remote window
	var/mob/living/carbon/human/H = make_person(null)
	var/datum/op_result/touched = test_menu(H, D, "ui_open")
	TEST_ASSERT(!touched || touched.outcome == ACT_REFUSED, "a human cannot open the remote window")

/// Every airlock-family controller's window names the console it draws (EmbeddedController/index.tsx throws without internalTemplateName)
/// with the program state that console reads, and its program buttons reach the program.
/datum/unit_test/dq_ops_menu_airlock_controller_window

/datum/unit_test/dq_ops_menu_airlock_controller_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/expect = list(
		/obj/machinery/embedded_controller/radio/airlock/airlock_controller = list("AirlockConsoleSimple", "chamber_pressure", "exterior_status", "interior_status", "processing"),
		/obj/machinery/embedded_controller/radio/airlock/advanced_airlock_controller = list("AirlockConsoleAdvanced", "chamber_pressure", "external_pressure", "internal_pressure", "purge", "secure"),
		/obj/machinery/embedded_controller/radio/airlock/access_controller = list("DoorAccessConsole", "exterior_status", "interior_status", "processing"),
	)
	var/list/known = list("AirlockConsoleAdvanced", "AirlockConsoleSimple", "AirlockConsolePhoron", "AirlockConsoleDocking", "DockingConsoleSimple", "DockingConsoleMulti", "DoorAccessConsole", "EscapePodConsole", "EscapePodBerthConsole")
	for(var/path in expect)
		var/obj/machinery/embedded_controller/C = allocate(path, T)
		var/list/data = hc_data(C, H)
		var/list/wanted = expect[path]
		TEST_ASSERT_EQUAL(data["internalTemplateName"], wanted[1], "[path] names its console: [json_encode(data)]")
		for(var/i in 2 to length(wanted))
			TEST_ASSERT(wanted[i] in data, "[path] window has [wanted[i]]: [json_encode(data)]")
	// every concrete controller subtype under the airlock family names a console the window knows
	for(var/path in subtypesof(/obj/machinery/embedded_controller/radio/airlock))
		var/obj/machinery/embedded_controller/C = allocate(path, T)
		var/name = hc_data(C, H)["internalTemplateName"]
		TEST_ASSERT(name in known, "[path] names a console EmbeddedController knows ([name || "none"])")
	// a program button reaches the program: abort clears a cycle in progress
	var/obj/machinery/embedded_controller/radio/airlock/airlock_controller/simple = allocate(/obj/machinery/embedded_controller/radio/airlock/airlock_controller, T)
	var/datum/embedded_program/airlock/program = simple.program
	program.set_memory_at("chamber_sensor_pressure", ONE_ATMOSPHERE) // a pressure difference: the press starts a cycle rather than just toggling a door
	var/datum/op_result/pressed = hc_ui(H, simple, "cycle_ext")
	TEST_ASSERT(istype(pressed) && pressed.outcome != ACT_REFUSED, "cycle_ext runs ([istype(pressed) ? pressed.outcome : pressed])")
	TEST_ASSERT(program.target_state != program.state, "cycle_ext starts the cycle ([program.state] -> [program.target_state])")

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

/// Every airlock-family controller opens its own console window with the program state that console reads, and its program buttons
/// reach the program.
/datum/unit_test/dq_ops_menu_airlock_controller_window

/datum/unit_test/dq_ops_menu_airlock_controller_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/expect = list(
		/obj/machinery/embedded_controller/radio/airlock/airlock_controller = list("AirlockConsoleSimple", "chamber_pressure", "exterior_status", "interior_status", "processing"),
		/obj/machinery/embedded_controller/radio/airlock/advanced_airlock_controller = list("AirlockConsoleAdvanced", "chamber_pressure", "external_pressure", "internal_pressure", "purge", "secure"),
		/obj/machinery/embedded_controller/radio/airlock/access_controller = list("DoorAccessConsole", "exterior_status", "interior_status", "processing"),
	)
	var/list/known = list("AirlockConsoleAdvanced", "AirlockConsoleSimple", "AirlockConsoleDocking", "DockingConsoleSimple", "DockingConsoleMulti", "DoorAccessConsole", "EscapePodConsole", "EscapePodBerthConsole")
	for(var/path in expect)
		var/obj/machinery/embedded_controller/C = allocate(path, T)
		var/list/data = hc_data(C, H)
		var/list/wanted = expect[path]
		TEST_ASSERT_EQUAL(C.ui_interface(H), wanted[1], "[path] opens its console's window")
		for(var/i in 2 to length(wanted))
			TEST_ASSERT(wanted[i] in data, "[path] window has [wanted[i]]: [json_encode(data)]")
	// every concrete controller subtype opens one of the console windows
	for(var/path in subtypesof(/obj/machinery/embedded_controller/radio))
		if(is_abstract(path))
			continue
		var/obj/machinery/embedded_controller/C = allocate(path, T)
		var/name = C.ui_interface(H)
		TEST_ASSERT(name in known, "[path] opens a console window ([name || "none"])")
	// a program button reaches the program: abort clears a cycle in progress
	var/obj/machinery/embedded_controller/radio/airlock/airlock_controller/simple = allocate(/obj/machinery/embedded_controller/radio/airlock/airlock_controller, T)
	var/datum/op_result/pressed = hc_ui(H, simple, "cycle_ext")
	TEST_ASSERT(istype(pressed) && pressed.outcome != ACT_REFUSED, "cycle_ext runs ([istype(pressed) ? pressed.outcome : pressed])")
	TEST_ASSERT(simple.target_state != simple.cycle_state, "cycle_ext starts the cycle ([simple.cycle_state] -> [simple.target_state])")

/// The Menu on a floor lists a held item's lines only when the item fits them: an analyzer is not offered graffiti, a crayon is, a sharp thing
/// is offered the engraving.
/datum/unit_test/dq_ops_menu_floor_graffiti_needs_fitting_item

/datum/unit_test/dq_ops_menu_floor_graffiti_needs_fitting_item/Run()
	var/turf/simulated/floor/plating = test_floor() // whichever deck tile the test room has; the lines depend on the held item, not the tile
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, plating)
	var/list/held_labels = list(
		/obj/item/analyzer = list("Draw graffiti" = FALSE, "Engrave graffiti" = FALSE),
		/obj/item/pen/crayon = list("Draw graffiti" = TRUE, "Engrave graffiti" = FALSE),
		/obj/item/material/knife = list("Draw graffiti" = FALSE, "Engrave graffiti" = TRUE),
	)
	for(var/held_type in held_labels)
		if(H.get_active_hand())
			qdel(H.get_active_hand())
		H.put_in_active_hand(allocate(held_type, plating))
		var/list/labels = dq_menu_sanity_labels(H, plating)
		var/list/expect = held_labels[held_type]
		for(var/label in expect)
			TEST_ASSERT_EQUAL(!!(label in labels), expect[label], "[held_type] on plating: \"[label]\" listed = [expect[label]]: [json_encode(labels)]")

/// What each Menu row of `actor` on `target` holding `held` runs through: row key -> its candidate, so a test can read the binding.
/proc/dq_menu_row_candidates(mob/actor, atom/target, obj/held)
	. = list()
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_MENU, actor_authority(actor), null, null)
	for(var/datum/op_cand/C as anything in R.ordered)
		if(!.[C.oplan.key])
			.[C.oplan.key] = C

/// The Menu lists what could apply, each choice once: for common held things on common targets no label repeats (stance variants and generic
/// "use what you hold" ops collapse into one line), no listed op needs a tool the held thing is not, and no generic op wears a specific label.
/datum/unit_test/dq_ops_menu_relevance_sanity

/datum/unit_test/dq_ops_menu_relevance_sanity/Run()
	var/turf/T = test_floor()
	var/turf/plating = get_step(T, EAST)
	var/turf/previous = plating.type
	plating.ChangeTurf(/turf/simulated/floor/plating, tell_universe = FALSE)
	plating = get_step(T, EAST)
	var/turf/simulated/wall/W = dq_menu_sanity_wall(T)
	TEST_ASSERT(W, "a wall near the test room")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/door/airlock/D = allocate(/obj/machinery/door/airlock, T)
	var/obj/item/stack/tile/floor/tile = allocate(/obj/item/stack/tile/floor, T)
	var/obj/machinery/power/apc/apc = null
	for(var/obj/machinery/power/apc/found in REGISTRY_MEMBERS(REGISTRY_APCS))
		apc = found
		break
	var/list/targets = list(plating, T, tile, W, D, other)
	if(apc)
		targets += apc
	var/list/helds = list(null, /obj/item/analyzer, /obj/item/tool/wrench, /obj/item/tool/screwdriver, /obj/item/pen/crayon, /obj/item/pda)
	var/list/stances = list(I_HELP, I_HURT)
	var/rows_checked = 0
	for(var/held_type in helds)
		if(H.get_active_hand())
			qdel(H.get_active_hand())
		var/obj/item/held = null
		if(held_type)
			held = allocate(held_type, T)
			H.put_in_active_hand(held)
		for(var/stance in stances)
			H.set_use_stance(stance)
			for(var/atom/target as anything in targets)
				var/list/data = interaction_menu_data(H, target)
				var/list/candidates = dq_menu_row_candidates(H, target, held)
				var/list/seen = list()
				var/list/lines = list()
				for(var/list/entry as anything in data["available"] + data["blocked"])
					var/label = entry["name"]
					lines += "[label][entry["reason"] ? " (grey: [entry["reason"]])" : ""]"
					rows_checked++
					TEST_ASSERT(!seen[label], "[target.type] holding [held_type || "nothing"] in stance [stance] lists \"[label]\" once: [json_encode(lines)]")
					seen[label] = TRUE
					var/datum/op_cand/C = candidates[entry["id"]]
					if(!C)
						continue // a tool hint or a legacy line
					TEST_ASSERT(!C.oplan.passes || length(C.oplan.effects), "[target.type] holding [held_type || "nothing"] lists the do-nothing \"[label]\"")
					if(C.binding?.bind_kind == BIND_TOOL && !entry["reason"]) // a greyed row is the hint "needs a <tool>"
						var/fits = FALSE
						for(var/quality in C.binding.args["quality"])
							if(held?.op_tool_quality(quality))
								fits = TRUE
						TEST_ASSERT(fits, "[target.type] holding [held_type || "nothing"] lists the tool op \"[label]\" it is not the tool for: [json_encode(C.binding.args["quality"])]")
					if(held && op_cand_click_carrier(C))
						TEST_ASSERT_EQUAL(label, "Use [held.name]", "a generic item op reads as using the held thing, not \"[label]\" ([target.type], [held_type])")
				log_test("MENU [held_type || "empty hand"] / [stance] on [target.type]: [json_encode(lines)]")
	TEST_ASSERT(rows_checked, "the menus had rows to look at")
	plating.ChangeTurf(previous, tell_universe = FALSE)

/// The floor's stance variants of "do something with what you hold" are one line, "Use <item>", never "Hit the floor" twice or a graffiti line for a wrench.
/datum/unit_test/dq_ops_menu_floor_item_one_line

/datum/unit_test/dq_ops_menu_floor_item_one_line/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	H.put_in_active_hand(wrench)
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		H.set_use_stance(stance)
		var/list/labels = dq_menu_sanity_labels(H, T)
		TEST_ASSERT(!(("Hit the floor" in labels) || ("Draw graffiti" in labels)), "stance [stance]: no stance-named floor line for a wrench: [json_encode(labels)]")
		var/uses = 0
		for(var/label in labels)
			if(label == "Use [wrench.name]")
				uses++
		TEST_ASSERT_EQUAL(uses, 1, "stance [stance]: one \"Use [wrench.name]\" line: [json_encode(labels)]")

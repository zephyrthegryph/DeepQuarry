// The order ops answer a click and fill a menu in (resolve.dm: op_resolution_sort). The golden tables (dx_menu_order_golden.dm) were last
// captured when binding specificity (op_binding_specificity) replaced the storage.put_in default anchor; they pin every click and menu order
// since, so an ordering change shows up as a DXDIFF line.
//
// One scenario is a target and a held item (null: an empty hand); the target is the holder type, a floor, or a box, so a holder's own ops and
// the ops it brings as a held item are both ordered. Each scenario records three strings:
//   all   - every op bound to the input, gates ignored, sorted as a click sorts them (the state-independent order)
//   click - the survivors of a real help-intent click
//   menu  - the keys of op_menu() for the same input
// The test asserts click and menu. A scenario whose three strings are empty is not listed; the test counts them, so an op appearing where none was fails too.

/// The holders whose ops lost a priority(above(...)).
/proc/dx_menu_order_holders()
	return list(
		/obj/machinery/door/airlock, /obj/structure/firedoor_assembly, /obj/structure/door_assembly,
		/obj/item/reagent_containers/glass/paint, /obj/item/storage/backpack/holding, /obj/item/storage/backpack/holding/duffle,
		/obj/item/storage/bible, /obj/item/storage/box, /obj/item/storage/box/matches, /obj/item/storage/pill_bottle,
		/obj/item/storage/lockbox, /obj/item/storage/secure, /obj/item/storage, /obj/item/storage/quickdraw,
		/obj/item/reagent_containers/glass/beaker, /obj/item/reagent_containers/spray, /obj/structure/bed/chair,
		/obj/machinery/vending, /mob/living/bot/floorbot, /mob/living/bot/medbot, /obj/machinery/power/apc, /obj/structure/table)

/// What each holder is touched with.
/proc/dx_menu_order_helds()
	return list(
		null, /obj/item/tool/crowbar, /obj/item/weldingtool, /obj/item/tool/screwdriver, /obj/item/tool/wirecutters, /obj/item/pen,
		/obj/item/reagent_containers/glass/beaker, /obj/item/flame/match, /obj/item/melee/energy/blade, /obj/item/lightreplacer,
		/obj/item/stack/tile/floor, /obj/item/storage/backpack/holding, /obj/item/robot_parts/l_arm, /mob/living/carbon/human)

/proc/dx_menu_order_keys(list/cands)
	var/list/keys = list()
	for(var/datum/op_cand/C as anything in cands)
		keys += C.oplan.key
	return jointext(keys, ",")

/// The three strings of one scenario, joined with " | ".
/proc/dx_menu_order_line(mob/living/carbon/human/H, atom/target, obj/item/held)
	var/datum/op_resolution/R = op_resolve(H, target, held, ORIGIN_CLICK, AUTH_PHYSICAL, GESTURE_CLICK, null, TRUE)
	var/datum/op_resolution/S = new
	S.ordered = R.all.Copy()
	op_resolution_sort(S)
	var/all = dx_menu_order_keys(S.ordered)
	// op_resolve() sorts pass-one candidates; only pass two evaluates when().
	var/click = dx_menu_order_keys(op_resolution_matches(R))
	var/list/menu = list()
	for(var/list/row as anything in op_menu(H, target, held))
		menu += row["key"]
	if(!length(all) && !length(click) && !length(menu))
		return null
	return "[all] | [click] | [jointext(menu, ",")]"

/// The part of a scenario line a player sees: the click survivors and the menu. The "all" part also lists ops that cannot answer the input (a
/// held storage's put_in beside a target storage's), so it is recorded for diagnosis but not asserted.
/proc/dx_menu_order_answered(line)
	var/first = findtext(line, " | ")
	return copytext(line, first + 3)

/datum/unit_test/dx_menu_order
	priority = TEST_LONGER

/datum/unit_test/dx_menu_order/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_use_stance(I_HELP)
	var/list/golden = dx_menu_order_golden()
	var/list/seen = list()
	var/diffs = 0
	var/capture = !length(golden)
	var/obj/item/storage/box/crate = allocate(/obj/item/storage/box, T)
	for(var/holder_type in dx_menu_order_holders())
		for(var/held_type in dx_menu_order_helds())
			for(var/mode in list("on", "as_held", "in_box"))
				if(mode != "on" && !ispath(holder_type, /obj/item))
					continue
				if(mode != "on" && !isnull(held_type))
					continue
				var/atom/target
				var/obj/item/held = null
				var/label
				switch(mode)
					if("on")
						target = allocate(holder_type, T)
						if(!isnull(held_type))
							held = allocate(held_type, T)
						label = "[holder_type] <- [held_type || "-"]"
					if("as_held")
						target = T
						held = allocate(holder_type, T)
						label = "floor <- [holder_type]"
					else
						target = crate
						held = allocate(holder_type, T)
						label = "box <- [holder_type]"
				var/line = dx_menu_order_line(H, target, held)
				if(mode == "on" && !QDELETED(target))
					qdel(target)
				if(held && !QDELETED(held))
					qdel(held)
				for(var/atom/movable/leftover in T)
					if(leftover != H && leftover != crate)
						qdel(leftover)
				if(capture)
					if(line)
						log_test("DXORDER|[label]|[line]")
					continue
				if(line)
					seen[label] = line
					if(dx_menu_order_answered(line) != dx_menu_order_answered(golden[label]))
						log_test("DXDIFF|[label]|[golden[label]]|[line]")
						diffs++
	if(capture)
		TEST_FAIL("no golden table: captured the orders into the log (DXORDER lines)")
		return
	TEST_ASSERT_EQUAL(diffs, 0, "scenarios whose click or menu order changed (the DXDIFF lines of the log)")
	TEST_ASSERT_EQUAL(length(seen), length(golden), "the same scenarios resolve to a non-empty order as when the table was captured")

// ---- every type, statically ----

/// The order of a type's own ops with every gate ignored (one target-side candidate per binding at its op's tier, in declaration order), as the
/// click sort puts them: a string of keys. Only types that carry something the default precedence orders (a construction step, the maintenance
/// access, two item inputs where one is the narrower) or a relative priority are listed, so the table is the whole set the default can move.
/proc/dx_menu_order_static(type)
	var/datum/type_table/T = table_of_type(type)
	if(!T)
		return null
	var/datum/op_index/index = op_index_of_table(T)
	if(!length(index?.ordered))
		return null
	var/interesting = FALSE
	var/datum/op_resolution/S = new
	S.ordered = list()
	var/list/item_types = list()
	var/broad = FALSE
	var/tooled = FALSE
	var/seq = 0
	for(var/datum/op_plan/P as anything in index.ordered)
		var/key = P.key
		if(findtext(key, "construction.") == 1 || findtext(key, "panel.") == 1 || findtext(key, "wires.") == 1 || key == "storage.put_in" || length(P.priority_rel))
			interesting = TRUE
		for(var/datum/entry/part/bind/B as anything in P.bindings)
			var/datum/op_cand/C = new
			C.oplan = P
			C.tier = P.tier
			C.seq = ++seq
			C.specificity = op_binding_specificity(B)
			if(C.specificity == 1)
				broad = TRUE
			else if(C.specificity == 2)
				tooled = TRUE
			if("family" in C.vars)
				C.vars["family"] = call("/proc/op_family_of")(key)
			if(B.bind_kind == BIND_ITEM || B.bind_kind == BIND_STACK)
				var/item_type = B.args["type"]
				if("item_type" in C.vars)
					C.vars["item_type"] = item_type
				for(var/other in item_types)
					if(other != item_type && (ispath(other, item_type) || ispath(item_type, other)))
						interesting = TRUE
				item_types += item_type
			S.ordered += C
	if(broad && tooled)
		interesting = TRUE // a tool and a broad item: binding specificity orders them
	if(!interesting)
		return null
	op_resolution_sort(S)
	return dx_menu_order_keys(S.ordered)

/datum/unit_test/dx_menu_order_static/Run()
	var/list/golden = dx_menu_order_static_golden()
	if(!length(golden))
		// capture (see dx_menu_order_golden.dm): every type the static order lists
		for(var/type in typesof(/obj, /mob, /turf))
			var/order = null
			try
				order = dx_menu_order_static(type)
			catch
				continue // a type that cannot build its table outside a map; the capture lists only the ones that can
			if(order)
				log_test("DXSTATIC|[type]|[order]")
		TEST_FAIL("no golden table: captured the orders into the log (DXSTATIC lines)")
		return
	for(var/name in golden)
		var/type = text2path(name)
		TEST_ASSERT(ispath(type), "[name] is still a type")
		// Ops declared since the capture (a converted interaction, a verb) may be new; the ones it had keep their order.
		var/list/want = splittext(golden[name], ",")
		var/list/have = splittext(dx_menu_order_static(type), ",")
		var/list/kept = list()
		for(var/key in have)
			if(key in want)
				kept += key
		TEST_ASSERT_EQUAL(jointext(kept, ","), golden[name], "[name]: the order of its ops is the one captured before the default precedence")

// ---- the maintenance hatch's canonical click order, on an APC ----

/// An APC with no cell, so an empty hand on the open bay meets the build ladder and not the cell bay.
/obj/machinery/power/apc/dx_click_order
	cell_type = null

/// maintenance_hatch() declares once which op a tool picks when several could (click_order(), code/engine/parts/plan.dm), and a construction placed
/// at(SPACE_HATCH) offers its undo steps only with the hatch open (a step behind a shut cover is set aside): the APC writes no priority(above(...)) or when(COVER_OPEN) of its own.
///   screwdriver: a construction step, then the panel; wirecutters: the construction undo, then the wires; multitool: the subversion reset
///   (in the hatch, so only with the cover open, as the old APC asked), else the wires; empty hand: the construction undo, then the wires window, then the APC's own window.
/datum/unit_test/dx_apc_click_order

/datum/unit_test/dx_apc_click_order/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_use_stance(I_HELP)
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc/dx_click_order, T)
	var/obj/item/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/wirecutters = allocate(/obj/item/tool/wirecutters, T)
	var/obj/item/multitool = allocate(/obj/item/multitool, T)
	TEST_ASSERT_EQUAL(graph_current(A), STAGE_APC_SECURED, "a finished APC")
	// shut up: the hatch's tools work the panel, the hand opens the window
	TEST_ASSERT(assert_resolves(H, A, screwdriver, GESTURE_CLICK, "panel.open"), "shut: a screwdriver works the panel, not the build ladder behind the cover")
	TEST_ASSERT(assert_resolves(H, A, null, GESTURE_CLICK, "ui_open"), "shut: an empty hand opens the window")
	// the panel open (the cover shut): the wires
	key_set(A, PANEL_OPEN, TRUE)
	TEST_ASSERT(assert_resolves(H, A, wirecutters, GESTURE_CLICK, "wires.cut"), "panel open: wirecutters go to the wires")
	TEST_ASSERT(assert_resolves(H, A, multitool, GESTURE_CLICK, "wires.pulse"), "panel open: a multitool goes to the wires")
	TEST_ASSERT(assert_resolves(H, A, null, GESTURE_CLICK, "wires.open"), "panel open: an empty hand opens the wires before the window")
	// subverted, the cover shut: the reset sits in the hatch behind the cover (set aside), so the multitool still pulses a wire
	key_set(A, EMAG_EMAGGED, TRUE)
	TEST_ASSERT(assert_resolves(H, A, multitool, GESTURE_CLICK, "wires.pulse"), "subverted, cover shut: the multitool pulses a wire: [explain_click(H, A, multitool)]")
	// the cover open: the build ladder's steps come first
	key_set(A, COVER_OPEN, TRUE)
	TEST_ASSERT(assert_resolves(H, A, multitool, GESTURE_CLICK, "subversion_reset.use"), "subverted, cover open: the multitool resets it: [explain_click(H, A, multitool)]")
	key_set(A, EMAG_EMAGGED, FALSE)
	TEST_ASSERT(assert_resolves(H, A, screwdriver, GESTURE_CLICK, "construction.undo:apc_secured"), "cover open: the screwdriver unfastens the electronics before the panel")
	graph_undo(A)
	TEST_ASSERT_EQUAL(graph_current(A), STAGE_APC_WIRED, "back at the wired stage")
	TEST_ASSERT(assert_resolves(H, A, wirecutters, GESTURE_CLICK, "construction.undo:apc_wired"), "wired: wirecutters take the cable out before cutting a wire")
	TEST_ASSERT(assert_resolves(H, A, screwdriver, GESTURE_CLICK, "construction.build:apc_secured"), "wired: the screwdriver fastens the electronics before the panel")
	graph_undo(A)
	TEST_ASSERT_EQUAL(graph_current(A), STAGE_APC_BOARD, "back at the board stage")
	TEST_ASSERT(assert_resolves(H, A, null, GESTURE_CLICK, "construction.undo:apc_board"), "board: an empty hand takes the board out before the wires window")
	// the cover shut again: no step back is offered, the tools fall through to the hatch
	key_set(A, COVER_OPEN, FALSE)
	TEST_ASSERT(assert_resolves(H, A, null, GESTURE_CLICK, "wires.open"), "shut at the board stage: the undo is not offered, the hand reaches the wires")
	if(A.terminal)
		qdel(A.terminal) // made when the APC initialized; graph_undo() steps back without the ladder's own effects


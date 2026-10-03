// The order ops answer a click and fill a menu in (resolve.dm: op_resolution_sort). The golden table below was captured BEFORE the default
// family precedence replaced the priority(above(...)) lines that only ordered menu entries, so it proves the removal changed nothing.
//
// One scenario is a target and a held item (null: an empty hand); the target is the holder type, a floor, or a box, so a holder's own ops and
// the ops it brings as a held item are both ordered. Each scenario records three strings:
//   all   - every op bound to the input, gates ignored, sorted as a click sorts them (the state-independent order)
//   click - the survivors of a real help-intent click
//   menu  - the keys of op_menu() for the same input
// A scenario whose three strings are empty is not listed; the test counts them, so an op appearing where none was fails too.

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
	var/datum/op_resolution/R = op_resolve(H, target, held, ORIGIN_CLICK, AUTH_PHYSICAL, GESTURE_CLICK, null, FALSE, TRUE)
	var/datum/op_resolution/S = new
	S.ordered = R.all.Copy()
	op_resolution_sort(S)
	var/all = dx_menu_order_keys(S.ordered)
	var/click = dx_menu_order_keys(R.ordered)
	var/list/menu = list()
	for(var/list/row as anything in op_menu(H, target, held))
		menu += row["key"]
	if(!length(all) && !length(click) && !length(menu))
		return null
	return "[all] | [click] | [jointext(menu, ",")]"

/datum/unit_test/dx_menu_order
	priority = TEST_LONGER

/datum/unit_test/dx_menu_order/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_use_stance(I_HELP)
	var/list/golden = dx_menu_order_golden()
	var/list/seen = list()
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
					TEST_ASSERT_EQUAL(line, golden[label], "[label]: the click and menu order is the one captured before the default precedence")
	if(capture)
		TEST_FAIL("no golden table: captured the orders into the log (DXORDER lines)")
		return
	TEST_ASSERT_EQUAL(length(seen), length(golden), "the same scenarios resolve to a non-empty order as when the table was captured")

// ---- every type, statically ----

/// The order of a type's own ops with every gate ignored (one target-side candidate per op at its tier, in declaration order), as the click
/// sort puts them: a string of keys. Only types that carry an op the default precedence orders (a construction step or the storage fallback) or
/// a relative priority are listed, so the table is the whole set the default can move.
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
	var/seq = 0
	for(var/datum/op_plan/P as anything in index.ordered)
		if(findtext(P.key, "construction.") == 1 || P.key == "storage.put_in" || length(P.priority_rel))
			interesting = TRUE
		var/datum/op_cand/C = new
		C.oplan = P
		C.tier = P.tier
		C.seq = ++seq
		S.ordered += C
	if(!interesting)
		return null
	op_resolution_sort(S)
	return dx_menu_order_keys(S.ordered)

/datum/unit_test/dx_menu_order_static/Run()
	var/list/golden = dx_menu_order_static_golden()
	TEST_ASSERT(length(golden), "the golden table exists")
	for(var/name in golden)
		var/type = text2path(name)
		TEST_ASSERT(ispath(type), "[name] is still a type")
		TEST_ASSERT_EQUAL(dx_menu_order_static(type), golden[name], "[name]: the order of its ops is the one captured before the default precedence")

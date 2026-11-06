// The ops that used to order themselves with a hand-written priority(above(...)) / priority(below(...)) now sit in a click_order() of the bundle that
// composes them (plan.dm). This pins the order each of those types gives its ops (every gate ignored, as the click sort puts them: dx_menu_order_static)
// to the one captured before the conversion, so the conversion moved nothing.

/// The types whose ops lost a priority(above/below(...)).
/proc/dx_click_order_types()
	return list(
		/obj/machinery/door/airlock, /obj/item/material/ashtray, /obj/item/reagent_containers/glass/paint, /obj/item/storage/bible,
		/obj/item/storage/box, /obj/item/storage/lockbox, /obj/item/storage/secure, /obj/structure/closet/secure_closet/personal,
		/obj/item/reagent_containers/glass/beaker, /obj/item/reagent_containers/glass/bucket, /obj/item/reagent_containers/spray,
		/obj/structure/bed/chair, /obj/machinery/vending, /obj/item/lightreplacer/dogborg, /obj/structure/table)

/datum/unit_test/dx_click_order_conversion

/datum/unit_test/dx_click_order_conversion/Run()
	var/list/golden = dx_click_order_golden()
	if(!length(golden))
		for(var/type in dx_click_order_types())
			log_test("DXCLICK|[type]|[dx_menu_order_static(type, TRUE)]")
		TEST_FAIL("no golden table: captured the orders into the log (DXCLICK lines)")
		return
	for(var/type in dx_click_order_types())
		TEST_ASSERT_EQUAL(dx_menu_order_static(type, TRUE), golden["[type]"], "[type]: the order of its ops is the one captured before click_order() replaced its relative priorities")

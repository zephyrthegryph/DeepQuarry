// Behaviour pins for procs that were split into smaller ones (the exosuit window data, the vore chat export and OOC escape, a dismembered limb).

/// Every view of the exosuit window still carries what it carried: the main view's sections all land in one list.
/datum/unit_test/dq_p3_mecha_window_views

/datum/unit_test/dq_p3_mecha_window_views/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	var/list/main = mech.ui_data_obj_mecha(pilot, null, null)
	for(var/key in list("title", "damage_reports", "integrity_percent", "cell_percent", "tank_pressure", "cabin_pressure", "lights", "cargo", "radio_freq", "id_upload_locked", "equipment", "commands", "slots", "can_eject"))
		TEST_ASSERT(key in main, "the main view carries [key]")
	TEST_ASSERT_EQUAL(length(main["slots"]), 7, "seven slot kinds are counted")
	TEST_ASSERT(main["can_eject"], "a seated pilot can be ejected")
	mech.set_tgui_subview("log")
	var/list/log_view = mech.ui_data_obj_mecha(pilot, null, null)
	TEST_ASSERT("log_entries" in log_view, "the log view carries the log")
	TEST_ASSERT(!("slots" in log_view), "and not the main view")
	mech.set_tgui_subview("access")
	var/list/access_view = mech.ui_data_obj_mecha(pilot, null, null)
	TEST_ASSERT("access_current" in access_view, "the access view lists the access asked for")
	TEST_ASSERT("access_available" in access_view, "and what the card could add")
	mech.set_tgui_subview("maint")
	var/list/maint_view = mech.ui_data_obj_mecha(pilot, null, null)
	TEST_ASSERT("maint_can_set_air" in maint_view, "the maintenance view carries its permissions")
	TEST_ASSERT(!("equipment" in maint_view), "and not the main view")
	mech.set_tgui_subview("main")

/// The belly chat export lists every message list in order, each as a titled list of the belly's own messages.
/datum/unit_test/dq_p3_vore_export_sections

/datum/unit_test/dq_p3_vore_export_sections/Run()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human)
	var/obj/belly/B = new /obj/belly(pred)
	B.set_struggle_messages_outside(list("outside one", "outside two"))
	B.set_examine_messages(list("full"))
	var/list/sections = pred.vore_export_sections(B)
	TEST_ASSERT_EQUAL(length(sections), 37, "thirty-seven titled lists are exported")
	var/list/first = sections[1]
	TEST_ASSERT_EQUAL(first[1], "Struggle messages (outside):", "the first list is the outside struggle messages")
	TEST_ASSERT_EQUAL(first[2], B.struggle_messages_outside, "and it is the belly's own list")
	var/list/last = sections[length(sections)]
	TEST_ASSERT_EQUAL(last[1], "Examine messages (with absorbed victims):", "the last list is the absorbed examine messages")
	var/found = FALSE
	for(var/list/section as anything in sections)
		if(section[1] == "Examine messages (when full):")
			found = TRUE
			TEST_ASSERT_EQUAL(section[2], B.examine_messages, "the full examine list is the belly's own")
	TEST_ASSERT(found, "the full examine messages are exported")

/// The OOC escape from a belly asks, then (once answered) puts the prey on the floor and out of the belly; outside any belly it only says so.
/datum/unit_test/dq_p3_vore_escape_from_belly

/datum/unit_test/dq_p3_vore_escape_from_belly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human, T)
	var/obj/belly/B = new /obj/belly(pred)
	prey.forceMove(B)
	TEST_ASSERT_EQUAL(prey.loc, B, "the prey starts in the belly")
	prey.vore_escape_stage(list("a1" = "Cancel"))
	TEST_ASSERT_EQUAL(prey.loc, B, "a cancelled escape leaves them there")
	prey.vore_escape_stage(list("a1" = "Okay"))
	TEST_ASSERT_EQUAL(prey.loc, T, "a confirmed escape puts them on the floor")
	prey.vore_escape_stage(list())
	TEST_ASSERT_EQUAL(prey.loc, T, "outside any belly the button does nothing")

/// A clean amputation takes the limb off its owner and leaves it a loose item on the floor.
/datum/unit_test/dq_p3_droplimb_edge_and_gib

/datum/unit_test/dq_p3_droplimb_edge_and_gib/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	var/obj/item/organ/external/arm = victim.get_organ(BP_L_ARM)
	TEST_ASSERT(arm, "the victim has a left arm")
	arm.droplimb(TRUE, DROPLIMB_EDGE)
	own(arm)
	TEST_ASSERT(!QDELETED(arm), "a clean cut leaves the arm")
	TEST_ASSERT_NULL(arm.owner, "but not on its owner")
	var/obj/item/organ/external/leg = victim.get_organ(BP_L_LEG)
	TEST_ASSERT(leg, "the victim has a left leg")
	leg.droplimb(FALSE, DROPLIMB_BURN)
	TEST_ASSERT(QDELETED(leg), "a burned-off leg is gone")
	var/obj/effect/decal/cleanable/ash/ash = locate() in T
	TEST_ASSERT(ash, "and leaves ash")
	own(ash)

// ---- the portable pump follows its cell without a hand-called refresh ----

/// How many times a probe pump has been drawn.
GLOBAL_VAR_INIT(p3_pump_draws, 0)

/// A pump that counts its draws.
/obj/machinery/portable_atmospherics/powered/pump/p3_probe

/obj/machinery/portable_atmospherics/powered/pump/p3_probe/draw(datum/look/look)
	..()
	GLOB.p3_pump_draws++

/// A cell that runs dry redraws the portable pump it sits in, and one that is charged again redraws it once more; a change of charge that keeps
/// some charge draws nothing.
/datum/unit_test/dq_p3_pump_follows_cell_charge

/datum/unit_test/dq_p3_pump_follows_cell_charge/Run()
	var/turf/T = test_floor()
	var/obj/machinery/portable_atmospherics/powered/pump/p3_probe/pump = allocate(/obj/machinery/portable_atmospherics/powered/pump/p3_probe, T)
	var/obj/item/cell/cell = pump.cell
	TEST_ASSERT(cell, "the pump comes with its cell")
	set_global(nameof(GLOB.p3_pump_draws), 0)
	pump.set_on(TRUE)
	stat_drain_point()
	refresh_flush()
	TEST_ASSERT(cell.charged, "a full cell is charged")
	var/draws = GLOB.p3_pump_draws
	cell.set_charge(cell.maxcharge * 0.5)
	stat_drain_point()
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.p3_pump_draws, draws, "a cell that still has charge redraws nothing")
	cell.set_charge(0)
	stat_drain_point()
	refresh_flush()
	TEST_ASSERT(!cell.charged, "an empty cell is not charged")
	TEST_ASSERT_EQUAL(GLOB.p3_pump_draws, draws + 1, "a cell that runs dry redraws the pump")
	cell.set_charge(cell.maxcharge)
	stat_drain_point()
	refresh_flush()
	TEST_ASSERT(cell.charged, "a recharged cell is charged")
	TEST_ASSERT_EQUAL(GLOB.p3_pump_draws, draws + 2, "and redraws it again")

// ---- the vending catalog (strings/vending/catalog.json) ----

/// A cola machine that sets nothing of its own.
/obj/machinery/vending/cola/p3_plain

/// A cola machine that stocks its own products and keeps the catalog's contraband and prices.
/obj/machinery/vending/cola/p3_own_products
	products = list(/obj/item/coin = 2)

/// The record of a vendor stocking `path`, or null.
/datum/unit_test/proc/p3_vending_record(obj/machinery/vending/V, path)
	for(var/datum/stored_item/vending_product/R as anything in V.product_records)
		if(R.item_path == path)
			return R
	return null

/// A vendor's stock comes from the catalog row of its type: products with their amounts, contraband hidden, prices on the items.
/datum/unit_test/dq_p3_vending_catalog_stock

/datum/unit_test/dq_p3_vending_catalog_stock/Run()
	var/turf/T = test_floor()
	var/obj/machinery/vending/cola/V = allocate(/obj/machinery/vending/cola, T)
	TEST_ASSERT(length(V.product_records) > 10, "a cola machine is stocked")
	var/datum/stored_item/vending_product/cola = p3_vending_record(V, /obj/item/reagent_containers/food/drinks/cans/cola)
	TEST_ASSERT(cola, "it sells cola")
	TEST_ASSERT_EQUAL(cola.get_amount(), 10, "ten of them")
	TEST_ASSERT_EQUAL(cola.price, 1, "at the catalog's price")
	TEST_ASSERT_EQUAL(cola.category, CAT_NORMAL, "on the open shelf")
	var/datum/stored_item/vending_product/loko = p3_vending_record(V, /obj/item/reagent_containers/food/drinks/cans/thirteenloko)
	TEST_ASSERT(loko, "it hides thirteen loko")
	TEST_ASSERT_EQUAL(loko.category, CAT_HIDDEN, "as contraband")
	TEST_ASSERT(V.refill?[/obj/item/reagent_containers/food/drinks/cans/cola], "a refill cartridge restocks what it sells")
	TEST_ASSERT_NULL(V.products, "the lists are dropped once the records are built")

/// A subtype takes its parent type's catalog row for whatever it sets nothing of; one list set on the type wins for that list only.
/datum/unit_test/dq_p3_vending_catalog_inherits

/datum/unit_test/dq_p3_vending_catalog_inherits/Run()
	var/turf/T = test_floor()
	var/obj/machinery/vending/cola/V = allocate(/obj/machinery/vending/cola, T)
	var/obj/machinery/vending/cola/p3_plain/plain = allocate(/obj/machinery/vending/cola/p3_plain, T)
	TEST_ASSERT_EQUAL(length(plain.product_records), length(V.product_records), "a subtype with no lists of its own stocks like its parent")
	var/obj/machinery/vending/cola/p3_own_products/own = allocate(/obj/machinery/vending/cola/p3_own_products, T)
	var/datum/stored_item/vending_product/coin = p3_vending_record(own, /obj/item/coin)
	TEST_ASSERT(coin, "the type's own products are stocked")
	TEST_ASSERT_NULL(p3_vending_record(own, /obj/item/reagent_containers/food/drinks/cans/cola), "and replace the catalog's")
	TEST_ASSERT(p3_vending_record(own, /obj/item/reagent_containers/food/drinks/cans/thirteenloko), "while the contraband still comes from the catalog")

/// Every type the catalog names is a vendor, and every item in it is a real type (a typo would otherwise stock nothing).
/datum/unit_test/dq_p3_vending_catalog_is_sound

/datum/unit_test/dq_p3_vending_catalog_is_sound/Run()
	var/list/catalog = vending_catalog_load()
	TEST_ASSERT(length(catalog) > 50, "the catalog is read")
	for(var/type_text in catalog)
		var/vendor_type = text2path(type_text)
		TEST_ASSERT(vendor_type && ispath(vendor_type, /obj/machinery/vending), "[type_text] is a vendor type")
		var/list/row = catalog[type_text]
		for(var/section in row)
			TEST_ASSERT(section in list("products", "contraband", "premium", "prices"), "[type_text] has a known list [section]")
			for(var/path in row[section])
				// A collapsed type (the seed packets) is named by its VARIANT() reference: its row's base type is what stocks.
				TEST_ASSERT(ispath(path) || ispath(saved_type_path(path)), "[type_text] [section] names a type ([path])")

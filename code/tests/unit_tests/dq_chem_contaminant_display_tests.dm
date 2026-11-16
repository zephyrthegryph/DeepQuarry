// What a chemistry window shows and what a dispense gives: a dispense of N units is N units in all (the source's impurities are taken out of the N), the
// window rows list the contaminants last and flag them, and no machine pulls a single chemical out of a mixture.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A chemical dispenser with a hydrogen cartridge and an empty beaker set in it.
/datum/unit_test/proc/dq_cdisp_dispenser()
	var/obj/machinery/chemical_dispenser/ert/D = allocate(/obj/machinery/chemical_dispenser/ert, test_floor())
	var/obj/item/reagent_containers/chem_disp_cartridge/C = own(variant_new(VARIANT(/obj/item/reagent_containers/chem_disp_cartridge/hydrogen), test_floor()))
	D.cartridges[C.label] = C
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	move_into(D, nameof(D.container), B)
	return D

/// 10u dispensed is exactly 10u in the beaker, contaminants included, and what the window reads out is the same figure.
/datum/unit_test/dq_chem_dispense_gives_exactly_the_amount
	boot_needs = list()

/datum/unit_test/dq_chem_dispense_gives_exactly_the_amount/Run()
	var/obj/machinery/chemical_dispenser/D = dq_cdisp_dispenser()
	var/obj/item/reagent_containers/chem_disp_cartridge/C
	for(var/label in D.cartridges)
		C = D.cartridges[label]
		break
	TEST_ASSERT_NOTNULL(C, "the dispenser holds a cartridge")
	TEST_ASSERT(C.reagents.contaminant_volume() > 0, "the cartridge carries trace contaminants")
	var/datum/act/op/stub = new
	D.set_amount(10)
	D.ui_act_dispense(stub, C.label)
	var/datum/reagents/H = D.container.reagents
	TEST_ASSERT(abs(H.total_volume - 10) < 0.001, "10u dispensed is 10u in the beaker ([H.total_volume])")
	TEST_ASSERT(H.contaminant_volume() > 0, "the traces are among them")
	TEST_ASSERT(H.get_reagent_amount(REAGENT_ID_HYDROGEN) < 10, "taken out of the 10u, not added to it")
	var/list/data = D.ui_data_part_chemical_dispenser(null)
	TEST_ASSERT(abs(data["beakerCurrentVolume"] - 10) < 0.001, "and the window's count says 10")
	var/shown = 0
	for(var/list/row in data["beakerContents"])
		shown += row["volume"]
	TEST_ASSERT(abs(shown - 10) < 0.001, "its rows add up to 10 ([shown])")
	// A holder (the synthesizer's pull) and a second dispense add up the same way.
	var/datum/reagents/vessel = new /datum/reagents(100)
	var/moved = C.dispense_to_holder(vessel, 10)
	TEST_ASSERT(abs(moved - 10) < 0.001 && abs(vessel.total_volume - 10) < 0.001, "10u into a holder is 10u")
	D.ui_act_dispense(stub, C.label)
	TEST_ASSERT(abs(H.total_volume - 20) < 0.001, "two dispenses are 20u")
	// A bottled or recharged source adds its amount in all, too.
	var/datum/reagents/bottle = new /datum/reagents(100)
	var/added = bottle.add_sourced_reagent(REAGENT_ID_HYDROGEN, 30, chem_source_profile(REAGENT_ID_HYDROGEN, "test lot", GRADE_STANDARD))
	TEST_ASSERT(abs(added - 30) < 0.001 && abs(bottle.total_volume - 30) < 0.001, "30u of a sourced reagent is 30u in all ([bottle.total_volume])")

/// The rows of every listing put the contaminants after the real chemicals and flag them.
/datum/unit_test/dq_chem_window_rows_put_contaminants_last
	boot_needs = list()

/datum/unit_test/dq_chem_window_rows_put_contaminants_last/Run()
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	// The contaminants go in first, so a plain listing would show them first.
	B.reagents.add_reagent(REAGENT_ID_CONTAMINANT_HEAVY_METAL, 2, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_DEXALIN, 10, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_CONTAMINANT_SALTS, 1, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_ANTITOXIN, 5, safety = 1)
	var/list/rows = B.reagents.ui_rows()
	TEST_ASSERT_EQUAL(length(rows), 4, "four rows")
	var/seen_contaminant = FALSE
	for(var/list/row in rows)
		if(row["contaminant"])
			seen_contaminant = TRUE
		else
			TEST_ASSERT(!seen_contaminant, "[row["name"]] is a real chemical listed after a contaminant")
	TEST_ASSERT(rows[3]["contaminant"] && rows[4]["contaminant"], "the last two rows are the contaminants")
	TEST_ASSERT(!rows[1]["contaminant"] && !rows[2]["contaminant"], "and the first two are not flagged")
	// The windows read the same rows.
	var/obj/machinery/chemical_dispenser/ert/D = allocate(/obj/machinery/chemical_dispenser/ert, test_floor())
	move_into(D, nameof(D.container), B)
	var/list/shown = D.ui_data_part_chemical_dispenser(null)["beakerContents"]
	TEST_ASSERT(shown[3]["contaminant"] && shown[4]["contaminant"] && !shown[1]["contaminant"], "the dispenser's beaker rows list them last, flagged")
	var/obj/machinery/chem_master/M = allocate(/obj/machinery/chem_master, test_floor())
	var/obj/item/reagent_containers/glass/beaker/large/other = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	other.reagents.add_reagent(REAGENT_ID_CONTAMINANT_SULFUR, 1, safety = 1)
	other.reagents.add_reagent(REAGENT_ID_DEXALIN, 4, safety = 1)
	move_into(M, nameof(M.beaker), other)
	var/list/master = M.ui_data_part_chem_master(null)["beaker_reagents"]
	TEST_ASSERT(!master[1]["contaminant"] && master[2]["contaminant"], "the chem master's beaker rows list them last, flagged")
	var/list/order = other.reagents.listed_reagents()
	var/datum/reagent/first = order[1]
	TEST_ASSERT_EQUAL(first.id, REAGENT_ID_DEXALIN, "and its analysis numbers its rows in that order")

/// The per-chemical separations are gone: no isolate, no per-reagent remove in the dispenser, and the chem master moves only the whole mix.
/datum/unit_test/dq_chem_no_single_chem_separation
	boot_needs = list()

/datum/unit_test/dq_chem_no_single_chem_separation/Run()
	var/obj/machinery/chemical_dispenser/ert/D = allocate(/obj/machinery/chemical_dispenser/ert, test_floor())
	TEST_ASSERT(!hascall(D, "ui_act_remove"), "the dispenser has no per-reagent remove or isolate")
	var/datum/reagents/H = dq_contam_holder()
	TEST_ASSERT(!hascall(H, "isolate_reagent"), "a holder cannot isolate one reagent")
	var/obj/machinery/chem_master/M = allocate(/obj/machinery/chem_master, test_floor())
	var/obj/item/reagent_containers/glass/beaker/large/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
	B.reagents.add_reagent(REAGENT_ID_DEXALIN, 30, safety = 1)
	B.reagents.add_reagent(REAGENT_ID_ANTITOXIN, 10, safety = 1)
	move_into(M, nameof(M.beaker), B)
	var/datum/act/op/stub = new
	M.ui_act_add(stub, 20)
	TEST_ASSERT(abs(M.reagents.get_reagent_amount(REAGENT_ID_DEXALIN) - 15) < 0.001, "the chem master takes the mix: half the dexalin")
	TEST_ASSERT(abs(M.reagents.get_reagent_amount(REAGENT_ID_ANTITOXIN) - 5) < 0.001, "and half the antitoxin")

#endif

// Actual constructors exercise A2 declared lifecycle jobs, not their helpers.
/datum/unit_test/dq_a2_item_init
	abstract_type = /datum/unit_test/dq_a2_item_init

/datum/unit_test/dq_a2_item_init/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_a2_item_init/lighter_inheritance/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/flame/lighter/cheap = allocate(/obj/item/flame/lighter, test_floor())
	var/obj/item/flame/lighter/zippo/zippo = allocate(/obj/item/flame/lighter/zippo, test_floor())
	TEST_ASSERT_EQUAL(length(cheap.overlays), 1, "A real cheap lighter receives one randomized casing")
	TEST_ASSERT_EQUAL(length(zippo.overlays), 0, "Zippo setup clears the inherited cheap casing after it was drawn")

/datum/unit_test/dq_a2_item_init/sandbag_parent/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/stack/sandbags/bags = allocate(/obj/item/stack/sandbags, test_floor(), 15)
	TEST_ASSERT_EQUAL(bags.get_amount(), 15, "The stack parent applies the constructor amount before setup")
	TEST_ASSERT_EQUAL(bags.slowdown, 1.5, "Sandbag setup computes slowdown from the parent's applied amount")
	TEST_ASSERT_EQUAL(bags.recipes, GLOB.sandbag_recipes, "Sandbag setup attaches the actual shared recipe table")

/datum/unit_test/dq_a2_item_init/standin_guard/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/cell/standin/valid = allocate(/obj/item/cell/standin, test_floor(), H)
	TEST_ASSERT(!QDELETED(valid), "A stand-in cell with its real human source is kept")
	TEST_ASSERT_EQUAL(valid.charge, nutrition_of(H), "The kept cell's existing setup reads actual human nutrition")
	TEST_ASSERT_EQUAL(valid.maxcharge, H.starting_nutrition(), "The kept cell uses its human's nutrition capacity")
	var/obj/item/cell/standin/invalid = allocate(/obj/item/cell/standin, test_floor())
	TEST_ASSERT(QDELETED(invalid), "A stand-in without a human is discarded before charging setup")

/datum/unit_test/dq_a2_item_init/paired_charge/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/turf/T = test_floor()
	var/list/before = contents_of(T, /obj/item/flame/lighter/zippo/c4detonator)
	var/obj/item/syndie/c4explosive/charge = allocate(/obj/item/syndie/c4explosive, T)
	var/list/created
	for(var/obj/item/flame/lighter/zippo/c4detonator/D as anything in contents_of(T, /obj/item/flame/lighter/zippo/c4detonator))
		if(D in before)
			continue
		own(D)
		LAZYADD(created, D)
	TEST_ASSERT_EQUAL(length(created), 1, "A charge constructor creates one paired detonator at its location")
	var/obj/item/flame/lighter/zippo/c4detonator/detonator = created[1]
	TEST_ASSERT_EQUAL(detonator.bomb(), charge, "The real detonator names the charge that created it")
	var/start = findtext(charge.desc, "You see ")
	TEST_ASSERT(start, "The charge receives its generated engraving")
	var/key = copytext(charge.desc, start + 8, start + 14)
	TEST_ASSERT_EQUAL(length(key), 6, "The paired engraving preserves its six-character key")
	TEST_ASSERT(findtext(detonator.desc, key), "The detonator receives the charge's same engraving key")

/datum/unit_test/dq_a2_item_init/meal_components/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/storage/box/tgmc_mre/meal = allocate(/obj/item/storage/box/tgmc_mre, test_floor())
	var/components = 0
	for(var/obj/item/I as anything in meal.slot_contents(CONTAINER_SLOT_STORAGE))
		own(I)
		if(istype(I, /obj/item/reagent_containers/food/snacks/tgmc_mre_component))
			components++
	TEST_ASSERT_EQUAL(components, 4, "A real MRE contains its four separately flavored food components")
	TEST_ASSERT(findtext(meal.name, "("), "The MRE constructor labels the selected entree")
	var/obj/item/reagent_containers/food/snacks/tgmc_mre_component/entree = allocate(/obj/item/reagent_containers/food/snacks/tgmc_mre_component, test_floor(), "grilled chicken")
	TEST_ASSERT_EQUAL(entree.seasoning, REAGENT_ID_SODIUMCHLORIDE, "The existing flavor parameter selects the actual entree seasoning")
	TEST_ASSERT_EQUAL(entree.reagents.get_reagent_amount(REAGENT_ID_SODIUMCHLORIDE), 1, "Declared setup adds exactly the original one unit after reagents and flavor exist")

/obj/item/radio/headset/dq_a2_security
	ks1type = /obj/item/encryptionkey/headset_sec

/datum/unit_test/dq_a2_item_init/headset_channels/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/radio/headset/H = allocate(/obj/item/radio/headset/dq_a2_security, test_floor())
	TEST_ASSERT(istype(H.keyslot1, /obj/item/encryptionkey/headset_sec), "The real headset's declared starting key exists")
	TEST_ASSERT(CHANNEL_SECURITY in H.channels, "Key channels are computed before the headset materializes")
	TEST_ASSERT_EQUAL(H.channels[CHANNEL_SECURITY], 1, "The starting key preserves its security channel value")

/datum/unit_test/dq_a2_item_init/candles_and_assembly/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/flame/candle/everburn/candle = allocate(/obj/item/flame/candle/everburn, test_floor())
	var/obj/item/flame/candle/candelabra/everburn/candelabra = allocate(/obj/item/flame/candle/candelabra/everburn, test_floor())
	TEST_ASSERT(candle.lit && candelabra.lit, "Both real everburn candle constructors light themselves")
	var/obj/item/flamethrower/full/thrower = allocate(/obj/item/flamethrower/full, test_floor())
	TEST_ASSERT(thrower.status, "The full flamethrower marks its assembly complete")
	TEST_ASSERT(thrower.igniter && thrower.weldtool, "Its declared igniter and welder exist before complete-assembly setup")

/datum/unit_test/dq_a2_item_init/implant_backlink/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/implant/integrated_circuit/implant = allocate(/obj/item/implant/integrated_circuit, test_floor())
	TEST_ASSERT_NOTNULL(implant.IC, "The real implant has its declared starting electronics assembly")
	TEST_ASSERT_EQUAL(implant.IC.implant, implant, "Setup links the already-created electronics back to its implant")
	var/obj/machinery/implantchair/chair = allocate(/obj/machinery/implantchair, test_floor())
	TEST_ASSERT_EQUAL(length(chair.implant_list), chair.max_implants, "The real chair starts with its complete loyalty implant supply")
	for(var/obj/item/implant/loyalty/I as anything in chair.implant_list)
		TEST_ASSERT_EQUAL(I.loc, chair, "Each actual starting implant is inside its owner chair")

/datum/unit_test/dq_a2_item_init/static_goggles/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/clothing/glasses/ghost/goggles = allocate(/obj/item/clothing/glasses/ghost, test_floor())
	var/obj/item/clothing/glasses/ghost/advanced/clear = allocate(/obj/item/clothing/glasses/ghost/advanced, test_floor())
	TEST_ASSERT_EQUAL(goggles.overlay, GLOB.global_hud.heavy_whitense, "Standard goggles link to the real static HUD overlay")
	TEST_ASSERT_NULL(clear.overlay, "The advanced type's actual static_vision flag suppresses the overlay")

/datum/unit_test/dq_a2_item_init/material_ashtray/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/material/ashtray/tray = allocate(/obj/item/material/ashtray, test_floor())
	TEST_ASSERT(tray.material && !QDELETED(tray), "The material parent resolves a real material before dish setup")
	TEST_ASSERT_EQUAL(initial(tray.icon_state), "blank", "The formerly fixed initialization state is now the type default")
	TEST_ASSERT_EQUAL(tray.max_butts, round(tray.material.hardness / 5), "Capacity uses the parent's actual material hardness")
	TEST_ASSERT_NULL(tray.color, "The material dish clears the parent's overall material tint")
	TEST_ASSERT_NOTNULL(tray.base_overlay, "The dish setup builds its material-colored base overlay")

/datum/unit_test/dq_a2_item_init/pipe_painter_mode/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/pipe_painter/P = allocate(/obj/item/pipe_painter, test_floor())
	TEST_ASSERT(length(P.modes) > 0, "The real constructor derives its complete paint catalog")
	TEST_ASSERT_NOTNULL(P.mode, "The real constructor chooses a paint mode before returning")
	TEST_ASSERT(P.mode in P.modes, "The chosen initial mode belongs to the real derived paint catalog")
	TEST_ASSERT_EQUAL(length(P.modes), length(GLOB.pipe_colors), "Setup retains every configured paint colour")

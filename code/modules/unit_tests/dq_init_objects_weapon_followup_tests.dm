// Native weapon constructor hooks: material, owned children and final parent state.
/datum/unit_test/dq_init_objects_weapon_followup

/datum/unit_test/dq_init_objects_weapon_followup/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/material/sharpeningkit/K = allocate(/obj/item/material/sharpeningkit, T, MAT_STEEL)
	TEST_ASSERT_NOTNULL(K.material, "the real material parent resolves the sharpening kit material")
	TEST_ASSERT_EQUAL(K.repair_amount, K.material.hardness * 0.1, "setup uses the completed material hardness")
	TEST_ASSERT_EQUAL(K.repair_time, K.material.density * 0.5, "setup uses the completed material density")
	TEST_ASSERT_EQUAL(K.sharpen_time, K.material.density * 3, "setup retains the initial sharpening duration")
	var/obj/item/clothing/mask/smokable/ecig/simple/E = allocate(/obj/item/clothing/mask/smokable/ecig/simple, T)
	var/obj/item/reagent_containers/ecig_cartridge/cartridge = E.ec_cartridge
	TEST_ASSERT_NOTNULL(cartridge, "native ownership creates the actual cartridge before final setup")
	TEST_ASSERT_EQUAL(E.item_state, E.icon_off, "the real loaded e-cig starts with its off in-hand state")
	E.set_active(TRUE)
	TEST_ASSERT_EQUAL(E.item_state, E.icon_on, "the existing setter still synchronizes the active state")
	qdel(E)
	TEST_ASSERT(QDELETED(cartridge), "deleting the real e-cig deletes its native owned cartridge")

/datum/unit_test/dq_init_objects_weapon_followup/standin

/mob/living/carbon/human/dq_init_standin_provider/starting_nutrition()
	return 317

/datum/unit_test/dq_init_objects_weapon_followup/standin/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/dq_init_standin_provider, T)
	var/obj/item/cell/standin/C = allocate(/obj/item/cell/standin, T, H)
	TEST_ASSERT(!QDELETED(C), "the real supplied human keeps the stand-in cell")
	TEST_ASSERT_EQUAL(C.hume(), H, "the constructor retains its exact borrowed human provider")
	TEST_ASSERT_EQUAL(C.maxcharge, H.starting_nutrition(), "setup uses the actual provider's starting nutrition limit")
	TEST_ASSERT_EQUAL(C.charge, nutrition_of(H), "setup derives charge from the actual provider's nutrition")
	var/obj/item/cell/standin/invalid = allocate(/obj/item/cell/standin, T)
	TEST_ASSERT(QDELETED(invalid), "a stand-in with no provider is discarded before charge setup")
	qdel(C)
	TEST_ASSERT(!QDELETED(H), "deleting a stand-in never deletes its borrowed human provider")

/datum/unit_test/dq_init_objects_weapon_followup/transforming

/datum/unit_test/dq_init_objects_weapon_followup/transforming/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/tool/transforming/altevian/A = allocate(/obj/item/tool/transforming/altevian, T)
	var/obj/item/weldingtool/welder = A.welder
	TEST_ASSERT_NOTNULL(welder, "a tool with welding mode creates its real owned welder")
	TEST_ASSERT(istype(welder, A.weldertype), "the factory preserves the declared welder subtype")
	TEST_ASSERT_EQUAL(welder.loc, A, "the native factory passes its actual tool as the constructor location")
	TEST_ASSERT_EQUAL(A.current_tooltype, 1, "final setup preserves the initial mode index")
	qdel(A)
	TEST_ASSERT(QDELETED(welder), "deleting the transforming tool deletes its actual owned welder")
	var/obj/item/tool/transforming/jawsoflife/J = allocate(/obj/item/tool/transforming/jawsoflife, T)
	TEST_ASSERT_NULL(J.welder, "a tool without a welding mode creates no phantom child")
	TEST_ASSERT_EQUAL(J.icon_state, "jaws_pry", "the subtype's real initial mode setup selects its prying presentation")

/datum/unit_test/dq_init_objects_weapon_followup/blade_glow

/datum/unit_test/dq_init_objects_weapon_followup/blade_glow/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/melee/energy/blade/B = allocate(/obj/item/melee/energy/blade)
	TEST_ASSERT_EQUAL(glow_of(B).range, B.lrange, "initial blade setup retains the actual mapped glow range")
	TEST_ASSERT_EQUAL(glow_of(B).power, B.lpower, "initial blade setup retains the actual mapped glow power")
	TEST_ASSERT_EQUAL(glow_of(B).color, B.lcolor, "initial blade setup retains the actual mapped glow color")

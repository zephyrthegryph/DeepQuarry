// Constructor-only input is consumed by native parameter application, then dropped normally.
/datum/unit_test/dq_init_temp_param_capabilities
	abstract_type = /datum/unit_test/dq_init_temp_param_capabilities

/datum/unit_test/dq_init_temp_param_capabilities/decoy
/datum/unit_test/dq_init_temp_param_capabilities/decoy/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/pen/source = allocate(/obj/item/pen, test_floor())
	source.set_alpha(73)
	source.set_dir(EAST)
	var/obj/effect/temp_visual/decoy/D = allocate(/obj/effect/temp_visual/decoy, test_floor(), source)
	TEST_ASSERT_EQUAL(D.name, source.name, "The real parameter application sees the temporary source before it is dropped")
	TEST_ASSERT_EQUAL(D.icon, source.icon, "The actual source appearance is copied")
	TEST_ASSERT_EQUAL(D.alpha, 73, "The source's alpha overrides the decoy's initial alpha")
	TEST_ASSERT_EQUAL(D.dir, EAST, "The source direction overrides the native random direction")
	TEST_ASSERT_EQUAL(D.mouse_opacity, MOUSE_OPACITY_TRANSPARENT, "The decoy remains non-interactive")
	TEST_ASSERT_NULL(D.mimiced_atom, "Constructor-only source reference is still dropped after init")
	var/image/custom = image('icons/obj/candle.dmi', "candle1")
	custom.alpha = 91
	var/obj/effect/temp_visual/decoy/override = allocate(/obj/effect/temp_visual/decoy, test_floor(), source, custom.appearance)
	TEST_ASSERT_EQUAL(override.icon, custom.icon, "The explicit appearance still wins over the mimicked source")
	TEST_ASSERT_EQUAL(override.alpha, 91, "Explicit appearance retains its actual alpha")
	TEST_ASSERT_NULL(override.customappearance, "Explicit constructor appearance is not retained as shadow state")

/datum/unit_test/dq_init_temp_param_capabilities/statue
/datum/unit_test/dq_init_temp_param_capabilities/statue/Run()
	dq_init_objects_fixture_scope()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/endurance = H.get_endurance()
	var/vitality = H.vitality()
	var/obj/structure/closet/statue/S = allocate(/obj/structure/closet/statue, test_floor(), H)
	TEST_ASSERT_EQUAL(H.loc, S, "The native petrification callback moves the actual subject inside")
	TEST_ASSERT(H.sdisabilities & MUTE, "The same subject is muted")
	TEST_ASSERT_EQUAL(S.max_integrity, endurance + 100, "The statue uses the actual subject endurance")
	TEST_ASSERT_EQUAL(S.original_int, vitality * endurance + 100, "The actual original-integrity calculation is retained")
	TEST_ASSERT_EQUAL(S.name, "statue of [H.name]", "The subject's real name is used")
	TEST_ASSERT_NULL(S.statue_of, "The constructor-only subject reference is dropped")
	qdel(S)
	TEST_ASSERT(!QDELETED(H), "Deleting the statue retains its real released subject")

/datum/unit_test/dq_init_temp_param_capabilities/drop_pod
/datum/unit_test/dq_init_temp_param_capabilities/drop_pod/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/item/pen/cargo = allocate(/obj/item/pen, T)
	var/obj/structure/drop_pod/P = allocate(/obj/structure/drop_pod, T, cargo, TRUE)
	for(var/turf/tile as anything in block(get_step(T, SOUTHWEST), get_step(T, NORTHEAST)))
		own_turf_contents(tile)
	TEST_ASSERT_EQUAL(cargo.loc, P, "The real cargo is loaded before construction returns")
	TEST_ASSERT_NULL(P.loc, "The falling pod has entered nullspace")
	TEST_ASSERT(P.air, "The original owned gas exists before delivery starts")
	TEST_ASSERT_EQUAL(P.auto_open, TRUE, "The retained opening policy is preserved")
	TEST_ASSERT_NULL(P.cargo_at_make, "The temporary cargo argument is dropped after the callback uses it")
	qdel(P)

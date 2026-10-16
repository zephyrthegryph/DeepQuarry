// Native pre-parent contracts retain actual companions, tethers and map tape outcomes.
/datum/unit_test/dq_init_items_phase_contracts
	abstract_type = /datum/unit_test/dq_init_items_phase_contracts

/datum/unit_test/dq_init_items_phase_contracts/flipper
/datum/unit_test/dq_init_items_phase_contracts/flipper/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/paicard/flipper/F = allocate(/obj/item/paicard/flipper, test_floor())
	var/mob/living/silicon/pai/flipper/P = F.pai
	TEST_ASSERT(istype(P), "the actual flipper constructs its declared concrete companion")
	own(P)
	TEST_ASSERT_EQUAL(P.loc, F, "the actual companion is contained in its original card")
	TEST_ASSERT_EQUAL(P.card, F, "the companion's parent initializer binds the exact supplied card")
	TEST_ASSERT_EQUAL(P.radio, F.radio, "the actual companion and card share their original radio")
	TEST_ASSERT_EQUAL(P.chassis_name, PAI_DEFAULT_EMAGGED_CHASSIS, "the real flipper retains its constructor-selected chassis")
	TEST_ASSERT_EQUAL(F.current_emotion, 4, "the flipper's final construction hook retains its original expression")
	qdel(F)
	TEST_ASSERT(P.stat == DEAD || QDELETED(P), "deleting the card retains its original companion death policy")

/datum/unit_test/dq_init_items_phase_contracts/tethers
/datum/unit_test/dq_init_items_phase_contracts/tethers/Run()
	dq_init_objects_fixture_scope()
	for(var/path in list(/obj/item/defib_kit, /obj/item/bluespaceradio, /obj/item/proton_pack, /obj/item/medigun_backpack))
		var/obj/item/H = allocate(path, test_floor())
		var/obj/item/handheld = H.tethered_handheld()
		TEST_ASSERT_NOTNULL(handheld, "the actual host constructs its real starting handheld")
		TEST_ASSERT_EQUAL(handheld.tether_host(), H, "the real paired activation refers to its exact host")
		TEST_ASSERT_EQUAL(handheld.loc, H, "the real handheld begins contained in its original host")
		qdel(H)
		TEST_ASSERT(QDELETED(handheld), "host destruction retains the existing native activation's handheld cleanup")
	var/obj/item/medigun_backpack/cmo/C = allocate(/obj/item/medigun_backpack/cmo, test_floor())
	var/obj/item/bork_medigun/linked/G = C.get_medigun()
	TEST_ASSERT_EQUAL(G.medigun_base_unit, C, "post-parent medigun setup binds its exact base unit")
	TEST_ASSERT_EQUAL(G.beam_range, 4, "the one-handed subtype preserves its original beam range")
	TEST_ASSERT_EQUAL(G.icon_state, "medblaster_cmo", "the actual one-handed subtype retains its initial handheld state")
	TEST_ASSERT_EQUAL(G.wielded_item_state, "", "the one-handed subtype retains its empty wielded override")

/datum/unit_test/dq_init_items_phase_contracts/applied_tape
/datum/unit_test/dq_init_items_phase_contracts/applied_tape/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/machinery/door/airlock/D = allocate(/obj/machinery/door/airlock, T)
	var/obj/item/taperoll/engineering/applied/R = new(T)
	own(R)
	TEST_ASSERT(QDELETED(R), "the actual mapped applied roll is discarded after applying its tape")
	var/count = 0
	for(var/obj/item/tape/engineering/tape in T)
		own(tape)
		count++
	TEST_ASSERT_EQUAL(count, 1, "the real map initializer applies exactly one actual engineering tape over its door")
	TEST_ASSERT(!QDELETED(D), "initial tape application retains its original real door")
	var/obj/item/taperoll/engineering/applied/unplaced = new(null)
	own(unplaced)
	TEST_ASSERT(!QDELETED(unplaced), "an applied roll without a real turf retains the original early-return behavior")

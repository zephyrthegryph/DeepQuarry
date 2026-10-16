// Constructor ordering and lifetime for the residual nine-row cohort.
/obj/item/reagent_containers/powder/dq_init_remaining_probe
	var/appearance_calls = 0
	var/saw_reagents = FALSE

/obj/item/reagent_containers/powder/dq_init_remaining_probe/get_appearance()
	appearance_calls++
	saw_reagents = !isnull(reagents)
	return ..()

/obj/machinery/door/blast/dq_init_mercenary_match
	id = "smindicate"

/datum/unit_test/dq_init_objects_remaining

/datum/unit_test/dq_init_objects_remaining/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/flamethrower/full/F = allocate(/obj/item/flamethrower/full)
	var/obj/item/flamethrower/plain = allocate(/obj/item/flamethrower)
	TEST_ASSERT(F.status && !plain.status, "only the full variant secures its completed assembly")
	TEST_ASSERT(F.igniter && !F.igniter.secured, "the full assembly retains its actual unsecured starting igniter")
	var/obj/item/assembly/igniter/I = F.igniter
	qdel(F)
	TEST_ASSERT(QDELETED(I), "the full assembly still owns and deletes its igniter")
	var/obj/item/melee/shock_maul/M = allocate(/obj/item/melee/shock_maul)
	TEST_ASSERT_EQUAL(combat_of(M).force, M.force_unwielded, "the actual maul constructor applies unwielded combat force")
	TEST_ASSERT_EQUAL(M.launch_force, M.launch_force_unwielded, "the actual maul constructor applies unwielded launch strength")
	TEST_ASSERT_EQUAL(M.weaken_force, M.weaken_force_unwielded, "the actual maul constructor applies unwielded weakening")
	var/obj/item/reagent_containers/powder/dq_init_remaining_probe/P = allocate(/obj/item/reagent_containers/powder/dq_init_remaining_probe)
	TEST_ASSERT_EQUAL(P.appearance_calls, 1, "powder appearance is initialized exactly once")
	TEST_ASSERT(P.saw_reagents, "powder appearance runs after the real reagent holder materializes")
	var/obj/item/tank/phoron/pressurized/T = allocate(/obj/item/tank/phoron/pressurized)
	TEST_ASSERT_EQUAL(T.icon_scale_x, 0.8, "the fuel can retains its horizontal scale")
	TEST_ASSERT_EQUAL(T.icon_scale_y, 0.8, "the fuel can retains its vertical scale")
	TEST_ASSERT(T.air_contents.return_pressure() > 0, "the fuel can still initializes its actual gas before returning")

/datum/unit_test/dq_init_objects_remaining/sprayers

/datum/unit_test/dq_init_objects_remaining/sprayers/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/grenade/confetti/C = allocate(/obj/item/grenade/confetti)
	var/obj/item/grenade/smokebomb/S = allocate(/obj/item/grenade/smokebomb)
	var/obj/item/grenade/smokebomb/primed/P = allocate(/obj/item/grenade/smokebomb/primed)
	TEST_ASSERT_EQUAL(C.confetti_spread.holder, C, "confetti's real starting sprayer attaches to its grenade")
	TEST_ASSERT_EQUAL(S.smoke.holder, S, "smoke's real starting sprayer attaches to its grenade")
	TEST_ASSERT_EQUAL(P.smoke.holder, P, "the primed variant attaches its inherited sprayer")
	TEST_ASSERT(!S.active && P.active, "only the primed constructor activates its fuse")
	TEST_ASSERT_EQUAL(P.icon_state, "[initial(P.icon_state)]_active", "activation keeps its actual active appearance")
	var/datum/effect/effect/system/confetti_spread/CS = C.confetti_spread
	var/datum/effect/effect/system/smoke_spread/bad/SS = S.smoke
	qdel(C)
	qdel(S)
	qdel(P)
	TEST_ASSERT(QDELETED(CS) && QDELETED(SS), "both grenades retain ownership of their attached sprayers")

/datum/unit_test/dq_init_objects_remaining/mercenary

/datum/unit_test/dq_init_objects_remaining/mercenary/Run()
	dq_init_objects_fixture_scope()
	var/obj/machinery/door/blast/dq_init_mercenary_match/D = allocate(/obj/machinery/door/blast/dq_init_mercenary_match, run_loc_floor_bottom_left)
	var/obj/machinery/door/blast/other = allocate(/obj/machinery/door/blast, run_loc_floor_bottom_left)
	var/obj/item/commcard/mercenary/C = allocate(/obj/item/commcard/mercenary)
	var/list/doors = C.internal_data["shuttle_doors"]
	TEST_ASSERT(D in doors, "the actual constructor resolves an existing matching blast door")
	TEST_ASSERT(!(other in doors), "the actual constructor excludes nonmatching blast doors")
	TEST_ASSERT_EQUAL(C.internal_data["shuttle_door_code"], "smindicate", "the existing cartridge policy survives setup")

/datum/unit_test/dq_init_objects_remaining/map_laws

/datum/unit_test/dq_init_objects_remaining/map_laws/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/aiModule/reset/A = allocate(/obj/item/aiModule/reset)
	var/obj/item/aiModule/reset/B = allocate(/obj/item/aiModule/reset)
	TEST_ASSERT(A.laws && A.laws.type == using_map.default_law_type, "reset modules create the map's actual law type")
	TEST_ASSERT(B.laws && A.laws != B.laws, "each reset module owns its own mutable law datum")
	TEST_ASSERT_EQUAL(owner_of(A.laws), A, "the map-law factory uses native ownership")
	var/datum/ai_laws/L = A.laws
	qdel(A)
	TEST_ASSERT(QDELETED(L), "deleting the module deletes its actual map-law set")
	TEST_ASSERT(!QDELETED(B.laws), "deleting another module leaves an independent law set alive")

// Restore diagnostic counters changed by real constructor/draw/cleanup work.
/datum/unit_test/proc/dq_init_objects_fixture_scope()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)

/datum/unit_test/dq_init_objects_weapon_links
/datum/unit_test/dq_init_objects_weapon_links/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/weldpack/P = allocate(/obj/item/weldpack, test_floor())
	var/obj/item/weldingtool/tubefed/N = P.nozzle
	TEST_ASSERT(istype(N), "The declared pack starts with its real tube-fed nozzle")
	TEST_ASSERT_EQUAL(N.mounted_pack, P, "The nozzle setup links its actual pack before construction returns")
	TEST_ASSERT_EQUAL(N.loc, P, "Link setup does not move the nozzle out of the pack")
	var/obj/item/weldingtool/tubefed/invalid = new(test_floor())
	TEST_ASSERT(QDELETED(invalid), "A tube-fed nozzle without its pack is still rejected")
	var/obj/item/mecha_parts/mecha_equipment/E = allocate(/obj/item/mecha_parts/mecha_equipment, test_floor())
	var/obj/item/weldingtool/electric/mounted/exosuit/W = allocate(/obj/item/weldingtool/electric/mounted/exosuit, E)
	TEST_ASSERT_EQUAL(W.equip_mount(), E, "The mounted welder links the actual equipment during setup")
	var/obj/item/weldingtool/electric/mounted/exosuit/unmounted = allocate(/obj/item/weldingtool/electric/mounted/exosuit, test_floor())
	TEST_ASSERT_NULL(unmounted.equip_mount(), "An unmounted welder does not acquire an unrelated equipment link")
	qdel(W)
	qdel(E)
	qdel(P)
	TEST_ASSERT(QDELETED(N), "The pack retains ownership of its nozzle")

/datum/unit_test/dq_init_objects_primed_cluster
/datum/unit_test/dq_init_objects_primed_cluster/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/grenade/flashbang/clusterbang/primed/G = allocate(/obj/item/grenade/flashbang/clusterbang/primed, test_floor())
	TEST_ASSERT_EQUAL(G.active, TRUE, "The primed cluster is active as soon as construction returns")
	TEST_ASSERT_EQUAL(G.icon_state, "[initial(G.icon_state)]_active", "Activation still sets the armed appearance")
	qdel(G)

/datum/unit_test/dq_init_objects_c4_pair
/datum/unit_test/dq_init_objects_c4_pair/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/item/syndie/c4explosive/B = allocate(/obj/item/syndie/c4explosive, T)
	var/obj/item/flame/lighter/zippo/c4detonator/D
	for(var/obj/item/flame/lighter/zippo/c4detonator/candidate in T)
		if(candidate.bomb() == B)
			TEST_ASSERT_NULL(D, "Setup creates exactly one matching detonator")
			D = candidate
	TEST_ASSERT(D, "The charge creates a real sibling detonator before construction returns")
	var/list/engraving = splittext(D.desc, " You see ")
	TEST_ASSERT(length(engraving) >= 2, "The detonator has its generated engraving")
	var/code = copytext(engraving[length(engraving)], 1, 7)
	TEST_ASSERT_EQUAL(length(code), 6, "The paired code retains six characters")
	TEST_ASSERT(findtext(B.desc, "[code] engraved"), "Charge and detonator carry the same generated code")
	qdel(B)
	TEST_ASSERT(!QDELETED(D), "The sibling detonator is linked rather than owned by the charge")
	TEST_ASSERT_NULL(D.bomb(), "Deleting the charge clears the detonator reference")
	qdel(D)

/datum/unit_test/dq_init_objects_material_dish
/datum/unit_test/dq_init_objects_material_dish/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/material/ashtray/A = allocate(/obj/item/material/ashtray, test_floor())
	TEST_ASSERT(A.material, "The parent material exists before dish setup")
	TEST_ASSERT_EQUAL(A.max_butts, round(A.material.hardness / 5), "The dish capacity still follows actual material hardness")
	TEST_ASSERT_EQUAL(A.icon_state, "blank", "Material overlays replace the underlying icon state")
	TEST_ASSERT_NULL(A.color, "Material-specific overlay coloring clears the holder tint")
	TEST_ASSERT(A.base_overlay, "The material dish overlay exists before construction returns")
	TEST_ASSERT_EQUAL(A.butts, 0, "A new empty dish reports no contents")

/datum/unit_test/dq_init_objects_jetpack_trail
/datum/unit_test/dq_init_objects_jetpack_trail/Run()
	dq_init_objects_fixture_scope()
	var/turf/T = test_floor()
	var/obj/item/tank/jetpack/J = allocate(/obj/item/tank/jetpack, T)
	var/datum/effect/effect/system/ion_trail_follow/trail = J.ion_trail
	TEST_ASSERT(trail, "The declared jetpack child exists before construction returns")
	TEST_ASSERT_EQUAL(trail.holder, J, "The native trail constructor attaches to the exact jetpack")
	TEST_ASSERT_EQUAL(trail.oldposition(), T, "The trail records the jetpack's actual initial turf")
	TEST_ASSERT_EQUAL(trail.on, TRUE, "Removing redundant setup preserves the original trail flag")
	TEST_ASSERT_EQUAL(trail.processing, TRUE, "Removing redundant setup preserves the original processing flag")
	TEST_ASSERT(!J.on, "Attaching the trail does not turn the jetpack on")
	qdel(J)
	TEST_ASSERT(QDELETED(trail), "The jetpack still owns and deletes its declared trail")

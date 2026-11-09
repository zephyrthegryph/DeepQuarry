// A wall-mounted light fixture sits behind the mobs that stand on or over its tile: its picture and its glow are on the mob plane at a layer
// under MOB_LAYER, whichever wall it hangs on, so a large mob reaching over it covers it. Only an overhead lamp (a lamp post, fairy lights, a
// tall floor lamp) draws over mobs, and it says so by its plane or layer.

/// A fixture made facing `facing` as a map load makes one (the facing is known to its init), deleted when the test is over.
/datum/unit_test/proc/wall_fixture_made(type, turf/T, facing)
	var/obj/machinery/light/L = make(type, at = T, dir = facing)
	TEST_ASSERT(!isnull(L), "[type] was made")
	return own(L)

/// Wall fixtures of every facing, and the wall torch and neon signs, draw under a mob's layer on a plane no higher than the mob plane.
/datum/unit_test/dq_wall_fixture_under_mobs

/datum/unit_test/dq_wall_fixture_under_mobs/Run()
	var/turf/T = test_floor()
	for(var/facing in list(NORTH, SOUTH, EAST, WEST))
		var/obj/machinery/light/L = wall_fixture_made(/obj/machinery/light, T, facing)
		TEST_ASSERT(L.plane <= MOB_PLANE, "a [dir2text(facing)]-facing tube light is not on a plane above the mobs")
		TEST_ASSERT(L.plane < MOB_PLANE || L.layer < MOB_LAYER, "a [dir2text(facing)]-facing tube light draws under a mob's layer on the mob plane (layer [L.layer])")
	for(var/type in list(/obj/machinery/light/small, /obj/machinery/light/small/torch, /obj/machinery/light/small/neon, /obj/machinery/light/small/neon/generic_green))
		var/obj/machinery/light/L = wall_fixture_made(type, T, SOUTH)
		TEST_ASSERT(L.plane <= MOB_PLANE, "[type] is not on a plane above the mobs")
		TEST_ASSERT(L.plane < MOB_PLANE || L.layer < MOB_LAYER, "[type] draws under a mob's layer on the mob plane (layer [L.layer])")

/// A human standing in the fixture's tile draws over the fixture: same plane or a higher one, and a higher layer.
/datum/unit_test/dq_wall_fixture_mob_covers_it

/datum/unit_test/dq_wall_fixture_mob_covers_it/Run()
	var/turf/T = test_floor()
	var/obj/machinery/light/L = wall_fixture_made(/obj/machinery/light, T, SOUTH)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(H.plane > L.plane || (H.plane == L.plane && H.layer > L.layer), "the mob (plane [H.plane], layer [H.layer]) is drawn over the south-facing fixture (plane [L.plane], layer [L.layer])")

/// A wall fixture's lit glow is not on the lighting-above plane (nothing on the mob plane could cover it there): it is the tinted image on the
/// fixture's own plane plus an emissive copy. An overhead lamp keeps its glow above the mobs.
/datum/unit_test/dq_wall_fixture_glow_plane

/datum/unit_test/dq_wall_fixture_glow_plane/Run()
	var/turf/T = test_floor()
	var/obj/machinery/light/wall = wall_fixture_made(/obj/machinery/light, T, SOUTH)
	var/image/glow = wall.light_overlay()
	TEST_ASSERT(glow.plane != PLANE_LIGHTING_ABOVE, "a wall fixture's glow image is not on the lighting-above plane, over the mobs")
	var/mutable_appearance/emissive = wall.light_emissive()
	TEST_ASSERT_EQUAL(emissive.plane, PLANE_EMISSIVE, "and its dark-piercing copy is emissive, so a mob's emissive blocker in front of it stops it")
	var/obj/machinery/light/lamp = allocate(/obj/machinery/light/lamppost, T)
	TEST_ASSERT_EQUAL(lamp.light_overlay().plane, PLANE_LIGHTING_ABOVE, "an overhead lamp keeps its glow above the mobs")
	TEST_ASSERT(lamp.plane >= ABOVE_MOB_PLANE, "and its body is on the plane above the mobs")

// Turf damage on the packet and integrity (doc/rewrite/damage.md §5, D-turf).
// Floors keep their condition as integrity: below the failure fraction the
// tile breaks, at zero it is torn up; explosions reach every turf through
// /turf/ex_act() -> receive_explosion().

/datum/unit_test/dq_turf_floor_integrity

/datum/unit_test/dq_turf_floor_integrity/Run()
	var/turf/start = test_floor()
	var/turf/T = get_step(start, NORTH) || start
	var/original_type = T.type
	var/turf/simulated/floor/F = T.ChangeTurf(/turf/simulated/floor/tiled)
	TEST_ASSERT(istype(F), "ChangeTurf to a tiled floor produced [F?.type]")
	TEST_ASSERT(F.uses_integrity, "floors use integrity")
	TEST_ASSERT_EQUAL(F.get_integrity(), F.max_integrity, "a fresh floor starts intact")

	// A blast packet below the failure fraction breaks the tile.
	F.deal_damage(DAMAGE_BLAST, F.max_integrity * 0.6, flags = DAMAGE_PACKET_SILENT | DAMAGE_PACKET_UNARMORED)
	TEST_ASSERT(F.get_integrity() <= F.max_integrity * F.integrity_failure, "integrity [F.get_integrity()] should be at or below the failure fraction")
	if(F.flooring && (F.flooring.flags & TURF_CAN_BREAK))
		TEST_ASSERT(!isnull(F.broken), "crossing the failure fraction breaks the tile")

	// Destroying the tile tears it up to plating with a fresh condition.
	F.deal_damage(DAMAGE_BLAST, F.max_integrity, flags = DAMAGE_PACKET_SILENT | DAMAGE_PACKET_UNARMORED)
	var/turf/simulated/floor/after = locate(F.x, F.y, F.z)
	if(istype(after))
		TEST_ASSERT(after.is_plating() || after.type != /turf/simulated/floor/tiled, "a destroyed tile leaves plating")
		// New flooring restores the condition.
		after.install_flooring(get_flooring_data(/datum/decl/flooring/tiling))
		TEST_ASSERT_EQUAL(after.get_integrity(), after.max_integrity, "laying a tile restores integrity")

	var/turf/restore = locate(F.x, F.y, F.z)
	restore.ChangeTurf(original_type)

/datum/unit_test/dq_turf_bomb_proof

/datum/unit_test/dq_turf_bomb_proof/Run()
	var/turf/start = test_floor()
	var/turf/T = get_step(start, NORTH) || start
	var/original_type = T.type
	var/turf/lava = T.ChangeTurf(/turf/simulated/floor/lava)
	TEST_ASSERT_EQUAL(lava.ex_act(1), 0, "bomb-proof turfs ignore the blast")
	TEST_ASSERT(istype(locate(lava.x, lava.y, lava.z), /turf/simulated/floor/lava), "lava survives an epicentre blast")
	var/turf/restore = locate(lava.x, lava.y, lava.z)
	restore.ChangeTurf(original_type)

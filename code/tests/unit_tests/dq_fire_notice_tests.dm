// fire_act() overrides are atom_fire_act notice reactions (a simulated turf scorches that way).

// fire_act() overrides are atom_fire_act notice reactions (a simulated turf scorches that way).
/datum/unit_test/dq_fire_notice_wanted_by_simulated_turf

/datum/unit_test/dq_fire_notice_wanted_by_simulated_turf/Run()
	var/turf/simulated/T = dq_containment_floor()
	TEST_ASSERT(notice_wanted(T, /datum/notice/atom_fire_act, ACT_COMMITTED), "a simulated turf listens for flame contact")

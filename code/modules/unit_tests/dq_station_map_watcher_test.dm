/// A holomap watcher is a single relationship whose movement and teardown
/// retire the same observation and restore idle power use.
/datum/unit_test/dq_station_map_watcher_lifecycle
	needs_test_block = FALSE

/datum/unit_test/dq_station_map_watcher_lifecycle/Run()
	var/turf/floor = test_floor()
	var/obj/machinery/station_map/station_map = allocate(/obj/machinery/station_map, floor)
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, floor)
	TEST_ASSERT(om_link(station_map, /datum/object_model/relation/station_map_watcher, first), "the holomap should accept a watcher")
	TEST_ASSERT_EQUAL(station_map.watching_mob, first, "the watcher mirror should follow the edge")
	TEST_ASSERT_EQUAL(station_map.use_power, USE_POWER_ACTIVE, "watching should use active power")
	first.dir = GLOB.reverse_dir[station_map.dir]
	SEND_SIGNAL(first, COMSIG_MOVABLE_ATTEMPTED_MOVE, floor, floor)
	TEST_ASSERT_NULL(station_map.watching_mob, "turning away should stop watching")
	TEST_ASSERT_NULL(om_first_linked(station_map, /datum/object_model/relation/station_map_watcher), "movement should remove the watcher edge")
	TEST_ASSERT_EQUAL(station_map.use_power, USE_POWER_IDLE, "stopping should restore idle power")
	TEST_ASSERT(om_link(station_map, /datum/object_model/relation/station_map_watcher, first), "the first watcher should reconnect")
	SEND_SIGNAL(first, COMSIG_MOB_LOGOUT)
	TEST_ASSERT_NULL(station_map.watching_mob, "logout should release the map for another watcher")
	TEST_ASSERT_EQUAL(station_map.use_power, USE_POWER_IDLE, "logout should restore idle power")
	TEST_ASSERT(om_link(station_map, /datum/object_model/relation/station_map_watcher, first), "the watcher should reconnect after logout")
	qdel(first)
	TEST_ASSERT_NULL(station_map.watching_mob, "destroying the watcher should clear the mirror")
	TEST_ASSERT_EQUAL(station_map.use_power, USE_POWER_IDLE, "destroying the watcher should restore idle power")
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, floor)
	TEST_ASSERT(om_link(station_map, /datum/object_model/relation/station_map_watcher, second), "the holomap should accept a replacement watcher")
	qdel(station_map)
	TEST_ASSERT_NULL(om_first_linked_to(second, /datum/object_model/relation/station_map_watcher), "destroying the holomap should remove its watcher edge")

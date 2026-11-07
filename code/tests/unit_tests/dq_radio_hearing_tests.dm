// Who hears a radio broadcast (radio_hearers()): a listener on a turf a receiving radio reaches, worked out from the listeners.

/// An intercom reaches its canhear_range with the square's corners cut; a headset only its own turf; another level never;
/// an observer always.
/datum/unit_test/dq_radio_hearers_by_reach

/datum/unit_test/dq_radio_hearers_by_reach/Run()
	var/turf/origin = test_floor()
	var/obj/item/radio/intercom/I = allocate(/obj/item/radio/intercom, origin)
	var/range = I.canhear_range
	var/turf/edge = locate(origin.x + range, origin.y, origin.z)
	var/turf/beyond = locate(origin.x + range + 1, origin.y, origin.z)
	var/turf/corner = locate(origin.x + range, origin.y + range, origin.z)
	TEST_ASSERT(edge && beyond && corner, "the test floor has room round it")
	var/mob/living/carbon/human/at_edge = allocate(/mob/living/carbon/human, edge)
	var/mob/living/carbon/human/too_far = allocate(/mob/living/carbon/human, beyond)
	var/mob/living/carbon/human/in_corner = allocate(/mob/living/carbon/human, corner)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, beyond)
	var/list/heard = radio_hearers(list(I), list(at_edge, too_far, in_corner, ghost))
	TEST_ASSERT(at_edge in heard, "a listener at the intercom's range hears it")
	TEST_ASSERT(!(too_far in heard), "one a turf further does not")
	TEST_ASSERT(!(in_corner in heard), "nor one in the corner of the square, outside the circle")
	TEST_ASSERT(ghost in heard, "an observer hears every broadcast")

	var/obj/item/radio/headset/worn = allocate(/obj/item/radio/headset, edge)
	worn.forceMove(at_edge) // carried by its wearer
	heard = radio_hearers(list(worn), list(at_edge, too_far))
	TEST_ASSERT(at_edge in heard, "the wearer hears a headset")
	TEST_ASSERT(!(too_far in heard), "the next turf does not")

	var/turf/elsewhere = locate(origin.x, origin.y, origin.z == 1 ? 2 : 1)
	if(elsewhere)
		var/mob/living/carbon/human/other_level = allocate(/mob/living/carbon/human, elsewhere)
		TEST_ASSERT(!(other_level in radio_hearers(list(I), list(other_level))), "a radio on another level is not heard")

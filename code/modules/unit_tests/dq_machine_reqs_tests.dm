// The machine library's actor requirements (code/library/machine/machine.dm): req_on_holder_turf() and req_held_releasable().

/// req_on_holder_turf(): only an actor standing on the holder's own turf.
/datum/unit_test/dq_machine_req_on_holder_turf/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/beside = locate(T.x + 1, T.y, T.z)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/station_map/holder = allocate(/obj/machinery/station_map, T)
	var/datum/act/op/A = take(/datum/act/op)
	A.actor = H
	A.holder = holder
	A.target = holder
	var/datum/entry/part/req/on_holder_turf/R = req_on_holder_turf()
	TEST_ASSERT(R.holds(A), "on the holder's turf: holds")
	H.forceMove(beside)
	TEST_ASSERT(!R.holds(A), "beside it: refused")
	var/list/keys = R.read_keys(A)
	TEST_ASSERT_EQUAL(length(keys), 2, "it follows both the actor's and the holder's moves")
	A.release()

/// req_held_releasable(): the held item can leave the hand; a stuck one is refused with the release refusal as the reason.
/datum/unit_test/dq_machine_req_held_releasable/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/item = allocate(/obj/item/paper, T)
	var/datum/act/op/A = take(/datum/act/op)
	A.actor = H
	A.held = item
	var/datum/entry/part/req/held_releasable/R = req_held_releasable()
	TEST_ASSERT(R.holds(A), "loose on the floor: releasable")
	TEST_ASSERT(H.put_in_active_hand(item), "picked up")
	TEST_ASSERT(R.holds(A), "in hand: releasable")
	add_trait(item, TRAIT_NODROP, "dq_machine_req_held_releasable")
	TEST_ASSERT(!R.holds(A), "stuck to the hand: refused")
	TEST_ASSERT(!isnull(R.refusal(A)), "the refusal says why")
	remove_trait(item, TRAIT_NODROP, "dq_machine_req_held_releasable")
	TEST_ASSERT(R.holds(A), "unstuck: releasable again")
	A.release()

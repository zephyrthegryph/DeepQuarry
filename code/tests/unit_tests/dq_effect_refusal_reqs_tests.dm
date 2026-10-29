// Refusals that effects used to make at run time, moved into the ops' requirements (sys dx_review: effect_refusal).

/// A full syringe fails its draw requirement (held again at commit after the take_blood wait); an empty one passes it.
/datum/unit_test/dq_effect_refusal_full_syringe/Run()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe, run_loc_floor_bottom_left)
	var/datum/capability/lib/needle/needle = cap_of(S, CAP_NEEDLE)
	TEST_ASSERT_NOTNULL(needle, "setup: the syringe is a needle")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = S
	TEST_ASSERT_NULL(needle.room_for_blood(A), "an empty syringe has room to draw")
	S.reagents.add_reagent(REAGENT_ID_WATER, S.reagents.maximum_volume)
	TEST_ASSERT_EQUAL(needle.room_for_blood(A), /datum/msg/needle/full, "a full syringe is refused before the draw")
	A.holder = null
	A.release()

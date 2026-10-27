// %LIMB% (the target's limb the user aims at) and the thick-hide rolls it words (the injector's and the needle's chance()).

/// %LIMB% names the limb the user aims at on a human target, and reads empty when there is none.
/datum/unit_test/dq_msg_limb_token/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	dq_give_zone_sel(user)
	hud_of(user).zone_sel.set_selecting(BP_L_ARM)
	var/obj/item/organ/external/arm = target.get_organ(BP_L_ARM)
	TEST_ASSERT_NOTNULL(arm, "setup: the target has a left arm")
	TEST_ASSERT_EQUAL(msg_fill("into %LIMB%", user, target), "into \the [arm]", "the aimed limb is named")
	TEST_ASSERT_EQUAL(msg_fill("%LIMB% holds", user, target), "\The [arm] holds", "capitalised at the start of a line")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT_EQUAL(msg_fill("into %LIMB%", user, pen), "into ", "a target that is not a human has no limb")

/// Without a thick hide the needle always goes in: the roll's chance is 100 and no hold chance exists.
/datum/unit_test/dq_thick_hide_roll_chance/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	dq_give_zone_sel(user)
	TEST_ASSERT_EQUAL(target.thick_skin_hold_chance(target.get_organ(BP_TORSO)), 0, "an ordinary hide never holds")
	var/obj/item/reagent_containers/hypospray/autoinjector/injector = allocate(/obj/item/reagent_containers/hypospray/autoinjector, T)
	var/datum/capability/lib/injector/cap = cap_of(injector, CAP_INJECTOR)
	TEST_ASSERT_NOTNULL(cap, "setup: the autoinjector is an injector")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = injector
	A.target = target
	A.actor = user
	TEST_ASSERT_EQUAL(cap.needle_gets_through(A), 100, "the injection's roll always succeeds through an ordinary hide")
	A.holder = null
	A.target = null
	A.actor = null
	A.release()

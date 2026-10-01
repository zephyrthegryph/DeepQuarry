// cap_smokable() (code/datums/capabilities/library/smokable.dm).

/obj/item/dq_cap_fixture/cig
	icon_state = "cig"

/obj/item/dq_cap_fixture/cig/capabilities()
	. = ..()
	. += cap_smokable(burn_time = 20 SECONDS, drag = 2, butt = /obj/item/trash/cigbutt, lit_state = "cig_on", burnt_state = "cig_burnt")

/obj/item/dq_cap_fixture/cig/Initialize(mapload)
	. = ..()
	create_reagents(10)
	reagents.add_reagent(REAGENT_ID_SUGAR, 10)

/// No butt: it stays as a burnt husk.
/obj/item/dq_cap_fixture/pipe/capabilities()
	. = ..()
	. += cap_smokable(burn_time = 10 SECONDS)

/datum/unit_test/dx_cap_smokable

/datum/unit_test/dx_cap_smokable/Run()
	var/turf/T = test_floor()
	var/obj/item/dq_cap_fixture/cig/F = allocate(/obj/item/dq_cap_fixture/cig, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/flame/match/match = allocate(/obj/item/flame/match, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)

	var/datum/interaction/capability/light = dx_cap_entry(F, "Light")
	var/datum/interaction/capability/drag = dx_cap_entry(F, "Take a drag")
	var/datum/interaction/capability/snuff = dx_cap_entry(F, "Put out")
	TEST_ASSERT_NOTNULL(light, "the Light entry")
	TEST_ASSERT(light.is_meant(H, F, match), "a match selects Light")
	TEST_ASSERT(!light.is_meant(H, F, pen), "a pen doesn't")
	TEST_ASSERT_EQUAL(drag.entry, INTERACTION_ENTRY_SELF, "using it in hand takes a drag")
	TEST_ASSERT_EQUAL(light.why_not(H, F, match), "\the [match] isn't lit", "an unlit match can't light it")
	TEST_ASSERT_EQUAL(drag.why_not(H, F, F), "it isn't lit", "no drag while unlit")
	TEST_ASSERT_EQUAL(snuff.why_not(H, F, null), "it isn't lit", "nothing to put out")
	TEST_ASSERT(("It is still fresh." in caps_examine(F, H)), "examine: fresh")

	match.light()
	light.perform(H, F, match)
	TEST_ASSERT(cap_has(F, CAP_LIT), "lit")
	TEST_ASSERT(("It's lit." in caps_examine(F, H)), "examine says it's lit")
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "cig_on", "draw shows the lit state")
	TEST_ASSERT_EQUAL(light.why_not(H, F, match), "it's already lit", "no lighting it twice")

	drag.perform(H, F, F)
	TEST_ASSERT_EQUAL(F.reagents.total_volume, 8, "a drag draws `drag` units")
	TEST_ASSERT(H.ingested.get_reagent_amount(REAGENT_ID_SUGAR) > 0, "into the smoker")
	TEST_ASSERT_EQUAL(cap_smokable_burn_left(F), 16 SECONDS, "and burns that much faster")

	cap_smokable_puff(F)
	TEST_ASSERT_EQUAL(cap_smokable_burn_left(F), 14 SECONDS, "a puff burns two seconds")
	TEST_ASSERT(F.reagents.total_volume < 8, "not worn: a little burns away")

	snuff.perform(H, F, null)
	TEST_ASSERT(!cap_has(F, CAP_LIT), "put out")
	refresh_flush()
	TEST_ASSERT_EQUAL(F.icon_state, "cig_burnt", "draw shows the part-burnt state")
	cap_smokable_puff(F)
	TEST_ASSERT_EQUAL(cap_smokable_burn_left(F), 14 SECONDS, "an unlit one doesn't burn")

	light.perform(H, F, match)
	TEST_ASSERT(cap_has(F, CAP_LIT), "relit")
	cap_smokable_burn(F, 1 MINUTES)
	TEST_ASSERT(QDELETED(F), "burnt out, it is gone")
	var/obj/item/trash/cigbutt/butt = locate() in T
	TEST_ASSERT_NOTNULL(butt, "leaving its butt")
	qdel(butt)

	var/obj/item/dq_cap_fixture/pipe/P = allocate(/obj/item/dq_cap_fixture/pipe, T)
	var/datum/interaction/capability/light_pipe = dx_cap_entry(P, "Light")
	light_pipe.perform(H, P, match)
	TEST_ASSERT(cap_has(P, CAP_LIT), "the pipe lit")
	cap_smokable_burn(P, 1 MINUTES)
	TEST_ASSERT(!QDELETED(P), "without a butt it stays")
	TEST_ASSERT(!cap_has(P, CAP_LIT), "out")
	TEST_ASSERT(("It is burnt out." in caps_examine(P, H)), "examine: burnt out")
	TEST_ASSERT_EQUAL(light_pipe.why_not(H, P, match), "it's burnt out", "nothing left to light")

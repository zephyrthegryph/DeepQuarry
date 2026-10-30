// The ratchet tail (untyped, escape_hatches): what the converted vars hold now.

/// A hand drawn from a deck names its deck by the deck's handle (ref_token()), so it mixes back into that deck only.
/datum/unit_test/dq_ratchet_tail_card_family

/datum/unit_test/dq_ratchet_tail_card_family/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/deck/cards/deck = allocate(/obj/item/deck/cards, T)
	var/obj/item/deck/cards/other = allocate(/obj/item/deck/cards, T)
	deck.deck_verb_draw(user)
	var/obj/item/hand/H = user.get_type_in_hands(/obj/item/hand)
	TEST_ASSERT_NOTNULL(H, "drawing puts a hand of cards in the user's hands")
	TEST_ASSERT_EQUAL(H.parentdeck, ref_token(deck), "the hand names its deck by the deck's handle")
	TEST_ASSERT_EQUAL(deck.can_draw(user, deck, null), TRUE, "the same deck draws into that hand again")
	TEST_ASSERT(istext(other.can_draw(user, other, null)), "another deck refuses to mix its cards into that hand")

/// A beam keeps the handle of the turf each end stood on, and redraws when an end moves to another turf.
/datum/unit_test/dq_ratchet_tail_beam_handles

/datum/unit_test/dq_ratchet_tail_beam_handles/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/east = get_step(T, EAST)
	var/obj/item/pen/origin = allocate(/obj/item/pen, T)
	var/obj/item/pen/target = allocate(/obj/item/pen, east)
	var/datum/beam/beam = allocate(/datum/beam, origin, target, 'icons/effects/beam.dmi', "b_beam", 1 MINUTE, 10, /obj/effect/ebeam, 1 SECOND)
	TEST_ASSERT_EQUAL(beam.origin_oldloc, ref_token(T), "the origin's turf is kept as its handle")
	TEST_ASSERT_EQUAL(beam.target_oldloc, ref_token(east), "the target's turf is kept as its handle")
	TEST_ASSERT(!beam.static_beam, "a beam between two movables is not static")
	beam.Start()
	var/turf/further = get_step(east, NORTH)
	target.forceMove(further)
	beam.beam_tick()
	TEST_ASSERT_EQUAL(beam.target_oldloc, ref_token(further), "an end that moved is redrawn from its new turf")
	TEST_ASSERT_EQUAL(beam.origin_oldloc, ref_token(T), "an end that stayed keeps its turf")
	beam.End()
	beam.beam_tick()

/// A health implant reads the body it sits in, whether it was implanted (imp_in) or made inside it by the cloning computer.
/datum/unit_test/dq_ratchet_tail_health_implant

/datum/unit_test/dq_ratchet_tail_health_implant/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/implant/health/imp = allocate(/obj/item/implant/health, H)
	TEST_ASSERT_EQUAL(imp.sensehealth(), "ERROR", "an implant that was never implanted reads nothing")
	imp.implanted = TRUE // what the cloning computer sets on the one it makes inside the body
	TEST_ASSERT_NOTEQUAL(imp.sensehealth(), "ERROR", "an implanted health implant reads its host")

/// The painting lateload takes its admin as an argument (or the admin whose proc call is running), never usr.
/datum/unit_test/dq_ratchet_tail_painting_admin

/datum/unit_test/dq_ratchet_tail_painting_admin/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/structure/sign/painting/P = allocate(/obj/structure/sign/painting, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(P.admin_lateload_painting(0, 0), 0, "with no admin given and no admin proc call running, nothing is asked")
	TEST_ASSERT_EQUAL(P.admin_lateload_painting(0, 0, H), 0, "a mob with no admin holder is refused")

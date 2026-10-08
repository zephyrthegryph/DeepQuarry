// The emag capability (code/datums/capabilities/library/emag.dm).

/obj/cap_fixture/emag
	var/effects = 0
	var/mob/last_user

/obj/cap_fixture/emag/capabilities()
	. = ..()
	. += cap_emag(say = "You short out %T%.", effect = PROC_REF(on_emag), already_say = "It is fried already.")

/obj/cap_fixture/emag/proc/on_emag(mob/user, obj/item/card/emag/card)
	effects++
	last_user = user

/obj/cap_fixture/emag/on_destroy(force)
	last_user = null
	..()

/obj/cap_fixture/emag_repeatable/capabilities()
	. = ..()
	. += cap_emag(mode = EMAG_REPEATABLE)

/// An emag sets the bit, runs the effect and spends a use; EMAG_ONCE refuses a second swipe.
/datum/unit_test/dx_cap_emag_once/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/emag/A = allocate(/obj/cap_fixture/emag, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/datum/interaction/capability/entry = cap_test_entry(A, "emag")
	TEST_ASSERT_NOTNULL(entry, "an emag entry")
	TEST_ASSERT_EQUAL(entry.log, LOG_ADMIN, "logged to admins by default")
	TEST_ASSERT(!entry.is_meant(H, A, null), "an empty hand is not meant")
	TEST_ASSERT(H.put_in_active_hand(card), "the human holds the card")
	var/uses = card.uses
	TEST_ASSERT(entry.perform(H, A, card), "the emag runs")
	TEST_ASSERT(is_emagged(A), "CAP_EMAGGED is set")
	TEST_ASSERT_EQUAL(A.effects, 1, "the effect ran once")
	TEST_ASSERT_EQUAL(A.last_user, H, "the effect got the user")
	TEST_ASSERT_EQUAL(card.uses, uses - 1, "one use was spent")
	var/result = cap_dispatch(new /datum/dispatch_context(H, A, card, entry))
	TEST_ASSERT_EQUAL(result, UI_REFUSED, "a second swipe is refused")
	TEST_ASSERT_EQUAL(A.effects, 1, "the effect did not run again")
	TEST_ASSERT_EQUAL(card.uses, uses - 1, "and no use was spent")
	refresh_flush()
	TEST_ASSERT(!length(A.rx?.look_overlays), "the emag draws nothing")

/// A spent card is refused; EMAG_REPEATABLE runs every time.
/datum/unit_test/dx_cap_emag_repeatable/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/emag_repeatable/A = allocate(/obj/cap_fixture/emag_repeatable, T)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, T)
	var/datum/interaction/capability/entry = cap_test_entry(A, "emag")
	TEST_ASSERT(H.put_in_active_hand(card), "the human holds the card")
	card.uses = 3
	TEST_ASSERT(entry.perform(H, A, card), "the first emag runs")
	TEST_ASSERT_NOTEQUAL(cap_dispatch(new /datum/dispatch_context(H, A, card, entry)), UI_REFUSED, "a repeatable emag runs again")
	TEST_ASSERT_EQUAL(card.uses, 1, "each swipe spent a use")
	card.uses = 0
	TEST_ASSERT_EQUAL(cap_dispatch(new /datum/dispatch_context(H, A, card, entry)), UI_REFUSED, "a spent card is refused")

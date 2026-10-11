// Record against OLD production before applying native consent conversion.
/datum/unit_test/dq_vore_consent_order/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/pred = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	prey.devourable = FALSE
	prey.set_absorbed(TRUE)
	pred.set_absorbed(TRUE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_devour, pred, prey), "They aren't able to be devoured.", "Preference wins over both absorbed refusals")
	prey.devourable = TRUE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_devour, pred, prey), "They aren't in a state to be devoured.", "Prey absorbed refusal")
	prey.set_absorbed(FALSE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_devour, pred, prey), "They aren't in a state to be devoured.", "Predator absorbed refusal remains after prey recovers")
	pred.set_absorbed(FALSE)
	TEST_ASSERT_NULL(vore_consent_refusal(/datum/predicate/vore_devour, pred, prey), "Both recovered permit devour")
	prey.digestable = FALSE
	prey.set_absorbed(TRUE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_digest, pred, prey), "they don't allow digestion", "Digest preference wins over absorbed")
	prey.digestable = TRUE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_digest, pred, prey), "they are already absorbed", "Digest absorbed refusal after preference recovers")
	prey.set_absorbed(FALSE)
	TEST_ASSERT_NULL(vore_consent_refusal(/datum/predicate/vore_digest, pred, prey), "Digest recovery")
	prey.contaminate_pref = FALSE
	TEST_ASSERT_EQUAL(vore_consent_refusal(/datum/predicate/vore_affect_worn, pred, prey), "they don't allow their worn items to be affected", "Worn addon refusal")
	TEST_ASSERT(!vore_consents(/datum/predicate/vore_affect_worn, pred, prey), "Effect-domain boolean derives refusal")
	prey.contaminate_pref = TRUE
	TEST_ASSERT(vore_consents(/datum/predicate/vore_affect_worn, pred, prey), "Worn addon recovery")


// OLD coverage: real shared folder/closet definitions, no replacement fixture policies.
/datum/unit_test/dq_custom_native_slot_old/Run()
	var/turf/T = test_floor()
	// Allocate closets first so their map-time collection cannot consume later fixtures.
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	C.set_storage_capacity(1000)
	var/obj/item/folder/F = allocate(/obj/item/folder, T)
	var/mob/living/carbon/human/mover = allocate(/mob/living/carbon/human, T)
	for(var/path in list(/obj/item/paper, /obj/item/photo, /obj/item/paper_bundle))
		var/obj/item/I = allocate(path, T)
		TEST_ASSERT_NULL(dq_ledger_refusal(I, F, CONTAINER_SLOT_PAGES, mover), "Actual paperwork tag accepts each supported family")
		TEST_ASSERT(move_into(F, CONTAINER_SLOT_PAGES, I, mover), "Real paperwork insertion succeeds")
		TEST_ASSERT_EQUAL(I.loc, F, "Accepted object actually belongs to folder")
	var/obj/item/flashlight/rejected = allocate(/obj/item/flashlight, T)
	TEST_ASSERT_EQUAL(dq_ledger_refusal(rejected, F, CONTAINER_SLOT_PAGES, mover), "only paper, photos and bundles fit", "Exact folder refusal is preserved")
	TEST_ASSERT(!move_into(F, CONTAINER_SLOT_PAGES, rejected, mover), "Refused object is not inserted")
	TEST_ASSERT_EQUAL(rejected.loc, T, "Folder refusal preserves custody")
	var/obj/item/flashlight/bolted = allocate(/obj/item/flashlight, T)
	bolted.set_anchored(TRUE)
	TEST_ASSERT_EQUAL(dq_ledger_refusal(bolted, C, CONTAINER_SLOT_INTERIOR, mover), "it is fastened down", "Actual anchored candidate refuses with exact text")
	bolted.set_anchored(FALSE)
	TEST_ASSERT_NULL(dq_ledger_refusal(bolted, C, CONTAINER_SLOT_INTERIOR, mover), "Real anchor setter recovers admission")
	TEST_ASSERT(move_into(C, CONTAINER_SLOT_INTERIOR, bolted, mover), "Recovered candidate really enters closet")
	TEST_ASSERT_EQUAL(bolted.loc, C, "Closet acceptance has actual custody consequences")
	var/mob/living/carbon/human/passenger = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(passenger != mover, "The query uses a distinct real mover")
	passenger.set_pinned(list(rejected))
	TEST_ASSERT_EQUAL(dq_ledger_refusal(passenger, C, CONTAINER_SLOT_INTERIOR, mover), "it is fastened down", "Living candidate pins refuse independently of mover state")
	passenger.set_pinned(null)
	TEST_ASSERT_NULL(dq_ledger_refusal(passenger, C, CONTAINER_SLOT_INTERIOR, mover), "Real pinned setter recovers living admission")
	var/obj/effect/dummy/chameleon/D = allocate(/obj/effect/dummy/chameleon, T)
	D.set_anchored(TRUE)
	TEST_ASSERT_NULL(dq_ledger_refusal(D, C, CONTAINER_SLOT_INTERIOR, mover), "The actual chameleon exception remains admissible despite anchor")

// Pins what happens to linked things when either end of a relation is deleted, replaced or handed over, read through the typed
// accessors only (bs_tx_target(), throw_subject(), action_owner(), leash_pet(), ...), so the same assertions hold on the legacy
// om_link relations and on the declared relations that replace them (doc/rewrite/final_api.html section 6).

/// A bluespace radio transmits to one receiver; a receiver serves many radios. Deleting the receiver frees the radio, deleting the radio
/// frees the receiver's list, and linking a second receiver replaces the first.
/datum/unit_test/dq_rel_pin_bluespace_tx

/datum/unit_test/dq_rel_pin_bluespace_tx/Run()
	var/obj/machinery/telecomms/receiver/first = allocate(/obj/machinery/telecomms/receiver)
	var/obj/machinery/telecomms/receiver/second = allocate(/obj/machinery/telecomms/receiver)
	first.id = "pin_tx_first"
	second.id = "pin_tx_second"
	var/obj/item/radio/R = allocate(/obj/item/radio)
	R.bluespace_radio = TRUE
	R.bs_tx_preload_id = "pin_tx_first"
	R.radio_after_init(null)
	TEST_ASSERT_EQUAL(R.bs_tx_target(), first, "the radio should transmit to the receiver its id names")
	TEST_ASSERT(R in first.bs_tx_radios(), "the receiver should list the radio")
	R.bs_tx_preload_id = "pin_tx_second"
	R.radio_after_init(null)
	TEST_ASSERT_EQUAL(R.bs_tx_target(), second, "linking a second receiver should replace the first")
	TEST_ASSERT(!(R in first.bs_tx_radios()), "the replaced receiver should drop the radio")
	TEST_ASSERT(R in second.bs_tx_radios(), "the new receiver should list the radio")
	qdel(second)
	TEST_ASSERT_NULL(R.bs_tx_target(), "deleting the receiver should free the radio")
	R.bs_tx_preload_id = "pin_tx_first"
	R.radio_after_init(null)
	TEST_ASSERT_EQUAL(R.bs_tx_target(), first, "setup: relink to the first receiver")
	qdel(R)
	TEST_ASSERT(!length(first.bs_tx_radios()), "deleting the radio should empty the receiver's list")

/// A bluespace radio receives from one broadcaster; the broadcaster forces its output onto many radios.
/datum/unit_test/dq_rel_pin_bluespace_rx

/datum/unit_test/dq_rel_pin_bluespace_rx/Run()
	var/obj/machinery/telecomms/broadcaster/first = allocate(/obj/machinery/telecomms/broadcaster)
	var/obj/machinery/telecomms/broadcaster/second = allocate(/obj/machinery/telecomms/broadcaster)
	first.id = "pin_rx_first"
	second.id = "pin_rx_second"
	var/obj/item/radio/R = allocate(/obj/item/radio)
	R.bluespace_radio = TRUE
	R.bs_rx_preload_id = "pin_rx_first"
	R.radio_after_init(null)
	TEST_ASSERT_EQUAL(R.bs_rx_source(), first, "the radio should receive from the broadcaster its id names")
	TEST_ASSERT(R in first.bs_rx_radios(), "the broadcaster should list the radio")
	R.bs_rx_preload_id = "pin_rx_second"
	R.radio_after_init(null)
	TEST_ASSERT_EQUAL(R.bs_rx_source(), second, "linking a second broadcaster should replace the first")
	TEST_ASSERT(!(R in first.bs_rx_radios()), "the replaced broadcaster should drop the radio")
	qdel(second)
	TEST_ASSERT_NULL(R.bs_rx_source(), "deleting the broadcaster should free the radio")
	R.bs_rx_preload_id = "pin_rx_first"
	R.radio_after_init(null)
	qdel(R)
	TEST_ASSERT(!length(first.bs_rx_radios()), "deleting the radio should empty the broadcaster's list")

/// A throw in flight and the thing it carries: deleting the thing deletes the throw; deleting the throw clears the thing's `throwing`.
/datum/unit_test/dq_rel_pin_throw

/datum/unit_test/dq_rel_pin_throw/Run()
	var/turf/T = get_turf(run_loc_floor_bottom_left)
	var/turf/far = locate(T.x + 4, T.y, T.z)
	var/obj/item/I = allocate(/obj/item, T)
	TEST_ASSERT(I.throw_at(far, 5, 1), "setup: the throw should start")
	var/datum/thrownthing/TT = I.throwing
	TEST_ASSERT_NOTNULL(TT, "a thrown item should hold its throw")
	TEST_ASSERT_EQUAL(TT.throw_subject(), I, "the throw should carry the item")
	qdel(I)
	TEST_ASSERT(QDELETED(TT), "deleting the thrown item should delete its throw")
	var/obj/item/J = allocate(/obj/item, T)
	TEST_ASSERT(J.throw_at(far, 5, 1), "setup: the second throw should start")
	var/datum/thrownthing/TT2 = J.throwing
	TEST_ASSERT_NOTNULL(TT2, "the second throw should exist")
	qdel(TT2)
	TEST_ASSERT_NULL(J.throwing, "deleting the throw should clear the item's throwing")
	TEST_ASSERT(!QDELETED(J), "deleting the throw must not delete the item")

/// An action acts for a datum (deleting that datum deletes the action) and is granted to a mob (deleting the mob, or Remove(), clears the owner
/// but keeps the action).
/datum/unit_test/dq_rel_pin_action

/datum/unit_test/dq_rel_pin_action/Run()
	var/obj/item/I = allocate(/obj/item)
	var/datum/action/A = new(I)
	TEST_ASSERT_EQUAL(A.action_target(), I, "the action should act for its item")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	A.Grant(H)
	TEST_ASSERT_EQUAL(A.action_owner(), H, "Grant should make the mob the owner")
	A.Remove(H)
	TEST_ASSERT_NULL(A.action_owner(), "Remove should clear the owner")
	A.Grant(H)
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human)
	A.Grant(H2)
	TEST_ASSERT_EQUAL(A.action_owner(), H2, "granting to a second mob should replace the owner")
	qdel(H2)
	TEST_ASSERT_NULL(A.action_owner(), "deleting the owner should clear the owner")
	TEST_ASSERT(!QDELETED(A), "deleting the owner must not delete the action")
	qdel(I)
	TEST_ASSERT(QDELETED(A), "deleting the item the action acts for should delete the action")

/// A leash is pet <-> leash <-> holder. Either person or the leash going ends the whole leash; a pet already leashed refuses a second leash.
/datum/unit_test/dq_rel_pin_leash

/datum/unit_test/dq_rel_pin_leash/Run()
	var/mob/living/carbon/human/pet = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/master = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human)
	var/obj/item/leash/L = allocate(/obj/item/leash)
	var/obj/item/leash/L2 = allocate(/obj/item/leash)
	TEST_ASSERT(L.attach(pet, master), "setup: the leash should attach")
	TEST_ASSERT_EQUAL(L.leash_pet(), pet, "the leash's pet")
	TEST_ASSERT_EQUAL(L.leash_master(), master, "the leash's holder")
	TEST_ASSERT_EQUAL(pet.leash_item(), L, "the pet's leash")
	TEST_ASSERT(!L2.attach(pet, other), "a pet already on a leash refuses a second one")
	TEST_ASSERT_EQUAL(pet.leash_item(), L, "the refused leash must not displace the first")
	L.clear_leash()
	TEST_ASSERT_NULL(L.leash_pet(), "clear_leash should free the pet")
	TEST_ASSERT_NULL(L.leash_master(), "clear_leash should free the holder")
	TEST_ASSERT(L.attach(pet, master), "setup: reattach")
	qdel(pet)
	TEST_ASSERT_NULL(L.leash_master(), "deleting the pet should let go of the holder")
	var/mob/living/carbon/human/pet2 = allocate(/mob/living/carbon/human)
	TEST_ASSERT(L.attach(pet2, master), "setup: attach a second pet")
	qdel(L)
	TEST_ASSERT_NULL(pet2.leash_item(), "deleting the leash should free the pet")
	TEST_ASSERT(!(pet2.alerts && pet2.alerts["leashed"]), "the freed pet should lose the alert")
	TEST_ASSERT(!(master.alerts && master.alerts["leash"]), "the holder should lose the alert")

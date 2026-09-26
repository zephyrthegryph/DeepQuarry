// Migration track 1c (doc/rewrite/lifecycle.md LC-refs): /datum/weakref is
// gone. Live links are relations (code/datums/om/library.dm, read through
// the accessor macros in code/__defines/om.dm); "remember who it was" refs
// are OM handles (om_handle()/om_resolve()). One test per relation added, plus
// the handle behaviour weakrefs used to provide.

// ---------------------------------------------------------------- handles

/// A handle doesn't keep its target alive: a datum BYOND collects without
/// qdel() stops resolving, as a weakref did.
/datum/unit_test/dq_refs_handle_is_weak

/datum/unit_test/dq_refs_handle_is_weak/Run()
	var/h = dq_refs_dropped_handle()
	TEST_ASSERT(om_is_handle(h), "the datum got a handle")
	TEST_ASSERT_NULL(om_resolve(h), "a collected datum's handle resolves to null")
	var/datum/E = new
	TEST_ASSERT_NULL(om_resolve(h), "a new datum never answers an old handle")
	TEST_ASSERT(om_handle(E) != h, "and gets a handle of its own")

/// A handle to a datum nothing else references: it resolves while the datum
/// is live, then BYOND collects the datum when this proc returns. (A helper,
/// because TEST_ASSERT_* keeps its operands in locals.)
/proc/dq_refs_dropped_handle()
	var/datum/D = new
	. = om_handle(D)
	if(om_resolve(.) != D)
		return null

/// QDEL_IN past the GC filter queue defers through a handle: it still deletes
/// the target, and does nothing once the target is already gone.
/datum/unit_test/dq_refs_qdel_handle

/datum/unit_test/dq_refs_qdel_handle/Run()
	var/obj/item/I = allocate(/obj/item/tape_roll)
	qdel_handle(om_handle(I))
	TEST_ASSERT(QDELETED(I), "qdel_handle() deletes what the handle names")
	qdel_handle(om_handle(I)) // a deleted datum has no handle: a no-op
	qdel_handle("junk")

/// IC refs: a reference on a circuit pin round-trips, and no sanitized string
/// can pass for one.
/datum/unit_test/dq_refs_ic_ref

/datum/unit_test/dq_refs_ic_ref/Run()
	var/obj/item/I = allocate(/obj/item/tape_roll)
	var/r = ic_ref(I)
	TEST_ASSERT(ic_is_ref(r), "ic_ref() makes an IC ref")
	TEST_ASSERT_EQUAL(ic_ref_resolve(r), I, "an IC ref resolves to its datum")
	var/forged = sanitizeSafe(r, MAX_MESSAGE_LEN, 0, 0)
	TEST_ASSERT(!ic_is_ref(forged), "sanitized pin text is never an IC ref")
	TEST_ASSERT(!ic_is_ref(om_handle(I)), "a bare handle is not an IC ref")
	qdel(I)
	TEST_ASSERT_NULL(ic_ref_resolve(r), "an IC ref to a deleted datum resolves to null")

// ---------------------------------------------------------------- bluespace radio links

/// A bluespace radio linked to a receiver: BS_TX_TARGET/BS_TX_RADIOS agree,
/// the receiver accepts the radio's bluespace signal and refuses a stranger's,
/// and deleting the receiver drops the link.
/datum/unit_test/dq_refs_bluespace_tx_link

/datum/unit_test/dq_refs_bluespace_tx_link/Run()
	var/obj/item/radio/R = allocate(/obj/item/radio)
	var/obj/item/radio/stranger = allocate(/obj/item/radio)
	var/obj/machinery/telecomms/receiver/RX = allocate(/obj/machinery/telecomms/receiver)
	TEST_ASSERT(istype(om_link(R, RX, /datum/om/relation/bluespace_tx_to), /datum/om/edge), "linking the radio should succeed")
	TEST_ASSERT_EQUAL(BS_TX_TARGET(R), RX, "BS_TX_TARGET(radio) is the receiver")
	TEST_ASSERT(R in BS_TX_RADIOS(RX), "the radio is in BS_TX_RADIOS(receiver)")

	var/datum/signal/ok = new
	ok.transmission_method = TRANSMISSION_BLUESPACE
	ok.data = list("radio" = R)
	TEST_ASSERT(RX.check_receive_level(ok), "the receiver accepts its linked radio")
	var/datum/signal/bad = new
	bad.transmission_method = TRANSMISSION_BLUESPACE
	bad.data = list("radio" = stranger)
	TEST_ASSERT(!RX.check_receive_level(bad), "the receiver refuses an unlinked radio")

	qdel(RX)
	TEST_ASSERT_NULL(BS_TX_TARGET(R), "deleting the receiver drops the radio's link")

/// A bluespace radio receiving from a broadcaster: deleting the radio drops it
/// from BS_RX_RADIOS.
/datum/unit_test/dq_refs_bluespace_rx_link

/datum/unit_test/dq_refs_bluespace_rx_link/Run()
	var/obj/item/radio/R = allocate(/obj/item/radio)
	var/obj/machinery/telecomms/broadcaster/TX = allocate(/obj/machinery/telecomms/broadcaster)
	om_link(R, TX, /datum/om/relation/bluespace_rx_from)
	TEST_ASSERT_EQUAL(BS_RX_SOURCE(R), TX, "BS_RX_SOURCE(radio) is the broadcaster")
	TEST_ASSERT(R in BS_RX_RADIOS(TX), "the radio is in BS_RX_RADIOS(broadcaster)")
	qdel(R)
	TEST_ASSERT_EQUAL(length(BS_RX_RADIOS(TX)), 0, "deleting the radio drops it from the broadcaster")

// ---------------------------------------------------------------- gripper

/// gripper_holding is single on both ends: wrapping a new item lets go of the
/// old one, and the held item being deleted clears the hold.
/datum/unit_test/dq_refs_gripper_holding

/datum/unit_test/dq_refs_gripper_holding/Run()
	var/obj/item/G = allocate(/obj/item/tape_roll) // any holder: the relation doesn't care
	var/obj/item/A = allocate(/obj/item/tape_roll)
	var/obj/item/B = allocate(/obj/item/tape_roll)
	om_link(G, A, /datum/om/relation/gripper_holding)
	TEST_ASSERT_EQUAL(GRIPPER_HELD(G), A, "GRIPPER_HELD is the wrapped item")
	om_link(G, B, /datum/om/relation/gripper_holding)
	TEST_ASSERT_EQUAL(GRIPPER_HELD(G), B, "wrapping another item replaces the first")
	TEST_ASSERT_NULL(dq_test_find_edge(G, A, /datum/om/relation/gripper_holding), "no edge is left to the first item")
	qdel(B)
	TEST_ASSERT_NULL(GRIPPER_HELD(G), "the wrapped item being deleted clears the hold")

// ---------------------------------------------------------------- UAV

/// A mob flying a UAV is one of its UAV_MASTERS and can move it; deleting the
/// mob removes it, and clear_masters() drops everyone.
/datum/unit_test/dq_refs_uav_master

/datum/unit_test/dq_refs_uav_master/Run()
	var/obj/item/uav/U = allocate(/obj/item/uav)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human)
	U.add_master(H)
	U.add_master(H2)
	TEST_ASSERT(H in UAV_MASTERS(U), "add_master() makes the mob a master")
	TEST_ASSERT_EQUAL(length(UAV_MASTERS(U)), 2, "a UAV can have several masters")
	U.state = 1 // UAV_ON (undefined outside uav.dm)
	TEST_ASSERT(U.relaymove(H, NORTH), "a master's movement is taken by the UAV")
	TEST_ASSERT(!U.relaymove(allocate(/mob/living/carbon/human), NORTH), "a stranger's is not")
	qdel(H)
	TEST_ASSERT_EQUAL(length(UAV_MASTERS(U)), 1, "a deleted master is dropped")
	U.clear_masters()
	TEST_ASSERT_EQUAL(length(UAV_MASTERS(U)), 0, "clear_masters() drops every master")
	U.state = 0 // UAV_OFF

// ---------------------------------------------------------------- stasis source

/// set_stasis() links the stasis modifier to its source; the source is found
/// again through STASIS_SOURCE, and deleting it leaves sourceless stasis.
/datum/unit_test/dq_refs_stasis_held_by

/datum/unit_test/dq_refs_stasis_held_by/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/source = allocate(/obj/item/tourniquet)
	H.set_stasis(/datum/modifier/stasis/light, source)
	var/datum/modifier/stasis/S = H.stasis_modifier_from(source)
	TEST_ASSERT_NOTNULL(S, "the source's stasis is found")
	TEST_ASSERT_EQUAL(STASIS_SOURCE(S), source, "STASIS_SOURCE is the source")
	TEST_ASSERT(H.has_stasis_from(source), "has_stasis_from() agrees")
	qdel(source)
	TEST_ASSERT_NULL(STASIS_SOURCE(S), "deleting the source unlinks it")
	H.set_stasis(null, null)
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0, "the leftover stasis is released as sourceless")

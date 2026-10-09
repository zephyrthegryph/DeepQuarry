// Migration track 1c (doc/rewrite/lifecycle.md LC-refs): /datum/weakref is
// gone. Live links are relations (code/datums/om/library.dm, read through
// the accessor macros in code/__defines/om.dm); "remember who it was" refs
// are OM handles (entity_handle()/resolve_handle()). One test per relation added, plus
// the handle behaviour weakrefs used to provide.

// ---------------------------------------------------------------- handles

/// A handle doesn't keep its target alive: a datum BYOND collects without
/// qdel() stops resolving, as a weakref did.
/datum/unit_test/dq_refs_handle_is_weak

/datum/unit_test/dq_refs_handle_is_weak/Run()
	var/h = dq_refs_dropped_handle()
	TEST_ASSERT(is_entity_handle(h), "the datum got a handle")
	// Resolving a handle whose target BYOND collected without qdel() is the
	// misuse the detector reports; this test builds that case on purpose, so
	// capture the report and check it fired instead of failing the run.
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/resolved = resolve_handle(h)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT_NULL(resolved, "a collected datum's handle resolves to null")
	TEST_ASSERT(length(capture) == 1 && findtext(capture[1], "HANDLE TARGET COLLECTED WITHOUT QDEL"), "the collected target was reported: [json_encode(capture)]")
	var/datum/E = new
	TEST_ASSERT_NULL(resolve_handle(h), "a new datum never answers an old handle")
	TEST_ASSERT(entity_handle(E) != h, "and gets a handle of its own")

/// A handle to a datum nothing else references: it resolves while the datum
/// is live, then BYOND collects the datum when this proc returns. (A helper,
/// because TEST_ASSERT_* keeps its operands in locals.)
/proc/dq_refs_dropped_handle()
	var/datum/D = new
	. = entity_handle(D)
	if(resolve_handle(.) != D)
		return null

/// QDEL_IN past the GC filter queue defers through a handle: it still deletes
/// the target, and does nothing once the target is already gone.
/datum/unit_test/dq_refs_qdel_handle

/datum/unit_test/dq_refs_qdel_handle/Run()
	var/obj/item/I = allocate(/obj/item/tape_roll)
	qdel_handle(entity_handle(I))
	TEST_ASSERT(QDELETED(I), "qdel_handle() deletes what the handle names")
	qdel_handle(entity_handle(I)) // a deleted datum has no handle: a no-op
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
	TEST_ASSERT(!ic_is_ref(entity_handle(I)), "a bare handle is not an IC ref")
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
	rel_set(R, nameof(R.bs_tx_receiver), RX)
	TEST_ASSERT_EQUAL(R?.bs_tx_target(), RX, "radio?.bs_tx_target() is the receiver")
	TEST_ASSERT(R in RX?.bs_tx_radios(), "the radio is in receiver?.bs_tx_radios()")

	var/datum/signal/ok = new
	ok.transmission_method = TRANSMISSION_BLUESPACE
	ok.data = list("radio" = R)
	TEST_ASSERT(RX.check_receive_level(ok), "the receiver accepts its linked radio")
	var/datum/signal/bad = new
	bad.transmission_method = TRANSMISSION_BLUESPACE
	bad.data = list("radio" = stranger)
	TEST_ASSERT(!RX.check_receive_level(bad), "the receiver refuses an unlinked radio")

	qdel(RX)
	TEST_ASSERT_NULL(R?.bs_tx_target(), "deleting the receiver drops the radio's link")

/// A bluespace radio receiving from a broadcaster: deleting the radio drops it
/// from BS_RX_RADIOS.
/datum/unit_test/dq_refs_bluespace_rx_link

/datum/unit_test/dq_refs_bluespace_rx_link/Run()
	var/obj/item/radio/R = allocate(/obj/item/radio)
	var/obj/machinery/telecomms/broadcaster/TX = allocate(/obj/machinery/telecomms/broadcaster)
	rel_set(R, nameof(R.bs_rx_broadcaster), TX)
	TEST_ASSERT_EQUAL(R?.bs_rx_source(), TX, "radio?.bs_rx_source() is the broadcaster")
	TEST_ASSERT(R in TX?.bs_rx_radios(), "the radio is in broadcaster?.bs_rx_radios()")
	qdel(R)
	TEST_ASSERT_EQUAL(length(TX?.bs_rx_radios()), 0, "deleting the radio drops it from the broadcaster")

// ---------------------------------------------------------------- gripper

/// gripper_holding is single on both ends: wrapping a new item lets go of the
/// old one, and the held item being deleted clears the hold.
/// A gripper that stays outside a robot (a real one qdels itself there) and has no pockets.
/obj/item/gripper/dq_test
	total_pockets = 0

/obj/item/gripper/dq_test/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_NORMAL

/datum/unit_test/dq_refs_gripper_holding

/datum/unit_test/dq_refs_gripper_holding/Run()
	var/obj/item/gripper/G = allocate(/obj/item/gripper/dq_test) // the accessor is declared on the gripper
	var/obj/item/A = allocate(/obj/item/tape_roll)
	var/obj/item/B = allocate(/obj/item/tape_roll)
	rel_set(G, nameof(/obj/item/gripper::held_item), A)
	TEST_ASSERT_EQUAL(G.get_wrapped_item(), A, "the wrapped item is held")
	rel_set(G, nameof(/obj/item/gripper::held_item), B)
	TEST_ASSERT_EQUAL(G.get_wrapped_item(), B, "wrapping another item replaces the first")
	qdel(B)
	TEST_ASSERT_NULL(G.get_wrapped_item(), "the wrapped item being deleted clears the hold")

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
	TEST_ASSERT(H in U.masters, "add_master() makes the mob a master")
	TEST_ASSERT_EQUAL(length(U.masters), 2, "a UAV can have several masters")
	U.set_state(1) // UAV_ON (undefined outside uav.dm)
	TEST_ASSERT(U.relaymove(H, NORTH), "a master's movement is taken by the UAV")
	TEST_ASSERT(!U.relaymove(allocate(/mob/living/carbon/human), NORTH), "a stranger's is not")
	qdel(H)
	TEST_ASSERT_EQUAL(length(U.masters), 1, "a deleted master is dropped")
	U.clear_masters()
	TEST_ASSERT_EQUAL(length(U.masters), 0, "clear_masters() drops every master")
	U.set_state(0) // UAV_OFF

// ---------------------------------------------------------------- stasis source

/// set_stasis() keys the stasis by its source (a handle); the source finds it again, and
/// deleting the source leaves sourceless stasis.
/datum/unit_test/dq_refs_stasis_held_by

/datum/unit_test/dq_refs_stasis_held_by/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/source = allocate(/obj/item/tourniquet)
	H.set_stasis(/datum/body_effect/stasis/light, source)
	TEST_ASSERT_EQUAL(H.stasis_type_from(source), /datum/body_effect/stasis/light, "the source's stasis is found")
	TEST_ASSERT(H.has_stasis_from(source), "has_stasis_from() agrees")
	TEST_ASSERT(!H.has_stasis_from(null), "while the source lives the stasis is not sourceless")
	qdel(source)
	TEST_ASSERT_EQUAL(H.stasis_type_from(null), /datum/body_effect/stasis/light, "deleting the source leaves sourceless stasis")
	H.set_stasis(null, null)
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0, "the leftover stasis is released as sourceless")

// ---------------------------------------------------------------- registries

/// A mob joins its declared registries when it materializes and its stat's
/// conditional registry; deleting it drops it from all of them.
/datum/unit_test/dq_refs_registry_mob_lists

/datum/unit_test/dq_refs_registry_mob_lists/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(H in REGISTRY_MEMBERS(REGISTRY_MOBS), "a human is in REGISTRY_MOBS")
	TEST_ASSERT(H in REGISTRY_MEMBERS(REGISTRY_HUMANS), "a human is in REGISTRY_HUMANS")
	TEST_ASSERT(registry_has(REGISTRY_LIVING_MOBS, H), "a live human is in REGISTRY_LIVING_MOBS")
	TEST_ASSERT(!registry_has(REGISTRY_DEAD_MOBS, H), "and not in REGISTRY_DEAD_MOBS")
	qdel(H)
	TEST_ASSERT(!(H in REGISTRY_MEMBERS(REGISTRY_MOBS)), "deleting it drops it from REGISTRY_MOBS")
	TEST_ASSERT(!(H in REGISTRY_MEMBERS(REGISTRY_HUMANS)), "and from REGISTRY_HUMANS")
	TEST_ASSERT(!registry_has(REGISTRY_LIVING_MOBS, H), "and from REGISTRY_LIVING_MOBS")

/// Preview dummies skip every mob registry, conditional ones included.
/datum/unit_test/dq_refs_registry_dummy_skips

/datum/unit_test/dq_refs_registry_dummy_skips/Run()
	var/mob/living/carbon/human/dummy/D = allocate(/mob/living/carbon/human/dummy)
	TEST_ASSERT(!(D in REGISTRY_MEMBERS(REGISTRY_MOBS)), "a dummy is not in REGISTRY_MOBS")
	TEST_ASSERT(!(D in REGISTRY_MEMBERS(REGISTRY_HUMANS)), "nor in REGISTRY_HUMANS")
	TEST_ASSERT(!registry_join(REGISTRY_LIVING_MOBS, D), "and can't join REGISTRY_LIVING_MOBS")

/// A conditional registry: join and leave by state, idempotently, and the
/// member drops out by itself when deleted.
/datum/unit_test/dq_refs_registry_conditional

/datum/unit_test/dq_refs_registry_conditional/Run()
	var/obj/item/radio_jammer/J = allocate(/obj/item/radio_jammer)
	TEST_ASSERT(!registry_has(REGISTRY_RADIO_JAMMERS, J), "an idle jammer is not in the registry")
	registry_join(REGISTRY_RADIO_JAMMERS, J)
	registry_join(REGISTRY_RADIO_JAMMERS, J)
	TEST_ASSERT(registry_has(REGISTRY_RADIO_JAMMERS, J), "registry_join() puts it in")
	var/count = 0
	for(var/obj/item/radio_jammer/member as anything in REGISTRY_MEMBERS(REGISTRY_RADIO_JAMMERS))
		if(member == J)
			count++
	TEST_ASSERT_EQUAL(count, 1, "joining twice lists it once")
	registry_leave(REGISTRY_RADIO_JAMMERS, J)
	TEST_ASSERT(!registry_has(REGISTRY_RADIO_JAMMERS, J), "registry_leave() takes it out")
	registry_join(REGISTRY_RADIO_JAMMERS, J)
	qdel(J)
	TEST_ASSERT(!registry_has(REGISTRY_RADIO_JAMMERS, J), "deleting it drops it")
	TEST_ASSERT(!(J in REGISTRY_MEMBERS(REGISTRY_RADIO_JAMMERS)), "from the member list too")

/// Datums that aren't atoms: a declared registry holds them from New(), a
/// conditional one while joined, and the destroy transaction drops them.
/datum/unit_test/dq_refs_registry_datums

/datum/unit_test/dq_refs_registry_datums/Run()
	var/datum/objective/O = new
	TEST_ASSERT(O in REGISTRY_MEMBERS(REGISTRY_OBJECTIVES), "a new objective is in REGISTRY_OBJECTIVES")
	qdel(O)
	TEST_ASSERT(!(O in REGISTRY_MEMBERS(REGISTRY_OBJECTIVES)), "deleting it drops it")
	var/datum/money_account/A = new
	TEST_ASSERT(!registry_has(REGISTRY_MONEY_ACCOUNTS, A), "an unregistered account is not listed")
	registry_join(REGISTRY_MONEY_ACCOUNTS, A)
	TEST_ASSERT(registry_has(REGISTRY_MONEY_ACCOUNTS, A), "registry_join() lists it")
	qdel(A)
	TEST_ASSERT(!registry_has(REGISTRY_MONEY_ACCOUNTS, A), "deleting it drops it")

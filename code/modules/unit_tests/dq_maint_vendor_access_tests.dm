#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/obj/machinery/maint_vendor/dq_access_probe
	abstract_type = /obj/machinery/maint_vendor/dq_access_probe
	req_access = list(ACCESS_MAINT_TUNNELS)
	req_one_access = list(ACCESS_SECURITY)

/datum/maint_recycler_vendor_entry/dq_access_probe
	required_access = list(ACCESS_ENGINE, ACCESS_MEDICAL)

/obj/item/card/id/dq_vendor_denied
	abstract_type = /obj/item/card/id/dq_vendor_denied
	access = list(ACCESS_MAINT_TUNNELS)
/obj/item/card/id/dq_vendor_allowed
	abstract_type = /obj/item/card/id/dq_vendor_allowed
	access = list(ACCESS_MAINT_TUNNELS, ACCESS_ENGINE)
/obj/item/card/id/dq_vendor_missing_all
	abstract_type = /obj/item/card/id/dq_vendor_missing_all
	access = list(ACCESS_ENGINE)

/datum/unit_test/dq_maint_vendor_access_policy/proc/credential_user(card_type, turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/under/color/grey/U = allocate(/obj/item/clothing/under/color/grey, T)
	var/obj/item/card/id/I = allocate(card_type, T)
	H.equip_to_slot_if_possible(U, SLOT_ID_UNIFORM, disable_warning = TRUE)
	H.equip_to_slot_if_possible(I, SLOT_ID_ID, disable_warning = TRUE)
	return H

/datum/unit_test/dq_maint_vendor_access_policy/Run()
	var/turf/T = test_floor()
	var/obj/machinery/maint_vendor/dq_access_probe/V = allocate(/obj/machinery/maint_vendor/dq_access_probe, T)
	var/datum/maint_recycler_vendor_entry/dq_access_probe/entry = allocate(/datum/maint_recycler_vendor_entry/dq_access_probe)
	var/list/all_policy = V.req_access
	var/list/one_policy = V.req_one_access
	var/mob/living/carbon/human/denied = credential_user(/obj/item/card/id/dq_vendor_denied, T)
	TEST_ASSERT_EQUAL(denied.GetIdCard()?.type, /obj/item/card/id/dq_vendor_denied, "The denied actor actually wears its credential")
	TEST_ASSERT_EQUAL(V.purchase_access_refusal(denied, entry), "Access Denied", "Machine access alone does not supply any required entry access")
	TEST_ASSERT_EQUAL(V.req_access, all_policy, "Denied admission leaves the exact all-access policy unchanged")
	TEST_ASSERT_EQUAL(V.req_one_access, one_policy, "Denied admission leaves the exact one-access policy unchanged")
	var/mob/living/carbon/human/allowed = credential_user(/obj/item/card/id/dq_vendor_allowed, T)
	TEST_ASSERT_EQUAL(allowed.GetIdCard()?.type, /obj/item/card/id/dq_vendor_allowed, "The allowed actor actually wears its credential")
	TEST_ASSERT_NULL(V.purchase_access_refusal(allowed, entry), "Actual all-access plus one entry credential admits without requiring the holder's unrelated one-access list")
	TEST_ASSERT_EQUAL(V.req_access, all_policy, "Allowed admission retains the exact all-access list")
	TEST_ASSERT_EQUAL(V.req_one_access, one_policy, "Allowed admission retains the exact one-access list")
	TEST_ASSERT(ACCESS_SECURITY in V.req_one_access, "The holder's preexisting restriction was not silently cleared")
	var/mob/living/carbon/human/missing_all = credential_user(/obj/item/card/id/dq_vendor_missing_all, T)
	TEST_ASSERT_EQUAL(missing_all.GetIdCard()?.type, /obj/item/card/id/dq_vendor_missing_all, "The final actor actually wears its entry-only credential")
	TEST_ASSERT_EQUAL(V.purchase_access_refusal(missing_all, entry), "Access Denied", "An entry credential does not bypass the machine's mandatory all-access list")

#endif

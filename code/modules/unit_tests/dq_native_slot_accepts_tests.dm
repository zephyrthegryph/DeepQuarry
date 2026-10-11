// Native declared-slot evaluation and real equipment custody regression coverage.
/obj/dq_native_slot_accepts
	var/admission_ready = FALSE
TRACKED(/obj/dq_native_slot_accepts, admission_ready)
CAPABILITIES(/obj/dq_native_slot_accepts)
	slot("dq-native-slot", accepts = list(req(PROC_REF(admission_reason)), req(PROC_REF(context_reason))))
/obj/dq_native_slot_accepts/proc/admission_reason(datum/act/op/A)
	return admission_ready ? null : "slot not ready"
/obj/dq_native_slot_accepts/proc/context_reason(datum/act/op/A)
	return A.destination == src && A.holder == src && A.slot_id == "dq-native-slot" && A.actor == A.mover && A.target ? null : "wrong slot query context"

/datum/unit_test/dq_native_declared_slot_accepts/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/dq_native_slot_accepts/H = allocate(/obj/dq_native_slot_accepts, T)
	var/obj/dq_native_slot_accepts/H2 = allocate(/obj/dq_native_slot_accepts, T)
	var/obj/item/pen/I = allocate(/obj/item/pen, T)
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture, T)
	var/datum/ledger/L = dq_ledger(H)
	var/datum/relation_definition/slot/D = L.def_by_id("dq-native-slot")
	TEST_ASSERT(D, "Actual declared native slot was compiled")
	TEST_ASSERT_EQUAL(D, dq_ledger(H2).def_by_id("dq-native-slot"), "Declared slot definition is immutable shared flyweight")
	TEST_ASSERT_EQUAL(D.refusal(H, I, M), "slot not ready", "Declared native slot preserves first exact refusal")
	var/list/reads = D.admission_read_keys(H, I, M)
	var/found = FALSE
	for(var/list/pair as anything in reads)
		if(pair[1] == H && pair[2] == nameof(H.admission_ready))
			found = TRUE
	TEST_ASSERT(found, "Refused native slot still exposes actual holder dependency")
	H.set_admission_ready(TRUE)
	TEST_ASSERT_NULL(D.refusal(H, I, M), "Real setter permits candidate with correct mover/destination/slot context")
	TEST_ASSERT_EQUAL(D.refusal(H2, I, M), "slot not ready", "Shared definition never binds state to first holder")
	var/old_reason = GLOB.act_last_reason
	TEST_ASSERT(move_into(H, "dq-native-slot", I, M), "Native requirement permits real transfer")
	TEST_ASSERT_EQUAL(I.loc, H, "Real insertion changes custody")
	var/datum/ledger/after_insert = dq_ledger(H)
	var/list/insert_record = after_insert.entries[I]
	TEST_ASSERT_NOTNULL(insert_record, "Actual physical insertion has a ledger record; holder ledger stable=[after_insert == L], tracked=[after_insert.tracked]")
	TEST_ASSERT_EQUAL(insert_record[LEDGER_E_SLOT], "dq-native-slot", "Actual insertion preserves requested slot id")
	TEST_ASSERT(I in after_insert.slots["dq-native-slot"], "Actual ledger slot contains candidate; recorded=[insert_record[LEDGER_E_SLOT]], slots=[english_list(after_insert.slots)]")
	H2.set_admission_ready(TRUE)
	TEST_ASSERT(move_into(H2, "dq-native-slot", I, M), "Real transfer to another holder removes candidate from old slot")
	TEST_ASSERT_EQUAL(I.loc, H2, "Real removal/adoption updates custody")
	TEST_ASSERT(!(I in dq_ledger(H).slots["dq-native-slot"]), "Actual old ledger slot is empty")
	GLOB.act_last_reason = old_reason

/datum/unit_test/dq_native_equipment_wearer_mover/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/mover = allocate(/mob/living/carbon/human, T)
	wearer.set_species(SPECIES_HUMAN)
	mover.set_species(SPECIES_HUMAN)
	var/obj/item/clothing/under/color/grey/U = allocate(/obj/item/clothing/under/color/grey, T)
	var/obj/item/pen/I = allocate(/obj/item/pen, T)
	var/obj/item/storage/wallet/B = allocate(/obj/item/storage/wallet, T)
	TEST_ASSERT(GLOB.native_equipment_acceptance, "Catalog singleton exists before native query")
	TEST_ASSERT(mover.equip_to_slot(U, SLOT_ID_UNIFORM), "Only actual mover initially wears uniform")
	var/datum/relation_definition/slot/D = dq_ledger(wearer).def_by_id(SLOT_ID_POCKET_L)
	TEST_ASSERT_EQUAL(D.refusal(wearer, I, mover), "you need a jumpsuit first", "Native catalog checks wearer rather than dressed mover")
	var/old_reason = GLOB.act_last_reason
	TEST_ASSERT(!move_into(wearer, SLOT_ID_POCKET_L, I, mover), "Real transfer refuses naked wearer despite dressed mover")
	TEST_ASSERT_EQUAL(I.loc, T, "Refusal leaves real custody untouched")
	TEST_ASSERT_NULL(wearer.get_equipped_item(SLOT_ID_POCKET_L), "Refusal leaves actual destination empty")
	TEST_ASSERT(mover.unEquip(U), "Actual uniform removal succeeds")
	TEST_ASSERT(wearer.equip_to_slot(U, SLOT_ID_UNIFORM), "Actual wearer now wears uniform")
	TEST_ASSERT_NULL(mover.get_equipped_item(SLOT_ID_UNIFORM), "Actual mover no longer wears uniform")
	TEST_ASSERT_NULL(D.refusal(wearer, I, mover), "Native catalog now permits dressed wearer with naked mover")
	TEST_ASSERT(move_into(wearer, SLOT_ID_POCKET_L, I, mover), "Distinct mover performs allowed real insertion")
	TEST_ASSERT_EQUAL(wearer.get_equipped_item(SLOT_ID_POCKET_L), I, "Actual wearer pocket contains candidate")
	TEST_ASSERT_EQUAL(I.loc, wearer, "Actual custody is wearer, not mover")
	TEST_ASSERT(move_into(B, CONTAINER_SLOT_STORAGE, I, mover), "Distinct mover performs real removal into actual storage")
	TEST_ASSERT_NULL(wearer.get_equipped_item(SLOT_ID_POCKET_L), "Actual wearer slot empties after removal")
	TEST_ASSERT_EQUAL(I.loc, B, "Actual removed candidate reaches storage")
	GLOB.act_last_reason = old_reason

// Records the NTNet programs named by a counter now name by their handle, ref_token() (relations.md D9a, lint entity_ids).

/// A warrant is named to the window by its handle, and the edit button names it back as the warrant itself.
/datum/unit_test/dq_entity_handle_warrant/Run()
	var/datum/data/record/warrant/W = allocate(/datum/data/record/warrant)
	rel_add(GLOB.data_core, nameof(/datum/datacore::warrants), W)
	var/datum/computer_file/program/digitalwarrant/P = allocate(/datum/computer_file/program/digitalwarrant)
	TEST_ASSERT_EQUAL(resolve_window_ref(ref_token(W)), W, "the handle the window holds resolves to the warrant")
	P.ui_act_editwarrant(null, W)
	TEST_ASSERT_EQUAL(P.activewarrant_ref, W, "editing a filed warrant opens it")
	rel_remove(GLOB.data_core, nameof(/datum/datacore::warrants), W)
	var/datum/data/record/warrant/unfiled = allocate(/datum/data/record/warrant)
	P.ui_act_back(null)
	P.ui_act_editwarrant(null, unfiled)
	TEST_ASSERT_NULL(P.activewarrant_ref, "a warrant that is not on file is not opened")

/// A chat channel's id is its handle, and the network finds the channel by it.
/datum/unit_test/dq_entity_handle_chat_channel/Run()
	var/datum/ntnet_conversation/C = allocate(/datum/ntnet_conversation)
	TEST_ASSERT_EQUAL(C.id, ref_token(C), "the channel's id is its handle")
	TEST_ASSERT_EQUAL(GLOB.ntnet_global.get_chat_channel_by_id(C.id), C, "the network finds the channel by its handle")

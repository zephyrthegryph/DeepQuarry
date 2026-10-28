/// The admin-record accessors answer for a player too: no stealth key, no rank, no rights to edit, nothing marked, no href token.
/datum/unit_test/dq_admin_accessors_player/Run()
	var/client/nobody = null
	TEST_ASSERT_NULL(admin_fakekey(nobody), "no stealth key")
	TEST_ASSERT_NULL(admin_rank_names(nobody), "no rank")
	TEST_ASSERT_EQUAL(admin_editable_rights(nobody), NONE, "no rights to edit")
	TEST_ASSERT_EQUAL(admin_rank_flags(nobody), NONE, "no rank rights")
	TEST_ASSERT_NULL(admin_marked_datum(nobody), "nothing marked")
	TEST_ASSERT_NULL(admin_href_token(nobody), "no href token")
	admin_set_fakekey(nobody, "ghost") // a player has no record: nothing is written, nothing breaks
	TEST_ASSERT_NULL(admin_fakekey(nobody), "setting a stealth key on a player does nothing")

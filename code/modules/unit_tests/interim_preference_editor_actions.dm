/// A preference editor routes its own actions: their arguments go through schemas (numeric text is a number, other text refuses), and an action
/// it has no handler for changes nothing.
/datum/unit_test/interim_preference_editor_actions/Run()
	var/datum/preference_editor/birthday/editor = GLOB.preference_editors_by_key["birthday"]
	TEST_ASSERT_NOTNULL(editor, "the birthday editor is registered")
	var/datum/preferences/dq_loadout_test_stub/p = new()
	TEST_ASSERT_EQUAL(editor.handle_action(p, "set_month", list("value" = "march"), null), PREF_UPDATE_REJECTED, "a month that is not a number refuses")
	TEST_ASSERT_EQUAL(editor.handle_action(p, "set_month", list("value" = "3"), null), PREF_UPDATE_ACCEPTED, "numeric text is read as a number")
	TEST_ASSERT_EQUAL(p.read_preference(/datum/preference/numeric/human/bday_month), 3, "the month is written")
	TEST_ASSERT_EQUAL(editor.handle_action(p, "no_such_action", list(), null), PREF_UPDATE_UNCHANGED, "an unknown action changes nothing")
	qdel(p)

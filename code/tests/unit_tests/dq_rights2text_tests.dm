/// rights2text() names each right a bitfield holds, in its fixed order and with its old spelling.
/datum/unit_test/dq_rights2text/Run()
	TEST_ASSERT_EQUAL(rights2text(0), "NONE", "no rights read as NONE")
	TEST_ASSERT_EQUAL(rights2text(R_SOUNDS | R_BAN), "+BAN+SOUND", "rights come out in the fixed order, SOUNDS spelled SOUND")
	TEST_ASSERT_EQUAL(rights2text(R_MOD | R_DBRANKS, " "), " +MODERATOR +DBRANKS", "the separator goes before each prefix")

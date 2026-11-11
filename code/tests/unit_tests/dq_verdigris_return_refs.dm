/// A list a Verdigris bind returns (`hand_list` in verdigris/ffi/src/held.rs) belongs to DM alone: BYOND takes the
/// persistent reference the bind created with the return value (byondapi_cpp_wrappers.h, ByondValueResult). If Rust also
/// kept its reference the list would carry one more than a DM-made list; if it released it as well, the list would
/// carry one fewer (or be freed under us).
/datum/unit_test/dq_verdigris_returned_list_refs/Run()
	var/list/args_in = list(10, 1, 0, 0, 30, 0, 1)
	var/list/made = list(1, 2, 3)
	var/expected = refcount(made)
	var/base_args = refcount(args_in)
	for(var/i in 1 to 200)
		var/list/got = vg_chem_metabolism_cycle(args_in)
		TEST_ASSERT(islist(got), "the bind returns a list")
		if(i == 1 || i == 200)
			log_test("dq_verdigris_returned_list_refs: call [i] refcount [refcount(got)] (a DM list: [expected])")
		TEST_ASSERT_EQUAL(refcount(got), expected, "a returned list is referenced only by the var holding it")
	TEST_ASSERT_EQUAL(refcount(args_in), base_args, "the argument list keeps no reference from the bind")

/// A machine's VV edit of a var the machinery handler does not own runs the parent chain: the edit lands and the datum is marked edited.
/datum/unit_test/dq_machinery_vv_edit_chains_parent/Run()
	var/obj/machinery/light_switch/M = allocate(/obj/machinery/light_switch, run_loc_floor_bottom_left)
	TEST_ASSERT(M.vv_edit_var(nameof(M.name), "vv probe"), "an edit of a plain var on a machine succeeds")
	TEST_ASSERT_EQUAL(M.name, "vv probe", "the edit landed")
	TEST_ASSERT(M.datum_flags & DF_VAR_EDITED, "the datum handler ran and marked the machine edited")

/// An EMP over general records touches only the fields a general record holds, over security records only the name and criminal status.
/datum/unit_test/dq_records_emp_field_sets/Run()
	var/list/general = list()
	var/list/security = list()
	for(var/i in 1 to 300)
		var/datum/data/record/G = allocate(/datum/data/record)
		G.set_fields_at("name", "probe")
		G.set_fields_at("sex", "Male")
		G.set_fields_at("age", 30)
		G.set_fields_at("p_stat", "Active")
		G.set_fields_at("m_stat", "Stable")
		general += G
		var/datum/data/record/S = allocate(/datum/data/record)
		S.set_fields_at("name", "probe")
		S.set_fields_at("criminal", "None")
		S.set_fields_at("sex", "Male")
		S.set_fields_at("age", 30)
		S.set_fields_at("p_stat", "Active")
		security += S
	var/datum/datacore/core = GLOB.data_core
	core.emp_scramble(general, 1, FALSE)
	core.emp_scramble(security, 1, TRUE)
	var/general_changed = 0
	for(var/datum/data/record/G in general)
		if(QDELETED(G))
			continue
		TEST_ASSERT_NULL(G.fields["criminal"], "a general record never gains a criminal status")
		if(G.fields["name"] != "probe" || G.fields["sex"] != "Male" || G.fields["age"] != 30 || G.fields["p_stat"] != "Active" || G.fields["m_stat"] != "Stable")
			general_changed++
	TEST_ASSERT(general_changed > 0, "an EMP at severity 1 scrambles some general records")
	var/security_changed = 0
	for(var/datum/data/record/S in security)
		if(QDELETED(S))
			continue
		TEST_ASSERT_EQUAL(S.fields["sex"], "Male", "a security record's sex is left alone")
		TEST_ASSERT_EQUAL(S.fields["age"], 30, "a security record's age is left alone")
		TEST_ASSERT_EQUAL(S.fields["p_stat"], "Active", "a security record's physical status is left alone")
		if(S.fields["name"] != "probe" || S.fields["criminal"] != "None")
			security_changed++
	TEST_ASSERT(security_changed > 0, "an EMP at severity 1 scrambles some security records")

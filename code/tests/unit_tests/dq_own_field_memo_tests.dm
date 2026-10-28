// own_field_changed()'s memo (code/engine/refs/table.dm) against the checks of its full path.

/// For every relation var of every type with a live instance: the memo says what the static checks say now, and when the fast path would skip
/// a write, every check of the full path finds nothing to do.
/datum/unit_test/dq_own_field_memo_parity

/datum/unit_test/dq_own_field_memo_parity/Run()
	var/list/seen = list()
	var/pairs = 0
	var/skips = 0
	for(var/atom/A in world)
		if(seen[A.type] || QDELETED(A))
			continue
		seen[A.type] = TRUE
		var/datum/own_table/T = own_table_of(A)
		for(var/var_name in T.entries)
			pairs++
			var/memo = own_field_static_work(A, var_name)
			var/fresh = own_field_static_readers(A, var_name)
			TEST_ASSERT_EQUAL(!!memo, !!fresh, "[A.type].[var_name]: the memo says [memo], the static checks say [fresh]")
			var/datum/rx_state/S = A.rx
			var/dynamic = S && (S.observed || S.worn_watched || S.hooks)
			if(memo || dynamic || GLOB.derived_read_vars[var_name] || GLOB.change_hop_keys[var_name])
				continue
			skips++
			TEST_ASSERT(!READERS(A, var_name), "[A.type].[var_name]: the fast path skips a write that READERS() says is read")
			TEST_ASSERT(!GLOB.stat_input_keys[var_name], "[A.type].[var_name]: skipped, but a stat reads it")
			TEST_ASSERT(!draw_hop_reads_var(var_name), "[A.type].[var_name]: skipped, but a draw reads it a hop away")
			var/list/fields = GLOB.om_reg.fields_of(A.type)
			TEST_ASSERT(!fields[var_name], "[A.type].[var_name]: skipped, but it raises an OM channel")
		if(length(seen) >= 400)
			break
	TEST_ASSERT(pairs > 100, "relation vars checked ([pairs])")
	log_world("dq_own_field_memo_parity: [length(seen)] types, [pairs] relation vars, [skips] the fast path skips; [GLOB.own_field_memo_spared] writes spared so far")

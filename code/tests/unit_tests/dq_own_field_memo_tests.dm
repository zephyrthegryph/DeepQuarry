// own_field_changed()'s memo (code/engine/refs/table.dm) against the checks of its full path.

/// For every relation var of every type with a live instance: the memo's OFW_* bits are what the static checks say now, and every part of the
/// full path whose bit is clear (and that nothing dynamic reaches) finds nothing to do.
/datum/unit_test/dq_own_field_memo_parity

/datum/unit_test/dq_own_field_memo_parity/Run()
	var/list/seen = list()
	var/pairs = 0
	var/skips = 0
	var/parts_skipped = 0
	for(var/atom/A in world)
		if(seen[A.type] || QDELETED(A))
			continue
		seen[A.type] = TRUE
		var/datum/own_table/T = own_table_of(A)
		for(var/var_name in T.entries)
			pairs++
			var/memo = own_field_static_work(A, var_name)
			var/fresh = own_field_static_readers(A, var_name)
			TEST_ASSERT_EQUAL(memo, fresh, "[A.type].[var_name]: the memo says [memo], the static checks say [fresh]")
			var/datum/rx_state/S = A.rx
			var/dynamic = S && (S.observed || S.worn_watched || S.hooks)
			var/stat_global = GLOB.stat_input_keys[var_name] && (GLOB.stat_hop_index[var_name] || GLOB.stat_sys_vars[var_name])
			var/datum/stat_type_info/I = stat_type_of(A)
			if(!(memo & OFW_READ) && !dynamic && !GLOB.change_hop_keys[var_name])
				parts_skipped++
				TEST_ASSERT(!READERS(A, var_name), "[A.type].[var_name]: READERS() is not asked, but it says the var is read")
			if(!(memo & OFW_STAT_REL) && I)
				parts_skipped++
				TEST_ASSERT(!(I.hop_rels && (var_name in I.hop_rels)), "[A.type].[var_name]: stat_relation_changed() is not entered, but a stat hop of the type crosses the var")
				for(var/datum/stat_contrib/ct as anything in I.ct_entries)
					TEST_ASSERT(ct.rel != var_name, "[A.type].[var_name]: stat_relation_changed() is not entered, but a contribution of the type is carried by the var")
			if(!(memo & OFW_STAT_IN) && !stat_global)
				parts_skipped++
				TEST_ASSERT(!I || !I.inputs[var_name], "[A.type].[var_name]: stat_inputs_changed() is not entered, but a stat of the type takes the var as an input")
			if(!(memo & OFW_HOP))
				TEST_ASSERT(!draw_hop_reads_var(var_name), "[A.type].[var_name]: not published a hop away, but a draw reads it a hop away")
			if(!(memo & OFW_CHANNEL))
				var/list/fields = GLOB.definition_store.fields_of(A.type)
				TEST_ASSERT(!fields[var_name], "[A.type].[var_name]: no channel is raised, but the var has one")
			if(memo || dynamic || stat_global || GLOB.derived_read_vars[var_name] || GLOB.change_hop_keys[var_name])
				continue
			skips++
			// A stat of some other type reading the var is no reader here: a skip needs only that nothing of this type's stat layer acts on it.
			TEST_ASSERT(!stat_type_reads_key(A, var_name), "[A.type].[var_name]: skipped, but a stat reads it")
		if(length(seen) >= 400)
			break
	TEST_ASSERT(pairs > 100, "relation vars checked ([pairs])")
	log_world("dq_own_field_memo_parity: [length(seen)] types, [pairs] relation vars, [skips] the fast path skips, [parts_skipped] parts not entered; [GLOB.own_field_memo_spared] writes spared so far")

/// A batch of relation writes publishes each (holder, var) once, at its commit, and nothing before it; outside a batch every write publishes at once.
/datum/unit_test/dq_rel_write_batch_publishes_once_at_commit

/datum/unit_test/dq_rel_write_batch_publishes_once_at_commit/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/A = allocate(/obj/item/tool/wrench, T)
	var/before = GLOB.own_field_full_paths
	var/batched = GLOB.rel_writes_batched
	set_global(nameof(GLOB.own_field_memo_off), TRUE) // every write enters the full path, so the count shows each publish
	rel_write_batch_begin()
	rel_write_batch_begin() // nested: only the outermost commit publishes
	own_field_changed(A, "name")
	own_field_changed(A, "name")
	own_field_changed(A, "desc")
	rel_write_batch_commit()
	TEST_ASSERT_EQUAL(GLOB.own_field_full_paths, before, "nothing is published while the batch is open")
	TEST_ASSERT_EQUAL(GLOB.rel_writes_batched - batched, 3, "every write was noted")
	rel_write_batch_commit()
	TEST_ASSERT_EQUAL(GLOB.own_field_full_paths - before, 2, "the commit publishes each (holder, var) once")
	TEST_ASSERT_NULL(GLOB.rel_write_batch, "and closes the batch")
	own_field_changed(A, "name")
	TEST_ASSERT_EQUAL(GLOB.own_field_full_paths - before, 3, "outside a batch a write publishes at once")
	set_global(nameof(GLOB.own_field_memo_off), FALSE)

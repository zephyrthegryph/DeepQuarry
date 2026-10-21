// The stat layer's index, as the runtime builders make it (doc/rewrite/proposals/change_graph.md section 11 step 3, the stats fold).
//
// stat_type_build() registers what a type's contributions and formulas read into the global indexes state_changed() asks: GLOB.stat_input_keys
// (a var some stat reads), GLOB.stat_hop_index (a var read a relation away, by the reader type) and the system reads. The fold moves those rules
// into `analyze gen plans`; this sweep records, for every creatable type, what the runtime builder registers, so the generated index can be proved
// equal to it once before the runtime registration is deleted. Each shard writes data/stat-index/shard-N.tsv (type, kind, key).
//
// Exhaustive and sharded (dq_focused_test.sh sweep_pins): it makes one fresh instance of every creatable type, like dq_fresh_look_default.

/datum/unit_test/dq_stat_index_oracle
	tier = TEST_TIER_EXHAUSTIVE
	timeout = 3600
	is_sweep_test = TRUE

/// The rows `I` (one type's stat info) registers in the global indexes, sorted.
/proc/dq_stat_index_rows(datum/stat_type_info/I)
	. = list()
	for(var/key in I.inputs)
		if(findtext(key, "stat:") != 1)
			. |= "input\t[key]"
	for(var/remote in I.hops)
		for(var/datum/stat_hop/H as anything in I.hops[remote])
			if(remote == "sys")
				. |= "sys\t[H.system]"
			else
				. |= "hop\t[jointext(H.path, ".")].[H.remote_var]"
	for(var/datum/stat_contrib/ct as anything in I.ct_entries)
		if(ct.rel)
			. |= "ct\t[ct.rel]"
	sortTim(., GLOBAL_PROC_REF(cmp_text_asc))

/datum/unit_test/dq_stat_index_oracle/Run()
	var/turf/T = test_floor()
	var/list/out = list()
	var/made = 0
	var/with_stats = 0
	for(var/type in sweep_types(dq_fresh_look_universe()))
		made++
		dq_fresh_look_reset(T)
		var/datum/stat_type_info/I
		try
			var/atom/A = dq_snapshot_allocate(type, T)
			if(!QDELETED(A))
				I = stat_type_of(A)
				dq_fresh_look_delete(A)
		catch(var/exception/e)
			out += "[type]\truntime\t[e.name]"
		dq_fresh_look_drain(T)
		if(!istype(I))
			continue
		with_stats++
		for(var/row in dq_stat_index_rows(I))
			out += "[type]\t[row]"
	dq_fresh_look_reset(T)
	// Coverage: every name the builder registers is in the generated, over-inclusive GLOB.stat_input_keys (the registration is deleted).
	var/list/missing = list()
	for(var/row in out)
		var/list/cols = splittext(row, "	")
		if(length(cols) < 3 || cols[2] == "runtime")
			continue
		var/key = cols[3]
		if(findtext(key, "capkey:") == 1 || findtext(key, "graph:") == 1)
			continue // ids, not vars: their changes reach the stat layer by their own paths
		var/list/names = list()
		switch(cols[2])
			if("sys")
				names += copytext(key, findtext(key, ".") + 1)
			if("hop")
				var/list/segments = splittext(key, ".")
				names += segments[1]
				names += segments[length(segments)]
			else
				names += key
		for(var/name in names)
			if(!GLOB.stat_input_keys[name])
				missing["[name] ([cols[1]] [cols[2]] [key])"] = TRUE
	log_test("stat index oracle: generated input set [length(GLOB.stat_input_keys)] names, [length(missing)] missing")
	TEST_ASSERT(!length(missing), "the generated stat input set misses what the builder registers:\n[jointext(missing, "\n")]")
	var/path = "data/stat-index/shard-[GLOB.dq_test_shard_index].tsv"
	fdel(path)
	text2file(jointext(out, "\n"), path)
	log_test("stat index oracle: [made] types made, [with_stats] with stats, [length(out)] rows -> [path]")
	TEST_ASSERT(made, "the sweep made nothing")

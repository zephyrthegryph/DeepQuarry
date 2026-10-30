// stat_hop_targets() (code/engine/stats/recompute.dm): the readers a write reaches through a relation. A flip of one channel of an area reached its machines by every
// registered reader type scanning every reader (entries x readers istype() tests: 60-265 ms for the 555-machine Atmospherics area); each reader now looks up the hops
// of its own type. The set reached must be exactly what the scan reached.

/// The scan stat_notify_hops() did before: each entry, every reader of the relation, filtered by the entry's type.
/proc/dq_stat_hop_targets_oracle(datum/E, key)
	var/list/out = list()
	for(var/list/entry as anything in GLOB.stat_hop_index[key])
		var/reader_type = entry[1]
		var/datum/stat_hop/hop = entry[2]
		var/list/frontier
		if(hop.fast)
			var/list/direct = E.rx?.stats?.hop_in?[hop.rel_var]
			frontier = direct ? direct.Copy() : list()
		else
			frontier = list(E)
		for(var/i in (hop.fast ? 0 : length(hop.path)) to 1 step -1)
			var/segment = hop.path[i]
			var/list/next_frontier = list()
			for(var/datum/at as anything in frontier)
				for(var/datum/source as anything in hop_sources(at, segment))
					if(!QDELETED(source))
						next_frontier |= list(source)
			frontier = next_frontier
			if(!length(frontier))
				break
		for(var/datum/reader as anything in frontier)
			if(istype(reader, reader_type))
				out += list(reader, hop)
	return out

/datum/unit_test/dq_stat_hop_targets_match_the_per_entry_scan

/datum/unit_test/dq_stat_hop_targets_match_the_per_entry_scan/Run()
	var/area/target
	for(var/area/A)
		if(!target || length(A.power_machines) > length(target.power_machines))
			target = A
	TEST_ASSERT_NOTNULL(target, "the test map has areas")
	TEST_ASSERT(length(target.power_machines) > 3, "the busiest area holds machines of several types ([length(target.power_machines)])")
	var/checked = 0
	for(var/key in list("power_equip", "power_light", "power_environ", "requires_power"))
		var/list/entries = GLOB.stat_hop_index[key]
		if(!length(entries))
			continue
		var/list/fast = stat_hop_targets(target, key, entries)
		var/list/oracle = dq_stat_hop_targets_oracle(target, key)
		TEST_ASSERT_EQUAL(length(fast), length(oracle), "[key]: the same number of (reader, hop) pairs are reached")
		var/list/counts = list()
		for(var/i in 1 to length(oracle) step 2)
			counts["[REF(oracle[i])]|[REF(oracle[i + 1])]"]++
		for(var/i in 1 to length(fast) step 2)
			var/pair = "[REF(fast[i])]|[REF(fast[i + 1])]"
			TEST_ASSERT(counts[pair] > 0, "[key]: ([fast[i]], [fast[i + 1]]) is reached by the scan too")
			counts[pair]--
		checked += length(oracle) / 2
	TEST_ASSERT(checked > 0, "the area's channels reach machines through a relation hop")

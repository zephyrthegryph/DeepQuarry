// The cost passes of dq_rel_perf_tests.dm over the alist forms: a ref_many set, a keyed ref_many (numeric keys) and a keyed owns_many.

/datum/unit_test/dq_rel_perf_alist_forms
	tier = TEST_TIER_EXHAUSTIVE // a measurement, run by name or with --tier=all

/datum/unit_test/dq_rel_perf_alist_forms/Run()
	for(var/n in list(2500, 10000))
		var/datum/relperf_holder/H = new
		var/list/made = list()
		for(var/i in 1 to n)
			made += new /datum/relperf_member
		var/t = REALTIMEOFDAY
		for(var/datum/relperf_member/M as anything in made)
			rel_add(H, nameof(H.member_set), M)
		var/add_us = RELPERF_US(t, n)
		TEST_ASSERT_EQUAL(length(H.member_set), n, "every member joined the set")
		t = REALTIMEOFDAY
		for(var/datum/relperf_member/M as anything in made)
			rel_add(H, nameof(H.member_set), M)
		var/dup_us = RELPERF_US(t, n)
		TEST_ASSERT_EQUAL(length(H.member_set), n, "a duplicate add changes nothing")
		t = REALTIMEOFDAY
		for(var/i in 1 to n step 2)
			rel_remove(H, nameof(H.member_set), made[i])
		var/remove_us = RELPERF_US(t, n / 2)
		log_test("REL PERF ref_many alist set n=[n]: add [add_us] us/op, duplicate add [dup_us] us/op, remove [remove_us] us/op")
		t = REALTIMEOFDAY
		var/deleted = 0
		for(var/i in 2 to n step 2)
			qdel(made[i])
			deleted++
		TEST_ASSERT_EQUAL(length(H.member_set), 0, "a deleted member left the set")
		log_test("REL PERF ref_many alist set n=[n]: qdel of a member [RELPERF_US(t, deleted)] us/op")
		// keyed, numeric keys
		var/list/keyed = list()
		for(var/i in 1 to n)
			keyed += new /datum/relperf_member
		t = REALTIMEOFDAY
		for(var/i in 1 to n)
			rel_add(H, nameof(H.member_table), keyed[i], i)
		var/put_us = RELPERF_US(t, n)
		TEST_ASSERT_EQUAL(length(H.member_table), n, "every member sits under its number")
		t = REALTIMEOFDAY
		for(var/i in 1 to n step 2)
			rel_remove(H, nameof(H.member_table), keyed[i])
		var/unkey_us = RELPERF_US(t, n / 2)
		t = REALTIMEOFDAY
		deleted = 0
		for(var/i in 2 to n step 2)
			qdel(keyed[i])
			deleted++
		TEST_ASSERT_EQUAL(length(H.member_table), 0, "a deleted member left every key")
		log_test("REL PERF ref_many alist map n=[n]: put [put_us] us/op, remove [unkey_us] us/op, qdel of a member [RELPERF_US(t, deleted)] us/op")
		// owned
		t = REALTIMEOFDAY
		var/list/kids = list()
		for(var/i in 1 to n)
			var/datum/relperf_member/kid = new
			kids += kid
			rel_add(H, nameof(H.kid_table), kid, i)
		var/own_put_us = RELPERF_US(t, n)
		t = REALTIMEOFDAY
		for(var/i in 1 to n step 2)
			qdel(kids[i])
		TEST_ASSERT_EQUAL(length(H.kid_table), n / 2, "a deleted child left its key")
		log_test("REL PERF owns_many alist map n=[n]: put [own_put_us] us/op, qdel of a child [RELPERF_US(t, n / 2)] us/op")
		t = REALTIMEOFDAY
		qdel(H)
		log_test("REL PERF owns_many alist map n=[n]: teardown [RELPERF_US(t, n / 2)] us/child")

// Relation and handle cost (the reference-storage core: code/engine/refs, code/engine/time/handles.dm).
//
// A micro-measurement, not a benchmark: each pass prints microseconds per operation (log_test) at two sizes so a linear-per-op cost shows as a
// ratio, and asserts correctness only (no timing threshold, so a slow machine never fails it). REALTIMEOFDAY ticks in tenths of a second: the
// passes are sized to run a few tenths each.

/// A holder with one many of each declared kind the cost passes use.
/datum/relperf_holder
	var/list/members
	var/list/kids
	/// A ref_many held as an alist set (member -> TRUE).
	var/alist/member_set = alist()
	/// A keyed ref_many held as an alist map (key -> member), a number as the key.
	var/alist/member_table = alist()
	/// An owns_many held as an alist set.
	var/alist/kid_set = alist()
	/// A keyed owns_many held as an alist map (a number as the key: a sparse table).
	var/alist/kid_table = alist()
	/// A keyed owns_many in a plain list (a text key).
	var/list/kid_text

CAPABILITIES(/datum/relperf_holder)
	ref_many(nameof(members))
	owns_many(nameof(kids))
	ref_many(nameof(member_set))
	ref_many(nameof(member_table))
	owns_many(nameof(kid_set))
	owns_many(nameof(kid_table))
	owns_many(nameof(kid_text))

/datum/relperf_member

/// Microseconds per operation for `ops` operations that took `started` to now (tenths of a second).
#define RELPERF_US(started, ops) (round(((REALTIMEOFDAY - started) * 100000) / max(1, ops), 0.1))

/datum/unit_test/dq_rel_perf_membership
	tier = TEST_TIER_EXHAUSTIVE // a measurement, run by name or with --tier=all

/datum/unit_test/dq_rel_perf_membership/Run()
	for(var/n in list(2500, 10000))
		var/datum/relperf_holder/H = new
		var/list/made = list()
		for(var/i in 1 to n)
			made += new /datum/relperf_member
		var/t = REALTIMEOFDAY
		for(var/datum/relperf_member/M as anything in made)
			rel_add(H, nameof(H.members), M)
		var/add_us = RELPERF_US(t, n)
		TEST_ASSERT_EQUAL(length(H.members), n, "every member was added")
		t = REALTIMEOFDAY
		for(var/datum/relperf_member/M as anything in made)
			rel_add(H, nameof(H.members), M) // already a member: refused as a duplicate
		var/dup_us = RELPERF_US(t, n)
		TEST_ASSERT_EQUAL(length(H.members), n, "a duplicate add changes nothing")
		t = REALTIMEOFDAY
		for(var/i in 1 to n step 2)
			rel_remove(H, nameof(H.members), made[i])
		var/remove_us = RELPERF_US(t, n / 2)
		TEST_ASSERT_EQUAL(length(H.members), n / 2, "half the members were removed")
		log_test("REL PERF ref_many n=[n]: add [add_us] us/op, duplicate add [dup_us] us/op, remove [remove_us] us/op")
		// qdel of members one by one: each leaves the holder's list
		t = REALTIMEOFDAY
		var/deleted = 0
		for(var/i in 2 to n step 2)
			qdel(made[i])
			deleted++
		var/qdel_us = RELPERF_US(t, deleted)
		TEST_ASSERT_EQUAL(length(H.members), 0, "a deleted member left the holder's list")
		log_test("REL PERF ref_many n=[n]: qdel of a member [qdel_us] us/op")
		// teardown of a holder with all members still linked
		var/datum/relperf_holder/H2 = new
		for(var/i in 1 to n)
			var/datum/relperf_member/M = new
			rel_add(H2, nameof(H2.members), M)
		t = REALTIMEOFDAY
		qdel(H2)
		log_test("REL PERF ref_many n=[n]: teardown of a holder with [n] members [RELPERF_US(t, n)] us/member")
		qdel(H)

/datum/unit_test/dq_rel_perf_owned
	tier = TEST_TIER_EXHAUSTIVE // a measurement, run by name or with --tier=all

/datum/unit_test/dq_rel_perf_owned/Run()
	for(var/n in list(1000, 4000))
		var/datum/relperf_holder/H = new
		var/t = REALTIMEOFDAY
		for(var/i in 1 to n)
			rel_add(H, nameof(H.kids), new /datum/relperf_member)
		var/add_us = RELPERF_US(t, n)
		TEST_ASSERT_EQUAL(length(H.kids), n, "every child was added")
		var/list/kids = H.kids.Copy()
		t = REALTIMEOFDAY
		for(var/i in 1 to n step 2)
			rel_remove(H, nameof(H.kids), kids[i])
		var/remove_us = RELPERF_US(t, n / 2)
		log_test("REL PERF owns_many n=[n]: add [add_us] us/op, remove (dispose) [remove_us] us/op")
		t = REALTIMEOFDAY
		qdel(H)
		log_test("REL PERF owns_many n=[n]: teardown [RELPERF_US(t, n / 2)] us/child")

/datum/unit_test/dq_rel_perf_handles
	tier = TEST_TIER_EXHAUSTIVE // a measurement, run by name or with --tier=all

/datum/unit_test/dq_rel_perf_handles/Run()
	var/n = 20000
	var/list/made = list()
	for(var/i in 1 to n)
		made += new /datum/relperf_member
	var/list/handles = list()
	var/t = REALTIMEOFDAY
	for(var/datum/relperf_member/M as anything in made)
		handles += entity_handle(M)
	var/create_us = RELPERF_US(t, n)
	t = REALTIMEOFDAY
	var/again = 0
	for(var/datum/relperf_member/M as anything in made)
		if(entity_handle(M) == handles[++again])
			continue
		TEST_FAIL("the same datum gave a different handle")
		break
	var/repeat_us = RELPERF_US(t, n)
	t = REALTIMEOFDAY
	var/resolved = 0
	for(var/h in handles)
		if(resolve_handle(h))
			resolved++
	var/resolve_us = RELPERF_US(t, n)
	TEST_ASSERT_EQUAL(resolved, n, "every handle resolved")
	log_test("REL PERF handles n=[n]: first entity_handle [create_us] us/op, repeat entity_handle [repeat_us] us/op, resolve_handle [resolve_us] us/op")
	// turfs
	var/list/turfs = list()
	for(var/turf/T as anything in block(locate(1, 1, 1), locate(world.maxx, world.maxy, 1)))
		turfs += T
	var/turf_count = length(turfs)
	var/rounds = max(1, round(n / max(1, turf_count)))
	t = REALTIMEOFDAY
	var/list/turf_handles = list()
	for(var/r in 1 to rounds)
		for(var/turf/T as anything in turfs)
			turf_handles += entity_handle(T)
	var/turf_create_us = RELPERF_US(t, length(turf_handles))
	t = REALTIMEOFDAY
	var/turf_resolved = 0
	for(var/h in turf_handles)
		if(resolve_handle(h))
			turf_resolved++
	var/turf_resolve_us = RELPERF_US(t, length(turf_handles))
	TEST_ASSERT_EQUAL(turf_resolved, length(turf_handles), "every turf handle resolved")
	t = REALTIMEOFDAY
	turf_resolved = 0
	for(var/h in turf_handles)
		if(resolve_handle(h))
			turf_resolved++
	var/turf_again_us = RELPERF_US(t, length(turf_handles))
	TEST_ASSERT_EQUAL(turf_resolved, length(turf_handles), "every turf handle resolved again")
	log_test("REL PERF turf handles n=[length(turf_handles)]: entity_handle [turf_create_us] us/op, resolve_handle [turf_resolve_us] us/op first time, [turf_again_us] us/op after")
	for(var/datum/relperf_member/M as anything in made)
		qdel(M)
	for(var/h in handles)
		if(resolve_handle(h))
			TEST_FAIL("a deleted datum's handle still resolved")
			break

/// What this engine's alist does, as the relation core relies on it (code/engine/refs/members.dm).
/datum/unit_test/dq_alist_semantics

/datum/unit_test/dq_alist_semantics/Run()
	var/alist/A = alist()
	TEST_ASSERT(!islist(A), "islist() is FALSE for an alist, so relation code asks REL_LISTLIKE()")
	TEST_ASSERT(istype(A, /alist) && REL_LISTLIKE(A) && REL_LISTLIKE(list()) && !REL_LISTLIKE(null), "REL_LISTLIKE() is TRUE for a list and an alist only")
	var/datum/relperf_member/M = new
	var/datum/relperf_member/M2 = new
	A[5] = "five"
	A[7] = "seven"
	A["t"] = "text"
	A[M] = TRUE
	A[M2] = TRUE
	TEST_ASSERT_EQUAL(length(A), 5, "an alist takes numbers, text and datums as keys")
	TEST_ASSERT(A[5] == "five" && isnull(A[6]), "a number is a key, not an index")
	TEST_ASSERT((5 in A) && !(6 in A) && (M in A), "`in` asks the keys")
	A -= 5
	TEST_ASSERT(!(5 in A) && length(A) == 4, "`-=` removes a key")
	A.Remove(M)
	TEST_ASSERT(!(M in A) && length(A) == 3, "Remove() removes a key")
	TEST_ASSERT(istype(A.Copy(), /alist), "Copy() is an alist")
	A[M2] = null
	TEST_ASSERT(length(A) == 3 && (M2 in A), "assigning null keeps the key: a member leaves by `-=`")
	var/list/as_list = A
	TEST_ASSERT_EQUAL(length(as_list), 3, "an alist can be passed where a list parameter is declared")
	var/pairs = 0
	for(var/key, value in A)
		pairs++
	TEST_ASSERT_EQUAL(pairs, 3, "for(key, value in alist) walks the pairs")
	A.Cut()
	TEST_ASSERT_EQUAL(length(A), 0, "Cut() empties it")
	qdel(M)
	qdel(M2)

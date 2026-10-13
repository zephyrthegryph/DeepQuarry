// The many-relation shapes (code/engine/refs/members.dm) and the handle table (code/engine/time/handles.dm): membership in a long list,
// alist sets, keyed numeric tables, a member that leaves by deletion, and a handle that outlives its slot's reuse.

/// A long ref_many list: a duplicate is refused through the reverse index, order is kept, removal and re-adding work, and the index
/// follows every write.
/datum/unit_test/dq_rel_core_long_list

/datum/unit_test/dq_rel_core_long_list/Run()
	var/datum/relperf_holder/H = new
	var/list/made = list()
	for(var/i in 1 to 200)
		var/datum/relperf_member/M = new
		made += M
		rel_add(H, nameof(H.members), M)
	TEST_ASSERT_EQUAL(length(H.members), 200, "200 members joined")
	for(var/datum/relperf_member/M as anything in made)
		rel_add(H, nameof(H.members), M)
	TEST_ASSERT_EQUAL(length(H.members), 200, "a member already in a long list is not added again")
	for(var/i in 1 to 200)
		TEST_ASSERT_EQUAL(H.members[i], made[i], "the list keeps the order members joined in ([i])")
	TEST_ASSERT(rel_names(H, nameof(H.members), made[150]), "the reverse index names a member of the long list")
	rel_remove(H, nameof(H.members), made[150])
	TEST_ASSERT_EQUAL(length(H.members), 199, "a removed member left the long list")
	TEST_ASSERT(!rel_names(H, nameof(H.members), made[150]), "and the index forgot it")
	rel_add(H, nameof(H.members), made[150])
	TEST_ASSERT_EQUAL(H.members[200], made[150], "a re-added member joins at the end")
	qdel(made[3])
	TEST_ASSERT_EQUAL(length(H.members), 199, "a deleted member left the long list")
	TEST_ASSERT(!(made[3] in H.members), "and is not in it")
	rel_clear(H, nameof(H.members))
	TEST_ASSERT_EQUAL(length(H.members), 0, "rel_clear empties the long list")
	var/datum/relperf_member/M = made[10]
	TEST_ASSERT(isnull(M.om_refs_in), "no member keeps a reverse index entry")
	qdel(H)

/// A ref_many held as an alist set: constant-time membership, no duplicates, removal, deletion of a member and of the holder.
/datum/unit_test/dq_rel_core_alist_set

/datum/unit_test/dq_rel_core_alist_set/Run()
	var/datum/relperf_holder/H = new
	var/datum/relperf_member/A = new
	var/datum/relperf_member/B = new
	var/datum/relperf_member/C = new
	rel_add(H, nameof(H.member_set), A)
	rel_add(H, nameof(H.member_set), B)
	rel_add(H, nameof(H.member_set), A)
	TEST_ASSERT_EQUAL(length(H.member_set), 2, "a set holds a member once")
	TEST_ASSERT((A in H.member_set) && (B in H.member_set) && !(C in H.member_set), "membership reads with `in`")
	TEST_ASSERT(rel_names(H, nameof(H.member_set), A), "the reverse index names the set's members")
	var/seen = 0
	for(var/datum/relperf_member/M in H.member_set)
		seen++
	TEST_ASSERT_EQUAL(seen, 2, "walking the set yields its members")
	TEST_ASSERT(rel_remove(H, nameof(H.member_set), A), "removing a member reports it")
	TEST_ASSERT(!rel_remove(H, nameof(H.member_set), A), "removing it again reports nothing to remove")
	TEST_ASSERT(!(A in H.member_set) && (B in H.member_set), "the set lost only A")
	TEST_ASSERT(!rel_names(H, nameof(H.member_set), A), "the index forgot A")
	qdel(B)
	TEST_ASSERT_EQUAL(length(H.member_set), 0, "a deleted member left the set")
	TEST_ASSERT(istype(H.member_set, /alist), "an emptied set is still an alist")
	rel_add(H, nameof(H.member_set), C)
	qdel(H)
	TEST_ASSERT(isnull(C.om_refs_in), "deleting the holder dropped its members' reverse index")
	qdel(A)
	qdel(C)

/// A keyed ref_many with numeric keys: put, replace, one member under several keys, empty a key, remove a member from all its keys, delete.
/datum/unit_test/dq_rel_core_keyed_numeric_ref

/datum/unit_test/dq_rel_core_keyed_numeric_ref/Run()
	var/datum/relperf_holder/H = new
	var/datum/relperf_member/A = new
	var/datum/relperf_member/B = new
	rel_add(H, nameof(H.member_table), A, 5)
	rel_add(H, nameof(H.member_table), A, 9)
	rel_add(H, nameof(H.member_table), B, 12)
	TEST_ASSERT_EQUAL(H.member_table[5], A, "A sits under 5")
	TEST_ASSERT_EQUAL(H.member_table[9], A, "and under 9")
	TEST_ASSERT_EQUAL(H.member_table[12], B, "B sits under 12")
	TEST_ASSERT(isnull(H.member_table[6]), "an unused number holds nothing")
	TEST_ASSERT(rel_names(H, nameof(H.member_table), A), "the reverse index names A once, whatever its keys")
	rel_add(H, nameof(H.member_table), B, 5) // B replaces A under 5; A still sits under 9
	TEST_ASSERT_EQUAL(H.member_table[5], B, "B replaced A under 5")
	TEST_ASSERT_EQUAL(H.member_table[9], A, "A kept its other key")
	TEST_ASSERT(rel_names(H, nameof(H.member_table), A), "and stayed linked while one key remained")
	rel_add(H, nameof(H.member_table), null, 9) // empties the key
	TEST_ASSERT(isnull(H.member_table[9]), "a null member empties its key")
	TEST_ASSERT(!rel_names(H, nameof(H.member_table), A), "A, under no key, is unlinked")
	TEST_ASSERT_EQUAL(length(H.member_table), 2, "two keys remain (5 and 12)")
	rel_remove(H, nameof(H.member_table), B)
	TEST_ASSERT_EQUAL(length(H.member_table), 0, "rel_remove takes a member from every key it sits under")
	rel_add(H, nameof(H.member_table), A, 1)
	rel_add(H, nameof(H.member_table), A, 2)
	rel_add(H, nameof(H.member_table), A, 3)
	qdel(A)
	TEST_ASSERT_EQUAL(length(H.member_table), 0, "a deleted member left all three of its keys")
	rel_add(H, nameof(H.member_table), B, 7)
	rel_clear(H, nameof(H.member_table))
	TEST_ASSERT_EQUAL(length(H.member_table), 0, "rel_clear empties the keyed table")
	TEST_ASSERT(!rel_names(H, nameof(H.member_table), B), "and unlinks its members")
	rel_add(H, nameof(H.member_table), B, 7)
	qdel(H)
	TEST_ASSERT(isnull(B.om_refs_in), "deleting the holder unlinked the keyed members")
	qdel(B)

/// An owns_many alist set: add, no duplicate, remove (disposes), a deleted child leaves, the holder takes its children with it.
/datum/unit_test/dq_rel_core_owned_set

/datum/unit_test/dq_rel_core_owned_set/Run()
	var/datum/relperf_holder/H = new
	var/datum/relperf_member/A = new
	var/datum/relperf_member/B = new
	var/datum/relperf_member/C = new
	rel_add(H, nameof(H.kid_set), A)
	rel_add(H, nameof(H.kid_set), B)
	rel_add(H, nameof(H.kid_set), C)
	rel_add(H, nameof(H.kid_set), A)
	TEST_ASSERT_EQUAL(length(H.kid_set), 3, "an owned set holds a child once")
	TEST_ASSERT_EQUAL(owner_of(A), H, "a child of the set is owned by the holder")
	rel_remove(H, nameof(H.kid_set), A)
	TEST_ASSERT(QDELETED(A), "removing an owned child disposes of it")
	qdel(B)
	TEST_ASSERT(!(B in H.kid_set) && (C in H.kid_set), "a deleted child left the set")
	var/list/taken = rel_take_all(H, nameof(H.kid_set))
	TEST_ASSERT(length(taken) == 1 && taken[1] == C && isnull(owner_of(C)), "rel_take_all hands the children back unowned")
	TEST_ASSERT(istype(H.kid_set, /alist) && !length(H.kid_set), "and leaves an empty set")
	rel_add(H, nameof(H.kid_set), C)
	qdel(H)
	TEST_ASSERT(QDELETED(C), "the holder's children go with it")

/// A keyed owns_many with numeric keys (a sparse table): replace disposes the old child, a child under two keys stays owned while one remains,
/// a deleted child leaves all its keys, take by key, empty a key, clear disposes.
/datum/unit_test/dq_rel_core_owned_numeric_table

/datum/unit_test/dq_rel_core_owned_numeric_table/Run()
	var/datum/relperf_holder/H = new
	var/datum/relperf_member/A = new
	var/datum/relperf_member/B = new
	var/datum/relperf_member/C = new
	rel_add(H, nameof(H.kid_table), A, 3)
	rel_add(H, nameof(H.kid_table), B, 40)
	TEST_ASSERT_EQUAL(H.kid_table[3], A, "A sits under 3")
	TEST_ASSERT_EQUAL(H.kid_table[40], B, "B sits under 40")
	TEST_ASSERT_EQUAL(owner_of(A), H, "a child of the table is owned by the holder")
	TEST_ASSERT_EQUAL(owner_of(B), H, "wherever its key is")
	rel_add(H, nameof(H.kid_table), C, 3) // replaces A
	TEST_ASSERT(QDELETED(A), "the child a key gave up is disposed of")
	TEST_ASSERT_EQUAL(H.kid_table[3], C, "C took key 3")
	rel_add(H, nameof(H.kid_table), C, 8) // C also under 8
	rel_add(H, nameof(H.kid_table), B, 3) // B replaces C under 3; C is still under 8
	TEST_ASSERT(!QDELETED(C) && H.kid_table[8] == C, "a child that still sits under another key is not disposed of")
	TEST_ASSERT_EQUAL(owner_of(C), H, "and stays owned")
	qdel(C)
	TEST_ASSERT(isnull(H.kid_table[8]), "a deleted child left its key")
	TEST_ASSERT_EQUAL(H.kid_table[3], B, "B sits under 3 and 40")
	var/datum/relperf_member/taken = rel_take(H, nameof(H.kid_table), key = 40)
	TEST_ASSERT_EQUAL(taken, B, "rel_take by key returns the child")
	TEST_ASSERT(!QDELETED(B) && H.kid_table[3] == B, "B still sits under key 3, so it stays owned")
	rel_add(H, nameof(H.kid_table), null, 3)
	TEST_ASSERT(QDELETED(B), "emptying a key disposes of its child")
	TEST_ASSERT_EQUAL(length(H.kid_table), 0, "the table is empty")
	var/datum/relperf_member/D = new
	rel_add(H, nameof(H.kid_table), D, 100)
	rel_clear(H, nameof(H.kid_table))
	TEST_ASSERT(QDELETED(D) && !length(H.kid_table), "rel_clear disposes of every child")
	qdel(H)

/// A keyed owns_many in a plain list with a text key (the original keyed shape) still releases a deleted child without a scan.
/datum/unit_test/dq_rel_core_owned_text_keys

/datum/unit_test/dq_rel_core_owned_text_keys/Run()
	var/datum/relperf_holder/H = new
	var/datum/relperf_member/A = new
	var/datum/relperf_member/B = new
	rel_add(H, nameof(H.kid_text), A, "a")
	rel_add(H, nameof(H.kid_text), B, "b")
	TEST_ASSERT_EQUAL(H.kid_text["a"], A, "A sits under its text key")
	TEST_ASSERT_EQUAL(owner_of(A), H, "and is owned")
	qdel(A)
	TEST_ASSERT(isnull(H.kid_text["a"]) && H.kid_text["b"] == B, "a deleted child left its key and only its key")
	var/datum/relperf_member/taken = rel_take(H, nameof(H.kid_text), key = "b")
	TEST_ASSERT(taken == B && isnull(owner_of(B)), "rel_take by text key hands the child back unowned")
	qdel(B)
	qdel(H)

/// A long owns_many list: a child already stamped as owned is not added twice, and a deleted child leaves.
/datum/unit_test/dq_rel_core_owned_long_list

/datum/unit_test/dq_rel_core_owned_long_list/Run()
	var/datum/relperf_holder/H = new
	var/list/made = list()
	for(var/i in 1 to 120)
		var/datum/relperf_member/M = new
		made += M
		rel_add(H, nameof(H.kids), M)
	for(var/datum/relperf_member/M as anything in made)
		rel_add(H, nameof(H.kids), M)
	TEST_ASSERT_EQUAL(length(H.kids), 120, "adding an owned child twice keeps one")
	qdel(made[60])
	TEST_ASSERT_EQUAL(length(H.kids), 119, "a deleted child left the long list")
	rel_remove(H, nameof(H.kids), made[1])
	TEST_ASSERT_EQUAL(length(H.kids), 118, "a removed child left it")
	var/datum/relperf_member/second = made[2]
	var/datum/relperf_member/last = made[120]
	qdel(H)
	TEST_ASSERT(QDELETED(second) && QDELETED(last), "the holder takes its children with it")

/// Handles: the same datum gives the same text; a deleted datum's handle stays dead when its slot is reused; a turf's handle is stable and
/// stops resolving when its z-level's generation moves on.
/datum/unit_test/dq_rel_core_handles

/datum/unit_test/dq_rel_core_handles/Run()
	var/datum/relperf_member/A = new
	var/h = entity_handle(A)
	TEST_ASSERT(is_entity_handle(h), "a datum's handle has the handle shape")
	TEST_ASSERT_EQUAL(entity_handle(A), h, "asking again gives the same handle")
	TEST_ASSERT_EQUAL(entity_handle_of(A), h, "entity_handle_of reads it without allocating")
	TEST_ASSERT_EQUAL(resolve_handle(h), A, "it resolves")
	TEST_ASSERT(entity_handle_is(h, A), "entity_handle_is agrees")
	qdel(A)
	TEST_ASSERT_NULL(resolve_handle(h), "a deleted datum's handle stops resolving")
	TEST_ASSERT_NULL(entity_handle(A), "and a deleted datum is given no handle")
	// the slot is reused: the old handle must not name the newcomer
	var/datum/relperf_member/B = new
	var/h2 = entity_handle(B)
	TEST_ASSERT(h2 != h, "a reused slot gives a new handle text")
	TEST_ASSERT_EQUAL(resolve_handle(h2), B, "the new handle resolves to the new datum")
	TEST_ASSERT_NULL(resolve_handle(h), "the old handle still names nothing after the slot was reused")
	var/list/seen = list()
	for(var/i in 1 to 50)
		var/datum/relperf_member/T = new
		var/th = entity_handle(T)
		TEST_ASSERT(isnull(seen[th]), "a handle text is never given twice")
		seen[th] = TRUE
		qdel(T)
		TEST_ASSERT_NULL(resolve_handle(th), "each deleted datum's handle is dead")
	TEST_ASSERT_NULL(resolve_handle("junk"), "junk resolves to nothing")
	TEST_ASSERT_NULL(resolve_handle("999999:0"), "an unissued slot text resolves to nothing")
	TEST_ASSERT_NULL(resolve_handle(null), "null resolves to nothing")
	qdel(B)
	// turfs
	var/turf/T = locate(world.maxx / 2, world.maxy / 2, 1)
	var/th = entity_handle(T)
	TEST_ASSERT(is_entity_handle(th), "a turf's handle has the handle shape")
	TEST_ASSERT_EQUAL(entity_handle(T), th, "a turf's handle is stable")
	TEST_ASSERT_EQUAL(resolve_handle(th), T, "and resolves to the turf")
	var/turf/other = get_step(T, EAST)
	TEST_ASSERT(entity_handle(other) != th && resolve_handle(entity_handle(other)) == other, "a neighbouring turf has its own handle")
	relation_z_generation_bump(T.z)
	TEST_ASSERT_NULL(resolve_handle(th), "a turf handle stops resolving when its z-level's generation moves on")
	GLOB.om_z_generations[T.z]-- // the test map's z-level was not really released
	TEST_ASSERT_EQUAL(resolve_handle(th), T, "and resolves again once the generation is back")

// Owned lists of every shape (code/engine/refs/ownership.dm): a text-keyed plain list, a plain list of members and a set (alist). Each is added to, removed
// from by value and by key, and disposed of when its owner is destroyed. A text-keyed plain list holds its members as values, so removing a member by value
// goes through the holder key index (own_remove()), the path respawn records, flows and cooldown rows use.

/datum/own_keyed_holder
	var/list/by_key
	var/list/plain
	var/alist/member_set = alist()

CAPABILITIES(/datum/own_keyed_holder)
	owns_many(nameof(by_key))
	owns_many(nameof(plain))
	owns_many(nameof(member_set))

/datum/own_keyed_member
	var/label = "member"

/datum/unit_test/ownership_keyed_text_add_remove

/datum/unit_test/ownership_keyed_text_add_remove/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/own_keyed_holder/H = new
	var/datum/own_keyed_member/A = new
	var/datum/own_keyed_member/B = new
	rel_add(H, nameof(H.by_key), A, "a")
	rel_add(H, nameof(H.by_key), B, "b")
	TEST_ASSERT_EQUAL(H.by_key["a"], A, "a member is added under its key")
	TEST_ASSERT_EQUAL(H.by_key["b"], B, "a second member is added under its own key")
	TEST_ASSERT_EQUAL(owner_of(A), H, "a keyed member is owned")
	TEST_ASSERT(rel_remove(H, nameof(H.by_key), A), "removing a keyed member by value succeeds")
	TEST_ASSERT(isnull(H.by_key["a"]) && length(H.by_key) == 1, "the member key goes with it, the other stays")
	TEST_ASSERT(QDELETED(A), "an owned member removed by value is disposed of")
	TEST_ASSERT(!QDELETED(B) && owner_of(B) == H, "the other member is untouched")
	TEST_ASSERT(!rel_remove(H, nameof(H.by_key), A), "removing it again refuses")
	TEST_ASSERT(rel_remove(H, nameof(H.by_key), B), "removing the last member succeeds")
	TEST_ASSERT(!length(H.by_key), "the emptied list holds nothing")
	TEST_ASSERT(QDELETED(B), "the last member is disposed of")
	qdel(H)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(!length(capture), "no reports: [json_encode(capture)]")

/datum/unit_test/ownership_keyed_text_take_by_key

/datum/unit_test/ownership_keyed_text_take_by_key/Run()
	var/datum/own_keyed_holder/H = new
	var/datum/own_keyed_member/A = new
	var/datum/own_keyed_member/B = new
	rel_add(H, nameof(H.by_key), A, "a")
	rel_add(H, nameof(H.by_key), B, "b")
	TEST_ASSERT_EQUAL(rel_take(H, nameof(H.by_key), key = "b"), B, "taking by key returns the member")
	TEST_ASSERT(isnull(H.by_key["b"]) && isnull(owner_of(B)) && !QDELETED(B), "a taken member is unowned and alive")
	// A member under two keys stays owned until its last key goes.
	rel_add(H, nameof(H.by_key), A, "a2")
	TEST_ASSERT_EQUAL(rel_take(H, nameof(H.by_key), key = "a"), A, "taking one of two keys returns the member")
	TEST_ASSERT_EQUAL(owner_of(A), H, "a member that still sits under another key stays owned")
	TEST_ASSERT_EQUAL(H.by_key["a2"], A, "and keeps the other key")
	TEST_ASSERT(rel_remove(H, nameof(H.by_key), A), "removing it by value takes its last key")
	TEST_ASSERT(!length(H.by_key) && QDELETED(A), "the list is empty and the member disposed of")
	qdel(B)
	qdel(H)

/datum/unit_test/ownership_keyed_member_under_two_keys

/datum/unit_test/ownership_keyed_member_under_two_keys/Run()
	var/datum/own_keyed_holder/H = new
	var/datum/own_keyed_member/A = new
	rel_add(H, nameof(H.by_key), A, "x")
	rel_add(H, nameof(H.by_key), A, "y")
	TEST_ASSERT(rel_remove(H, nameof(H.by_key), A), "a member under two keys is removed by value")
	TEST_ASSERT(!length(H.by_key), "both keys went")
	TEST_ASSERT(QDELETED(A), "and the member was disposed of once")
	qdel(H)

/datum/unit_test/ownership_keyed_dispose_on_owner_destroy

/datum/unit_test/ownership_keyed_dispose_on_owner_destroy/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/own_keyed_holder/H = new
	var/datum/own_keyed_member/text_a = new
	var/datum/own_keyed_member/text_b = new
	var/datum/own_keyed_member/plain_a = new
	var/datum/own_keyed_member/set_a = new
	rel_add(H, nameof(H.by_key), text_a, "a")
	rel_add(H, nameof(H.by_key), text_b, "b")
	rel_add(H, nameof(H.plain), plain_a)
	rel_add(H, nameof(H.member_set), set_a)
	qdel(H)
	TEST_ASSERT(QDELETED(text_a) && QDELETED(text_b), "destroying the owner deletes its text-keyed members")
	TEST_ASSERT(QDELETED(plain_a), "and its plain-list members")
	TEST_ASSERT(QDELETED(set_a), "and its set members")
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(!length(capture), "no reports: [json_encode(capture)]")

/datum/unit_test/ownership_plain_and_set_add_remove

/datum/unit_test/ownership_plain_and_set_add_remove/Run()
	var/datum/own_keyed_holder/H = new
	var/datum/own_keyed_member/P = new
	var/datum/own_keyed_member/Q = new
	var/datum/own_keyed_member/S = new
	rel_add(H, nameof(H.plain), P)
	rel_add(H, nameof(H.plain), Q)
	rel_add(H, nameof(H.member_set), S)
	TEST_ASSERT((P in H.plain) && (Q in H.plain) && (S in H.member_set), "members are added to the plain list and the set")
	TEST_ASSERT(rel_remove(H, nameof(H.plain), P), "a plain list member is removed by value")
	TEST_ASSERT(!(P in H.plain) && (Q in H.plain) && QDELETED(P), "only that member goes, and it is disposed of")
	TEST_ASSERT_EQUAL(rel_take(H, nameof(H.plain), Q), Q, "a plain list member is taken by value")
	TEST_ASSERT(isnull(owner_of(Q)) && !QDELETED(Q), "a taken member is unowned and alive")
	TEST_ASSERT(rel_remove(H, nameof(H.member_set), S), "a set member is removed by value")
	TEST_ASSERT(!(S in H.member_set) && QDELETED(S), "and disposed of")
	TEST_ASSERT(!rel_remove(H, nameof(H.member_set), S), "removing it again refuses")
	qdel(Q)
	qdel(H)

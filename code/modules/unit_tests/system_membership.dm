/// System membership: O(1) join and swap-remove leave, hooks, and the one-shot on_members_ready() pass.

/datum/system/test_members
	abstract_type = /datum/system/test_members
	var/joined = 0
	var/left = 0
	var/ready_calls = 0
	var/members_at_ready = 0

/datum/system/test_members/on_join(atom/A)
	joined++

/datum/system/test_members/on_leave(atom/A)
	left++

/datum/system/test_members/on_members_ready()
	ready_calls++
	members_at_ready = member_count()

/datum/unit_test/system_membership

/datum/unit_test/system_membership/Run()
	var/datum/system/test_members/S = new
	var/atom/a = allocate(/obj/effect/landmark)
	var/atom/b = allocate(/obj/effect/landmark)
	var/atom/c = allocate(/obj/effect/landmark)
	var/atom/d = allocate(/obj/effect/landmark)

	// Members join before the system is ready: recorded at once, evaluated later.
	TEST_ASSERT(S.kernel_join(a), "first join is new")
	TEST_ASSERT(S.kernel_join(b), "second join is new")
	TEST_ASSERT(S.kernel_join(c), "third join is new")
	TEST_ASSERT(!S.kernel_join(b), "a second join of the same atom is refused")
	TEST_ASSERT_EQUAL(length(S.member_list()), 3, "three members recorded")
	TEST_ASSERT_EQUAL(S.joined, 3, "on_join ran once per new member")
	TEST_ASSERT_EQUAL(S.ready_calls, 0, "on_members_ready() waits for the boot pass")
	TEST_ASSERT(S.is_member(a) && S.is_member(b) && S.is_member(c), "is_member sees them")
	TEST_ASSERT(!S.is_member(d), "a non-member is not a member")

	// Swap-remove: the last member takes the freed slot and its index follows.
	TEST_ASSERT(S.kernel_leave(a), "leaving removes a member")
	TEST_ASSERT(!S.kernel_leave(a), "leaving twice is a no-op")
	TEST_ASSERT(!S.kernel_leave(d), "a non-member cannot leave")
	TEST_ASSERT_EQUAL(S.member_list()[1], c, "the last member took the vacated slot")
	TEST_ASSERT(S.is_member(c) && S.is_member(b), "the others stay members")
	TEST_ASSERT(!S.is_member(a), "the leaver is gone")

	// The bulk pass runs once and sees every member that joined before it.
	S.kernel_members_ready()
	S.kernel_members_ready()
	TEST_ASSERT_EQUAL(S.ready_calls, 1, "on_members_ready() runs exactly once")
	TEST_ASSERT_EQUAL(S.members_at_ready, 2, "the pass saw the members that joined during boot")
	TEST_ASSERT(S.members_ready, "the system is marked ready")

	// Late joiners are members at once.
	TEST_ASSERT(S.kernel_join(d), "a late join is new")
	TEST_ASSERT_EQUAL(length(S.member_list()), 3, "late joiner recorded")

	// Emptying the system frees its lists.
	S.kernel_leave(b)
	S.kernel_leave(c)
	S.kernel_leave(d)
	TEST_ASSERT_EQUAL(S.member_count(), 0, "an emptied system has no members")
	TEST_ASSERT_EQUAL(S.left, 4, "every leave ran on_leave")

	// metrics() is the telemetry channel.
	var/list/m = S.metrics()
	TEST_ASSERT_EQUAL(m["members"], 0, "metrics report the member count")

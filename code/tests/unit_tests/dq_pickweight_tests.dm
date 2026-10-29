// pickweight(): weight 0 is never picked, a null weight counts as 1, and the caller's list is never written.

#define PICKWEIGHT_ROLLS 4000

/// A weight of 0 is never chosen, however many rolls.
/datum/unit_test/dq_pickweight_zero_never_picked

/datum/unit_test/dq_pickweight_zero_never_picked/Run()
	var/list/L = list("a" = 0, "b" = 3, "c" = 0, "d" = 1)
	for(var/i in 1 to PICKWEIGHT_ROLLS)
		var/picked = pickweight(L)
		TEST_ASSERT(picked == "b" || picked == "d", "picked [picked] though its weight is 0")

/// A plain list entry has a null weight and counts as 1.
/datum/unit_test/dq_pickweight_null_weight_is_one

/datum/unit_test/dq_pickweight_null_weight_is_one/Run()
	var/list/L = list("x", "y")
	var/list/seen = list()
	for(var/i in 1 to PICKWEIGHT_ROLLS)
		seen[pickweight(L)] = TRUE
	TEST_ASSERT(seen["x"] && seen["y"], "both plain entries are reachable")
	var/list/mixed = list("p" = 0, "q")
	for(var/i in 1 to 200)
		TEST_ASSERT_EQUAL(pickweight(mixed), "q", "the null-weight entry is the only eligible one")

/// The input list is the same after the call: no assoc conversion, no weight written back.
/datum/unit_test/dq_pickweight_input_unchanged

/datum/unit_test/dq_pickweight_input_unchanged/Run()
	var/list/plain = list("x", "y", "z")
	var/list/plain_copy = plain.Copy()
	var/list/weighted = list("a" = 0, "b" = 2, "c")
	var/list/weighted_copy = weighted.Copy()
	for(var/i in 1 to 50)
		pickweight(plain)
		pickweight(weighted)
	TEST_ASSERT_EQUAL(length(plain), length(plain_copy), "plain list length")
	for(var/item in plain)
		TEST_ASSERT(isnull(plain[item]), "plain entry [item] gained a value")
	TEST_ASSERT(plain ~= plain_copy, "plain list contents")
	TEST_ASSERT_EQUAL(weighted["a"], 0, "an explicit 0 stays 0")
	TEST_ASSERT_EQUAL(weighted["b"], 2, "an explicit weight stays")
	TEST_ASSERT(isnull(weighted["c"]), "a null weight stays null")
	TEST_ASSERT_EQUAL(length(weighted), length(weighted_copy), "weighted list length")

/// Empty and all-zero lists return null.
/datum/unit_test/dq_pickweight_nothing_eligible_is_null

/datum/unit_test/dq_pickweight_nothing_eligible_is_null/Run()
	TEST_ASSERT_NULL(pickweight(list()), "empty list")
	TEST_ASSERT_NULL(pickweight(null), "null list")
	TEST_ASSERT_NULL(pickweight(list("a" = 0, "b" = 0)), "all-zero list")

/// Picks follow the weights (3:1 here), within a wide margin.
/datum/unit_test/dq_pickweight_proportions

/datum/unit_test/dq_pickweight_proportions/Run()
	var/list/L = list("heavy" = 3, "light" = 1)
	var/heavy = 0
	for(var/i in 1 to PICKWEIGHT_ROLLS)
		if(pickweight(L) == "heavy")
			heavy++
	var/share = heavy / PICKWEIGHT_ROLLS
	TEST_ASSERT(share > 0.70 && share < 0.80, "heavy share was [share], expected about 0.75")

#undef PICKWEIGHT_ROLLS

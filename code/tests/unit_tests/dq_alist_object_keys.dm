/// What BYOND's alist does with a reference to an object used as a key. Logged, because the answer decides where an alist may hold objects.
/datum/unit_test/dq_alist_object_key_refs

/datum/unit_test/dq_alist_object_key_refs/proc/local_alist(datum/D)
	var/alist/A = alist()
	A[D] = TRUE

/datum/unit_test/dq_alist_object_key_refs/proc/local_list(datum/D)
	var/list/L = list()
	L[D] = TRUE

/datum/unit_test/dq_alist_object_key_refs/proc/removed_key(datum/D)
	var/alist/A = alist()
	A[D] = TRUE
	A -= D

/datum/unit_test/dq_alist_object_key_refs/proc/cut_key(datum/D)
	var/alist/A = alist()
	A[D] = TRUE
	A.Cut()

/datum/unit_test/dq_alist_object_key_refs/proc/object_value(datum/D)
	var/alist/A = alist()
	A[1] = D

/datum/unit_test/dq_alist_object_key_refs/Run()
	var/datum/D = new
	var/base = refcount(D)
	local_list(D)
	TEST_ASSERT_EQUAL(refcount(D), base, "a plain list releases an object key when freed")
	removed_key(D)
	TEST_ASSERT_EQUAL(refcount(D), base, "an alist whose object key was removed keeps nothing")
	cut_key(D)
	TEST_ASSERT_EQUAL(refcount(D), base, "an alist whose object keys were cut keeps nothing")
	object_value(D)
	TEST_ASSERT_EQUAL(refcount(D), base, "an alist releases an object value when freed")
	// The BYOND bug itself. When this fails BYOND has fixed it: delete this line and the warning on keyed alists.
	local_alist(D)
	TEST_ASSERT_EQUAL(refcount(D), base + 1, "an alist freed with an object key still leaks that reference")

// The reference finder's fixtures (find_reference_sanity.dm). They live apart from the tests because that file is only compiled with REFERENCE_TRACKING_DEBUG,
// which the declaration generator cannot see: a CAPABILITIES block there would be generated for a type the build may not define.

/atom/movable/ref_holder
	var/static/atom/movable/ref_test/static_test
	var/atom/movable/ref_test/test
	var/list/test_list = list()
	var/list/test_assoc_list = list()


CAPABILITIES(/atom/movable/ref_holder)
	ref_one(nameof(test))

/atom/movable/ref_holder/on_destroy(force)
	// A static var outlives the instance: clear it by hand.
	rel_clear(src, nameof(static_test))
	..()

/atom/movable/ref_test
	// Gotta make sure we do a full check
	#ifdef REFERENCE_TRACKING
	references_to_clear = INFINITY
	#endif
	var/atom/movable/ref_test/self_ref

CAPABILITIES(/atom/movable/ref_test)
	ref_one(nameof(self_ref))

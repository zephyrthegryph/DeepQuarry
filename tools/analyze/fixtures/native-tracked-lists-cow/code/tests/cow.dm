/datum/cow_probe/test
	var/list/test_items

TRACKED(/datum/cow_probe/test, test_items)

#if 0
CAPABILITIES_PART(/datum/cow_probe/test, test_cow)
	per_type(nameof(test_items), PROC_REF(build), copy_on_write = TRUE)
#endif

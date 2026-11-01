/// A destroyed object ends the lookup reads that watch it. It used to walk the whole read index to find them, so each qdel cost the size of the index:
/// a thousand-object blast made that quadratic. The producer's own keys are found by name now.
/datum/unit_test/dq_lookup_reads_source_gone_unbinds_its_readers

/datum/unit_test/dq_lookup_reads_source_gone_unbinds_its_readers/Run()
	var/datum/producer = new
	var/datum/other = new
	var/datum/lookup_read_binding/binding = new
	binding.add_read(producer, "first")
	binding.add_read(producer, "second")
	binding.add_read(other, "third")
	var/producer_ref = "[REF(producer)]"
	TEST_ASSERT_EQUAL(length(GLOB.lookup_read_producer_keys[producer_ref]), 2, "both of the producer's keys are listed under it")
	TEST_ASSERT_NOTNULL(GLOB.lookup_read_index["[producer_ref]|first"], "the read is indexed")
	lookup_reads_source_gone(producer)
	// The binding has no live reader, so being told its source is gone unbinds all of it.
	TEST_ASSERT_NULL(GLOB.lookup_read_index["[producer_ref]|first"], "the first read left the index")
	TEST_ASSERT_NULL(GLOB.lookup_read_index["[producer_ref]|second"], "the second read left the index")
	TEST_ASSERT_NULL(GLOB.lookup_read_producer_keys[producer_ref], "nothing is left listed under the producer")
	TEST_ASSERT_NULL(GLOB.lookup_read_producer_keys["[REF(other)]"], "the other producer's read went with the binding")
	qdel(binding)
	qdel(producer)
	qdel(other)

/// What a destroyed object costs does not grow with the number of reads other objects hold.
/datum/unit_test/dq_lookup_reads_source_gone_does_not_scan_the_index

/datum/unit_test/dq_lookup_reads_source_gone_does_not_scan_the_index/Run()
	var/list/filler = list()
	for(var/i in 1 to 20000)
		var/key = "filler[i]|read"
		GLOB.lookup_read_index[key] = list()
		filler += key
	var/datum/producer = new
	var/stamp = TICK_USAGE_REAL
	for(var/i in 1 to 2000)
		lookup_reads_source_gone(producer)
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - stamp)
	for(var/key in filler)
		GLOB.lookup_read_index -= key
	qdel(producer)
	// 2000 destroys over 20000 entries was about 40 million key comparisons (seconds); by name it is a lookup each.
	TEST_ASSERT(ms < 500, "2000 destroyed objects cost [round(ms)] ms with 20000 reads in the index: the index is being scanned")

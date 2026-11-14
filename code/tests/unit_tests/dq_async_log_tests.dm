// The game's log files are written by a verdigris writer thread (code/host/helpers/logging/async_log.dm): lines keep the order they
// were queued in, a flush leaves them all on disk, and the writer starts again after world shutdown stopped it.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#define DQ_ASYNC_LOG_FILE "data/dq_async_log_test.log"
/// Its own file: a registered header stays with its path, so no other test may share it.
#define DQ_ASYNC_HEADER_FILE "data/dq_async_log_header_test.log"

/// Lines queued across two files land whole and in call order, and a flush is what makes them readable.
/datum/unit_test/dq_async_log_keeps_order

/datum/unit_test/dq_async_log_keeps_order/Run()
	var/second = "data/dq_async_log_test_b.log"
	fdel(DQ_ASYNC_LOG_FILE)
	fdel(second)
	var/list/before = log_file_counts()
	var/expected = ""
	var/expected_b = ""
	for(var/i in 1 to 300)
		log_file_append(DQ_ASYNC_LOG_FILE, "line [i]\n", FALSE)
		expected += "line [i]\n"
		if(!(i % 3))
			log_file_append(second, "b [i]\n", FALSE)
			expected_b += "b [i]\n"
	log_file_flush()
	var/list/after = log_file_counts()
	// The world logs through the same writer meanwhile, so the counts may exceed the test's own 400 lines.
	TEST_ASSERT(after[1] - before[1] >= 400, "every line was queued")
	TEST_ASSERT_EQUAL(after[2], after[1], "and every queued line was written once the flush returned")
	TEST_ASSERT_EQUAL(after[3] - before[3], 0, "and none failed")
	TEST_ASSERT_EQUAL(file2text(DQ_ASYNC_LOG_FILE), expected, "the first file holds its lines in call order")
	TEST_ASSERT_EQUAL(file2text(second), expected_b, "and the second holds its own")
	fdel(DQ_ASYNC_LOG_FILE)
	fdel(second)

/// A timestamped line carries the stamp and the newline rust-g used to add.
/datum/unit_test/dq_async_log_formats_a_line

/datum/unit_test/dq_async_log_formats_a_line/Run()
	fdel(DQ_ASYNC_LOG_FILE)
	log_file_append(DQ_ASYNC_LOG_FILE, "hello", TRUE)
	log_file_flush()
	var/text = file2text(DQ_ASYNC_LOG_FILE)
	TEST_ASSERT(copytext(text, 1, 2) == "\[" && copytext(text, 25, 27) == "] " && copytext(text, 27) == "hello\n", "the line is stamped and ends its line ([text])")
	fdel(DQ_ASYNC_LOG_FILE)

/// What world shutdown and a soft reboot do: stop the writer (it flushes first), and the next line starts it again with nothing lost.
/datum/unit_test/dq_async_log_flushes_on_stop

/datum/unit_test/dq_async_log_flushes_on_stop/Run()
	fdel(DQ_ASYNC_LOG_FILE)
	log_file_append(DQ_ASYNC_LOG_FILE, "before stop\n", FALSE)
	log_file_stop()
	TEST_ASSERT_EQUAL(file2text(DQ_ASYNC_LOG_FILE), "before stop\n", "stopping the writer wrote what was queued")
	log_file_append(DQ_ASYNC_LOG_FILE, "after stop\n", FALSE)
	log_file_flush()
	TEST_ASSERT_EQUAL(file2text(DQ_ASYNC_LOG_FILE), "before stop\nafter stop\n", "a line queued after the stop starts the writer again, in order")
	fdel(DQ_ASYNC_LOG_FILE)

/// A line is queued without waiting for the disk: a thousand lines take the tick a small share of what a thousand file writes did.
/datum/unit_test/dq_async_log_does_not_block

/datum/unit_test/dq_async_log_does_not_block/Run()
	fdel(DQ_ASYNC_LOG_FILE)
	var/started = TICK_USAGE_REAL
	for(var/i in 1 to 1000)
		log_file_append(DQ_ASYNC_LOG_FILE, "line [i]\n", FALSE)
	var/queue_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	log_file_flush()
	log_test("async log: 1000 lines queued in [round(queue_ms, 0.01)] ms ([round(queue_ms, 0.001)] ms a line)")
	TEST_ASSERT(queue_ms < 100, "queuing 1000 lines took [round(queue_ms, 0.1)] ms")
	fdel(DQ_ASYNC_LOG_FILE)

/// log_world() and every category log write (the readable and json files) go to the writer thread: none writes a file, or asks the disk
/// whether one exists, on the calling thread. The counter on the synchronous path (log_file_write_sync/log_file_append_sync) stays put.
/datum/unit_test/dq_log_world_writes_no_file_synchronously

/datum/unit_test/dq_log_world_writes_no_file_synchronously/Run()
	var/sync_before = GLOB.log_sync_writes
	var/list/counts_before = log_file_counts()
	for(var/i in 1 to 50)
		log_world("dq_log_sync_probe [i]")
	log_game("dq_log_sync_probe game")
	log_file_flush()
	var/list/counts_after = log_file_counts()
	TEST_ASSERT_EQUAL(GLOB.log_sync_writes, sync_before, "log_world and category logs made no synchronous file write")
	TEST_ASSERT(counts_after[1] - counts_before[1] >= 51, "the lines were queued to the writer ([counts_after[1] - counts_before[1]])")
	TEST_ASSERT_EQUAL(counts_after[2], counts_after[1], "and written")

/// A log file deleted while the round runs starts again with its header, put back by the writer thread when it next opens the file.
/datum/unit_test/dq_log_file_deleted_gets_its_header_back

/datum/unit_test/dq_log_file_deleted_gets_its_header_back/Run()
	fdel(DQ_ASYNC_HEADER_FILE)
	log_file_set_header(DQ_ASYNC_HEADER_FILE, "header\n")
	log_file_append(DQ_ASYNC_HEADER_FILE, "one\n", FALSE)
	log_file_flush()
	TEST_ASSERT_EQUAL(file2text(DQ_ASYNC_HEADER_FILE), "header\none\n", "the first open of a missing file starts it with the header")
	var/recovered = log_file_counts()[4]
	log_file_append(DQ_ASYNC_HEADER_FILE, "two\n", FALSE)
	log_file_flush()
	TEST_ASSERT_EQUAL(file2text(DQ_ASYNC_HEADER_FILE), "header\none\ntwo\n", "an existing file only gets the line")
	fdel(DQ_ASYNC_HEADER_FILE)
	log_file_append(DQ_ASYNC_HEADER_FILE, "three\n", FALSE)
	log_file_flush()
	TEST_ASSERT_EQUAL(file2text(DQ_ASYNC_HEADER_FILE), "header\nthree\n", "a deleted file starts again with its header")
	TEST_ASSERT(log_file_counts()[4] > recovered, "and the recovery is counted")
	fdel(DQ_ASYNC_HEADER_FILE)

#undef DQ_ASYNC_LOG_FILE
#undef DQ_ASYNC_HEADER_FILE

#endif

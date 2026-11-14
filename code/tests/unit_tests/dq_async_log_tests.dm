// The game's log files are written by a verdigris writer thread (code/host/helpers/logging/async_log.dm): lines keep the order they
// were queued in, a flush leaves them all on disk, and the writer starts again after world shutdown stopped it.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#define DQ_ASYNC_LOG_FILE "data/dq_async_log_test.log"

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

#undef DQ_ASYNC_LOG_FILE

#endif

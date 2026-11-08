// A client's recent chat messages (code/library/ui/tgchat/chat_history.dm): kept in order, found for a resend, replayed after a sequence,
// and only the newest CHAT_HISTORY_SIZE kept.
/datum/unit_test/dq_chat_history_ring
/datum/unit_test/dq_chat_history_ring/Run()
	var/datum/chat_history/history = new
	TEST_ASSERT_EQUAL(length(history.since(-1)), 0, "nothing kept before the first message")
	for(var/sequence in 0 to 9)
		history.keep(sequence, "message [sequence]")
	TEST_ASSERT_EQUAL(history.find(4), "message 4", "a kept message is found for a resend")
	TEST_ASSERT_NULL(history.find(10), "a message never sent is not")
	TEST_ASSERT_NULL(history.find(-1), "nor a nonsense sequence")
	TEST_ASSERT_EQUAL(jointext(history.since(6), ","), "message 7,message 8,message 9", "a moved window gets what came after what it showed, oldest first")
	for(var/i in 1 to CHAT_RELIABILITY_MAX_RESENDS + 1)
		TEST_ASSERT(history.take_resend(4), "a lost message is resent a few times")
	TEST_ASSERT(!history.take_resend(4), "then given up on")
	TEST_ASSERT(!history.take_resend(99), "a message not kept is never resent")
	// Past the ring's size the oldest go, and what is left stays in order.
	for(var/sequence in 10 to CHAT_HISTORY_SIZE + 24)
		history.keep(sequence, "message [sequence]")
	TEST_ASSERT_NULL(history.find(0), "the oldest message was overwritten")
	var/list/all = history.since(-1)
	TEST_ASSERT_EQUAL(length(all), CHAT_HISTORY_SIZE, "the ring keeps exactly its size")
	TEST_ASSERT_EQUAL(all[1], "message 25", "starting at the oldest still kept")
	TEST_ASSERT_EQUAL(all[length(all)], "message [CHAT_HISTORY_SIZE + 24]", "and ending at the newest")

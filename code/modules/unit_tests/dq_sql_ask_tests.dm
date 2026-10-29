// Reads that carry on from their answer (sql_ask(), sql_answer_rows(), code/engine/io/db.dm) and the callers converted from prompt flows
// (the login steps, the polls, the chat commands). No database is needed: without a connection the SQL backend answers with an error
// through the real I/O lane, and the steps' callbacks are called with canned answers where a test needs rows.

/// Owner of the reads started below.
/datum/sql_ask_probe
	var/list/log

/datum/sql_ask_probe/proc/start(tag)
	return sql_ask(src, "SELECT :x", list("x" = 1), PROC_REF(answered), tag)

/datum/sql_ask_probe/proc/answered(list/result, error, tag)
	LAZYADD(log, "[tag]:[isnull(result) ? "null" : "result"]:[error ? "error" : "ok"]")

/datum/unit_test/io_transport/sql_ask_without_connection_answers_with_error

/datum/unit_test/io_transport/sql_ask_without_connection_answers_with_error/run_io()
	var/datum/sql_ask_probe/P = allocate(/datum/sql_ask_probe)
	TEST_ASSERT(P.start("a"), "the read starts and returns a job id at once")
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 1, "one SQL job is in flight")
	TEST_ASSERT_NULL(P.log, "nothing waits: the answer has not arrived yet")
	test_time(0.1 SECONDS)
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(jointext(P.log || list(), ","), "a:null:error", "the callback gets no result and the error, with the context after it")
	TEST_ASSERT(!io_job_count(), "the answered job leaves the queue")

/datum/unit_test/io_transport/sql_ask_drops_answer_when_owner_gone

/datum/unit_test/io_transport/sql_ask_drops_answer_when_owner_gone/run_io()
	var/datum/sql_ask_probe/P = allocate(/datum/sql_ask_probe)
	P.start("b")
	var/list/witness = P.log
	qdel(P)
	test_time(0.1 SECONDS)
	test_time(0.1 SECONDS)
	TEST_ASSERT_NULL(witness, "a deleted owner never gets its answer")
	TEST_ASSERT(!io_job_count(), "the orphaned answer is drained")

/datum/unit_test/sql_answer_rows_reads_rows_and_nulls_errors

/datum/unit_test/sql_answer_rows_reads_rows_and_nulls_errors/Run()
	var/list/rows = sql_answer_rows(list("rows" = list(list(1, "a"), list(2, "b"))), null, "test")
	TEST_ASSERT_EQUAL(length(rows), 2, "the answer's rows come back as positional lists")
	TEST_ASSERT_EQUAL(rows[2][2], "b", "with their columns in order")
	var/list/none = sql_answer_rows(list("rows" = null), null, "test")
	TEST_ASSERT(islist(none) && !length(none), "a read that matched nothing is an empty list, not null")
	TEST_ASSERT_NULL(sql_answer_rows(null, "CONNECTION OFFLINE", "test"), "a failed read is null")

// ---------------------------------------------------------------- login: an answer reaches the client it was started for

/// Stands in for a connected client: the login answer dispatcher only looks it up by ckey, checks its computer id and calls a proc on it.
/datum/login_probe_client
	var/computer_id = "cid-1"
	var/login_serial = 5
	var/login_pending = TRUE
	var/list/log

/datum/login_probe_client/proc/login_admit()
	login_pending = FALSE
	LAZYADD(log, "admitted")

/datum/login_probe_client/proc/login_probe_answer(list/result, error, tag, number)
	LAZYADD(log, "[tag]:[number]:[length(result?["rows"])]:[error || "ok"]")

#define LOGIN_PROBE_CKEY "dqloginprobe"

/proc/login_probe_forget()
	GLOB.directory -= LOGIN_PROBE_CKEY

/datum/unit_test/login_answer_reaches_its_client_only

/datum/unit_test/login_answer_reaches_its_client_only/Run()
	defer_cleanup(null, GLOBAL_PROC_REF(login_probe_forget))
	var/datum/login_probe_client/probe = allocate(/datum/login_probe_client)
	GLOB.directory[LOGIN_PROBE_CKEY] = probe
	login_answered(list("rows" = list(list(1))), null, LOGIN_PROBE_CKEY, "cid-1", 5, "login_probe_answer", "ban", 7)
	TEST_ASSERT_EQUAL(jointext(probe.log || list(), ","), "ban:7:1:ok", "the step runs on the client with the answer and its context")
	login_answered(null, "boom", LOGIN_PROBE_CKEY, "cid-1", 5, "login_probe_answer", "ip", 8)
	TEST_ASSERT_EQUAL(probe.log[2], "ip:8:0:boom", "a failed read reaches the step as an error")
	login_answered(list("rows" = list()), null, LOGIN_PROBE_CKEY, "cid-2", 5, "login_probe_answer", "late", 9)
	TEST_ASSERT_EQUAL(length(probe.log), 2, "an answer started for another connection of the same ckey is dropped")
	login_answered(list("rows" = list()), null, LOGIN_PROBE_CKEY, "cid-1", 4, "login_probe_answer", "stale", 11)
	TEST_ASSERT_EQUAL(length(probe.log), 2, "an answer asked for an earlier connection of the same computer (another serial) is dropped")
	GLOB.directory -= LOGIN_PROBE_CKEY
	login_answered(list("rows" = list()), null, LOGIN_PROBE_CKEY, "cid-1", 5, "login_probe_answer", "gone", 10)
	TEST_ASSERT_EQUAL(length(probe.log), 2, "an answer for a client that left is dropped")

/datum/unit_test/login_old_timer_does_not_admit_a_new_connection

/datum/unit_test/login_old_timer_does_not_admit_a_new_connection/Run()
	defer_cleanup(null, GLOBAL_PROC_REF(login_probe_forget))
	var/datum/login_probe_client/probe = allocate(/datum/login_probe_client)
	GLOB.directory[LOGIN_PROBE_CKEY] = probe
	login_gate_timeout(LOGIN_PROBE_CKEY, "cid-1", 4)
	TEST_ASSERT(probe.login_pending, "the timer of the connection before it does not open the new connection's gate")
	TEST_ASSERT_NULL(probe.log, "and admits nothing")

/datum/unit_test/login_gate_serials_are_unique

/datum/unit_test/login_gate_serials_are_unique/Run()
	var/before = GLOB.login_seq
	var/first = ++GLOB.login_seq
	var/second = ++GLOB.login_seq
	TEST_ASSERT(first > before && second > first, "each connection takes the next number")
	GLOB.login_seq = before

/datum/unit_test/login_ban_row_refuses_even_if_it_cannot_be_described

/datum/unit_test/login_ban_row_refuses_even_if_it_cannot_be_described/Run()
	TEST_ASSERT_NULL(login_ban_refusal(list()), "no ban row: no refusal")
	TEST_ASSERT_NULL(login_ban_refusal(null), "a failed read: no refusal, the documented fail-open for a read error")
	TEST_ASSERT(login_ban_refusal(list(list("bob"))), "a ban row too short to describe still refuses")
	TEST_ASSERT(login_ban_refusal(list("junk")), "a ban row that is not even a list still refuses")
	var/refusal = login_ban_refusal(list(list("bob", "1.1.1.1", "7", "admin", "griefing", "later", "0", "now", "PERMABAN")))
	TEST_ASSERT(findtext(refusal, "griefing") && findtext(refusal, "admin"), "a whole row gives the reason and the admin")

#undef LOGIN_PROBE_CKEY

// ---------------------------------------------------------------- in-flight guards on double-submitted writes

/datum/unit_test/poll_inflight_guard_drops_a_repeat

/datum/unit_test/poll_inflight_guard_drops_a_repeat/Run()
	var/mob/new_player/voter = allocate(/mob/new_player)
	TEST_ASSERT(voter.poll_begin(7), "the first submit on a poll goes ahead")
	TEST_ASSERT(!voter.poll_begin(7), "a repeat while it is in flight is dropped")
	TEST_ASSERT(voter.poll_begin(8), "another poll is not blocked")
	voter.poll_release(7)
	TEST_ASSERT(voter.poll_begin(7), "the poll is open again once the first is answered")
	voter.poll_vote_written(list("rows" = list()), "boom", 7)
	TEST_ASSERT(voter.poll_begin(7), "a failed write also releases the guard")

/datum/unit_test/io_transport/privacy_vote_guard_and_result

/datum/unit_test/io_transport/privacy_vote_guard_and_result/run_io()
	var/mob/new_player/voter = allocate(/mob/new_player)
	var/datum/privacy_poll_dialog/dialog = allocate(/datum/privacy_poll_dialog, voter)
	dialog.record_vote("SIGNED")
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 1, "the first submit reads the earlier vote")
	dialog.record_vote("SIGNED")
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 1, "a double-submit reads nothing more")
	dialog.vote_checked(list("rows" = list()), null, "SIGNED")
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 2, "no earlier vote: the vote is written")
	dialog.vote_written(null, "boom", "SIGNED")
	TEST_ASSERT(!dialog.answered, "a vote that failed to write is not thanked or marked answered")
	TEST_ASSERT(!dialog.record_inflight, "and the player can try again")
	dialog.vote_checked(null, "boom", "SIGNED")
	TEST_ASSERT(!dialog.answered, "a failed earlier-vote read does not count as answered")
	dialog.vote_written(list("rows" = list()), null, "SIGNED")
	TEST_ASSERT(dialog.answered, "a written vote is answered")

// ---------------------------------------------------------------- polls: each step reads the next only when the one before allows it

/datum/unit_test/io_transport/poll_vote_chain_continues_only_on_a_valid_poll

/datum/unit_test/io_transport/poll_vote_chain_continues_only_on_a_valid_poll/run_io()
	var/mob/new_player/voter = allocate(/mob/new_player)
	voter.vote_poll_question_loaded(list("rows" = list()), null, 5, 9, 0)
	TEST_ASSERT_EQUAL(io_job_count(), 0, "a poll that is not open reads nothing further")
	voter.vote_poll_question_loaded(list("rows" = list(list("start", "end", "q", "TEXT", null))), null, 5, 9, 0)
	TEST_ASSERT_EQUAL(io_job_count(), 0, "a poll of another type reads nothing further")
	voter.vote_poll_question_loaded(null, "boom", 5, 9, 0)
	TEST_ASSERT_EQUAL(io_job_count(), 0, "a failed read is a poll that is not valid")
	voter.vote_poll_question_loaded(list("rows" = list(list("start", "end", "q", "OPTION", null))), null, 5, 9, 0)
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 1, "an open option poll reads the option next")
	voter.vote_poll_option_loaded(list("rows" = list()), null, 5, 9, 0, 0)
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 1, "an option that is not on the poll reads nothing further")
	voter.vote_poll_option_loaded(list("rows" = list(list(9))), null, 5, 9, 0, 0)
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 2, "a valid option reads the earlier votes next")
	voter.vote_poll_earlier_votes_loaded(list("rows" = list(list(3))), null, 5, 9, 0, 0)
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 2, "a player who already voted writes nothing")

/datum/unit_test/io_transport/poll_detail_ignores_a_deselected_poll

/datum/unit_test/io_transport/poll_detail_ignores_a_deselected_poll/run_io()
	var/mob/new_player/viewer = allocate(/mob/new_player)
	var/datum/poll_browser_dialog/dialog = allocate(/datum/poll_browser_dialog, viewer)
	dialog.set_selected_pollid(4)
	dialog.poll_detail_loaded(list("rows" = list(list("start", "end", "Other?", "OTHER", null))), null, 3)
	TEST_ASSERT_NULL(dialog.selected_detail, "the answer for a poll that is no longer selected is dropped")
	dialog.poll_detail_loaded(list("rows" = list()), null, 4)
	TEST_ASSERT_EQUAL(dialog.selected_detail["error"], "Poll question details not found.", "a poll that is gone shows its error")
	dialog.poll_detail_loaded(list("rows" = list(list("start", "end", "Best?", "OTHER", "2"))), null, 4)
	TEST_ASSERT_EQUAL(dialog.selected_detail["question"], "Best?", "a poll of a type with nothing more to read is shown at once")
	TEST_ASSERT_EQUAL(dialog.selected_detail["multi_max"], 2, "with its numbers read as numbers")
	dialog.set_selected_detail(null)
	dialog.poll_detail_loaded(list("rows" = list(list("start", "end", "Pick?", "OPTION", null))), null, 4)
	TEST_ASSERT_NULL(dialog.selected_detail, "an option poll is not shown until its options and votes have arrived")
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 1, "its options are read next")
	dialog.poll_detail_options_loaded(list("rows" = list(list(1, "Yes"), list(2, "No"))), null, 4, list("id" = 4, "poll_type" = "OPTION", "voted" = FALSE))
	TEST_ASSERT_EQUAL(io_job_count(/datum/io_backend/sql), 2, "and then the player's votes")
	var/list/detail = list("id" = 4, "poll_type" = "OPTION", "voted" = FALSE)
	dialog.poll_detail_votes_loaded(list("rows" = list(list(2))), null, 4, detail)
	TEST_ASSERT(dialog.selected_detail["voted"], "the earlier vote is shown once the last read arrives")
	TEST_ASSERT_EQUAL(dialog.selected_detail["voted_option_id"], 2, "as the option voted for")

// ---------------------------------------------------------------- chat commands: the reply goes out when the read is answered

/datum/unit_test/tgs_command_getkey_reply_and_hold

/datum/unit_test/tgs_command_getkey_reply_and_hold/Run()
	var/datum/tgs_chat_user/sender = allocate(/datum/tgs_chat_user)
	sender.friendly_name = "Tester"
	var/datum/tgs_chat_command/getkey/getkey = allocate(/datum/tgs_chat_command/getkey)
	TEST_ASSERT(findtext(getkey.getkey_reply(sender, "77", list()), "no such Discord ID"), "no rows: the id is not in the database")
	TEST_ASSERT_EQUAL(getkey.getkey_reply(sender, "77", list(list("bob"))), "<@77>'s ckey is bob", "a row names the ckey")
	var/datum/tgs_chat_command/discordping/ping = allocate(/datum/tgs_chat_command/discordping)
	TEST_ASSERT(findtext(ping.discordping_reply(sender, "bob", list()), "no such ckey"), "no rows: the ckey is not in the database")
	TEST_ASSERT(findtext(ping.discordping_reply(sender, "bob", list(list(null))), "no discord ID"), "a row without an id says so")
	TEST_ASSERT_EQUAL(ping.discordping_reply(sender, "bob", list(list("55"))), "bob's discord is <@55>", "a row with an id pings it")
	var/key = getkey.tgs_hold_sender(sender)
	TEST_ASSERT_EQUAL(getkey.tgs_held_sender(key), sender, "the sender is held while the read is out")
	getkey.getkey_found(list("rows" = list(list("bob"))), null, key, "77")
	TEST_ASSERT_NULL(getkey.tgs_held_sender(key), "answering the read replies and lets the sender go")
	getkey.getkey_found(list("rows" = list(list("bob"))), null, key, "77")
	TEST_ASSERT_NULL(getkey.tgs_held_sender(key), "a second answer for a released hold does nothing")

/datum/unit_test/tgs_command_whitelist_edit_answers

/datum/unit_test/tgs_command_whitelist_edit_answers/Run()
	set_global("job_whitelist", list())
	var/datum/tgs_chat_user/sender = allocate(/datum/tgs_chat_user)
	var/datum/tgs_chat_command/whitelist/whitelist = allocate(/datum/tgs_chat_command/whitelist)
	var/key = whitelist.tgs_hold_sender(sender)
	whitelist.whitelist_edit_done(null, "boom", key, "add", "job", "dqwhitelistprobe", "Captain")
	TEST_ASSERT_NULL(GLOB.job_whitelist["dqwhitelistprobe"], "a refused write does not touch the in-memory whitelist")
	TEST_ASSERT_NULL(whitelist.tgs_held_sender(key), "and still answers the channel")
	key = whitelist.tgs_hold_sender(sender)
	whitelist.whitelist_edit_done(list("rows" = list(), "affected" = 1), null, key, "add", "job", "dqwhitelistprobe", "Captain")
	TEST_ASSERT("Captain" in GLOB.job_whitelist["dqwhitelistprobe"], "a written add reaches the in-memory whitelist")
	TEST_ASSERT_NULL(whitelist.tgs_held_sender(key), "and answers the channel")
	key = whitelist.tgs_hold_sender(sender)
	whitelist.whitelist_edit_done(list("rows" = list(), "affected" = 1), null, key, "remove", "job", "dqwhitelistprobe", "Captain")
	TEST_ASSERT(!("Captain" in GLOB.job_whitelist["dqwhitelistprobe"]), "a written remove leaves it")
	whitelist.whitelist_edit_done(list("rows" = list(), "affected" = 1), null, "no-such-held-sender", "add", "job", "dqwhitelistprobe", "Warden")
	TEST_ASSERT("Warden" in GLOB.job_whitelist["dqwhitelistprobe"], "a written add reaches the in-memory whitelist even when the chat sender is no longer held")

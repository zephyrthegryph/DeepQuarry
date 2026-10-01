/// The metrics service records gauges, events, runtimes and overruns into its buffers, and builds
/// parameterized statements from them. Exercised without a database: the buffers are swapped for
/// fresh ones (restored at teardown) and the statements are checked as text and arguments.
/datum/unit_test/dq_metrics_buffers_and_statements

/datum/unit_test/dq_metrics_buffers_and_statements/Run()
	var/datum/world_service/server_metrics/M = GLOB.metrics_service
	for(var/buffer in list("known_keys", "new_keys", "pending_samples", "pending_events", "runtime_buffer", "overrun_buffer"))
		set_var(M, buffer, null)
	set_var(M, "recording", TRUE)
	set_var(M, "overruns_since_sample", 0)
	set_var(M, "events_dropped", 0)

	M.gauge("test/a", 5, METRICS_CAT_SERVER, "sub", "ms")
	M.gauge("test/a", 6, METRICS_CAT_SERVER, "sub", "ms")
	TEST_ASSERT_EQUAL(length(M.new_keys), 1, "a metric's key is queued once, however many samples it has")
	TEST_ASSERT_EQUAL(length(M.pending_samples), 6, "two samples, flat name/t/value triples")

	var/exception/E = new("dq metrics test runtime")
	E.file = "code/test.dm"
	E.line = 7
	M.note_runtime(E, "uid-1")
	M.note_runtime(E, "uid-1")
	M.note_runtime(E, "uid-2")
	TEST_ASSERT_EQUAL(length(M.runtime_buffer), 2, "runtimes are grouped by signature")
	var/list/entry = M.runtime_buffer[md5("uid-1")]
	TEST_ASSERT_EQUAL(entry[1], 2, "a repeated runtime is counted, not recorded twice")
	TEST_ASSERT_EQUAL(entry[2], "code/test.dm:7", "the runtime's location is file:line")

	for(var/usage in list(150, 120, 300, 110, 130, 200, 105))
		M.note_overrun(list("usage" = usage, "top_subsystem" = "Test"))
	TEST_ASSERT_EQUAL(M.overruns_since_sample, 7, "every overrun is counted")
	TEST_ASSERT_EQUAL(length(M.overrun_buffer), METRICS_OVERRUNS_PER_FLUSH, "only the worst overruns are kept in full")
	var/list/worst = M.overrun_buffer[1]
	var/list/least = M.overrun_buffer[METRICS_OVERRUNS_PER_FLUSH]
	TEST_ASSERT_EQUAL(worst["usage"], 300, "the buffer is worst first")
	TEST_ASSERT_EQUAL(least["usage"], 120, "the mildest kept overrun is the fifth worst")

	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, "Debug", "/datum/admin_verb/test", "tester", "Test Verb", null)
	TEST_ASSERT_EQUAL(length(M.pending_events), 1, "METRICS_EVENT records while recording")
	set_var(M, "recording", FALSE)
	set_config(/datum/config_entry/flag/metrics_enabled, TRUE)
	METRICS_EVENT(METRICS_EVENT_ROUND, "start", "", "", "round started", null)
	TEST_ASSERT_EQUAL(length(M.pending_events), 2, "an event before the first sample (the round start) is kept while metrics are enabled")
	set_config(/datum/config_entry/flag/metrics_enabled, FALSE)
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, "Debug", "/datum/admin_verb/test", "tester", "Test Verb", null)
	TEST_ASSERT_EQUAL(length(M.pending_events), 2, "nothing is recorded while metrics are off")
	M.recording = TRUE

	M.collect_buffered_events()
	TEST_ASSERT_EQUAL(length(M.pending_events), 2 + 2 + METRICS_OVERRUNS_PER_FLUSH, "runtimes and overruns become events at flush")
	TEST_ASSERT(!length(M.runtime_buffer) && !length(M.overrun_buffer), "the buffers are emptied once turned into events")

	var/list/key_statement = M.key_statement(M.new_keys)
	TEST_ASSERT(findtext(key_statement[1], "INSERT IGNORE INTO metric_key"), "keys are created idempotently")
	TEST_ASSERT_EQUAL(key_statement[2]["n1"], "test/a", "key names are parameters, not inlined")
	var/list/sample_statement = M.sample_statement(M.pending_samples, 1, length(M.pending_samples), 42, 100)
	TEST_ASSERT(findtext(sample_statement[1], "JOIN metric_key k ON k.name = v.name"), "samples resolve their key ids in SQL")
	TEST_ASSERT_EQUAL(sample_statement[2]["v2"], 6, "the second sample's value is the second parameter row")
	TEST_ASSERT_EQUAL(sample_statement[2]["round"], 42, "the round id is a parameter")
	var/list/event_statement = M.event_statement(M.pending_events, 42, 100)
	TEST_ASSERT(!findtext(event_statement[1], "Test Verb"), "event text is never inlined into SQL")

/// Every metrics source runs and reports under its own category.
/datum/unit_test/dq_metrics_sources_collect

/datum/unit_test/dq_metrics_sources_collect/Run()
	var/datum/world_service/server_metrics/M = GLOB.metrics_service
	if(!M.initialized)
		M.initialize()
	for(var/buffer in list("known_keys", "new_keys", "pending_samples"))
		set_var(M, buffer, null)
	var/datum/metrics_source/server/server_source = locate_in_list(M.sources, /datum/metrics_source/server)
	TEST_ASSERT_NOTNULL(server_source, "the server source is registered")
	set_var(server_source, "first_sample", TRUE)
	M.sample()
	TEST_ASSERT(!LAZYACCESS(M.known_keys, "server/tick/avg"), "the first sample leaves tick usage out (its window reaches into MC init)")
	M.sample()
	var/list/categories = list()
	for(var/list/key as anything in M.new_keys)
		categories[key[2]] = TRUE
	for(var/category in list(METRICS_CAT_SERVER, METRICS_CAT_MC, METRICS_CAT_LANE, METRICS_CAT_PLAYERS, METRICS_CAT_STAFF, METRICS_CAT_ERRORS))
		TEST_ASSERT(categories[category], "no metric reported under [category]: [json_encode(categories)]")
	TEST_ASSERT(LAZYACCESS(M.known_keys, "server/tick/avg"), "tick usage is sampled")
	TEST_ASSERT(LAZYACCESS(M.known_keys, "players/online"), "player count is sampled")

/// A ticket's state changes become ticket events: opened, handled, closed.
/datum/unit_test/dq_metrics_ticket_events

/datum/unit_test/dq_metrics_ticket_events/Run()
	var/datum/world_service/server_metrics/M = GLOB.metrics_service
	set_var(M, "pending_events", null)
	set_var(M, "recording", TRUE)
	var/datum/ticket/T = own(new /datum/ticket/dq_metrics_fixture)
	T.id = 9001
	T.state = AHELP_ACTIVE
	T.metrics_state_event()
	T.metrics_state_event("handled")
	T.state = AHELP_CLOSED
	T.metrics_state_event()
	T.state = AHELP_ACTIVE
	T.metrics_state_event()
	var/list/changes = list()
	for(var/list/event as anything in M.pending_events)
		TEST_ASSERT_EQUAL(event[2], METRICS_EVENT_TICKET, "a ticket change is a ticket event")
		TEST_ASSERT_EQUAL(event[4], "9001", "the ticket id is the event's signature")
		changes += event[3]
	TEST_ASSERT_EQUAL(jointext(changes, ","), "opened,handled,closed,reopened", "ticket changes are named in order")

/// A ticket that skips /datum/ticket/New() (which needs a client).
/datum/ticket/dq_metrics_fixture/New()
	return

/// The shutdown flush writes keys, samples and events synchronously, in order (the I/O lane has
/// stopped by then). Needs a database: without one (CI) it only notes that it didn't run.
/datum/unit_test/dq_metrics_shutdown_flush_writes

/datum/unit_test/dq_metrics_shutdown_flush_writes/Run()
	if(!SSdbcore.IsConnected() || isnull(GLOB.round_id))
		TEST_NOTICE(src, "no database: the shutdown flush was not exercised")
		return
	var/datum/world_service/server_metrics/M = GLOB.metrics_service
	for(var/buffer in list("known_keys", "new_keys", "pending_samples", "pending_events", "runtime_buffer", "overrun_buffer"))
		set_var(M, buffer, null)
	set_var(M, "recording", TRUE)
	var/key = "test/shutdown_flush_[world.time]"
	M.gauge(key, 7, METRICS_CAT_SERVER, "test", "")
	M.final_flush()
	TEST_ASSERT(!length(M.pending_samples) && !length(M.pending_events), "the flush emptied the buffers")
	var/datum/db_query/samples = SSdbcore.NewQuery(
		"SELECT s.value FROM metric_sample s JOIN metric_key k ON k.id = s.key_id WHERE s.round_id = :round AND k.name = :name",
		list("round" = text2num(GLOB.round_id), "name" = key))
	TEST_ASSERT(samples.Execute(async = FALSE), "sample read failed: [samples.ErrorMsg()]")
	TEST_ASSERT(samples.NextRow(), "the sample was written before the flush returned")
	TEST_ASSERT_EQUAL(text2num(samples.item[1]), 7, "the sample's value")
	qdel(samples)
	var/datum/db_query/events = SSdbcore.NewQuery(
		"SELECT COUNT(*) FROM metric_event WHERE round_id = :round AND kind = 'round' AND category = 'shutdown'",
		list("round" = text2num(GLOB.round_id)))
	TEST_ASSERT(events.Execute(async = FALSE), "event read failed: [events.ErrorMsg()]")
	TEST_ASSERT(events.NextRow() && text2num(events.item[1]) >= 1, "the shutdown event was written before the flush returned")
	qdel(events)

/// The database on one path and paths as requests (code/engine/io/; doc/rewrite/final_api.html section 2).

/// A query kind: two bound fields and a typed row.
/datum/io/sql/e6_scores
	query = "SELECT name, score FROM scores WHERE who = :who AND kind = :kind AND who != :who"
	row_type = /datum/io/sql/row/e6_score
	var/who
	var/kind
	/// What the fixture backend answers with: a list of rows, or null for a refusal.
	var/list/canned

/datum/io/sql/row/e6_score
	var/name
	var/score

/// A write kind.
/datum/io/sql/e6_bump
	query = "UPDATE scores SET score = score + 1 WHERE who = :who"
	expects_rows = FALSE
	var/who

/datum/io/sql/e6_scores/run_backend()
	after(src, 1, TYPE_PROC_REF(/datum/io/sql/e6_scores, answer_canned))

/datum/io/sql/e6_scores/proc/answer_canned()
	sql_done(isnull(canned) ? null : list("rows" = canned, "affected" = 0, "last_insert_id" = null), isnull(canned) ? "boom" : null)

/datum/io/sql/e6_bump/run_backend()
	after(src, 1, TYPE_PROC_REF(/datum/io/sql/e6_bump, answer_canned))

/datum/io/sql/e6_bump/proc/answer_canned()
	sql_done(list("rows" = list(), "affected" = 2, "last_insert_id" = 7), null)

/datum/e6_io_owner
	var/list/outcomes = list()

/datum/e6_io_owner/proc/done(datum/act/request/A)
	outcomes += A.request.outcome

/datum/unit_test/kernel_db_request

/datum/unit_test/kernel_db_request/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(e6_db_forget_override))
	var/datum/e6_io_owner/owner = allocate(/datum/e6_io_owner)
	// The query declares its binds: each :field is a var of the request, once, in order.
	var/datum/io/sql/e6_scores/probe = new
	TEST_ASSERT_EQUAL(jointext(probe.bound_fields(), ","), "who,kind", "the query binds :who and :kind, each once")
	probe.who = "alice"
	probe.kind = "chess"
	var/list/bound = probe.arguments()
	TEST_ASSERT_EQUAL(bound["who"], "alice", "a :field binds the request's var of that name")
	TEST_ASSERT_EQUAL(bound["kind"], "chess", "and so does the next")
	qdel(probe)

	// A round trip: the request goes out, the answer comes back as typed rows through the handler.
	SSdb.connected_override = TRUE
	var/datum/io/sql/e6_scores/answered = open_request(owner, /datum/io/sql/e6_scores, TYPE_PROC_REF(/datum/e6_io_owner, done), who = "alice", kind = "chess", canned = list(list("name" = "x", "score" = 3), list("name" = "y", "score" = 5)))
	TEST_ASSERT(answered.is_open(), "it is open until the backend answers")
	test_time(2)
	TEST_ASSERT_EQUAL(answered.outcome, REQ_ANSWERED, "the answer ends it REQ_ANSWERED")
	TEST_ASSERT_EQUAL(length(answered.rows), 2, "one row datum per result row")
	var/datum/io/sql/row/e6_score/first = answered.rows[1]
	TEST_ASSERT(istype(first), "of the declared row type")
	TEST_ASSERT_EQUAL(first.name, "x", "its columns are vars")
	TEST_ASSERT_EQUAL(first.score, 3, "of that name")
	TEST_ASSERT_EQUAL(length(owner.outcomes), 1, "the handler ran once")

	// A read that matches nothing is REQ_NO_RESULT, not an empty answer.
	open_request(owner, /datum/io/sql/e6_scores, TYPE_PROC_REF(/datum/e6_io_owner, done), who = "nobody", kind = "chess", canned = list())
	test_time(2)
	TEST_ASSERT_EQUAL(owner.outcomes[length(owner.outcomes)], REQ_NO_RESULT, "a query that matches nothing ends REQ_NO_RESULT")

	// A write reports what it changed and is answered without rows.
	var/datum/io/sql/e6_bump/bump = open_request(owner, /datum/io/sql/e6_bump, TYPE_PROC_REF(/datum/e6_io_owner, done), who = "alice")
	test_time(2)
	TEST_ASSERT_EQUAL(bump.outcome, REQ_ANSWERED, "a write is answered")
	TEST_ASSERT_EQUAL(bump.affected, 2, "with the rows it changed")
	TEST_ASSERT_EQUAL(bump.last_insert_id, 7, "and the id it inserted")

	// The backend refuses: the request fails with the error.
	var/datum/io/sql/e6_scores/refusal = open_request(owner, /datum/io/sql/e6_scores, TYPE_PROC_REF(/datum/e6_io_owner, done), who = "alice", kind = "chess")
	test_time(2)
	TEST_ASSERT_EQUAL(refusal.outcome, REQ_TRANSPORT_FAILED, "a backend that refuses ends REQ_TRANSPORT_FAILED")
	TEST_ASSERT_EQUAL(refusal.last_error, "boom", "with its error")

	// No connection: the request fails with a reason.
	SSdb.connected_override = FALSE
	var/datum/io/sql/e6_scores/down = open_request(owner, /datum/io/sql/e6_scores, TYPE_PROC_REF(/datum/e6_io_owner, done), who = "alice", kind = "chess")
	test_time(2)
	TEST_ASSERT_EQUAL(down.outcome, REQ_TRANSPORT_FAILED, "an offline request ends REQ_TRANSPORT_FAILED")
	TEST_ASSERT_EQUAL(down.last_error, "No connection!", "naming why")
	TEST_ASSERT_EQUAL(sql_write("UPDATE x SET y = :y", list("y" = 1)), 0, "sql_write queues nothing without a connection")

/proc/e6_db_forget_override()
	SSdb.connected_override = null

/datum/unit_test/kernel_path_request

/datum/unit_test/kernel_path_request/Run()
	var/datum/e6_io_owner/owner = allocate(/datum/e6_io_owner)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/goal = locate(start.x + 3, start.y, start.z)
	TEST_ASSERT(isturf(goal), "the test block is wide enough")
	var/datum/io/path/asked = open_request(owner, /datum/io/path, TYPE_PROC_REF(/datum/e6_io_owner, done), start = start, goal = goal)
	TEST_ASSERT(asked.is_open() || asked.outcome, "a path request is open until the search ends")
	for(var/waited in 1 to 100)
		if(!asked.is_open())
			break
		wait_ticks(1)
	TEST_ASSERT_EQUAL(asked.outcome, REQ_ANSWERED, "the path system answered")
	TEST_ASSERT(length(asked.path) >= 1, "with a path")
	TEST_ASSERT_EQUAL(length(owner.outcomes), 1, "and the handler ran once")
	// A search between z-levels is refused up front.
	var/turf/other = locate(start.x, start.y, start.z + 1)
	if(other)
		test_driver_begin()
		var/datum/io/path/refused = open_request(owner, /datum/io/path, TYPE_PROC_REF(/datum/e6_io_owner, done), start = start, goal = other)
		test_time(3)
		TEST_ASSERT_EQUAL(refused.outcome, REQ_TRANSPORT_FAILED, "a goal on another z-level cannot be searched")

/// rel_set_many() (code/engine/refs/views.dm) leaves what one rel_set() per holder leaves: each pipe's parent, the pipeline's members in the same
/// order, the reverse index of both ends, and a move from one pipeline to another unlinks the old one as rel_set() does.
/datum/unit_test/dq_rel_set_many_matches_rel_set

/datum/unit_test/dq_rel_set_many_matches_rel_set/proc/make_pipes(count)
	. = list()
	for(var/i in 1 to count)
		. += allocate(/obj/machinery/atmospherics/pipe/simple/hidden/supply, test_floor())

/// What a pipeline and its pipes hold: each member's index in the list and that its parent names the line, and each reverse row.
/datum/unit_test/dq_rel_set_many_matches_rel_set/proc/state_of(datum/pipeline/line, list/pipes)
	var/list/rows = list()
	for(var/i in 1 to length(pipes))
		var/obj/machinery/atmospherics/pipe/P = pipes[i]
		rows += "[i]: parent [P.parent == line] at [line.members.Find(P)] names [rel_names(line, nameof(line.members), P) ? 1 : 0]/[rel_names(P, nameof(P.parent), line) ? 1 : 0]"
	rows += "members [length(line.members)]"
	return jointext(rows, "\n")

/datum/unit_test/dq_rel_set_many_matches_rel_set/Run()
	var/datum/pipeline/one_by_one = allocate(/datum/pipeline)
	var/datum/pipeline/batched = allocate(/datum/pipeline)
	var/list/pipes_a = make_pipes(6)
	var/list/pipes_b = make_pipes(6)
	for(var/obj/machinery/atmospherics/pipe/P as anything in pipes_a)
		rel_set(P, nameof(P.parent), one_by_one)
	var/taken_before = GLOB.rel_set_many_holders
	TEST_ASSERT_EQUAL(rel_set_many(pipes_b, nameof(/obj/machinery/atmospherics/pipe::parent), batched), 6, "every holder names the target")
	TEST_ASSERT(GLOB.rel_set_many_holders > taken_before, "the pipes took the fast form")
	TEST_ASSERT_EQUAL(state_of(batched, pipes_b), state_of(one_by_one, pipes_a), "the batch leaves what one rel_set() per pipe leaves")
	// A second batch onto a line that already holds some of them adds only the rest, in order.
	var/list/more_a = make_pipes(2)
	var/list/more_b = make_pipes(2)
	for(var/obj/machinery/atmospherics/pipe/P as anything in more_a)
		rel_set(P, nameof(P.parent), one_by_one)
	rel_set_many(pipes_b + more_b, nameof(/obj/machinery/atmospherics/pipe::parent), batched)
	TEST_ASSERT_EQUAL(state_of(batched, pipes_b + more_b), state_of(one_by_one, pipes_a + more_a), "a batch over members already held adds only the new ones")
	// Moving the pipes to another line unlinks them from the old one.
	var/datum/pipeline/moved_one = allocate(/datum/pipeline)
	var/datum/pipeline/moved_batch = allocate(/datum/pipeline)
	for(var/obj/machinery/atmospherics/pipe/P as anything in pipes_a)
		rel_set(P, nameof(P.parent), moved_one)
	rel_set_many(pipes_b, nameof(/obj/machinery/atmospherics/pipe::parent), moved_batch)
	TEST_ASSERT_EQUAL(state_of(moved_batch, pipes_b), state_of(moved_one, pipes_a), "a move leaves the new line as rel_set() does")
	TEST_ASSERT_EQUAL(length(batched.members), length(one_by_one.members), "and the old line lost the same members")

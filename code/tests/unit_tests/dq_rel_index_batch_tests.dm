// The init frame batches reverse-index writes (S4 step 6, code/engine/refs/views.dm rel_pending): a link made while a materialize frame runs
// queues its index row, every reader of the index (and a target's teardown) merges that target's rows first, and the frame merges the rest
// once when it closes. What a reader sees is the same with the batch on and off.

/// A source with one declared view and the target it names.
/datum/rel_batch_source
	var/datum/rel_batch_target/target

CAPABILITIES(/datum/rel_batch_source)
	ref_one(nameof(target))

/datum/rel_batch_target

/datum/unit_test/dq_rel_index_batch
	abstract_type = /datum/unit_test/dq_rel_index_batch

/// How the sources naming `target` read, sorted: "type.var" per row. The shape of the index without the identities.
/datum/unit_test/dq_rel_index_batch/proc/index_shape(datum/target)
	var/list/shape = list()
	for(var/list/pair as anything in rel_sources(target))
		var/datum/source = pair[1]
		shape += "[source.type].[pair[2]]"
	return sortTim(shape, GLOBAL_PROC_REF(cmp_text_asc))

/// A link made inside the frame is queued, not written; closing the frame writes it, and nothing is left queued.
/datum/unit_test/dq_rel_index_batch/queues_and_lands_on_close

/datum/unit_test/dq_rel_index_batch/queues_and_lands_on_close/Run()
	var/datum/rel_batch_source/source = new /datum/rel_batch_source
	var/datum/rel_batch_target/target = new /datum/rel_batch_target
	var/batched_before = GLOB.rel_index_batched
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_rel_batch_test")
	rel_set(source, nameof(source.target), target)
	var/batched = GLOB.rel_index_batched - batched_before
	var/raw_empty = isnull(target.refs_in)
	var/queued_targets = length(GLOB.rel_pending)
	var/frame_rows = frame.rel_index_queued
	var/frame_targets = frame.rel_index_targets
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(batched, 1, "the view's index row was queued, not written")
	TEST_ASSERT(raw_empty, "the target had no index while the frame ran")
	TEST_ASSERT_EQUAL(queued_targets, 1, "one target had rows queued")
	TEST_ASSERT_EQUAL(frame_rows, 1, "the frame counted its queued rows")
	TEST_ASSERT_EQUAL(frame_targets, 1, "the frame counted its targets")
	TEST_ASSERT_EQUAL(length(GLOB.rel_pending), 0, "closing the frame left nothing queued")
	TEST_ASSERT_NOTNULL(target.refs_in, "the target's index was written when the frame closed")
	TEST_ASSERT_EQUAL(rel_incoming_refs(target), 1, "the target is named once by the source's view")

/// Several sources naming one target share one merge.
/datum/unit_test/dq_rel_index_batch/one_merge_per_target

/datum/unit_test/dq_rel_index_batch/one_merge_per_target/Run()
	var/datum/rel_batch_target/target = new /datum/rel_batch_target
	var/list/sources = list()
	for(var/i in 1 to 5)
		sources += new /datum/rel_batch_source
	var/merged_before = GLOB.rel_index_merged
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_rel_batch_test")
	for(var/datum/rel_batch_source/source as anything in sources)
		rel_set(source, nameof(source.target), target)
	var/frame_rows = frame.rel_index_queued
	var/frame_targets = frame.rel_index_targets
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(frame_rows, 5, "five rows were queued")
	TEST_ASSERT_EQUAL(frame_targets, 1, "for one target")
	TEST_ASSERT_EQUAL(GLOB.rel_index_merged - merged_before, 1, "and merged once")
	TEST_ASSERT_EQUAL(length(rel_sources(target)), 5, "the index names all five")

/// A read inside the frame sees the link: the target's queued rows are merged by the read.
/datum/unit_test/dq_rel_index_batch/read_inside_frame_sees_the_link

/datum/unit_test/dq_rel_index_batch/read_inside_frame_sees_the_link/Run()
	var/datum/rel_batch_source/source = new /datum/rel_batch_source
	var/datum/rel_batch_target/target = new /datum/rel_batch_target
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_rel_batch_test")
	rel_set(source, nameof(source.target), target)
	var/list/found = rel_sources(target)
	var/incoming = rel_incoming_refs(target)
	var/pending_after = length(GLOB.rel_pending)
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(length(found), 1, "a read of the target's index inside the frame finds the source")
	TEST_ASSERT(found[1][1] == source, "the source is the one linked")
	TEST_ASSERT_EQUAL(incoming, 1, "the incoming count sees the link")
	TEST_ASSERT_EQUAL(pending_after, 0, "the read merged the target's rows")

/// A link made and unmade inside the frame leaves no row behind.
/datum/unit_test/dq_rel_index_batch/detach_inside_frame_leaves_no_row

/datum/unit_test/dq_rel_index_batch/detach_inside_frame_leaves_no_row/Run()
	var/datum/rel_batch_source/source = new /datum/rel_batch_source
	var/datum/rel_batch_target/target = new /datum/rel_batch_target
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_rel_batch_test")
	rel_set(source, nameof(source.target), target)
	rel_clear(source, nameof(source.target))
	SSatoms.batch_close(frame)
	TEST_ASSERT_NULL(source.target, "the view is cleared")
	TEST_ASSERT_EQUAL(length(rel_sources(target)), 0, "the target's index names no source")
	TEST_ASSERT_EQUAL(rel_incoming_refs(target), 0, "nothing counts as naming the target")

/// A target deleted inside the frame clears the views naming it, as it does outside one.
/datum/unit_test/dq_rel_index_batch/target_deleted_inside_frame

/datum/unit_test/dq_rel_index_batch/target_deleted_inside_frame/Run()
	var/datum/rel_batch_source/source = new /datum/rel_batch_source
	var/datum/rel_batch_target/target = new
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_rel_batch_test")
	rel_set(source, nameof(source.target), target)
	qdel(target)
	var/cleared = isnull(source.target)
	SSatoms.batch_close(frame)
	TEST_ASSERT(cleared, "the deleted target left the source before the frame closed")
	TEST_ASSERT_EQUAL(length(GLOB.rel_pending), 0, "no row of a deleted target is left queued")

/// A source deleted inside the frame leaves no row on its target.
/datum/unit_test/dq_rel_index_batch/source_deleted_inside_frame

/datum/unit_test/dq_rel_index_batch/source_deleted_inside_frame/Run()
	var/datum/rel_batch_source/source = new
	var/datum/rel_batch_target/target = new /datum/rel_batch_target
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_rel_batch_test")
	rel_set(source, nameof(source.target), target)
	qdel(source)
	SSatoms.batch_close(frame)
	TEST_ASSERT_EQUAL(length(rel_sources(target)), 0, "the target's index names no source")
	TEST_ASSERT_EQUAL(rel_incoming_refs(target), 0, "nothing counts as naming the target")

/// The index a batched run builds reads the same as the one written link by link.
/datum/unit_test/dq_rel_index_batch/matches_unbatched

/datum/unit_test/dq_rel_index_batch/matches_unbatched/Run()
	var/datum/rel_batch_target/batched_target = new /datum/rel_batch_target
	var/datum/rel_batch_target/plain_target = new /datum/rel_batch_target
	var/list/batched = list()
	var/list/plain = list()
	for(var/i in 1 to 6)
		batched += new /datum/rel_batch_source
		plain += new /datum/rel_batch_source
	var/datum/materialize_batch/frame = SSatoms.batch_open("dq_rel_batch_test")
	for(var/datum/rel_batch_source/source as anything in batched)
		rel_set(source, nameof(source.target), batched_target)
	SSatoms.batch_close(frame)
	for(var/datum/rel_batch_source/source as anything in plain)
		rel_set(source, nameof(source.target), plain_target)
	TEST_ASSERT_EQUAL(jointext(index_shape(batched_target), ","), jointext(index_shape(plain_target), ","), "the index reads the same with the batch on and off")
	TEST_ASSERT_EQUAL(rel_incoming_refs(batched_target), rel_incoming_refs(plain_target), "the incoming counts agree")
	TEST_ASSERT_EQUAL(rel_incoming_refs(batched_target), 6, "all six links count")

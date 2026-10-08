// Chunked materialize and init_from_table (doc/rewrite/init_and_turfs.md sec 3.1, 3.3a).
// The ordering rules are listed at the top of code/controllers/subsystems/atoms_batch.dm.

/// ("init" or "late", probe) entries, in the order they happened.
GLOBAL_LIST_EMPTY(dq_batch_probe_log)

/// Records its Initialize() and its after_init() in one shared log.
/obj/effect/dq_batch_probe
	name = "batch probe"
	/// The frame that was active while this probe initialized.
	var/tmp/datum/materialize_batch/seen_batch

/obj/effect/dq_batch_probe/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(seen_batch), SSatoms.active_batch)
	GLOB.dq_batch_probe_log.Add(list(list("init", src)))

CAPABILITIES(/obj/effect/dq_batch_probe)
	after_init(0, then(PROC_REF(log_late)))

/obj/effect/dq_batch_probe/proc/log_late(datum/act/timer/A)
	GLOB.dq_batch_probe_log.Add(list(list("late", src)))

/datum/unit_test/dq_materialize_batch
	abstract_type = /datum/unit_test/dq_materialize_batch

/// `count` probes created without initializing, as the map loader leaves them.
/datum/unit_test/dq_materialize_batch/proc/uninitialized_probes(count)
	var/list/made = list()
	SSatoms.map_loader_begin("dq_batch_test")
	for(var/i in 1 to count)
		made += new /obj/effect/dq_batch_probe(null)
	SSatoms.map_loader_stop("dq_batch_test")
	for(var/obj/effect/dq_batch_probe/probe as anything in made)
		own(probe)
	return made

/// Drops the test hooks; the probes are own()ed and go with the test. The probe log is read
/// after this, so it is cleared when the test goes (on_destroy), not here.
/datum/unit_test/dq_materialize_batch/proc/reset_hooks()
	SSatoms.batch_yield_probe = null
	SSatoms.batch_trace = null

/datum/unit_test/dq_materialize_batch/on_destroy(force)
	GLOB.dq_batch_probe_log.Cut()
	return ..()

/// Index of the first (or last) log entry of `kind` for any atom in `atoms`.
/datum/unit_test/dq_materialize_batch/proc/log_index(kind, list/atoms, last = FALSE)
	var/list/log = GLOB.dq_batch_probe_log
	var/found = 0
	for(var/i in 1 to length(log))
		var/list/entry = log[i]
		if(entry[1] == kind && (entry[2] in atoms))
			found = i
			if(!last)
				return i
	return found

/// Rules 1, 2, 5: a batch yields only between chunks, keeps the caller's order, runs its
/// late loaders after its last atom, and is isolated while it sleeps.
/datum/unit_test/dq_materialize_batch/chunks_and_yields
	var/list/main_batch
	var/list/yield_reports

/datum/unit_test/dq_materialize_batch/chunks_and_yields/Run()
	GLOB.dq_batch_probe_log.Cut()
	var/total = MATERIALIZE_CHUNK_SIZE * 2 + 10
	main_batch = uninitialized_probes(total)
	SSatoms.batch_trace = list()
	SSatoms.batch_yield_probe = list(src, PROC_REF(on_yield))
	SSatoms.InitializeAtoms(main_batch.Copy())
	var/datum/materialize_batch/batch = SSatoms.batch_trace[1]
	reset_hooks()

	TEST_ASSERT_NULL(SSatoms.active_batch, "a closed frame left itself active")
	TEST_ASSERT_EQUAL(batch.chunks, 3, "chunks for [total] atoms")
	TEST_ASSERT_EQUAL(batch.yields, 2, "a batch yields only between chunks")
	for(var/report in yield_reports)
		TEST_FAIL(report)
	yield_reports = null

	// Rule 1: initialized in list order.
	var/list/log = GLOB.dq_batch_probe_log
	var/next = 1
	for(var/list/entry as anything in log)
		if(entry[1] != "init" || !(entry[2] in main_batch))
			continue
		TEST_ASSERT(entry[2] == main_batch[next], "atom [next] initialized out of order")
		next++
	TEST_ASSERT_EQUAL(next - 1, total, "atoms initialized")
	// Rule 2: every late loader after the last atom.
	TEST_ASSERT(log_index("late", main_batch) > log_index("init", main_batch, TRUE), "an after_init() ran before its batch finished")
	for(var/obj/effect/dq_batch_probe/probe as anything in main_batch)
		TEST_ASSERT(probe.seen_batch == batch, "an atom initialized outside its frame")
		TEST_ASSERT(probe.flags & ATOM_MATERIALIZED, "an atom was not materialized")

/// At each yield: nothing is active, deferral is refused, the chunk before is done and the
/// one after untouched, and a frame opened meanwhile owns its work and finishes on its own.
/datum/unit_test/dq_materialize_batch/chunks_and_yields/proc/on_yield(datum/materialize_batch/batch)
	if(SSatoms.active_batch)
		LAZYADD(yield_reports, "a frame stayed active across a yield")
	if(SSatoms.batch_defer(BATCH_WORK_CABLE_BINDS, src))
		LAZYADD(yield_reports, "work was deferred into a sleeping frame")
	var/boundary = batch.chunks * MATERIALIZE_CHUNK_SIZE
	var/obj/effect/dq_batch_probe/before = main_batch[boundary]
	var/obj/effect/dq_batch_probe/after = main_batch[boundary + 1]
	if(!(before.flags & ATOM_INITIALIZED) || (after.flags & ATOM_INITIALIZED))
		LAZYADD(yield_reports, "yield [batch.yields] was not at a chunk boundary")
	if(log_index("late", main_batch))
		LAZYADD(yield_reports, "a late loader ran while its frame slept")
	// Another map load while this one sleeps.
	var/list/other = uninitialized_probes(2)
	SSatoms.InitializeAtoms(other)
	var/datum/materialize_batch/other_batch = SSatoms.batch_trace[length(SSatoms.batch_trace)]
	if(other_batch == batch || other_batch.owner) // a closed owner frame clears its owner link
		LAZYADD(yield_reports, "a frame opened during a yield joined the sleeping frame")
	if(!log_index("late", other))
		LAZYADD(yield_reports, "a frame opened during a yield did not run its own late loaders")

/// Rules 3, 4: a nested call joins the running frame's deferred work but runs its own
/// late loaders; deferred work flushes once, when the owner closes.
/datum/unit_test/dq_materialize_batch/nested_joins

/datum/unit_test/dq_materialize_batch/nested_joins/Run()
	GLOB.dq_batch_probe_log.Cut()
	var/list/pair = uninitialized_probes(1)
	var/obj/effect/dq_batch_probe/inner = pair[1]
	SSatoms.batch_trace = list()
	// A running frame (as while an outer batch initializes), then a nested call.
	var/datum/materialize_batch/outer_batch = SSatoms.batch_open("dq_batch_test_outer")
	SSatoms.InitializeAtoms(list(inner))
	TEST_ASSERT(SSatoms.active_batch == outer_batch, "closing a nested frame did not restore the outer one")
	SSatoms.batch_close(outer_batch)

	var/frames = length(SSatoms.batch_trace)
	var/datum/materialize_batch/inner_batch = SSatoms.batch_trace[frames]
	reset_hooks()
	TEST_ASSERT_EQUAL(frames, 2, "frames opened")
	TEST_ASSERT(inner_batch.owner == outer_batch, "a nested frame did not join the running one")
	TEST_ASSERT(inner.seen_batch == inner_batch, "the nested atom did not see its own frame")
	TEST_ASSERT(log_index("late", list(inner)), "the nested frame's late loaders waited for the outer frame")
	TEST_ASSERT_NULL(SSatoms.active_batch, "a closed frame left itself active")

	// Work deferred from inside the nested frame lands on the owner and flushes once.
	var/obj/structure/cable/cable = allocate(/obj/structure/cable, test_floor())
	var/datum/materialize_batch/owner = SSatoms.batch_open("dq_batch_test_owner")
	var/datum/materialize_batch/joined = SSatoms.batch_open("dq_batch_test_joined")
	TEST_ASSERT(SSatoms.batch_defer(BATCH_WORK_CABLE_BINDS, cable), "an active frame refused work")
	TEST_ASSERT(owner.work[BATCH_WORK_CABLE_BINDS][cable], "joined work did not reach the owner")
	SSatoms.batch_close(joined)
	TEST_ASSERT(owner.work[BATCH_WORK_CABLE_BINDS][cable], "a joined frame flushed its owner's work")
	SSatoms.batch_undefer(BATCH_WORK_CABLE_BINDS, cable)
	TEST_ASSERT(!owner.work[BATCH_WORK_CABLE_BINDS][cable], "undefer left the cable queued")
	SSatoms.batch_close(owner)
	TEST_ASSERT_NULL(SSatoms.active_batch, "closing the owner left a frame active")

/// init_from_table types end up in the same state from table_initialize() as from the
/// Initialize() chain (forced by an extra New() argument).
/datum/unit_test/dq_materialize_batch/table_init_parity

/datum/unit_test/dq_materialize_batch/table_init_parity/Run()
	var/checked = 0
	for(var/path in subtypesof(/obj/structure/sign) + subtypesof(/obj/effect/decal))
		var/obj/sample = path
		if(!initial(sample.init_from_table))
			continue
		var/obj/table = allocate(path, test_floor())
		var/obj/chain = allocate(path, test_floor(), TRUE)
		var/wanted = ATOM_INITIALIZED | ATOM_MATERIALIZED
		TEST_ASSERT_EQUAL(table.flags & wanted, wanted, "[path] via table_initialize()")
		TEST_ASSERT_EQUAL(chain.flags & wanted, wanted, "[path] via Initialize()")
		TEST_ASSERT_EQUAL(length(table.overlays), length(chain.overlays), "[path] overlays differ between the two paths")
		TEST_ASSERT_EQUAL(table.get_integrity(), chain.get_integrity(), "[path] integrity differs between the two paths")
		if(++checked >= 20)
			break
	TEST_ASSERT(checked, "no init_from_table sign or decal types to check")

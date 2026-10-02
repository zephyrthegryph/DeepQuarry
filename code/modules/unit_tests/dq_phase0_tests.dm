// Phase 0 framework fixes (review defects D3-D6): reaction delivery conventions and drain isolation.

// ---------------------------------------------------------------- D3: global handlers get the holder first

GLOBAL_LIST_EMPTY(rx_fx_g_seen)

/// Holds two tracked vars; one reaction is a global handler, one a global guard.
/datum/rx_fx_g
	var/watched = 0

TRACKED(/datum/rx_fx_g, watched)

/datum/rx_fx_g/reactions()
	. = ..()
	. += on_change(list(nameof(watched)), GLOBAL_PROC_REF(rx_fx_g_changed))
	. += before_op("rx_fx_g_op", GLOBAL_PROC_REF(rx_fx_g_guard))

/proc/rx_fx_g_changed(datum/rx_fx_g/holder, list/keys)
	GLOB.rx_fx_g_seen += list(list(holder, keys.Copy()))

/proc/rx_fx_g_guard(datum/rx_fx_g/holder, ctx)
	GLOB.rx_fx_g_seen += list(list(holder, ctx))
	return "no"

/datum/unit_test/dq_phase0_global_handler_holder_first/Run()
	GLOB.rx_fx_g_seen = list()
	var/datum/rx_fx_g/A = allocate(/datum/rx_fx_g)
	var/datum/rx_fx_g/B = allocate(/datum/rx_fx_g)
	A.set_watched(1)
	B.set_watched(1)
	rx_drain()
	TEST_ASSERT_EQUAL(length(GLOB.rx_fx_g_seen), 2, "each holder's change delivered once")
	var/list/first = GLOB.rx_fx_g_seen[1]
	var/list/second = GLOB.rx_fx_g_seen[2]
	TEST_ASSERT(first[1] == A && second[1] == B, "a global on_change handler is told which holder changed")
	TEST_ASSERT_EQUAL(first[2][1], nameof(/datum/rx_fx_g::watched), "and then gets the changed keys")
	GLOB.rx_fx_g_seen = list()
	var/veto = rx_before_op(A, "rx_fx_g_op", null, "ctx-marker")
	TEST_ASSERT_EQUAL(veto, "no", "a global guard can veto")
	var/list/guarded = GLOB.rx_fx_g_seen[1]
	TEST_ASSERT(guarded[1] == A && guarded[2] == "ctx-marker", "a global before_op handler gets (holder, ctx)")
	GLOB.rx_fx_g_seen = list()

// ---------------------------------------------------------------- D4: a looping handler quarantines only itself

/// `loop` is read by a handler that re-dirties it forever; `calm` is read by an ordinary handler.
/datum/rx_fx_loop
	var/loop = 0
	var/calm = 0
	var/loop_runs = 0
	var/calm_runs = 0

TRACKED(/datum/rx_fx_loop, loop)
TRACKED(/datum/rx_fx_loop, calm)

/datum/rx_fx_loop/reactions()
	. = ..()
	. += on_change(list(nameof(loop)), PROC_REF(on_loop))
	. += on_change(list(nameof(calm)), PROC_REF(on_calm))

/datum/rx_fx_loop/proc/on_loop(list/keys)
	loop_runs++
	set_loop(loop + 1)

/datum/rx_fx_loop/proc/on_calm(list/keys)
	calm_runs++

/datum/unit_test/dq_phase0_drain_quarantines_only_the_loop/Run()
	var/datum/rx_fx_loop/looper = allocate(/datum/rx_fx_loop)
	var/datum/rx_fx_loop/bystander = allocate(/datum/rx_fx_loop)
	set_global("rx_drain_loop_expected", TRUE)
	looper.set_loop(1)
	looper.set_calm(1)
	bystander.set_calm(1)
	rx_drain()
	set_global("rx_drain_loop_expected", FALSE)
	TEST_ASSERT_EQUAL(looper.loop_runs, RX_DRAIN_PASSES, "the loop is cut at the limit")
	TEST_ASSERT_EQUAL(looper.calm_runs, 1, "the same holder's other reaction still delivered")
	TEST_ASSERT_EQUAL(bystander.calm_runs, 1, "another holder's queued change was not discarded")
	TEST_ASSERT_EQUAL(length(GLOB.rx_pending), 0, "nothing is left queued")

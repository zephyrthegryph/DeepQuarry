// Declared dependencies (code/datums/capabilities/derived.dm): a change to a var a derived output reads
// re-derives only that output; relation hops, derive() values, factor reads, the coalesced Rust push,
// capability contributions, the output-writes-state assertion and the drift audit's hint.

// ---------------------------------------------------------------- fixtures

/// The laser pointer case: should_run() reads energy, draw() reads pointing, the UI reads energy.
/obj/cap_fixture/dx_deps_laser
	icon_state = "fixture_base"
	periodic_cadence = PERIODIC_SLOW
	var/energy = 8
	var/max_energy = 8
	var/pointing = FALSE
	/// Tracked, but nothing reads it.
	var/spare = 0
	var/should_run_calls = 0
	var/draw_calls = 0

TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_laser, energy, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_laser, pointing, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_laser, spare, CHANGE_DATUM_A)

/obj/cap_fixture/dx_deps_laser/derived()
	. = ..()
	. += runs_while(nameof(energy))
	. += drawn_from(nameof(pointing))
	. += ui_from(nameof(energy))

/obj/cap_fixture/dx_deps_laser/should_run()
	should_run_calls++
	return energy < max_energy

/obj/cap_fixture/dx_deps_laser/draw(datum/look/look)
	..()
	draw_calls++
	look.state(pointing ? "pointing" : "idle")

/// The same reads with no derived(): any tracked change re-derives everything.
/obj/cap_fixture/dx_deps_legacy
	icon_state = "fixture_base"
	var/tier = 0
	var/draw_calls = 0

TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_legacy, tier, CHANGE_DATUM_A)

/obj/cap_fixture/dx_deps_legacy/draw(datum/look/look)
	..()
	draw_calls++
	look.state(tier ? "high" : "low")

/// What the hops read.
/obj/cap_fixture/dx_deps_source
	var/glow = FALSE
	var/other = 0

TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_source, glow, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_source, other, CHANGE_DATUM_A)

/// draw() reads the source's glow through the declared REL view `source`.
/obj/cap_fixture/dx_deps_watcher
	icon_state = "fixture_base"
	var/obj/cap_fixture/dx_deps_source/source
	var/draw_calls = 0

/obj/cap_fixture/dx_deps_watcher/relations()
	. = ..()
	. += rel_one(nameof(source))

/obj/cap_fixture/dx_deps_watcher/derived()
	. = ..()
	. += drawn_from(rel(nameof(source), nameof(/obj/cap_fixture/dx_deps_source::glow)))

/obj/cap_fixture/dx_deps_watcher/draw(datum/look/look)
	..()
	draw_calls++
	look.state(source?.glow ? "lit" : "dark")

/// A plain datum (a UI panel) whose UI reads the glow of every member of a REL_LIST.
/datum/dx_deps_panel
	var/list/members

/datum/dx_deps_panel/relations()
	. = ..()
	. += rel_many(nameof(members))

/datum/dx_deps_panel/New()
	..()
	derived_attach(src)

/datum/dx_deps_panel/derived()
	. = ..()
	. += ui_from(rel_each(nameof(members), nameof(/obj/cap_fixture/dx_deps_source::glow)))

/// Cached values: total = a + b, twice = total * 2 (declared first: the order must follow the reads),
/// heard = the feed's `other` through a hop. draw() reads total.
/obj/cap_fixture/dx_deps_derive
	icon_state = "fixture_base"
	var/a = 1
	var/b = 0
	var/total = 0
	var/twice = 0
	var/heard = 0
	var/obj/cap_fixture/dx_deps_source/feed
	var/derive_calls = 0
	var/draw_calls = 0

/obj/cap_fixture/dx_deps_derive/relations()
	. = ..()
	. += rel_one(nameof(feed))
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_derive, a, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_derive, b, CHANGE_DATUM_A)

/obj/cap_fixture/dx_deps_derive/derived()
	. = ..()
	. += derive(nameof(twice), nameof(total))
	. += derive(nameof(total), nameof(a), nameof(b))
	. += derive(nameof(heard), rel(nameof(feed), nameof(/obj/cap_fixture/dx_deps_source::other)))
	. += drawn_from(nameof(total))

/obj/cap_fixture/dx_deps_derive/proc/derive_total()
	derive_calls++
	return a + b

/obj/cap_fixture/dx_deps_derive/proc/derive_twice()
	return total * 2

/obj/cap_fixture/dx_deps_derive/proc/derive_heard()
	return feed ? feed.other : -1

/obj/cap_fixture/dx_deps_derive/draw(datum/look/look)
	..()
	draw_calls++
	look.state(total > 3 ? "big" : "small")

/// A hop through a plain var: refused at init.
/obj/cap_fixture/dx_deps_plainhop
	var/obj/cap_fixture/dx_deps_source/plain

/obj/cap_fixture/dx_deps_plainhop/derived()
	. = ..()
	. += drawn_from(rel(nameof(plain), nameof(/obj/cap_fixture/dx_deps_source::glow)))

/// A factor read.
/obj/cap_fixture/dx_deps_factor
	periodic_cadence = PERIODIC_SLOW

/obj/cap_fixture/dx_deps_factor/derived()
	. = ..()
	. += runs_while(factor_dep(BF_SLOWDOWN))

/obj/cap_fixture/dx_deps_factor/should_run()
	return TRUE

/// An output that writes state.
/obj/cap_fixture/dx_deps_writer
	icon_state = "fixture_base"
	var/tier = 0
	var/lie = 0

TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_writer, tier, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_writer, lie, CHANGE_DATUM_A)

/obj/cap_fixture/dx_deps_writer/derived()
	. = ..()
	. += drawn_from(nameof(tier))

/obj/cap_fixture/dx_deps_writer/draw(datum/look/look)
	..()
	look.state("written")
	set_lie(lie + 1)

/// draw() reads `shade`, which derived() forgot.
/obj/cap_fixture/dx_deps_sloppy
	icon_state = "fixture_base"
	var/shade = 0
	var/other = 0

TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_sloppy, shade, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_sloppy, other, CHANGE_DATUM_A)

/obj/cap_fixture/dx_deps_sloppy/derived()
	. = ..()
	. += drawn_from(nameof(other))

/obj/cap_fixture/dx_deps_sloppy/draw(datum/look/look)
	..()
	look.state(shade ? "shaded" : "plain")

/// push_to_rust() reads target and mode.
/obj/cap_fixture/dx_deps_pusher
	var/target = 0
	var/mode = 0
	var/noise = 0
	var/pushes = 0

TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_pusher, target, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_pusher, mode, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_pusher, noise, CHANGE_DATUM_A)

/obj/cap_fixture/dx_deps_pusher/derived()
	. = ..()
	. += rust_push(nameof(target), nameof(mode))

/obj/cap_fixture/dx_deps_pusher/push_to_rust()
	pushes++

/// A capability that draws the holder's `gadget`, and says so itself.
/datum/capability/dx_deps_reads

/datum/capability/dx_deps_reads/draw(atom/holder, datum/look/look)
	look.overlay("gadget", when = !!holder.vars[nameof(/obj/cap_fixture/dx_deps_cap::gadget)])

/datum/capability/dx_deps_reads/derived_reads(atom/holder)
	return list(drawn_from(nameof(/obj/cap_fixture/dx_deps_cap::gadget)))

/obj/cap_fixture/dx_deps_cap
	icon_state = "fixture_base"
	var/gadget = FALSE
	var/spare = 0

TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_cap, gadget, CHANGE_DATUM_A)
TRACKED_BRIDGED(/obj/cap_fixture/dx_deps_cap, spare, CHANGE_DATUM_A)

/obj/cap_fixture/dx_deps_cap/capabilities()
	. = ..()
	. += new /datum/capability/dx_deps_reads

/// An empty runs_while() makes the type exact: only what it (or its capabilities) reads re-derives.
/obj/cap_fixture/dx_deps_cap/derived()
	. = ..()
	. += runs_while()

// ---------------------------------------------------------------- tests

/// The laser pointer case: a drop in energy wakes the recharge, and only should_run() (and the UI) re-run.
/datum/unit_test/dx_deps_should_run_wake/Run()
	var/obj/cap_fixture/dx_deps_laser/F = allocate(/obj/cap_fixture/dx_deps_laser)
	refresh_flush()
	TEST_ASSERT(!(!isnull(F.periodic_pipe)), "a full pointer does not recharge")
	var/draws = F.draw_calls
	var/checks = F.should_run_calls
	F.set_energy(3)
	TEST_ASSERT_EQUAL(F.refresh_queued, DEP_RUN | DEP_UI, "energy is read by should_run() and the UI only")
	refresh_flush()
	TEST_ASSERT((!isnull(F.periodic_pipe)), "the drop woke the recharge")
	TEST_ASSERT_EQUAL(F.should_run_calls, checks + 1, "should_run() re-checked once")
	TEST_ASSERT_EQUAL(F.draw_calls, draws, "draw() was not re-run for an energy change")
	F.set_energy(8)
	refresh_flush()
	TEST_ASSERT(!(!isnull(F.periodic_pipe)), "a full pointer parks again")
	// A change that reaches only draw().
	checks = F.should_run_calls
	F.set_pointing(TRUE)
	TEST_ASSERT_EQUAL(F.refresh_queued, DEP_DRAW, "pointing is read by draw() only")
	refresh_flush()
	TEST_ASSERT_EQUAL(F.draw_calls, draws + 1, "draw() re-ran")
	TEST_ASSERT_EQUAL(F.should_run_calls, checks, "should_run() did not")

/// A tracked change nobody reads re-derives nothing; a type that declares nothing, and a plain
/// changed(), re-derive everything.
/datum/unit_test/dx_deps_undeclared_no_refresh/Run()
	var/obj/cap_fixture/dx_deps_laser/F = allocate(/obj/cap_fixture/dx_deps_laser)
	var/obj/cap_fixture/dx_deps_legacy/L = allocate(/obj/cap_fixture/dx_deps_legacy)
	refresh_flush()
	var/draws = F.draw_calls
	var/checks = F.should_run_calls
	F.set_spare(5)
	TEST_ASSERT_EQUAL(F.refresh_queued, 0, "nothing reads spare: nothing is queued")
	refresh_flush()
	TEST_ASSERT_EQUAL(F.draw_calls, draws, "no draw")
	TEST_ASSERT_EQUAL(F.should_run_calls, checks, "no should_run()")
	changed(F)
	TEST_ASSERT_EQUAL(F.refresh_queued, DEP_ALL, "a plain changed() still re-derives everything")
	refresh_flush()
	var/legacy_draws = L.draw_calls
	L.set_tier(2)
	TEST_ASSERT_EQUAL(L.refresh_queued, DEP_ALL, "a type that declares nothing keeps the old rule")
	refresh_flush()
	TEST_ASSERT_EQUAL(L.draw_calls, legacy_draws + 1, "and re-draws")

/// A draw re-queued from a relation hop; the reverse index follows link and unlink.
/datum/unit_test/dx_deps_draw_from_hop/Run()
	var/obj/cap_fixture/dx_deps_source/S = allocate(/obj/cap_fixture/dx_deps_source)
	var/obj/cap_fixture/dx_deps_source/S2 = allocate(/obj/cap_fixture/dx_deps_source)
	var/obj/cap_fixture/dx_deps_watcher/W = allocate(/obj/cap_fixture/dx_deps_watcher)
	rel_set(W, nameof(/obj/cap_fixture/dx_deps_watcher::source), S)
	TEST_ASSERT_EQUAL(W.refresh_queued & DEP_DRAW, DEP_DRAW, "linking the view re-derives what reads through it")
	refresh_flush()
	var/draws = W.draw_calls
	S.set_glow(TRUE)
	TEST_ASSERT_EQUAL(W.refresh_queued, DEP_DRAW, "the source's glow re-queues the watcher's draw")
	refresh_flush()
	TEST_ASSERT_EQUAL(W.draw_calls, draws + 1, "the watcher re-drew")
	S.set_other(4)
	TEST_ASSERT_EQUAL(W.refresh_queued, 0, "a var the watcher does not hop to is not passed on")
	refresh_flush()
	// Unlinked: the old source no longer reaches it.
	rel_set(W, nameof(/obj/cap_fixture/dx_deps_watcher::source), null)
	refresh_flush()
	draws = W.draw_calls
	S.set_glow(FALSE)
	TEST_ASSERT_EQUAL(W.refresh_queued, 0, "an unlinked source reaches nobody")
	refresh_flush()
	// Relinked to another source: that one does.
	rel_set(W, nameof(/obj/cap_fixture/dx_deps_watcher::source), S2)
	refresh_flush()
	draws = W.draw_calls
	S2.set_glow(TRUE)
	TEST_ASSERT_EQUAL(W.refresh_queued, DEP_DRAW, "the new source reaches the watcher")
	refresh_flush()
	TEST_ASSERT_EQUAL(W.draw_calls, draws + 1, "and it re-drew")
	// The source going away clears the view and re-derives the watcher.
	qdel(S2)
	refresh_flush()
	TEST_ASSERT(isnull(W.source), "the view was cleared with its target")

/// A UI push from rel_each: every member of the list is followed.
/datum/unit_test/dx_deps_ui_from_rel_each/Run()
	var/obj/cap_fixture/dx_deps_source/S1 = allocate(/obj/cap_fixture/dx_deps_source)
	var/obj/cap_fixture/dx_deps_source/S2 = allocate(/obj/cap_fixture/dx_deps_source)
	var/datum/dx_deps_panel/P = allocate(/datum/dx_deps_panel)
	rel_add(P, nameof(/datum/dx_deps_panel::members), S1)
	rel_add(P, nameof(/datum/dx_deps_panel::members), S2)
	refresh_flush()
	var/ref_text = REF(P)
	var/pushes = GLOB.derived_ui_flushes[ref_text] || 0
	S2.set_glow(TRUE)
	TEST_ASSERT_EQUAL(P.refresh_queued, DEP_UI, "a member's glow queues the panel's UI push")
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.derived_ui_flushes[ref_text], pushes + 1, "and it is pushed once")
	S1.set_other(3)
	TEST_ASSERT_EQUAL(P.refresh_queued, 0, "a var the panel does not follow is not passed on")
	rel_remove(P, nameof(/datum/dx_deps_panel::members), S2)
	refresh_flush()
	pushes = GLOB.derived_ui_flushes[ref_text]
	S2.set_glow(FALSE)
	TEST_ASSERT_EQUAL(P.refresh_queued, 0, "a member that left is not followed")
	S1.set_glow(TRUE)
	TEST_ASSERT_EQUAL(P.refresh_queued, DEP_UI, "the one that stayed is")
	refresh_flush()
	TEST_ASSERT_EQUAL(GLOB.derived_ui_flushes[ref_text], pushes + 1, "pushed again")

/// derive(): recomputed only when a read changed, in read order, coalesced, tracked by its readers, and
/// fed through a hop.
/datum/unit_test/dx_deps_derive_chain/Run()
	var/obj/cap_fixture/dx_deps_source/S = allocate(/obj/cap_fixture/dx_deps_source)
	var/obj/cap_fixture/dx_deps_derive/F = allocate(/obj/cap_fixture/dx_deps_derive)
	rel_set(F, nameof(/obj/cap_fixture/dx_deps_derive::feed), S)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.total, 1, "total = a + b")
	TEST_ASSERT_EQUAL(F.twice, 2, "twice read total, which ran first although it was declared second")
	TEST_ASSERT_EQUAL(F.heard, 0, "heard follows the feed")
	var/calls = F.derive_calls
	var/draws = F.draw_calls
	// Two writes in one frame recompute total once; it comes out unchanged, so nothing that reads it re-runs.
	F.set_a(2)
	F.set_b(-1)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.derive_calls, calls + 1, "recomputed once for two changed reads")
	TEST_ASSERT_EQUAL(F.total, 1, "unchanged")
	TEST_ASSERT_EQUAL(F.draw_calls, draws, "an unchanged value re-runs nothing")
	F.set_a(5)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.total, 4, "total follows a")
	TEST_ASSERT_EQUAL(F.twice, 8, "twice follows total")
	TEST_ASSERT_EQUAL(F.draw_calls, draws + 1, "draw() reads total, which changed")
	calls = F.derive_calls
	S.set_other(9)
	refresh_flush()
	TEST_ASSERT_EQUAL(F.heard, 9, "a hop feeds a derived value")
	TEST_ASSERT_EQUAL(F.derive_calls, calls, "and recomputes nothing else")

/// A hop through a plain var is refused at init with a clear error.
/datum/unit_test/dx_deps_refuse_plain_hop/Run()
	set_global("derived_error_expected", TRUE)
	GLOB.derived_errors.Cut()
	allocate(/obj/cap_fixture/dx_deps_plainhop)
	set_global("derived_error_expected", FALSE)
	TEST_ASSERT(length(GLOB.derived_errors) > 0, "the hop was refused")
	TEST_ASSERT(findtext(GLOB.derived_errors[1], "not a declared relation"), "and says why: [GLOB.derived_errors[1]]")
	GLOB.derived_errors.Cut()

/// factor_dep(): a recomputed body factor that changed re-checks the reader; one it doesn't read doesn't.
/datum/unit_test/dx_deps_factor_dep/Run()
	var/obj/cap_fixture/dx_deps_factor/F = allocate(/obj/cap_fixture/dx_deps_factor)
	refresh_flush()
	var/list/same = new /list(BF_COUNT)
	for(var/id in 1 to BF_COUNT)
		same[id] = body_factor_baseline(id)
	derived_factors_recomputed(F, null, same)
	TEST_ASSERT_EQUAL(F.refresh_queued, 0, "baseline to baseline changes nothing")
	var/list/other = same.Copy()
	other[BF_VISION] = 0.5
	derived_factors_recomputed(F, null, other)
	TEST_ASSERT_EQUAL(F.refresh_queued, 0, "a factor it does not read")
	var/list/slowed = same.Copy()
	slowed[BF_SLOWDOWN] = 2
	derived_factors_recomputed(F, null, slowed)
	TEST_ASSERT_EQUAL(F.refresh_queued, DEP_RUN, "the factor it reads re-checks should_run()")
	refresh_flush()
	derived_factors_recomputed(F, slowed, slowed)
	TEST_ASSERT_EQUAL(F.refresh_queued, 0, "an unchanged factor")

/// push_to_rust() runs once per frame however many of its reads changed, and not for other changes.
/datum/unit_test/dx_deps_rust_push/Run()
	var/obj/cap_fixture/dx_deps_pusher/F = allocate(/obj/cap_fixture/dx_deps_pusher)
	refresh_flush()
	var/pushes = F.pushes
	F.set_target(1)
	F.set_mode(2)
	TEST_ASSERT_EQUAL(F.refresh_queued, DEP_PUSH, "both reads feed the one output")
	refresh_flush()
	TEST_ASSERT_EQUAL(F.pushes, pushes + 1, "pushed once for two changes")
	F.set_noise(3)
	TEST_ASSERT_EQUAL(F.refresh_queued, 0, "an unread var pushes nothing")

/// A capability contributes the reads of its own draw(): the holder declares only its own.
/datum/unit_test/dx_deps_capability_reads/Run()
	var/obj/cap_fixture/dx_deps_cap/F = allocate(/obj/cap_fixture/dx_deps_cap)
	refresh_flush()
	F.set_gadget(TRUE)
	TEST_ASSERT_EQUAL(F.refresh_queued, DEP_DRAW, "the capability's draw reads gadget")
	refresh_flush()
	F.set_spare(1)
	TEST_ASSERT_EQUAL(F.refresh_queued, 0, "a var neither the holder nor a capability reads")

/// Outputs must not write state: a tracked write inside draw() is reported.
/datum/unit_test/dx_deps_output_writes_state/Run()
	set_global("derived_write_expected", TRUE)
	set_global("refresh_self_mark_expected", TRUE)
	GLOB.derived_write_violations.Cut()
	allocate(/obj/cap_fixture/dx_deps_writer)
	refresh_flush()
	set_global("derived_write_expected", FALSE)
	set_global("refresh_self_mark_expected", FALSE)
	TEST_ASSERT(length(GLOB.derived_write_violations) > 0, "the write was reported")
	TEST_ASSERT(findtext(GLOB.derived_write_violations[1], "lie"), "and names the var: [GLOB.derived_write_violations[1]]")
	GLOB.derived_write_violations.Cut()
	GLOB.refresh_self_marks.Cut()

/// The drift audit finds a look that no longer matches and names the undeclared read behind it.
/datum/unit_test/dx_deps_drift_names_read/Run()
	var/obj/cap_fixture/dx_deps_sloppy/F = allocate(/obj/cap_fixture/dx_deps_sloppy)
	refresh_flush()
	F.set_shade(1)
	TEST_ASSERT_EQUAL(F.refresh_queued, 0, "shade is declared nowhere: the change is dropped")
	refresh_flush()
	set_global("refresh_drift_expected", TRUE)
	GLOB.refresh_drift.Cut()
	var/found = refresh_check_drift(F)
	set_global("refresh_drift_expected", FALSE)
	TEST_ASSERT(found, "the audit saw the stale look")
	TEST_ASSERT(length(GLOB.refresh_drift) > 0 && findtext(GLOB.refresh_drift[1], "shade"), "and named the likely undeclared read: [length(GLOB.refresh_drift) ? GLOB.refresh_drift[1] : "no report"]")
	GLOB.refresh_drift.Cut()
